//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableReorderFixture.swift
//
//  A real `Table` with `onMove`, rendered and driven through the real mouse
//  dispatcher — the Table half of the pair with ``ListReorderFixture``.
//
//  Shared rather than private to one suite because the two views hold the same
//  reorder rules in two places and keep drifting apart, so a case worth writing
//  is usually worth writing on both sides — and it should not have to bring its
//  own scaffolding to do it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

struct TableReorderRow: Identifiable, Sendable {
    let id: String
    var name: String { id }
}

/// A row-order holder plus the pieces to render it. A reference type so the
/// `onMove` closure — which fires during a later mouse dispatch, not during
/// the render that installed it — writes straight back into `rows`.
@MainActor
final class TableReorderFixture {
    var rows: [String]
    let reorderable: Bool
    /// Rows selected before the gesture. Non-empty switches the table to
    /// multi-selection, which is what makes a drag pick up a block.
    var selection: Set<String> = []
    private(set) var moves = 0
    let tui = TUIContext()
    var env = EnvironmentValues()

    init(
        rows: [String] = ["a", "b", "c", "d", "e"], reorderable: Bool = true,
        feedback: RowReorderFeedback = .live,
        scrollbar: ScrollIndicatorVisibility = .automatic
    ) {
        self.rows = rows
        self.reorderable = reorderable
        env.focusManager = FocusManager()
        // The "▲/▼ N more" style, spelled out. Since #555 the visibility
        // and the style are separate questions, and the cases below read
        // row geometry off the screen: which line the indicator took, where
        // a slot sits. The `scrollbar:` argument answers the first question
        // — the cases that want a bar pass `.visible` AND ask for the bar
        // style, which is what the two together mean.
        env.scrollIndicatorStyle = scrollbar == .visible ? .scrollbar : .text
        env.rowReorderFeedback = feedback
        // Vertical only: a `Table` has no horizontal bar to configure.
        env.verticalScrollIndicatorVisibility = scrollbar
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
    }

    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

    @discardableResult
    func render() -> FrameBuffer {
        dispatcher.beginRenderPass()
        let move: (IndexSet, Int) -> Void = {
            self.moves += 1
            self.rows.move(fromOffsets: $0, toOffset: $1)
        }
        let table: AnyView
        if selection.isEmpty {
            let base = Table(rows.map(TableReorderRow.init), selection: .constant(String?.none)) {
                TableColumn<TableReorderRow>("Name", value: \.name)
            }
            table = AnyView(reorderable ? AnyView(base.onMove(move)) : AnyView(base))
        } else {
            let base = Table(
                rows.map(TableReorderRow.init),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 })
            ) {
                TableColumn<TableReorderRow>("Name", value: \.name)
            }
            table = AnyView(reorderable ? AnyView(base.onMove(move)) : AnyView(base))
        }
        let view = table.frame(width: 20, height: 9)
        var context = RenderContext(
            availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
        context.hasExplicitHeight = true
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// The table's own handler — the press focuses it, which is what makes
    /// it reachable from here.
    var handler: ItemListHandler<String>? {
        env.focusManager?.currentFocused as? ItemListHandler<String>
    }

    /// The screen line of the row whose text IS `label`, matched on its
    /// letters alone.
    ///
    /// Not "contains": a Table draws a column HEADER ("Name"), and matching
    /// by containment pressed that instead of row "a". And not the whole
    /// stripped line either: the scrollbar path appends a bar cell (▲/█/▼) to
    /// every row, which is why the same test passed without a bar and missed
    /// every row with one.
    func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
        buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == label } ?? -1
    }

    /// Press on `source`'s line, drag to `target`'s, release there — with a
    /// render between each step, as the run loop has.
    func drag(from source: String, to target: String) {
        let buffer = render()
        let ySource = rowY(buffer, source)
        let yTarget = rowY(buffer, target)
        dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        render()
        dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        render()
        dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
        render()
    }
}
