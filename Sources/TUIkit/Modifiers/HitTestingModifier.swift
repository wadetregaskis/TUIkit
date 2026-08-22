//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HitTestingModifier.swift
//
//  Taking the MOUSE away from a view without taking its space or its drawing:
//  `allowsHitTesting(false)` leaves the view exactly as it looked and lets
//  clicks fall through to whatever is beneath.
//
//  `hidden()` is the same idea taken all the way: the view keeps its space
//  and loses everything else — its drawing, its mouse, its overlays.
//
//  ⚠️ Declaring a `View.hidden()` has one non-obvious consequence, found the
//  hard way. TUIkit conforms `Optional` to `View` (PrimitiveTypes+View.swift),
//  so `hidden` becomes a member reachable through an Optional — and inside a
//  swift-testing `#expect(…)` macro expansion, that is enough to derail the
//  implicit member `.hidden` in an `Optional<SomeEnum>` argument position. It
//  compiles clean and evaluates wrong. It is not specific to any TUIkit type:
//  a private `enum Fruit { case hidden, apple }` reproduces it, and renaming
//  this method to anything else makes it go away. Outside the macro, in a
//  non-Optional position, or with the case spelled out in full, resolution is
//  correct. So: inside `#expect`, write `SomeEnum.hidden`, not `.hidden`.
//  ScrollbarModifierWiringTests carries the one in-tree instance.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - allowsHitTesting()

extension View {
    /// Controls whether this view can be the target of mouse input.
    ///
    /// Mirrors SwiftUI's `allowsHitTesting(_:)`. With `false` the view still
    /// draws and still occupies its space; clicks, drags and wheel events pass
    /// through it to whatever is beneath.
    ///
    /// ```swift
    /// // A decorative overlay that must not swallow clicks.
    /// content.overlay(watermark.allowsHitTesting(false))
    /// ```
    ///
    /// This is not ``View/disabled(_:)``. A disabled control looks disabled and
    /// leaves the focus ring; a non-hit-testable one looks entirely normal and
    /// stays reachable by keyboard. Reach for this when the view is *decoration*
    /// that happens to sit over something interactive — not when an action is
    /// unavailable.
    ///
    /// - Parameter enabled: Whether the view may be hit. Default `true`.
    /// - Returns: A view whose hit regions are kept or dropped.
    public func allowsHitTesting(_ enabled: Bool) -> some View {
        _HitTestingView(content: self, enabled: enabled)
    }
}

// MARK: - hidden()

extension View {
    /// Hides this view unconditionally, without giving up its space.
    ///
    /// Mirrors SwiftUI's `hidden()`. The view is laid out exactly as it would
    /// have been and then draws nothing: a hole the shape of the view, which
    /// takes no clicks and floats no pop-ups.
    ///
    /// ```swift
    /// // Both rows keep the same width; only one of them is legible.
    /// HStack { Text("total"); Text(amount).hidden() }
    /// ```
    ///
    /// Reach for this when the layout must not move — a placeholder holding a
    /// column open, a value that appears later. To remove the space as well,
    /// leave the view out of the hierarchy (`if`/`else`) instead.
    ///
    /// - Returns: A view that occupies its space and shows nothing.
    public func hidden() -> some View {
        _HiddenView(content: self)
    }
}

/// Renders `content` for its geometry only, then blanks it.
///
/// Blanking the *rendered* buffer rather than sizing a hole from
/// `sizeThatFits` is deliberate: measure and render are allowed to disagree
/// (a minimum can exceed a proposal), and a hidden view whose hole is a
/// different shape from the view it hides would move the layout — the one
/// thing this modifier promises not to do.
///
/// - Important: Framework infrastructure, created by ``View/hidden()``.
private struct _HiddenView<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never { fatalError("_HiddenView renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Rendered through the backdrop isolation, because a view with no
        // picture has no powers either. Everything a subtree does happens
        // WHILE it renders — `FocusRegistration.register` writes into the real
        // focus manager, `.keyboardShortcut` files itself, `.statusBarItems`
        // publishes — and throwing the buffer away afterwards undid none of it.
        // `Button("Press") {}.hidden()` was an invisible, fully live Tab stop.
        //
        // Which also fixes the worse case. This modifier's contract says it
        // leaves "a hole the shape of the view, which takes no clicks and
        // floats no pop-ups", so dropping a presentation's overlay is intended
        // — but the presentation had already activated its focus section and
        // grabbed the keyboard by the time the buffer was discarded, leaving an
        // invisible dialog holding the keyboard. Isolated, it grabs a throwaway
        // and the app is unaffected.
        //
        // Same treatment, and the same reasoning, as `.dimmed()`: a modifier
        // that takes the picture away takes the powers with it. `@State`,
        // `.onAppear`/`.task`, lifecycle and preferences stay shared, so a
        // hidden view is still alive — as it is in SwiftUI.
        let drawn = TUIkit.renderToBuffer(content, context: context.isolatedForBackground())
        // Spaces, not zero-width nothing: this is the same convention `Spacer`
        // uses for space that is occupied but blank, and it is what stops the
        // hole from collapsing in a stack. Overlays, hit regions and animated
        // runs are all left behind by construction.
        return FrameBuffer(emptyWithWidth: drawn.width, height: drawn.height)
    }
}

/// Drops the hit regions of `content` when disabled.
///
/// - Important: Framework infrastructure, created by
///   ``View/allowsHitTesting(_:)``.
private struct _HitTestingView<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let enabled: Bool

    var body: Never { fatalError("_HitTestingView renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var drawn = TUIkit.renderToBuffer(content, context: context)
        guard !enabled else { return drawn }
        // The regions of any ANCHORED overlay the subtree floated have to go
        // too — a pop-up menu is carried in `overlays` rather than in the
        // buffer's own lines, so clearing only the top level would leave a
        // drop-down clickable underneath a view that just said it was not.
        //
        // A CENTRED one is exempt, for the reason `_HiddenView` above spells
        // out: a `.sheet` presented from this subtree is not part of this
        // subtree's hit area, it is a panel over the whole screen with its own
        // buttons. Clearing its regions produced a dialog that drew perfectly
        // and whose every button was dead — and the modifier the author wrote
        // was about the page, not about the dialog it opens.
        drawn.hitTestRegions = []
        for index in drawn.overlays.indices where !drawn.overlays[index].centered {
            drawn.overlays[index].content.hitTestRegions = []
        }
        return drawn
    }
}
