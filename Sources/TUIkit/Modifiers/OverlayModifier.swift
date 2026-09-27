//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Internal modifier that layers an overlay view on top of the base content.
///
/// The overlay is laid out **inside the base's frame**: the base is rendered
/// with the space this modifier was given, the overlay is then offered the size
/// the base came back at, positioned in it by `alignment`, and cut to it. The
/// result is the base's size on both axes — an overlay never resizes what it is
/// laid over, which is the whole difference between `.overlay` and a `ZStack`.
///
/// The exception is an axis the base has no extent on at all: there is no frame
/// to lay the overlay in, so the overlay is drawn whole and is what the
/// modifier measures. `EmptyView().overlay { … }` is that case, and so is a
/// base whose entire payload floats (an `OffsetView` renders no in-flow lines).
public struct OverlayModifier<Base: View, Overlay: View>: View {
    /// The base content.
    let base: Base

    /// The overlay content.
    let overlay: Overlay

    /// The alignment of the overlay within the base bounds.
    let alignment: Alignment

    public var body: Never {
        fatalError("OverlayModifier renders via Renderable")
    }
}

// MARK: - Equatable Conformance

extension OverlayModifier: @preconcurrency Equatable where Base: Equatable, Overlay: Equatable {
    public static func == (lhs: OverlayModifier<Base, Overlay>, rhs: OverlayModifier<Base, Overlay>) -> Bool {
        lhs.base == rhs.base && lhs.overlay == rhs.overlay && lhs.alignment == rhs.alignment
    }
}

// MARK: - Renderable

extension OverlayModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The base renders at this modifier's own identity; the overlay, below,
        // under an identity of its OWN.
        //
        // Rendered through the same context, the two subtrees bind their
        // `@State` under one `StateKey(identity, propertyIndex)`: same-typed
        // properties silently share a box, and differently-typed ones make
        // `storage(for:default:)` swap the box every frame, which resets BOTH
        // sides to their defaults forever. A badge, a focus ring or a loading
        // veil over a stateful card is an ordinary `.overlay()`, and any of
        // them holding state corrupted the view underneath.
        //
        // Index 1, with the base left where it was: the same shape
        // `ListRowStyleModifiers` uses for a row's background, and leaving the
        // base at the parent identity means no existing view's `@State` slot or
        // focus id moves.
        let baseBuffer = TUIkit.renderToBuffer(base, context: context)
        let overlayContext = context.withChildIdentity(type: Overlay.self, index: 1)

        // Shortcut a layer with NOTHING in it — but `isEmpty` only inspects
        // in-flow lines, and a line-empty buffer can still be carrying the
        // whole point of the view. `OffsetView` documents exactly that output:
        // no lines, one `OverlayLayer` holding the offset content, plus its hit
        // regions. Returning the other layer then threw that away — the base
        // side losing the content AND its interactivity, the overlay side
        // losing a `.offset()`-positioned badge entirely. Falling through to
        // `composited(with:at:)` is correct for both: it keeps this buffer's
        // layers and regions and lifts the other's, shifted into place, and it
        // already special-cases a line-empty overlay for exactly this reason.
        if baseBuffer.isEmpty, baseBuffer.overlays.isEmpty, baseBuffer.hitTestRegions.isEmpty {
            return TUIkit.renderToBuffer(overlay, context: overlayContext)
        }

        // The overlay is laid out IN the base's frame, so it is offered the
        // size the base came back at rather than the whole space this modifier
        // was given. That is SwiftUI's rule, and it is what makes an overlay
        // whose own layout consumes its width — `.overlay { HStack { Spacer();
        // Text("!") } }` — pin to the base's trailing edge instead of to the
        // terminal's, eighty columns away and then clipped off.
        //
        // An axis the base has NO extent on is left alone: a zero-wide frame
        // draws nothing at all, and a base whose whole payload floats (an
        // `OffsetView`) reaches here with no in-flow lines and a layer.
        var framedContext = overlayContext
        if baseBuffer.width > 0 { framedContext.availableWidth = baseBuffer.width }
        if baseBuffer.height > 0 { framedContext.availableHeight = baseBuffer.height }
        let overlayBuffer = TUIkit.renderToBuffer(overlay, context: framedContext)

        if overlayBuffer.isEmpty, overlayBuffer.overlays.isEmpty,
            overlayBuffer.hitTestRegions.isEmpty
        {
            return baseBuffer
        }

        // Calculate the position of the overlay based on alignment
        let baseWidth = baseBuffer.width
        let baseHeight = baseBuffer.height
        let overlayWidth = overlayBuffer.width
        let overlayHeight = overlayBuffer.height

        // Calculate horizontal position — from the overlay's own explicit
        // `.alignmentGuide` when it set one, so a badge can hang off the corner
        // it is aligned to rather than sit squarely on it.
        let overlaySize = (width: overlayWidth, height: overlayHeight)
        let horizontalOffset =
            horizontalGuidePlacement(
                of: overlay, size: overlaySize, alignment: alignment.horizontal, in: baseWidth)
            ?? alignment.horizontal.childOffset(childWidth: overlayWidth, in: baseWidth)

        // Calculate vertical position
        let verticalOffset =
            verticalGuidePlacement(
                of: overlay, size: overlaySize, alignment: alignment.vertical, in: baseHeight)
            ?? alignment.vertical.childOffset(childHeight: overlayHeight, in: baseHeight)

        // Composite the overlay onto the base, asking for a render at each step of a
        // run of the base whose field the overlay shows and whose frames turn it: the
        // composite punches the run there.
        //
        // Asked under this modifier's type as well as its identity, the key
        // `AnimationStore` gives a modifier's animations: the base renders at this
        // identity, so `.overlay { A }.overlay { B }` puts two overlays at one path,
        // and a wake is kept per token. Under the path alone the outer's request
        // replaced the inner's, and the inner's label held its field between the
        // outer run's steps. The outer's `Base` holds the inner's type, so the two
        // are never one type — unless each one's base is an `AnyView`, which draws
        // its content at its own identity too. The type is spelled by its metadata
        // pointer, which no two types share, not by a hash of it, which two could.
        let showingThrough = baseBuffer.runsShowingThrough(
            overlayBuffer, at: (x: horizontalOffset, y: verticalOffset))
        if !showingThrough.isEmpty {
            context.requestWake(
                token: "overlay-base-run-\(context.identity.path)-\(UInt(bitPattern: ObjectIdentifier(Self.self)))",
                forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
        }
        let composite = baseBuffer.compositedCarryingClaimsOverNothing(
            with: overlayBuffer, at: (x: horizontalOffset, y: verticalOffset),
            palette: context.environment.palette)

        // `composited` grows to fit an overlay that reaches past the base, and
        // a layer that resizes what it is laid over is a `ZStack` — the one
        // thing `.overlay` is not. Cut back to the base's box with the clamp
        // every container already uses on content that came back larger than
        // the space it was given; it keeps the free-floating layers (a badge
        // `.offset()` off the corner still hangs there) and trims the in-flow
        // hit and opacity regions to what survives.
        //
        // Per axis, and only where there is a frame to cut to: see the note on
        // `framedContext` above for the base that has no in-flow lines.
        return composite.clamped(
            toWidth: baseBuffer.width > 0 ? baseBuffer.width : composite.width,
            height: baseBuffer.height > 0 ? baseBuffer.height : composite.height)
    }
}

// MARK: - Layoutable

extension OverlayModifier: Layoutable {
    /// The base's size, flexibility and all: the overlay is laid out inside it
    /// and ``renderToBuffer(context:)`` cuts the composite back to it, so the
    /// overlay cannot contribute a cell.
    ///
    /// This answered `max(base, overlay)` on each axis until 2026-09-20, which
    /// is a `ZStack`'s rule rather than an overlay's: a badge wider than the
    /// thing it badges widened the view it was laid on, and with it every
    /// sibling in the enclosing stack.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let baseSize = measureChild(base, proposal: proposal, context: context)
        // Returned whole — `isNaturalSize` included, which this is entitled to
        // pass on because the answer IS the base's answer and consumes no other
        // measurement. The overlay is not measured at all here: it cannot move
        // the result, and a badge over a card is a subtree walked once per
        // enclosing measure pass for nothing.
        if baseSize.width > 0, baseSize.height > 0 { return baseSize }

        // No frame on at least one axis, so on that axis the overlay is what
        // there is to draw — the measure half of the two escapes in
        // `renderToBuffer(context:)`, and it has to agree with them.
        //
        // The same child identity the render uses, or the two passes resolve
        // different `@State` and measure a different view than they draw; and
        // the same frame on the axis that has one, or they disagree about how
        // much room the overlay was offered.
        var overlayContext = context.withChildIdentity(type: Overlay.self, index: 1)
        var overlayProposal = proposal
        if baseSize.width > 0 {
            overlayContext.availableWidth = baseSize.width
            overlayProposal.width = baseSize.width
        }
        if baseSize.height > 0 {
            overlayContext.availableHeight = baseSize.height
            overlayProposal.height = baseSize.height
        }
        let overlaySize = measureChild(
            overlay, proposal: overlayProposal, context: overlayContext)
        return ViewSize(
            width: baseSize.width > 0 ? baseSize.width : overlaySize.width,
            height: baseSize.height > 0 ? baseSize.height : overlaySize.height,
            isWidthFlexible: baseSize.width > 0
                ? baseSize.isWidthFlexible : overlaySize.isWidthFlexible,
            isHeightFlexible: baseSize.height > 0
                ? baseSize.isHeightFlexible : overlaySize.isHeightFlexible)
    }
}
