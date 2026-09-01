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
    static let defaultValue: Paint? = nil
}

extension EnvironmentValues {
    /// What text and other content is painted with.
    ///
    /// Set via `.foregroundStyle(_:)` on any View; `nil` means nothing has
    /// been stated and the palette default applies.
    ///
    /// A ``Paint`` rather than a ``Color`` because a gradient goes here too,
    /// and it goes in the SAME slot: a leaf reads one key however it was
    /// styled, and an outer gradient with an inner colour has an unambiguous
    /// answer rather than two keys and no rule for ordering them. Anything that
    /// needs one colour — and most chrome does — asks for
    /// ``Paint/representative``, which makes each collapse visible where it
    /// happens.
    public var foregroundStyle: Paint? {
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
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        _StyleEnvironmentView(
            content: self, style: style, slot: \.foregroundStyle, fades: true)
    }

    /// The colour spelling, so `.foregroundStyle(.red)` and
    /// `.foregroundStyle(.palette.accent)` keep inferring what they always did.
    ///
    /// `@_disfavoredOverload` is Apple's own answer to the same problem — see
    /// `tint`, which ships a generic `<S: ShapeStyle>` and a disfavoured
    /// `Color?` twin side by side. Without it a leading-dot member has to be
    /// found on `ShapeStyle` rather than on `Color`, and every static colour in
    /// the framework would need a `where Self == Color` forwarder to be
    /// reachable.
    @_disfavoredOverload
    public func foregroundStyle(_ style: Color) -> some View {
        _StyleEnvironmentView(
            content: self, style: style, slot: \.foregroundStyle, fades: true)
    }
}

// MARK: - Background Style Environment

/// Environment key for the default background style.
private struct BackgroundStyleKey: EnvironmentKey {
    static let defaultValue: Paint? = nil
}

extension EnvironmentValues {
    /// What ``View/background()`` and ``BackgroundStyle`` paint with.
    ///
    /// Set via ``View/backgroundStyle(_:)-(S)``; `nil` means nothing has been
    /// stated and the palette's own background applies.
    ///
    /// A ``Paint`` rather than SwiftUI's `AnyShapeStyle?`, for the reason
    /// ``foregroundStyle`` is one: an existential is not `Equatable`, and the
    /// render memo answers "incomparable" for anything that is not — which
    /// turns memoization off for the whole subtree beneath it.
    public var backgroundStyle: Paint? {
        get { self[BackgroundStyleKey.self] }
        set { self[BackgroundStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the background style for this view and its children.
    ///
    /// It paints nothing by itself: it names what ``View/background()`` and
    /// the ``ShapeStyle/background`` style will use, the way
    /// ``View/foregroundStyle(_:)-(S)`` names the ink rather than drawing it.
    ///
    /// ```swift
    /// VStack {
    ///     Text("Total").padding().background()
    /// }
    /// .backgroundStyle(LinearGradient(colors: [.rgb(20, 30, 60), .rgb(60, 20, 50)],
    ///                                 startPoint: .leading, endPoint: .trailing))
    /// ```
    ///
    /// - Parameter style: The style descendants should use as their background.
    /// - Returns: A view that publishes the style to its descendants.
    public func backgroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        _StyleEnvironmentView(
            content: self, style: style, slot: \.backgroundStyle, fades: false)
    }

    /// The colour spelling, so `.backgroundStyle(.red)` keeps inferring — the
    /// same `@_disfavoredOverload` pairing ``View/foregroundStyle(_:)-(S)`` needs, and
    /// for the same reason.
    @_disfavoredOverload
    public func backgroundStyle(_ style: Color) -> some View {
        _StyleEnvironmentView(
            content: self, style: style, slot: \.backgroundStyle, fades: false)
    }
}

/// Publishes a resolved ``Paint`` into one environment slot for its subtree.
///
/// A plain `.environment(\.foregroundStyle, _)` would do neither of the two
/// things that make this a view rather than a one-liner: a style has to be
/// resolved where the palette is, and the memo has to be TOLD, or a subtree
/// below a scoped style change serves a buffer painted in the old one. That
/// second half is a known bug class — see `RenderContext`'s note on
/// `setting()` — so both style slots go through this one type rather than
/// through two copies of the bookkeeping.
struct _StyleEnvironmentView<Content: View, S: ShapeStyle>: View {
    let content: Content
    let style: S

    /// Which slot to publish into.
    let slot: WritableKeyPath<EnvironmentValues, Paint?>

    /// Whether a colour change here should FADE under ``withAnimation(_:_:)``.
    ///
    /// True for the foreground, which is the last stop before the ink. False
    /// for a background style, which is a default that something else paints —
    /// and `BackgroundModifier` already asks the animator when it does, so
    /// fading here as well would animate toward a moving target and drag the
    /// transition out.
    let fades: Bool

    var body: Never {
        fatalError("_StyleEnvironmentView renders via Renderable")
    }

    private func childContext(_ context: RenderContext) -> RenderContext {
        // The same bookkeeping `EnvironmentModifier` does, and it is not
        // optional: a memoizing view below this one keys on the VIEW value,
        // which does not change when a style applied above it does, so without
        // this a scoped `.foregroundStyle` change serves a buffer rendered in
        // the old colour. Wrong pixels, not merely stale work — and there is a
        // test that says so.
        // The PAINT is what is tracked, not the style: a style is not required
        // to be `Equatable`, and `noteAppliedEnvironment` answers
        // `.incomparable` for anything that is not — which sets
        // `hasUncomparableEnvironmentValue` and refuses every memo store in the
        // subtree. Tracking the resolved paint also means a style that resolves
        // to the same colour does not count as a change, which is the right
        // answer as well as the cheap one.
        var paint = style.paint(in: context.environment)
        // A ramp fades as a colour does: every stop and every number of the
        // geometry moves on its own store entry. See ``PaintAnimation``.
        if fades {
            paint = PaintAnimation.resolving(paint, owner: Self.self, context: context)
        }
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                paint, identity: context.identity, keyPath: slot,
                depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity)
        }
        var childContext = context
        childContext.environment[keyPath: slot] = paint
        childContext.environmentApplicationDepth += 1
        return childContext
    }
}

extension _StyleEnvironmentView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: childContext(context))
    }
}

extension _StyleEnvironmentView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: childContext(context))
    }
}
