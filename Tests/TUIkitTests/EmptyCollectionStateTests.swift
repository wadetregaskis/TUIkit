//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EmptyCollectionStateTests.swift
//
//  What a List and a Table leave behind when their last row goes away. Both
//  publish per-frame geometry that outlives the frame unless it is cleared, and
//  each twin was missing the line the other had.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A collection that empties leaves nothing behind")
struct EmptyCollectionStateTests {

    private final class Rows: @unchecked Sendable {
        var values: [Int]
        init(_ values: [Int]) { self.values = values }
    }

    /// Renders a collection populated, then empty, through one context — so the
    /// handler is the same object across both frames, which is the whole point:
    /// the stale geometry belongs to it, not to the buffer.
    private struct Row: Identifiable, Hashable {
        let id: Int
    }

    private func handlerAfterEmptying<Selection: Hashable>(
        _ type: Selection.Type,
        focusElsewhereFirst: Bool = false,
        _ build: @escaping ([Int]) -> AnyView
    ) -> ItemListHandler<Selection>? {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tui)

        func pass(_ values: [Int]) {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(build(values), context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        pass([1, 2, 3])
        pass([1, 2, 3])
        let populated = focusManager.activeSection?.focusables
            .compactMap { $0 as? ItemListHandler<Selection> }.first
        #expect(populated?.visibleRowBands.isEmpty == false, "precondition: bands were published")
        if focusElsewhereFirst {
            // Somewhere that is not the collection, so the last frame renders
            // it unfocused — which is the state its bookkeeping has to reach.
            let elsewhere = focusManager.activeSection?.focusables
                .first { ($0 as? ItemListHandler<Selection>) == nil }
            #expect(elsewhere != nil, "precondition: something else to focus")
            elsewhere.map { focusManager.focus(id: $0.focusID) }
        }
        pass([])
        return populated
    }

    @Test("An emptied List drops the bands its last populated frame published")
    func listClearsBands() {
        // Bands drive drop and reorder hit-testing. Kept, they resolve a drag
        // against rows that are no longer on screen. A List gets this for free
        // — its two branches share a publisher — so this is a guard on that
        // arrangement rather than a fix; `Table` is the one that had to be
        // told, below.
        let handler = handlerAfterEmptying(Int.self) { values in
            AnyView(
                List {
                    ForEach(values, id: \.self) { Text("row \($0)") }
                })
        }
        #expect(handler?.visibleRowBands.isEmpty == true, "the emptied List kept its bands")
    }

    @Test("An emptied Table forgets that it held the focus")
    func tableClearsFocusEngagement() {
        // `isFocusEngaged` is what makes the Bottom key carry the cursor rather
        // than merely scroll, and it must belong to the table the user is in.
        // All THREE of Table's populated paths set it; its empty branch did
        // not, so a table that emptied while focused stayed engaged — the
        // mirror of the band clearing List gets for free and Table states.
        let handler = handlerAfterEmptying(Int.self, focusElsewhereFirst: true) { values in
            AnyView(
                VStack {
                    Table(values.map(Row.init), selection: .constant(nil)) {
                        TableColumn("n") { (row: Row) in "\(row.id)" }
                    }
                    Button("elsewhere") {}
                })
        }
        #expect(handler?.isFocusEngaged == false, "the emptied Table stayed engaged")
    }

    @Test("An emptied Table drops the bands its last populated frame published")
    func tableClearsBands() {
        let handler = handlerAfterEmptying(Int.self) { values in
            AnyView(
                Table(values.map(Row.init), selection: .constant(nil)) {
                    TableColumn("n") { (row: Row) in "\(row.id)" }
                })
        }
        #expect(handler?.visibleRowBands.isEmpty == true, "the emptied Table kept its bands")
    }
}
