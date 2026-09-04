//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableMultiLinePageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// PageDown on a multi-line `Table` moves by the rows on SCREEN.
///
/// The path used to publish the row count of the TAIL screenful instead — an
/// offset-independent number that once calibrated a maxOffset the height walk
/// now answers — so a page travelled by the wrong count wherever the rows at
/// the end were a different height from the rows in view. Uniform heights make
/// the two numbers coincide, which is why `TablePageDistanceTests` never saw it.
@MainActor
@Suite("A multi-line Table's page moves what is on screen")
struct TableMultiLinePageTests {
    private struct Row: Identifiable, Sendable {
        let id: String
        let text: String
    }

    @Test("PageDown moves the cursor by the rows drawn, not the tail screenful")
    func pageMovesTheDrawnRows() {
        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        env.scrollIndicatorStyle = .text
        // Rows 0-5 are one line; rows 6-11 wrap to three at this width.
        let rows = (0..<12).map { index in
            Row(id: "r\(index)", text: index < 6 ? "r\(index)" : "r\(index) aaaa bbbb cccc dddd eeee ffff gggg")
        }
        let ids = Set(rows.map(\.id))
        func render() -> FrameBuffer {
            let table = Table(rows, selection: .constant(String?.none)) {
                TableColumn<Row>("Name", value: \.text).lineLimit(3)
            }
            .frame(width: 22, height: 8)
            var context = RenderContext(
                availableWidth: 22, availableHeight: 12, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            fm.beginRenderPass()
            defer { fm.endRenderPass() }
            return renderToBuffer(table, context: context)
        }
        /// Row ids drawn, in order: a row's FIRST line carries its id, the
        /// wrapped remainder does not, so a row counts once.
        func drawnRows(_ buffer: FrameBuffer) -> [String] {
            buffer.lines.compactMap { line in
                let text = String(
                    line.stripped
                        .drop { !$0.isLetter && !$0.isNumber }
                        .prefix { $0.isLetter || $0.isNumber })
                return ids.contains(text) ? text : nil
            }
        }

        let onScreen = drawnRows(render())
        #expect(onScreen.count > 2 && onScreen.count < rows.count, "fixture: \(onScreen)")
        guard let handler = fm.currentFocused as? ItemListHandler<String> else {
            Issue.record("no handler")
            return
        }
        #expect(handler.focusedIndex == 0)
        #expect(handler.handleKeyEvent(KeyEvent(key: .pageDown)))
        #expect(
            handler.focusedIndex == onScreen.count,
            "a page is the \(onScreen.count) rows on screen; the tail screenful is fewer")
    }
}
