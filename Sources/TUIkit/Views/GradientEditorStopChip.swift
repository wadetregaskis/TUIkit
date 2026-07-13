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

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("█").foregroundStyle(color).background(color)
            _StopChipCentreCell(
                color: color,
                isSelected: isSelected,
                isFocused: configuration.isFocused,
                isHovered: configuration.isHovered)
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

// MARK: - Live Drag Handle

/// Wires a stop chip as a LIVE reorder handle: dragging the chip moves its
/// stop through the strip immediately, following the cursor — no drop
/// target, no floating preview; the reflowing strip (and the live gradient
/// preview above it) IS the feedback. A plain click still selects, forwarded
/// to the button by ``_DragHandle``.
///
/// The cursor→slot mapping is pure geometry
/// (``GradientEditorPanel/dragSlot(forX:y:count:)``): the drag's events stay
/// localized to THIS chip's original region for the whole drag (the
/// dispatcher's press capture), so adding the chip's strip origin — fixed at
/// render time — yields strip-relative coordinates however much the strip
/// reorders underneath.
struct _StopChipDragHandle<Content: View>: View {
    let content: Content

    /// The chip's stop index at render time — the drag's coordinate anchor.
    let index: Int

    /// How many stops the strip holds (fixed for the duration of a drag).
    let stopCount: Int

    /// Grabbing a chip (first movement) selects its stop.
    let grab: () -> Void

    /// Moves the stop currently at `from` to `to` (and follows it with the
    /// selection).
    let moveStop: (_ from: Int, _ to: Int) -> Void

    var body: Never {
        fatalError("_StopChipDragHandle renders via Renderable")
    }
}

extension _StopChipDragHandle: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIkit.renderToBuffer(content, context: context)
        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else { return buffer }

        let anchor = GradientEditorPanel.chipStripOrigin(of: index, count: stopCount)
        let dragged = _DraggedStopBox()
        let grab = self.grab
        let moveStop = self.moveStop
        let index = self.index
        let stopCount = self.stopCount
        // Localized event → strip-relative point → nearest slot; move the
        // dragged stop there the moment it differs from where it is now.
        func follow(_ event: MouseEvent) {
            guard let current = dragged.current else { return }
            let slot = GradientEditorPanel.dragSlot(
                forX: anchor.x + event.x, y: anchor.y + event.y, count: stopCount)
            if slot != current {
                moveStop(current, slot)
                dragged.current = slot
            }
        }
        _DragHandle.install(
            on: &buffer,
            dispatcher: dispatcher,
            onDragBegin: { event in
                dragged.current = index
                grab()
                follow(event)
            },
            onDragMove: follow,
            onDragEnd: { _ in dragged.current = nil })
        return buffer
    }
}

/// Where the dragged stop currently sits, tracked across the drag's events
/// (which all arrive at the closure captured at press time).
private final class _DraggedStopBox {
    var current: Int?
}
