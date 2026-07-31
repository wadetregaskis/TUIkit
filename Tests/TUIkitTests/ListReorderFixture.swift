//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderFixture.swift
//
//  The shared harness for the List reorder suites: a live `List` with an
//  editable `ForEach`, driven end-to-end through the real mouse dispatcher the
//  way the run loop drives it. Shared rather than duplicated because the
//  reorder suites keep growing and each copy of a harness is a place the two
//  can disagree about what they are testing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A row-order holder plus the pieces to render it — a reference type so the
/// `onMove` closure (which fires during a later mouse dispatch, not during
/// the render that installed it) writes straight back into `items`.
/// `@MainActor`, so capturing it in the closure is race-free.
@MainActor
final class ListReorderFixture {
    var items: [String]
    let reorderable: Bool
    /// Rows selected before the gesture starts. Non-empty switches the list
    /// to multi-selection, which is what makes a drag pick up a block.
    var selection: Set<String> = []
    /// How many times `onMove` has fired — the difference between "the list
    /// is the preview" and "the drop is the move".
    private(set) var moves = 0
    /// Rows rendered taller than one line, by label. Variable row heights
    /// are what make the drag's row geometry go stale as rows shuffle.
    var tallRows: [String: Int] = [:]
    let tui = TUIContext()
    var env = EnvironmentValues()

    init(
        items: [String] = ["a", "b", "c", "d", "e"], reorderable: Bool = true,
        feedback: RowReorderFeedback = .live
    ) {
        self.items = items
        self.reorderable = reorderable
        env.focusManager = FocusManager()
        env.rowReorderFeedback = feedback
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
    }

    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

    /// Renders the current order and arms the dispatcher.
    @discardableResult
    func render() -> FrameBuffer {
        dispatcher.beginRenderPass()
        let tall = tallRows
        let base = ForEach(items, id: \.self) { item in
            Text(
                tall[item].map { lines in
                    Array(repeating: item, count: lines).joined(separator: "\n")
                } ?? item)
        }
        let forEach =
            reorderable
            ? base.onMove {
                self.moves += 1
                self.items.move(fromOffsets: $0, toOffset: $1)
            }
            : base
        let view: AnyView =
            selection.isEmpty
            ? AnyView(List(selection: .constant(String?.none)) { forEach }.frame(height: 9))
            : AnyView(
                List(
                    selection: Binding(
                        get: { self.selection }, set: { self.selection = $0 })
                ) { forEach }.frame(height: 9))
        var context = RenderContext(
            availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
        context.hasExplicitHeight = true
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// The list's own handler — the press focuses it, which is what makes
    /// it reachable from here.
    var handler: ItemListHandler<String>? {
        env.focusManager?.currentFocused as? ItemListHandler<String>
    }

    func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
        buffer.lines.firstIndex { $0.stripped.contains(label) } ?? -1
    }

    func drag(from source: String, to target: String) {
        let buffer = render()
        let ySource = rowY(buffer, source)
        let yTarget = rowY(buffer, target)
        dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: ySource))
        dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 2, y: yTarget))
        dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: yTarget))
        render()
    }
}
