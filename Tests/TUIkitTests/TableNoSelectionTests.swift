//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableNoSelectionTests.swift
//
//  `Table(_:columns:)` — SwiftUI's selection-free table.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A Table with no selection")
struct TableNoSelectionTests {

    private struct Row: Identifiable, Sendable {
        let id: String
        var name: String { id }
    }

    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var env = EnvironmentValues()
        let rows = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]

        init() {
            env.focusManager = FocusManager()
            env.scrollIndicatorStyle = .text
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        func render(selectable: Bool) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            let table: AnyView =
                selectable
                ? AnyView(
                    Table(rows.map(Row.init), selection: .constant(String?.none)) {
                        TableColumn<Row>("Name", value: \.name)
                    })
                : AnyView(
                    Table(rows.map(Row.init)) {
                        TableColumn<Row>("Name", value: \.name)
                    })
            var context = RenderContext(
                availableWidth: 22, availableHeight: 9, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(table.frame(width: 22, height: 7), context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        var handler: ItemListHandler<String>? {
            env.focusManager?.currentFocused as? ItemListHandler<String>
        }

        func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
            buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == label } ?? -1
        }

        func click(_ buffer: FrameBuffer, on label: String) {
            let y = rowY(buffer, label)
            tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: y))
            tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: 2, y: y))
        }
    }

    /// The rows are drawn and the table is there — the arrangement is the same
    /// one the selection initializer produces.
    @Test("It draws the same table")
    func drawsTheRows() {
        let fixture = Fixture()
        let plain = fixture.render(selectable: false).lines.map(\.stripped)
        let selectable = fixture.render(selectable: true).lines.map(\.stripped)
        #expect(plain == selectable, "\(plain)\nvs\n\(selectable)")
    }

    /// Still focusable, and still scrollable from the keyboard — which is the
    /// difference between this and `.disabled(true)`, and the reason it exists
    /// rather than being spelled that way.
    @Test("It still takes focus, so it can still be scrolled")
    func staysFocusable() {
        let fixture = Fixture()
        let buffer = fixture.render(selectable: false)
        fixture.click(buffer, on: "alpha")
        _ = fixture.render(selectable: false)
        #expect(fixture.handler != nil, "the table took focus")
        #expect(fixture.handler?.canBeFocused == true)
    }
}
