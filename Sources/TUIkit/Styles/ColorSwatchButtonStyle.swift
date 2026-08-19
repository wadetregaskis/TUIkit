//  🖥️ TUIKit — Terminal UI Kit for Swift
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
struct _ColorSwatchButtonStyle: ButtonStyle {
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
            Text(bullet == nil ? "█" : "●")
                .foregroundStyle(bullet ?? fill)
                .background(fill)
            Text("█").foregroundStyle(fill).background(fill)
        }
        // The bullet is the CENTRE cell, hence offset 1. Composition, not a
        // `Renderable` core, so the runs are declared rather than written onto
        // a buffer — see ``View/animatedCells(_:)``.
        .animatedCells(bulletRuns(on: fill, cycle: cycle))
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
    private func pulseEndpoints(on fill: Color) -> (dim: Color, bright: Color) {
        let readable = palette.readableText(on: fill)
        return (readable.opacity(ViewConstants.focusPulseMin, over: fill), readable)
    }

    /// The run that breathes the centre cell, or none when the swatch is not
    /// focused (nothing moves) or the indicator style does not animate.
    private func bulletRuns(on fill: Color, cycle: SelectionEmphasisCycle) -> [AnimatedCellRun] {
        guard isFocused else { return [] }
        let (dim, bright) = pulseEndpoints(on: fill)
        return [
            cycle.run(dim: dim, bright: bright, offsetX: 1, offsetY: 0) { colour in
                ANSIRenderer.colorize("●", foreground: colour, background: fill)
            }
        ].compactMap { $0 }
    }
}

// MARK: - Geometry

extension _ColorSwatchButtonStyle {
    /// The cell width of a swatch — wide enough to read as a block of colour,
    /// and odd so the state bullet has a true centre.
    static let width = 3
}
