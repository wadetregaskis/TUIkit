//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Internal modifier that layers an overlay view on top of the base content.
///
/// The overlay is rendered on top of the base content. Both views are rendered
/// to their natural size, and the overlay is positioned according to the
/// specified alignment within the base content's bounds.
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
        // Render both contents — the overlay under an identity of its OWN.
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
        let overlayBuffer = TUIkit.renderToBuffer(
            overlay, context: context.withChildIdentity(type: Overlay.self, index: 1))

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
            return overlayBuffer
        }
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

        // Composite the overlay onto the base
        return baseBuffer.compositedResolvingOpacity(
            with: overlayBuffer, at: (x: horizontalOffset, y: verticalOffset),
            palette: context.environment.palette)
    }
}

// MARK: - Layoutable

extension OverlayModifier: Layoutable {
    /// `composited` grows to fit a wider/taller overlay (`max(base, offset +
    /// overlay)`), and the alignment offsets are clamped to `0...(base −
    /// overlay)`, so the result is `max(base, overlay)` on each axis — and fills
    /// an axis if either layer does.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let baseSize = measureChild(base, proposal: proposal, context: context)
        // The same child identity the render uses, or the two passes resolve
        // different `@State` and measure a different view than they draw.
        let overlaySize = measureChild(
            overlay, proposal: proposal,
            context: context.withChildIdentity(type: Overlay.self, index: 1))
        return ViewSize(
            width: max(baseSize.width, overlaySize.width),
            height: max(baseSize.height, overlaySize.height),
            isWidthFlexible: baseSize.isWidthFlexible || overlaySize.isWidthFlexible,
            isHeightFlexible: baseSize.isHeightFlexible || overlaySize.isHeightFlexible)
    }
}
