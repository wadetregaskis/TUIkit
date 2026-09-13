//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExternalDropChromeTests.swift
//
//  Where a drag from ANOTHER view lands while the pointer is on the chrome
//  ABOVE a list's or a table's rows — the top border, a `Table`'s column
//  header — rather than on a row. Past the last row a drop appends; above the
//  first it does not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Incoming drop over the chrome above the rows", .serialized)
struct ExternalDropChromeTests {
    /// What the destination was handed, in order.
    private final class Log: @unchecked Sendable {
        var got: [(Int, [String])] = []
    }

    /// The line a single-letter row is drawn on.
    private static func rowLine(_ name: String, in buffer: FrameBuffer) -> Int? {
        buffer.lines.firstIndex { $0.stripped.filter(\.isLetter) == name }
    }

    /// A pointer coming at a table from above crosses its top border and its
    /// column header before it reaches a row, and both are lines ABOVE the band
    /// space: negative content lines, which no band covers. The hover read "no
    /// band" as "past the rows" and appended, so the gap jumped below the last
    /// row while the pointer sat on the header, and a release there handed the
    /// app the end of the data.
    ///
    /// Unscrolled on purpose. The auto-scroll retarget answers this line with
    /// the first row, but it only runs while auto-scroll is driving, and
    /// scrolling UP needs content above — so a table at rest, which is where a
    /// drag first meets one, never got that correction.
    @Test("A drag over a Table's header or top border lands before the first row")
    func tableHeaderLandsBeforeTheFirstRow() throws {
        let log = Log()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)

        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = Table(
                ["a", "b", "c"].map(TableReorderRow.init), selection: .constant(String?.none)
            ) {
                TableColumn<TableReorderRow>("Name", value: \.name)
            }
            .dropDestination(for: String.self) { index, values in log.got.append((index, values)) }
            .frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let atRest = render()
        let restA = try #require(Self.rowLine("a", in: atRest))
        let rowB = try #require(Self.rowLine("b", in: atRest))
        let headerLine = atRest.lines.firstIndex { $0.stripped.contains("Name") }
        let headerY = try #require(headerLine)
        #expect(headerY > 0 && headerY < restA, "the header is drawn between the border and the rows")

        // In over row b first, so the gap starts somewhere that is not the top.
        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 3, y: rowB)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        _ = render()

        // Then up onto the header, and on up onto the border above it.
        for chromeY in [headerY, 0] {
            tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
                button: .left, phase: .dragged, x: 3, y: chromeY)
            tui.dragAndDropSession.dragMoved()
            let hovering = render()
            let drawnA = Self.rowLine("a", in: hovering)
            let drawn = hovering.lines.map(\.stripped)
            #expect(
                drawnA == restA + 1,
                "pointer on line \(chromeY): the gap opens above row a, not below the last row: \(drawn)")
        }

        #expect(tui.dragAndDropSession.performDrop(), "the table took it")
        #expect(log.got.first?.0 == 0, "before the first row, not appended: \(log.got)")
    }

    /// The `List` twin, through the same hover: a bordered list's top border is
    /// the line above its first row. And the half of the rule that must NOT
    /// move with it: past the last row, on the bottom border, a drop still
    /// appends.
    @Test("A drag over a List's top border lands before the first row, and its bottom border still appends")
    func listTopBorderLandsBeforeTheFirstRow() throws {
        let log = Log()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)

        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = List(selection: .constant(String?.none)) {
                ForEach(["a", "b", "c"], id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { index, values in
                        log.got.append((index, values))
                    }
            }
            .frame(width: 20, height: 9)
            var context = RenderContext(
                availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
            context.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let atRest = render()
        let restA = try #require(Self.rowLine("a", in: atRest))
        let rowB = try #require(Self.rowLine("b", in: atRest))
        // The default list style is bordered, so there is a line above the rows.
        try #require(restA > 0, "a top border is drawn above the first row")

        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 2, y: rowB)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        _ = render()

        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 2, y: restA - 1)
        tui.dragAndDropSession.dragMoved()
        let hovering = render()
        let drawnA = Self.rowLine("a", in: hovering)
        let drawn = hovering.lines.map(\.stripped)
        #expect(drawnA == restA + 1, "the gap opens above row a, not below the last row: \(drawn)")
        #expect(tui.dragAndDropSession.performDrop(), "the list took it")
        #expect(log.got.first?.0 == 0, "before the first row, not appended: \(log.got)")

        // Below the rows is a different place, and there "append" is the answer.
        log.got.removeAll()
        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 2, y: atRest.height - 1)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        _ = render()
        #expect(tui.dragAndDropSession.performDrop(), "the list took it")
        #expect(log.got.first?.0 == 3, "past the last row still appends: \(log.got)")
    }
}
