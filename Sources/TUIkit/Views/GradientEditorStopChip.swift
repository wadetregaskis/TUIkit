//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GradientEditorStopChip.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Stop Chip Style

/// ``GradientEditorPanel``'s stop-strip button style: the whole chip is a
/// 3-cell swatch of its stop's colour, and the CENTRE cell doubles as the
/// state indicator — a readable-contrast bullet on the stop being edited,
/// pulsing while the chip holds keyboard focus, dim as a hover hint. Every
/// state re-colours that one cell in place: no reserved indicator column, no
/// focus prefix, so chip geometry never changes. (The built-in `.plain` style
/// would prepend its 2-cell pulsing focus bullet — a second marker beside the
/// selection's.)
struct _StopChipStyle: ButtonStyle {
    /// The stop's colour — the swatch fill and the bullet's backdrop.
    let color: Color

    /// Whether this chip's stop is the one the panel below is editing.
    let isSelected: Bool

    /// Whether a dragged stop currently hovers this chip (release moves it
    /// here).
    let isDropTarget: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("█").foregroundStyle(color).background(color)
            _StopChipCentreCell(
                color: color,
                isSelected: isSelected,
                isFocused: configuration.isFocused,
                isHovered: configuration.isHovered,
                isDropTarget: isDropTarget)
            Text("█").foregroundStyle(color).background(color)
        }
    }
}

// MARK: - Centre Cell

/// The centre cell of a stop chip — a separate view so it can read the pulse
/// phase and palette from the environment (`ButtonStyle.makeBody` composes
/// views; it has no render context of its own).
struct _StopChipCentreCell: View {
    let color: Color
    let isSelected: Bool
    let isFocused: Bool
    let isHovered: Bool
    let isDropTarget: Bool

    @Environment(\.palette) private var palette

    /// Volatile: reading it also keeps the cell out of any render memo, so
    /// the focus pulse animates.
    @Environment(\.pulsePhase) private var pulsePhase

    var body: some View {
        Text(indicator == nil ? "█" : "●")
            .foregroundStyle(indicator ?? color)
            .background(color)
    }

    /// The bullet's colour for the current state, or `nil` for no bullet —
    /// an unadorned swatch cell. Contrast comes from
    /// `Palette.readableText(on:)`, so the bullet reads on any stop colour.
    private var indicator: Color? {
        let readable = palette.readableText(on: color)
        if isDropTarget {
            // A dragged stop hovers this chip: releasing moves it here. A
            // dim bullet — the drag is what the eye is on; the cue only
            // needs to say WHERE. Wins over the focus pulse: mid-drag, the
            // drop position outranks where keyboard focus happens to sit.
            return readable.opacity(ViewConstants.focusBorderDim, over: color)
        }
        if isFocused {
            // Focused: the bullet pulses whether or not this stop is
            // selected — activating (Enter / Space / click) selects it.
            let dim = readable.opacity(ViewConstants.focusPulseMin, over: color)
            return Color.lerp(dim, readable, phase: pulsePhase)
        }
        if isSelected { return readable }
        if isHovered {
            // A dim bullet: "you can pick me", without mimicking the
            // selected or focused look.
            return readable.opacity(ViewConstants.focusBorderDim, over: color)
        }
        return nil
    }
}
