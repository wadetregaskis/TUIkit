//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RowReorderFeedback.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Feedback Mode

/// What a `List` shows while a row is being dragged to a new position.
///
/// Reordering is offered by an editable `ForEach` — one carrying
/// ``DynamicViewContent/onMove(perform:)`` — and is driven by dragging a row
/// with the mouse. This chooses what the drag *looks* like; where the row ends
/// up is the same either way.
///
/// TUI-specific: SwiftUI's `List` has one built-in reorder animation and no
/// knob for it. A terminal has no translucency and no motion between frames, so
/// the trade-offs differ enough to be worth exposing — see
/// ``TUIkit/View/rowReorderFeedback(_:)``.
public enum RowReorderFeedback: String, Sendable, Hashable, CaseIterable {
    /// The rows reorder **as the cursor moves**, so the list always shows the
    /// result of dropping right here. The default.
    ///
    /// The cost is that `onMove` fires once per slot the row crosses rather
    /// than once for the whole gesture. Prefer ``ghost`` or ``cursor`` when
    /// each move is expensive or separately undoable.
    case live

    /// A floating copy of the row rides the cursor while the list stays put;
    /// the row cursor marks where it would land.
    ///
    /// `onMove` fires once, on release.
    case ghost

    /// The row cursor alone marks where the row would land; nothing moves
    /// until the drop.
    ///
    /// The quietest option, and the cheapest to redraw. `onMove` fires once,
    /// on release.
    case cursor
}

// MARK: - Environment

private struct RowReorderFeedbackKey: EnvironmentKey {
    static let defaultValue = RowReorderFeedback.live
}

extension EnvironmentValues {
    /// What a drag-to-reorder gesture shows in this subtree.
    ///
    /// Set by ``TUIkit/View/rowReorderFeedback(_:)``. Lists capture it each
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
    /// ``DynamicViewContent/onMove(perform:)``; this only changes the feedback
    /// while the drag is in flight.
    ///
    /// ```swift
    /// List {
    ///     ForEach(tracks) { Text($0.title) }
    ///         .onMove { from, to in tracks.move(fromOffsets: from, toOffset: to) }
    /// }
    /// .rowReorderFeedback(.ghost)
    /// ```
    ///
    /// The default, ``RowReorderFeedback/live``, calls `onMove` once per slot
    /// the row crosses — the list *is* the preview. Where that is too
    /// expensive, or where each call lands separately on an undo stack,
    /// ``RowReorderFeedback/ghost`` and ``RowReorderFeedback/cursor`` leave the
    /// data alone until the drop.
    ///
    /// - Parameter feedback: What to show while a row is being dragged.
    /// - Returns: A view whose lists reorder with that feedback.
    public func rowReorderFeedback(_ feedback: RowReorderFeedback) -> some View {
        environment(\.rowReorderFeedback, feedback)
    }
}
