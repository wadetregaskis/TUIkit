//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityClaim.swift
//
//  Deriving an `OpacityRegion` from the colours a view actually painted with —
//  the half of a translucent paint that travels beside the bytes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Claiming cells for a translucent paint

extension OpacityRegion {
    /// The claim a rectangle of cells painted in `ink` on `field` needs, or `nil`
    /// when neither colour asked for less than full strength.
    ///
    /// A translucent paint is always two halves: the SGR bytes, which must state
    /// the colour's ``Color/opaqueSpelling`` because an emitter has no backdrop to
    /// composite against, and a region saying which cells owe a blend. Writing
    /// them apart is how the halves drift, and they had drifted three ways before
    /// this existed — `Color` as a view, `Text`'s uniform arm and its per-fragment
    /// arm each derived `Double(alpha) / 255` by hand.
    ///
    /// ```swift
    /// let line = ANSIRenderer.colorize(
    ///     glyphs, foreground: ink.opaqueSpelling, background: field?.opaqueSpelling)
    /// var buffer = FrameBuffer(lines: [line], width: width, lineWidths: [width])
    /// buffer.opacityRegions += OpacityRegion.claim(
    ///     width: width, height: 1, ink: ink, field: field).map { [$0] } ?? []
    /// ```
    ///
    /// ## Why `nil` and not a region at opacity 1
    ///
    /// Because "no claim" has to be cheaper than "a claim that says nothing".
    /// Every resolving path is gated on `opacityRegions.isEmpty`, and a page of
    /// opaque text that carried one identity region per row would walk the
    /// resolver for all of them to reach the answer it started with. The
    /// `Optional` puts that decision in the one place rather than at each caller.
    ///
    /// - Parameters:
    ///   - offsetX: The rectangle's left edge, in the buffer's own coordinates.
    ///   - offsetY: The rectangle's top edge.
    ///   - width: How many cells wide. A non-positive width claims nothing.
    ///   - height: How many rows tall. A non-positive height claims nothing.
    ///   - ink: The colour the glyphs were drawn in, if any. Its alpha becomes
    ///     ``OpacityRegion/inkOpacity``.
    ///   - field: The colour the cells' background was painted in, if any. Its
    ///     alpha becomes ``OpacityRegion/fieldOpacity``.
    /// - Returns: The region, or `nil` when there is nothing to resolve.
    public static func claim(
        offsetX: Int = 0, offsetY: Int = 0, width: Int, height: Int,
        ink: Color? = nil, field: Color? = nil
    ) -> OpacityRegion? {
        claim(
            offsetX: offsetX, offsetY: offsetY, width: width, height: height,
            inkAlpha: ink?.alpha ?? .max, fieldAlpha: field?.alpha ?? .max)
    }

    /// One alpha as an opacity factor.
    ///
    /// `Double(alpha) / 255`, in the one place that division belongs. Three sites
    /// were spelling it out, which is the drift this file's own note says it exists
    /// to prevent — and unlike ``claim(offsetX:offsetY:width:height:inkAlpha:fieldAlpha:)``
    /// this makes no judgement about whether an opaque value is worth a region, which
    /// is what the background ramp path needs: it states a rectangle per row whatever
    /// the alpha, so the claims stay index-aligned with the rows they were painted for.
    public static func opacity(of alpha: UInt8) -> Double {
        Double(alpha) / 255
    }

    /// The same claim, from the alphas themselves.
    ///
    /// For a caller that has a `UInt8` and no `Color` to put it in — a ramp, whose
    /// `AlphaShape` is already stated in alphas. Three sites were dividing by 255 by
    /// hand instead, which is exactly the drift this file's own note says it exists
    /// to prevent.
    ///
    /// - Parameters:
    ///   - offsetX: The rectangle's left edge, in the buffer's own coordinates.
    ///   - offsetY: The rectangle's top edge.
    ///   - width: How many cells wide. A non-positive width claims nothing.
    ///   - height: How many rows tall. A non-positive height claims nothing.
    ///   - inkAlpha: The glyphs' alpha; `.max` for a claim about the field alone.
    ///   - fieldAlpha: The cells' background alpha; `.max` for an ink-only claim.
    /// - Returns: The region, or `nil` when there is nothing to resolve.
    ///
    /// Neither alpha is defaulted, unlike the colours above. With defaults on both,
    /// `claim(width:height:)` matched this overload as readily as that one and the
    /// call was ambiguous — and stating both channels is the right shape here anyway,
    /// since a caller reaching for this one has already decided what each is.
    public static func claim(
        offsetX: Int = 0, offsetY: Int = 0, width: Int, height: Int,
        inkAlpha: UInt8, fieldAlpha: UInt8
    ) -> OpacityRegion? {
        // Asked of the ALPHAS before the geometry: a fully opaque paint is the
        // overwhelming common case and answering it is two loads and a compare,
        // where the geometry check is only worth doing for the few that got past.
        guard inkAlpha != .max || fieldAlpha != .max else { return nil }
        guard width > 0, height > 0 else { return nil }
        return OpacityRegion(
            offsetX: offsetX, offsetY: offsetY, width: width, height: height,
            // `opacity` — the LAYER channel — is 1: a translucent colour is a
            // statement about the paint, not about how present the view is. A
            // layer at 0.5 lets whatever is behind it contest the glyph by the ½
            // rule; ink at 0.5 is faint text that is definitely drawn. Folding
            // them would make `.foregroundStyle(.red.opacity(0.3))` vanish.
            opacity: 1,
            inkOpacity: Double(inkAlpha) / 255, fieldOpacity: Double(fieldAlpha) / 255)
    }
}

// MARK: - Collecting claims along a row

extension Array where Element == OpacityRegion {
    /// Appends `claim`, merging it into the last region already here where the two
    /// are adjacent on the same row and owe the same alphas.
    ///
    /// Three places assemble a row's claims a run at a time — `ClaimingRow` for a
    /// track or a dial, `Text.fragmentAlphaClaims` for a concatenation's fragments,
    /// and `PaintRenderer.styled(pieces:)` for those fragments under a ramp — and
    /// each had written this out. What they share is not the loop but the merge
    /// rule, so that is what lives here.
    ///
    /// Merging is worth doing rather than leaving to the resolver: a rim drawn a cell
    /// at a time is one colour for most of its length, and the resolver's cost is per
    /// region per covered row (see `OpacityResolution.foldedAlphas`). It is also what
    /// keeps a claim COUNT out of the contract — the number of rectangles a row needs
    /// is an implementation detail, and tests that pinned it were pinning that.
    ///
    /// `nil` appends nothing, so a caller can hand the result of
    /// ``OpacityRegion/claim(offsetX:offsetY:width:height:ink:field:)`` straight in.
    public mutating func appendCoalescing(_ claim: OpacityRegion?) {
        guard let claim else { return }
        if var last, last.offsetY == claim.offsetY, last.height == claim.height,
            last.offsetX + last.width == claim.offsetX,
            last.inkOpacity == claim.inkOpacity, last.fieldOpacity == claim.fieldOpacity,
            last.opacity == claim.opacity, last.cycle == nil, claim.cycle == nil
        {
            last.width += claim.width
            self[count - 1] = last
            return
        }
        append(claim)
    }
}
