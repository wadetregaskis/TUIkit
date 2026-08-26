//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LifecycleModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Lifecycle Tokens

/// Derives the stable lifecycle token for a view's `.onAppear` / `.onDisappear`
/// / `.task` from its **structural identity**, not a per-construction `UUID`.
///
/// This matters because a modifier value is rebuilt every time its parent's
/// `body` is evaluated — i.e. on every frame. A `UUID()` baked in at
/// construction would therefore change every frame, so `LifecycleManager` would
/// see a brand-new token each time: `.task` would restart every frame (and, when
/// the task mutates `@State`, spin the render loop forever), `.onAppear` would
/// re-fire every frame, and `.onDisappear` would fire spuriously for views that
/// never left (their old token "disappears" the instant a new one appears). The
/// identity path is stable across frames for a fixed structural position, so the
/// token is too — the view appears, fires, and disappears exactly once.
///
/// This mirrors how `Spinner`, `ProgressView`, and `_ImageCore` already key
/// their lifecycle/animation tasks (`"spinner-\(context.identity.path)"` etc.).
///
/// - Note: Two lifecycle modifiers of the *same* kind chained on a single view
///   (`Text().task { a }.task { b }`) share an identity path and therefore a
///   token, so only the first fires. That is vanishingly rare — distinct kinds
///   (`.onAppear` + `.task`) use distinct prefixes and never collide.
private func lifecycleToken(_ prefix: String, _ context: RenderContext) -> String {
    "\(prefix)-\(context.identity.path)"
}

// MARK: - OnAppear Modifier

/// A modifier that executes an action when a view first appears.
struct OnAppearModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The action to execute on first appearance.
    let action: () -> Void

    var body: Never {
        fatalError("OnAppearModifier renders via Renderable")
    }
}

extension OnAppearModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Lifecycle bookkeeping is a render-pass side effect: a measure pass must
        // not record appearance, or it would mark the view "appeared" before the
        // real render and suppress the action. See the measure-side-effect rule.
        if !context.isMeasuring {
            // The appearance record is per-frame presence: a cached buffer
            // skipping it makes the token vanish from the frame's visible set,
            // so endRenderPass fires the disappear machinery for a row that is
            // still on screen. Declare the side effect so the memos decline.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            let token = lifecycleToken("appear", context)
            _ = context.environment.lifecycle!.recordAppear(token: token, action: action)
        }
        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - OnDisappear Modifier

/// A modifier that executes an action when a view disappears.
struct OnDisappearModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The action to execute when the view disappears.
    let action: () -> Void

    var body: Never {
        fatalError("OnDisappearModifier renders via Renderable")
    }
}

extension OnDisappearModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            // See OnAppearModifier: presence must be re-recorded every frame,
            // or the row "disappears" (firing the action) while still visible.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            let token = lifecycleToken("disappear", context)
            // Register the disappear callback…
            context.environment.lifecycle!.registerDisappear(token: token, action: action)
            // …and mark the view visible this render so it only "disappears"
            // (firing the callback) once it is actually removed from the tree.
            _ = context.environment.lifecycle!.recordAppear(token: token, action: {})
        }
        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - Task Modifier

/// A modifier that starts an async task when a view appears.
///
/// The task is cancelled when the view disappears.
struct TaskModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The async task to execute.
    ///
    /// `@isolated(any)`: the value carries the isolation the closure was
    /// written with, which `View/task(priority:_:)` arranges to be the view
    /// body's (`@MainActor`) unless the app asked for something else. Starting
    /// it therefore needs no isolation of its own — see `TUIContext.startTask`.
    let task: @isolated(any) @Sendable () async -> Void

    /// Task priority.
    let priority: TaskPriority

    /// A `.task(id:)` identifier, or `nil` for a plain `.task`.
    ///
    /// Type-erased through ``AnyEquatableBox`` so the comparison is the `==`
    /// SwiftUI documents — "the modifier tests whether a new value for the
    /// `id` parameter equals the previous value". It used to be the id's
    /// `String(describing:)` folded into the lifecycle token, which is a
    /// different relation in both directions: two UNEQUAL instances of an
    /// `Equatable` class describe identically, so swapping them never
    /// restarted the task (Apple's own worked example is exactly that), and
    /// two EQUAL structs whose description includes a field `==` ignores
    /// describe differently, so an in-flight task was cancelled and restarted
    /// for a change SwiftUI treats as a non-event.
    ///
    /// A changed id means the old token is no longer recorded this frame, so
    /// it "disappears" (cancelling the previous task) while the new token
    /// appears fresh and starts the new one — the same appear/disappear
    /// machinery that drives `.onAppear` / `.onDisappear`.
    let id: AnyEquatableBox?

    var body: Never {
        fatalError("TaskModifier renders via Renderable")
    }
}

extension TaskModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            // See OnAppearModifier: a cached row skipping this bookkeeping
            // "disappears" its token, CANCELLING the task while the row is
            // still on screen (and restarting it on the next cache miss).
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            let lifecycle = context.environment.lifecycle!
            var token = lifecycleToken("task", context)
            if let id { token += "-gen\(generation(for: id, context: context))" }

            // Start the task only on the first appearance for this identity.
            let isFirstAppear = !lifecycle.hasAppeared(token: token)
            _ = lifecycle.recordAppear(token: token) {}
            if isFirstAppear {
                lifecycle.startTask(token: token, priority: priority, operation: task)
            }

            // Cancel the task when the view leaves the tree.
            lifecycle.registerDisappear(token: token) { [lifecycle] in
                lifecycle.cancelTask(token: token)
            }
        }
        return TUIkit.renderToBuffer(content, context: context)
    }

    /// A counter that advances every time `id` stops being `==` to the value
    /// this identity last saw.
    ///
    /// The lifecycle machinery keys on a token and a token is a string, so the
    /// id's identity *as a value* has to become one somehow. A counter does it
    /// without ever rendering the value: the id itself is persisted beside it
    /// and compared with `==`, which is the whole point.
    ///
    /// A reserved NEGATIVE slot, because this modifier persists state at the
    /// same identity as the content it renders — index 0 belongs to that
    /// content's first `@State`. See ``StateStorage/StateKey``.
    private func generation(for id: AnyEquatableBox, context: RenderContext) -> Int {
        guard let stateStorage = context.stateStorage else { return 0 }
        let box: StateBox<TaskIDGeneration> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: TaskStateIndex.idGeneration),
            default: TaskIDGeneration(id: id, generation: 0))
        if box.value.id != id {
            box.value = TaskIDGeneration(id: id, generation: box.value.generation + 1)
        }
        // The box must survive the per-frame StateStorage GC, or the generation
        // resets to 0 every render and a task restarts forever.
        stateStorage.markActive(context.identity)
        return box.value.generation
    }
}

// MARK: - Layoutable

// These modifiers impose no geometry of their own — they render `content` under
// the unchanged context, and their lifecycle bookkeeping is already gated on
// `!context.isMeasuring` (the measure-side-effect rule). So forwarding the
// measurement to `content` is exactly render-consistent, and it keeps the
// wrapped subtree out of `measureChild`'s render-to-measure fallback, which
// would otherwise render the content to measure it (on top of the real render).

extension OnAppearModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension OnDisappearModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension TaskModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// The `.task(id:)` value an identity last saw, and how many times it has
/// changed since.
private struct TaskIDGeneration {
    let id: AnyEquatableBox
    let generation: Int
}

/// StateStorage property indices for ``TaskModifier``. A free enum because the
/// modifier is generic (which can't hold static stored properties).
private enum TaskStateIndex {
    /// Range -60, claimed in ``StateStorage/StateKey``'s table.
    static let idGeneration = -60
}
