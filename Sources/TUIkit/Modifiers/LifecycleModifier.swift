//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    let task: @Sendable () async -> Void

    /// Task priority.
    let priority: TaskPriority

    var body: Never {
        fatalError("TaskModifier renders via Renderable")
    }
}

extension TaskModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            let lifecycle = context.environment.lifecycle!
            let token = lifecycleToken("task", context)

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
}

// MARK: - Layoutable

// These modifiers impose no geometry of their own — they render `content` under
// the unchanged context, and their lifecycle bookkeeping is already gated on
// `!context.isMeasuring` (the measure-side-effect rule). So forwarding the
// measurement to `content` is exactly render-consistent, and it keeps the
// wrapped subtree out of `measureChild`'s render-to-measure fallback, which
// would otherwise render the content twice per measure (once at the proposal,
// once at `naturalWidth + 8` to probe flexibility) on top of the real render.

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
