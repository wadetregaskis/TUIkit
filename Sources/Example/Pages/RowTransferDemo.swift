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
///     The reorder is then app code too, because the drop is. Taken on the ROWS
///     (`ForEach.dropDestination(for:action:)`) rather than on the view, the
///     list still shows the landing slot and reports the index it opened at, so
///     a travelling row looks exactly like a reordering one.
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
    /// A selection binding per list — which is what gives each one a row
    /// CURSOR. Keyboard reordering picks up the cursor row, so a `List` with no
    /// selection has nothing to pick up: Ctrl-R and the Ctrl/⌥-arrow shortcuts
    /// were inert here purely for want of these two lines, while the `.onMove`
    /// demo above (which does bind a selection) responded to them.
    @State private var queueSelection: String?
    @State private var backlogSelection: String?

    var body: some View {
        DemoSection(L("page.list.transferSection")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("page.list.transferHint"))
                    .foregroundStyle(.palette.foregroundSecondary)
                // The same keyboard-reorder hint the `.onMove` demo carries —
                // the shortcuts are identical because they ARE the same
                // mechanism. A row's `.draggable` claims the press here, but a
                // press released without moving is a click and passes through
                // to the List, so clicking a row selects it exactly as it does
                // in the demo above.
                Text(L("page.rows.keyboardMoveHint"))
                    .foregroundStyle(.palette.foregroundTertiary)
                    .dim()
                HStack(alignment: .top, spacing: 3) {
                    list(.queue, title: L("page.list.transferQueue"))
                    list(.backlog, title: L("page.list.transferBacklog"))
                }
                ValueDisplayRow(L("page.list.transferLast"), status)
            }
        }
    }

    /// One of the two lists. Every row is a drag source, and the ROWS are the
    /// drop destination — `ForEach.dropDestination(for:action:)` rather than the
    /// `View` modifier of the same name, which is what makes the list open a
    /// landing slot under the pointer exactly as the reorder demo above does.
    /// A drop past the last row appends (and is the only way into an empty
    /// list); the index reports that as "before the row after the last one".
    @ViewBuilder private func list(_ side: Side, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).bold()
            List(selection: selection(side)) {
                ForEach(tracks(side)) { track in
                    HStack(spacing: 1) {
                        Text(track.name)
                        // The Spacer makes the WHOLE row width draggable rather
                        // than just its label — a row hugs its content, so
                        // without it a press to the right of a short name would
                        // fall through to the list. (Same reason as the
                        // drag-auto-scroll demo's folder rows.)
                        Spacer()
                    }
                    .draggable(TrackDrag(side: side, id: track.id))
                }
                .dropDestination(for: TrackDrag.self) { index, drops in
                    for drop in drops { perform(drop, to: side, at: index) }
                }
                // `.onMove` alongside `.draggable`, for the KEYBOARD. The two
                // cannot share a mouse gesture — `.draggable`'s region is inside
                // the row, so it claims the press and owns the rest — but
                // keyboard reordering never involves a press: Ctrl-R and the
                // Ctrl/⌥-arrow shortcuts go through the List's own key handling,
                // which is `.onMove`'s. Without this the rows here could only be
                // reordered with a mouse, while the `.onMove` demo above did it
                // from the keyboard, and nothing on screen explained why.
                //
                // Within-list only, which is what the keyboard can express: a
                // row still needs the mouse to change LISTS, because a list has
                // no way to name the other one.
                .onMove { source, destination in
                    var items = tracks(side)
                    items.move(fromOffsets: source, toOffset: destination)
                    setTracks(side, items)
                    // `self.` because this closure sits inside `list(_:title:)`,
                    // whose `title` parameter shadows the method of that name.
                    status = "\(L("page.list.transferReordered")) \(self.title(side))"
                }
            }
            .frame(width: 22, height: 7)
        }
    }

    // MARK: - The move

    private func tracks(_ side: Side) -> [Track] {
        side == .queue ? queue : backlog
    }

    private func selection(_ side: Side) -> Binding<String?> {
        side == .queue ? $queueSelection : $backlogSelection
    }

    private func setTracks(_ side: Side, _ tracks: [Track]) {
        if side == .queue { queue = tracks } else { backlog = tracks }
    }

    private func title(_ side: Side) -> String {
        side == .queue ? L("page.list.transferQueue") : L("page.list.transferBacklog")
    }

    /// Puts the dragged row at `index` in `side`'s list.
    ///
    /// `index` names the row the landing slot sits in front of, counted against
    /// the destination's DATA before anything moves — the same currency
    /// `onMove`'s `toOffset` takes. The dragged row is still counted there even
    /// though it is no longer DRAWN (a drag inside one list collapses its row,
    /// so the slot is the only gap), which is why the same-list case takes the
    /// row out first and then steps the index back past the hole it left; the
    /// cross-list case needs no such adjustment, the destination never having
    /// held the row.
    private func perform(_ drag: TrackDrag, to side: Side, at index: Int) {
        var source = tracks(drag.side)
        guard let from = source.firstIndex(where: { $0.id == drag.id }) else { return }
        let track = source.remove(at: from)

        if drag.side == side {
            let target = min(max(0, from < index ? index - 1 : index), source.count)
            guard target != from else { return }  // dropped back where it was
            source.insert(track, at: target)
            setTracks(side, source)
            status = "\(L("page.list.transferReordered")) \(title(side))"
        } else {
            setTracks(drag.side, source)
            var destination = tracks(side)
            destination.insert(track, at: min(max(0, index), destination.count))
            setTracks(side, destination)
            status = "\(track.name) → \(title(side))"
        }
    }
}
