//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RowTransferDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Rows that both reorder *and* travel: two lists whose rows can be dropped on
/// each other's rows to change the order, or on the other list to change which
/// list they are in.
///
/// This is the other half of the story the `.onMove` section tells. TUIkit has
/// two separate mechanisms, and the difference is worth knowing:
///
///   - **`.onMove` on a `ForEach`** is the built-in reorder. The `List` owns the
///     gesture, so it can show the drop slot (``RowReorderFeedback``) and the
///     app only implements the move. It knows nothing about what a row *is*,
///     which is exactly why the row cannot leave: there is no value to hand over.
///   - **`.draggable` + `.dropDestination`** carries a value the app defines, so
///     a row can go anywhere that accepts that value — including another list.
///     The reorder is then app code too, because the drop is.
///
/// A row cannot use both at once: whichever region claims the press owns the
/// rest of the gesture, and `.draggable`'s sits inside the row, so it wins. That
/// is why this section is a separate demo rather than the one above with extra
/// modifiers.
struct RowTransferDemoSection: View {
    /// Which list a row is in — and, on a drag, which list it came from.
    private enum Side {
        case queue, backlog
    }

    private struct Track: Identifiable, Hashable {
        let id: String
        var name: String { "🎵 " + id }
    }

    /// The dragged row. It names its origin as well as itself, so a drop can
    /// tell a reorder (same list) from a transfer (the other one) without
    /// searching both lists for the row.
    private struct TrackDrag {
        let side: Side
        let id: String
    }

    @State private var queue = ["Aurora", "Bloom", "Cinder"].map(Track.init)
    @State private var backlog = ["Drift", "Ember", "Fathom", "Glass"].map(Track.init)
    @State private var status = "—"

    var body: some View {
        DemoSection(L("page.list.transferSection")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("page.list.transferHint"))
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 3) {
                    list(.queue, title: L("page.list.transferQueue"))
                    list(.backlog, title: L("page.list.transferBacklog"))
                }
                ValueDisplayRow(L("page.list.transferLast"), status)
            }
        }
    }

    /// One of the two lists. Every row is a drag source and a drop target; the
    /// list around them takes the drops that land past the last row, which is
    /// how a row is appended (and the only way into an empty list).
    @ViewBuilder private func list(_ side: Side, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).bold()
            List {
                ForEach(tracks(side)) { track in
                    HStack(spacing: 1) {
                        Text(track.name)
                        // The Spacer makes the WHOLE row width a drop target
                        // rather than just its label — a row hugs its content,
                        // so without it a drop to the right of a short name
                        // would fall through to the list below. (Same reason
                        // as the drag-auto-scroll demo's folder rows.)
                        Spacer()
                    }
                    .draggable(TrackDrag(side: side, id: track.id))
                    .dropDestination(for: TrackDrag.self) { drops, _ in
                        for drop in drops { perform(drop, to: side, before: track.id) }
                        return true
                    }
                }
            }
            .frame(width: 22, height: 7)
            .dropDestination(for: TrackDrag.self) { drops, _ in
                for drop in drops { perform(drop, to: side, before: nil) }
                return true
            }
        }
    }

    // MARK: - The move

    private func tracks(_ side: Side) -> [Track] {
        side == .queue ? queue : backlog
    }

    private func setTracks(_ side: Side, _ tracks: [Track]) {
        if side == .queue { queue = tracks } else { backlog = tracks }
    }

    private func title(_ side: Side) -> String {
        side == .queue ? L("page.list.transferQueue") : L("page.list.transferBacklog")
    }

    /// Puts the dragged row in front of `targetID` in `side`'s list — or at the
    /// end when there is no target row (a drop past the last one).
    ///
    /// The row is removed BEFORE the insertion index is looked up, so a move
    /// down inside one list needs no index adjustment: the index of the row it
    /// was dropped on is already measured against the list without it.
    private func perform(_ drag: TrackDrag, to side: Side, before targetID: String?) {
        // Dropping a row on itself means "leave it alone". Worth saying out
        // loud: it would otherwise read as "insert before a row that is no
        // longer there", and land at the end of the list.
        guard drag.id != targetID else { return }

        var source = tracks(drag.side)
        guard let index = source.firstIndex(where: { $0.id == drag.id }) else { return }
        let track = source.remove(at: index)

        if drag.side == side {
            source.insert(track, at: source.firstIndex { $0.id == targetID } ?? source.count)
            setTracks(side, source)
            status = "\(L("page.list.transferReordered")) \(title(side))"
        } else {
            setTracks(drag.side, source)
            var destination = tracks(side)
            destination.insert(
                track, at: destination.firstIndex { $0.id == targetID } ?? destination.count)
            setTracks(side, destination)
            status = "\(track.name) → \(title(side))"
        }
    }
}
