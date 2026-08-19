//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorSwatchButtonStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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

    /// Volatile: reading it also keeps the cell out of any render memo, so the
    /// focus pulse animates. Read ONLY while focused — an ungated read would
    /// keep every swatch on the page redrawing forever.
    @Environment(\.pulsePhase) private var pulsePhase

    var body: some View {
        // Semantic colours have no components of their own, and both the fill
        // and the bullet's contrast need concrete ones.
        let fill = color.resolve(with: palette)
        let bullet = indicator(on: fill)
        return HStack(spacing: 0) {
            Text("█").foregroundStyle(fill).background(fill)
            Text(bullet == nil ? "█" : "●")
                .foregroundStyle(bullet ?? fill)
                .background(fill)
            Text("█").foregroundStyle(fill).background(fill)
        }
    }

    /// The bullet's colour for the current state, or `nil` for no bullet — an
    /// unadorned swatch cell. Contrast comes from `Palette.readableText(on:)`,
    /// so the bullet reads on any colour the swatch can hold.
    private func indicator(on fill: Color) -> Color? {
        let readable = palette.readableText(on: fill)
        if isFocused {
            // Focused: the bullet pulses whether or not this swatch is
            // selected — activating (Enter / Space / click) selects it.
            let dim = readable.opacity(ViewConstants.focusPulseMin, over: fill)
            return Color.lerp(dim, readable, phase: pulsePhase)
        }
        if isSelected { return readable }
        if isHovered {
            // A dim bullet: "you can pick me", without mimicking the selected
            // or focused look.
            return readable.opacity(ViewConstants.focusBorderDim, over: fill)
        }
        return nil
    }
}

// MARK: - Geometry

extension _ColorSwatchButtonStyle {
    /// The cell width of a swatch — wide enough to read as a block of colour,
    /// and odd so the state bullet has a true centre.
    static let width = 3
}
