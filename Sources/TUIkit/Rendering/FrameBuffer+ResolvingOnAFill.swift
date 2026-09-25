//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+ResolvingOnAFill.swift
//
//  A painter that puts a field under content it did not draw is the backdrop of
//  every fade inside that content, and the only place both are known: what the
//  content is, and what is right behind it. Carried further, a fade meets the
//  painter's field as if it were the faded layer's own, and fades it with
//  everything else toward whatever is behind the painter — the page, a sibling,
//  the terminal's own field — which is `.background` fading at the alpha of a
//  label drawn on it. `Opacity as composition.md` §96; the one painter that
//  always did this is `.listRowBackground` (§22), and a row that REVERSES is
//  another (§86.1).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension FrameBuffer {

    /// Whether anything on this buffer fades in a way whose answer depends on what
    /// is behind the faded cells: a layer's opacity below 1, or a cycle of one; a
    /// field's own alpha below 1; a run whose frames owe a translucent field.
    ///
    /// An ink's own alpha is not one. It is paint on the cell's own field, and the
    /// blend reads that field off the cell wherever it resolves, so it comes out the
    /// same at a painter as at the root — and a palette with a translucent ink puts a
    /// claim on every label it draws, which a painter that spent them would walk for
    /// nothing.
    var hasFadeOnWhatIsBehind: Bool {
        Self.fadesOnWhatIsBehind(opacityRegions, runAlphas: animatedCells.lazy.map(\.alpha))
    }

    /// ``hasFadeOnWhatIsBehind`` asked of the claims and the runs' alphas a buffer would
    /// carry, before one is built to carry them.
    static func fadesOnWhatIsBehind(
        _ regions: [OpacityRegion], runAlphas: some Sequence<AnimatedRunAlpha?>
    ) -> Bool {
        regions.contains { $0.opacity < 1 || $0.fieldOpacity < 1 || $0.cycle != nil }
            || runAlphas.contains { alpha in
                alpha?.perFrame.contains { $0.contains { $0.field < 1 } } == true
            }
    }

    /// This buffer — content a painter has just painted an OPAQUE field under,
    /// every cell of it and every run's ground, as it paints — with its opacity
    /// spent against that field, and its regions cleared, where anything in it
    /// fades toward what is behind it (``hasFadeOnWhatIsBehind``); otherwise the
    /// buffer as it is, its claims travelling on.
    ///
    /// Painted first, so the blend reads each cell as the painter left it: a cell
    /// the content left bare is on the fill, one the content gave a field of its
    /// own is on that, a stated 49 the painter let through is the terminal's own
    /// (§95), and a reversed cell's unstated side is the fill the 7 exchanges.
    /// Then each fades toward the fill under it, which is what is behind the fade.
    ///
    /// Only for an opaque fill. A translucent one is not a backdrop yet (§22): the
    /// content's fades travel up with the fill's own claim and resolve with it.
    ///
    /// - Parameters:
    ///   - fill: The painter's field alone — spaces painted exactly as the content
    ///     was — where it differs from cell to cell (a ramp), or `nil` where it is
    ///     `surface` under every cell. Asked for only when there is a fade to spend.
    ///   - surface: The fill's colour, or for a ramp the ambient background.
    ///   - palette: Resolves the surface and SGR 39.
    ///   - buildingRuns: `false` for a caller that keeps only the LINES — a breathing
    ///     row spending its content against a colour of its breath that the frame
    ///     being drawn does not show — so every run is left out rather than faded and
    ///     thrown away (``resolvingOpacity(over:at:surface:palette:buildingRuns:)``).
    /// - Returns: The buffer, spent, or as it was.
    func resolvingOpacity(
        onOpaqueFill fill: () -> FrameBuffer?, surface: Color, palette: any Palette, buildingRuns: Bool = true
    ) -> Self {
        // Nothing asking what is behind it — nearly every painter, nearly every
        // frame, and every label of a palette with a translucent ink — and nothing
        // built.
        guard hasFadeOnWhatIsBehind else { return self }
        var content = self
        // A whole region is the identity over an opaque fill: painted, every cell
        // states a field, and at full strength a cell with a field of its own is the
        // source outright (§9.7). Dropped rather than walked, which is what the
        // resolution does of its own accord only where there is nothing behind.
        content.opacityRegions.removeAll { !$0.isTranslucent && $0.cycle == nil }
        // The terminal's own field as a fill is the terminal's page: `Color.default`
        // never measures, and the page, once reported, does (§80).
        var backdrop = surface
        if case .terminalDefault = surface.value { backdrop = .terminalBackground }
        return content.resolvingOpacity(
            over: fill() ?? Self(), at: (x: 0, y: 0), surface: backdrop, palette: palette,
            fillingStatedTerminalField: false, buildingRuns: buildingRuns)
    }

    /// This buffer — content a painter has just drawn in REVERSE VIDEO, its lines
    /// and its runs' grounds, restating `ESC[7;<ink>;<field>m` after every reset as
    /// it paints — with its opacity spent against the reversal, where anything in it
    /// fades toward what is behind it; otherwise the buffer as it is.
    ///
    /// A reversal is a painter as a fill is: the row it draws is behind every fade
    /// inside it. Its field is its INK, which is what the reversal shows under a
    /// cell that states nothing, so that is the backdrop. Spent AFTER the painting,
    /// over the finished lines, where the reversal is already in force under every
    /// cell: the blend reads each cell as the row draws it, exchanged (rule 6), and
    /// spells its answer in the exchanged colours, the 7 only where they have no
    /// spelling without it (§85). A painter that restated its reversal over the spent
    /// span afterwards would reverse those cells a second time, so this is the last
    /// thing the painter does to them (`Opacity as composition.md` §86.1).
    ///
    /// The runs it blends drop their ground, as every blended run does (§101): the tick
    /// then restates no reversal over frames that already carry theirs.
    ///
    /// - Parameters:
    ///   - ink: The reversal's ink — the colour it shows as its field.
    ///   - palette: Resolves SGR 39 and the terminal's own colours.
    /// - Returns: The buffer, spent, or as it was.
    func resolvingOpacity(onReversal ink: Color, palette: any Palette) -> Self {
        guard hasFadeOnWhatIsBehind else { return self }
        var content = self
        content.opacityRegions.removeAll { !$0.isTranslucent && $0.cycle == nil }
        // `Color.default` as an ink is the terminal's own foreground.
        var backdrop = ink
        if case .terminalDefault = ink.value { backdrop = .terminalForeground }
        return content.resolvingOpacity(over: Self(), surface: backdrop, palette: palette)
    }
}
