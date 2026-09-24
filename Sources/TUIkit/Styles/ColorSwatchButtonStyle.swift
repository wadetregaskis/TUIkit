//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorSwatchButtonStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Swatch Style

/// A button whose whole body is a 3-cell block of one colour, using its CENTRE
/// cell as the state indicator.
///
/// A swatch cannot show focus, hover or selection the way every other control
/// does — by re-colouring itself — because its colour is the content: recolour
/// it and it no longer says what it is there to say. So each state re-colours
/// the middle cell **in place** instead: a readable-contrast bullet marks a
/// selected swatch, pulses while the swatch holds keyboard focus, and shows dim
/// as a hover hint. Nothing shifts, and the swatch stays exactly its colour.
///
/// Used by ``ColorPicker``'s swatch and by ``GradientEditorPanel``'s stop
/// chips. (The built-in `.plain` style would prepend its own 2-cell pulsing
/// focus bullet — a second marker beside this one, and 2 cells of geometry that
/// appear and disappear with focus.)
///
/// `Equatable` for the reason given under ``ButtonStyle``, and this is the one
/// built-in style where the comparison has to be exact rather than vacuous: a
/// swatch is built fresh each frame from live binding data — ``ColorPicker``
/// hands it the selection, the gradient and tone-curve editors a per-chip
/// colour and whether that chip is the one in hand. `makeBody` forwards exactly
/// `color` and `isSelected` into ``_ColorSwatchCells``, so equal values do draw
/// the same swatch, and the synthesized `==` over them is what drops the cells
/// painted in the previous colour.
struct _ColorSwatchButtonStyle: ButtonStyle, Equatable {
    /// The colour on show — the swatch fill and the bullet's backdrop.
    let color: Color

    /// Whether this swatch is the one its group currently acts on. Swatches
    /// that stand alone (a single ``ColorPicker``'s) leave it false.
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        _ColorSwatchCells(
            color: color,
            isSelected: isSelected,
            isFocused: configuration.isFocused,
            isHovered: configuration.isHovered)
    }
}

// MARK: - Cells

/// The three cells of a swatch — a separate view so it can read the palette and
/// the pulse phase from the environment (`ButtonStyle.makeBody` composes views;
/// it has no render context of its own).
struct _ColorSwatchCells: View {
    let color: Color
    let isSelected: Bool
    let isFocused: Bool
    let isHovered: Bool

    @Environment(\.palette) private var palette

    /// The shared focus clock — asked for a CYCLE, and only while focused. The
    /// cycle is computed from the static formula, so the swatch can hand its
    /// bullet to the run loop; asking for the live phase instead would mark the
    /// frame as having consulted the clock and re-render the whole page on
    /// every tick, to repaint one cell.
    @Environment(\.selectionEmphasis) private var emphasis

    var body: some View {
        // Semantic colours have no components of their own, and both the fill
        // and the bullet's contrast need concrete ones.
        let fill = color.resolve(with: palette)
        let cycle = emphasis.cycle(isFocused)
        let bullet = indicator(on: fill, cycle: cycle)
        return HStack(spacing: 0) {
            Text("█").foregroundStyle(fill).background(fill)
            // The bullet's run is declared on the CENTRE cell, inside the fill
            // it is drawn on, so the `.background` records that fill as what the
            // run's cells sit on (`AnimatedCellRun.ground`). Declared on the
            // whole swatch, after the fill had painted, the run recorded nothing
            // beneath it. Composition, not a `Renderable` core, so the run is
            // declared rather than written onto a buffer — see
            // ``View/animatedCells(_:)``.
            Text(bullet == nil ? "█" : "●")
                .foregroundStyle(bullet ?? fill)
                .animatedCells(bulletRuns(on: fill, cycle: cycle))
                .background(fill)
            Text("█").foregroundStyle(fill).background(fill)
        }
    }

    /// The bullet's colour for the current state, or `nil` for no bullet — an
    /// unadorned swatch cell. Contrast comes from `Palette.readableText(on:)`,
    /// so the bullet reads on any colour the swatch can hold.
    private func indicator(on fill: Color, cycle: SelectionEmphasisCycle) -> Color? {
        if isFocused {
            // Focused: the bullet pulses whether or not this swatch is
            // selected — activating (Enter / Space / click) selects it.
            let (dim, bright) = pulseEndpoints(on: fill)
            return cycle.colorNow(dim: dim, bright: bright)
        }
        if isSelected { return palette.readableText(on: fill) }
        if isHovered {
            // A dim bullet: "you can pick me", without mimicking the selected
            // or focused look.
            return palette.readableText(on: fill).opacity(
                ViewConstants.focusBorderDim, over: fill)
        }
        return nil
    }

    /// The two ends of the focused bullet's breath. One definition: the drawn
    /// bullet and the run that replays it have to agree, or the loop's first
    /// tick jumps to a different colour than the render left.
    ///
    /// Both ends SPEND a translucent palette's alpha against the fill, through
    /// ``Color/breathEnds(dimmedTo:over:)`` (§29). `readableText(on:)` is a
    /// re-spelling — it ends in a contrast floor, which carries the palette's
    /// foreground or background alpha — while the dim end was a composite, so under
    /// a faded palette the run breathed between an opaque colour and a translucent
    /// one, and building its frames tripped the emitter. The fill is not a guess:
    /// it is the cell the bullet is drawn on. An opaque palette's bright end comes
    /// back untouched, spelling included (§29.1).
    private func pulseEndpoints(on fill: Color) -> (dim: Color, bright: Color) {
        palette.readableText(on: fill).breathEnds(dimmedTo: ViewConstants.focusPulseMin, over: fill)
    }

    /// The run that breathes the centre cell — declared on that cell, so at offset
    /// 0 — or none when the swatch is not focused (nothing moves) or the indicator
    /// style does not animate.
    private func bulletRuns(on fill: Color, cycle: SelectionEmphasisCycle) -> [AnimatedCellRun] {
        guard isFocused else { return [] }
        let (dim, bright) = pulseEndpoints(on: fill)
        // The bullet alone, and NO field in the frame. A spliced frame is painted
        // over the background the line already has (`patchingAnimatedCells`
        // restates it), and the resolver blends a run frame's bare cells over the
        // field recorded beneath the run (its ground, which the `.background(fill)`
        // around it records) — so the frame gets exactly what `.background(fill)`
        // drew: the fill's opaque spelling and its field claim, the same in every
        // frame (§29.2), or nothing at all for a fill at alpha 0. Stating `fill` here raw
        // put a translucent swatch's colour into the emitter whatever the palette;
        // stating its opaque spelling would have painted black behind a `.clear` one.
        return [cycle.run("●", dim: dim, bright: bright, offsetX: 0, offsetY: 0)].compactMap { $0 }
    }
}

// MARK: - Geometry

extension _ColorSwatchButtonStyle {
    /// The cell width of a swatch — wide enough to read as a block of colour,
    /// and odd so the state bullet has a true centre.
    static let width = 3
}
