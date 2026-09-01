//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowReorderFeedback.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Feedback Mode

/// What a `List` shows while a row is being dragged to a new position.
///
/// Reordering is offered by an editable `ForEach` — one carrying
/// ``ForEach/onMove(perform:)`` — and is driven by dragging a row
/// with the mouse. This chooses what the drag *looks* like; where the row ends
/// up is the same either way.
///
/// TUI-specific: SwiftUI's `List` has one built-in reorder animation and no
/// knob for it. A terminal has no translucency and no motion between frames, so
/// the trade-offs differ enough to be worth exposing — see
/// ``TUIkit/View/rowReorderFeedback(_:)``.
///
/// A release **off the rows** — past the control's edge, or on its border —
/// means different things in different modes, and the difference is whether the
/// rows ever left the control.
///
/// Under ``live`` and ``dimmed`` they never do: both draw the rows inside the
/// control for the whole gesture, so what is on screen already IS the order a
/// drop would produce. Carrying the pointer out does not carry the rows out,
/// and letting go **commits** to what is shown — which, having dragged past an
/// edge, is the top or the bottom.
///
/// Under ``cursor`` they do: a copy rides the pointer, above every other view,
/// and its slot is dropped the moment the pointer leaves the rows. Out there it
/// is holding the rows over nothing, so a release **abandons** the gesture —
/// the rows go back where they were picked up and the preview walks home.
/// Dragging out is how a user changes their mind, and there is no key for it,
/// because a drag has to stay carriable across the app and that needs the
/// navigation keys to keep navigating.
///
/// "Off the rows" means off the CONTROL, not off the shortened list the drag
/// leaves behind. Closing up behind the rows in hand ends the row area in as
/// many blank lines as they occupied, and those lines are still the control's:
/// pointing at one aims at the row nearest it, and the gap reopens there.
public enum RowReorderFeedback: String, Sendable, Hashable, CaseIterable {
    /// The rows reorder **as the cursor moves**, so the list always shows the
    /// result of dropping right here. The default.
    ///
    /// The cost is that `onMove` fires once per slot the row crosses rather
    /// than once for the whole gesture. Prefer ``dimmed`` or ``cursor`` when
    /// each move is expensive or separately undoable.
    ///
    /// A release off the rows adds no move at all: the data is already where
    /// the list says it is, so committing is simply not undoing it.
    case live

    /// The row leaves its place and reappears **dimmed** in the slot it would
    /// land in. The list closes up behind it and keeps its length, so what is on
    /// screen is exactly the order a drop would produce.
    ///
    /// The row stays drawn at the slot it was last over even while the pointer
    /// is off the rows — nothing else on screen is holding it, so it has to be
    /// somewhere — and a release out there commits to exactly that slot.
    ///
    /// `onMove` fires once, on release, wherever the release happens.
    case dimmed

    /// Like ``dimmed``, but the row rides the **pointer**: a copy of it floats
    /// at the cursor, above every other view, and the slot it would land in is
    /// simply an empty gap. So the gesture reads as carrying the row rather
    /// than as the list rearranging itself around an invisible hand.
    ///
    /// Drag out of the list and the gap disappears, so releasing there cancels
    /// the reorder. `onMove` fires once, on release, and not at all when
    /// released away from the rows.
    case cursor
}

// MARK: - Environment

private struct RowReorderFeedbackKey: EnvironmentKey {
    static let defaultValue = RowReorderFeedback.live
}

extension EnvironmentValues {
    /// What a drag-to-reorder gesture shows in this subtree.
    ///
    /// Set by ``TUIkit/View/rowReorderFeedback(_:)``. Lists and tables capture it each
    /// render onto their persistent handler, so the drag can consult it at
    /// event time, when the environment is out of reach.
    public var rowReorderFeedback: RowReorderFeedback {
        get { self[RowReorderFeedbackKey.self] }
        set { self[RowReorderFeedbackKey.self] = newValue }
    }
}

extension View {
    /// Chooses what a drag-to-reorder gesture shows in this subtree.
    ///
    /// Rows become draggable when their `ForEach` carries
    /// ``ForEach/onMove(perform:)``; this only changes the feedback
    /// while the drag is in flight.
    ///
    /// ```swift
    /// List {
    ///     ForEach(tracks) { Text($0.title) }
    ///         .onMove { from, to in tracks.move(fromOffsets: from, toOffset: to) }
    /// }
    /// .rowReorderFeedback(.dimmed)
    /// ```
    ///
    /// The default, ``RowReorderFeedback/live``, calls `onMove` once per slot
    /// the row crosses — the list *is* the preview. Where that is too
    /// expensive, or where each call lands separately on an undo stack,
    /// ``RowReorderFeedback/dimmed`` and ``RowReorderFeedback/cursor`` leave the
    /// data alone until the drop.
    ///
    /// - Parameter feedback: What to show while a row is being dragged.
    /// - Returns: A view whose lists reorder with that feedback.
    public func rowReorderFeedback(_ feedback: RowReorderFeedback) -> some View {
        environment(\.rowReorderFeedback, feedback)
    }
}
