//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// Columns of viewport when the list is to be wrapped in a horizontal
    /// `ScrollView`, or `nil` for the plain list every other suite renders.
    /// The list is pinned 20 columns wide inside it, so scrolling right really
    /// cuts columns off its left edge — which is what puts a non-zero
    /// `HitTestRegion.leftClip` on its region.
    let horizontalViewport: Int?
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
        feedback: RowReorderFeedback = .live, horizontalViewport: Int? = nil
    ) {
        self.items = items
        self.reorderable = reorderable
        self.horizontalViewport = horizontalViewport
        env.focusManager = FocusManager()
        env.rowReorderFeedback = feedback
        // The "▲/▼ N more" style, spelled out: what these cases read off the
        // screen is row geometry — where the slot sits, which rows are blank —
        // and the default bar (#555) would put a track cell in every line's
        // last column. The reorder behaviour under test is the same either way.
        env.scrollIndicatorStyle = .text
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
    }

    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

    /// Scrolls the enclosing horizontal scroller right by `columns`, so that
    /// many of the list's own leftmost columns are clipped away. Only
    /// meaningful for a fixture built with a `horizontalViewport`.
    ///
    /// The render memo keys on the view VALUE, which a scroll does not change,
    /// so the cache is dropped: without that the next frame serves the
    /// unscrolled buffer and its unclipped regions.
    func scrollHorizontally(by columns: Int) {
        let scroller = env.focusManager?.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        scroller?.horizontal.scrollOffset = columns
        tui.renderCache.clearAll()
    }

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
        let list: AnyView =
            selection.isEmpty
            ? AnyView(List(selection: .constant(String?.none)) { forEach }.frame(height: 9))
            : AnyView(
                List(
                    selection: Binding(
                        get: { self.selection }, set: { self.selection = $0 })
                ) { forEach }.frame(height: 9))
        // 20 columns wide either way: on its own the list fills the context,
        // and inside the scroller the frame pins it, leaving
        // `20 - horizontalViewport` columns to scroll.
        let view: AnyView =
            horizontalViewport == nil
            ? list : AnyView(ScrollView([.horizontal]) { list.frame(width: 20) })
        var context = RenderContext(
            availableWidth: horizontalViewport ?? 20, availableHeight: 11,
            environment: env, tuiContext: tui)
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
