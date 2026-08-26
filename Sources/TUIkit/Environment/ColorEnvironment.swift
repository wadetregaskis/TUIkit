//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Foreground Style Environment

/// Environment key for the foreground style.
///
/// When set via `.foregroundStyle(_:)` on any View, this value propagates
/// down through the view hierarchy. Child views can read it from the
/// render context to apply the color.
private struct ForegroundStyleKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The foreground style (color) for text and other content.
    ///
    /// Set via `.foregroundStyle(_:)` modifier on any View.
    /// Returns `nil` if not explicitly set (use palette default).
    public var foregroundStyle: Color? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }
}

// MARK: - View Extension for foregroundStyle

extension View {
    /// Sets the foreground style for this view and its children.
    ///
    /// The style propagates through the view hierarchy via the environment.
    /// Child views that render text or other colored content should read
    /// `context.environment.foregroundStyle` and apply it.
    ///
    /// ## Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("Red text")
    ///     Text("Also red")
    /// }
    /// .foregroundStyle(.red)
    /// ```
    ///
    /// A change to the colour inside ``withAnimation(_:_:)`` fades rather than
    /// jumping.
    ///
    /// > Note: `Text` has its own `foregroundStyle(_:) -> Text` overload, which
    ///   carries the colour *in the view value* rather than painting it. There
    ///   is no modifier there to ask the animator, so a colour set that way
    ///   changes at once. Wrap the text — `VStack { Text(…) }.foregroundStyle(…)`
    ///   — to fade it. `Text` is the most-rendered view in the framework and a
    ///   store lookup per `Text` would be paid by every app on every frame.
    ///
    /// - Parameter style: The color to apply as foreground style.
    /// - Returns: A view with the foreground style set.
    public func foregroundStyle(_ style: Color?) -> some View {
        _AnimatableForegroundStyleView(content: self, style: style)
    }
}

/// Publishes a foreground style to its subtree, fading it when it changes
/// inside ``withAnimation(_:_:)``.
///
/// A plain `.environment(\.foregroundStyle, _)` would do everything but the
/// fade; the colour has to be resolved where the palette is, which is here.
/// See ``ColorAnimation``.
struct _AnimatableForegroundStyleView<Content: View>: View {
    let content: Content
    let style: Color?

    var body: Never {
        fatalError("_AnimatableForegroundStyleView renders via Renderable")
    }

    private func childContext(_ context: RenderContext) -> RenderContext {
        // The same bookkeeping `EnvironmentModifier` does, and it is not
        // optional: a memoizing view below this one keys on the VIEW value,
        // which does not change when a style applied above it does, so without
        // this a scoped `.foregroundStyle` change serves a buffer rendered in
        // the old colour. Wrong pixels, not merely stale work — and there is a
        // test that says so.
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                // `as Any` deliberately: the value tracked here is the
                // OPTIONAL, because clearing a style is a change the cache has
                // to notice as much as setting one. Without the cast this is a
                // warning on every build — the compiler cannot tell a meant
                // Optional from a forgotten unwrap.
                style as Any, identity: context.identity,
                keyPath: \EnvironmentValues.foregroundStyle,
                depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity)
        }
        var childContext = context
        childContext.environment.foregroundStyle = style.map {
            ColorAnimation.resolving($0, owner: Self.self, context: context)
        }
        childContext.environmentApplicationDepth += 1
        return childContext
    }
}

extension _AnimatableForegroundStyleView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: childContext(context))
    }
}

extension _AnimatableForegroundStyleView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: childContext(context))
    }
}
