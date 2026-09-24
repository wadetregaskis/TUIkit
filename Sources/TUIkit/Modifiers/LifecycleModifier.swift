//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LifecycleModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Lifecycle Tokens

/// The place ONE lifecycle modifier instance occupies, one step below the
/// identity it renders its content at.
///
/// NOT `context.identity`, which is shared: these modifiers are `Renderable`
/// and render content under the unchanged context, so two of a kind chained on
/// one view sit at a single identity. Sharing a token there meant only the
/// first `.onAppear` fired, the second `.onDisappear` registration simply
/// replaced the first in the callback table, and two `.task(id:)`s traded one
/// generation box and restarted each other every frame.
///
/// The step is the modifier's own generic type, which distinguishes them
/// because chaining strictly nests it: `OnAppearModifier<OnAppearModifier<Text>>`
/// wraps `OnAppearModifier<Text>`. Deliberately not a positionally claimed
/// counter, the way the `onChange` family disambiguates: a counter is stable
/// only while every pass claims in the same order, and a token that churns
/// re-fires an action or restarts a task rather than merely mis-slotting a
/// value. A key built from what the code says is the same under any walk.
private func lifecycleIdentity<Owner>(
    _ owner: Owner.Type, _ context: RenderContext
) -> ViewIdentity {
    context.identity.child(type: owner)
}

/// Derives the stable lifecycle token for one `.onAppear` / `.onDisappear` /
/// `.task` from its **structural identity**, not a per-construction `UUID`.
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
/// - Parameters:
///   - prefix: The kind of lifecycle event, so different kinds on one view
///     never collide.
///   - identity: This instance's own place — see ``lifecycleIdentity(_:_:)``.
private func lifecycleToken(_ prefix: String, _ identity: ViewIdentity) -> String {
    "\(prefix)-\(identity.path)"
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
            let token = lifecycleToken("appear", lifecycleIdentity(Self.self, context))
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
            let token = lifecycleToken("disappear", lifecycleIdentity(Self.self, context))
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
            let identity = lifecycleIdentity(Self.self, context)
            var token = lifecycleToken("task", identity)
            if let id {
                token += "-gen\(generation(for: id, identity: identity, context: context))"
            }

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
    /// this instance last saw.
    ///
    /// The lifecycle machinery keys on a token and a token is a string, so the
    /// id's identity *as a value* has to become one somehow. A counter does it
    /// without ever rendering the value: the id itself is persisted beside it
    /// and compared with `==`, which is the whole point.
    ///
    /// A reserved NEGATIVE slot, because the box sits at an identity a
    /// composite view could also occupy — index 0 belongs to such a view's
    /// first `@State`. See ``StateStorage/StateKey``.
    private func generation(
        for id: AnyEquatableBox, identity: ViewIdentity, context: RenderContext
    ) -> Int {
        guard let stateStorage = context.stateStorage else { return 0 }
        let box: StateBox<TaskIDGeneration> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: identity, propertyIndex: TaskStateIndex.idGeneration),
            default: TaskIDGeneration(id: id, generation: 0))
        if box.value.id != id {
            box.value = TaskIDGeneration(id: id, generation: box.value.generation + 1)
        }
        // The box must survive the per-frame StateStorage GC, or the generation
        // resets to 0 every render and a task restarts forever.
        stateStorage.markActive(identity)
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

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension OnAppearModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension OnDisappearModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension TaskModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Each draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnAppearModifier: DrawsContentUnchanged {}
extension OnDisappearModifier: DrawsContentUnchanged {}
extension TaskModifier: DrawsContentUnchanged {}
