//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuWrappedRowClickTests.swift
//
//  A menu item too long for its menu wraps onto a second line, and the row is
//  the whole of what it draws: a click on either line runs it, and the pointer
//  over either line highlights it. The pop-up slices its column into one row
//  per LINE and mapped each row back to its item from the item's LAST line
//  only, so the first line of a wrapped item was dead — clicked, nothing ran;
//  hovered, nothing lit. Found by the Stress `menus` session, in a 36-column
//  terminal, where "Export Everything As One Long Archive" wraps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct ExportApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { ExportPage() }
            .mouseSupport(.full)
    }
}

private struct ExportPage: View {
    @State private var ran = "nothing"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ran \(ran)")
            Spacer()
            Menu("Export") {
                Button("Export PDF") { ran = "pdf" }
                Button("Export Everything As One Long Archive") { ran = "archive" }
            }
        }
        .selectionIndicatorStyle(.none)
    }
}

@MainActor
private final class Harness {
    let app = HeadlessApp(ExportApp(), width: 36, height: 16)
    private var now: Int64 = 0

    init() {
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    /// The column where `text` starts on line `y`.
    func column(of text: String, on y: Int) -> Int? {
        let line = app.screen[y].stripped
        return line.range(of: text).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    }

    func click(x: Int, y: Int) {
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        app.send(MouseEvent(button: .left, phase: .released, x: x, y: y))
        frame()
    }

    /// Opens the menu with a click on its label, and returns the line the long
    /// item starts on.
    func open() throws -> Int {
        let y = try #require(app.screen.firstIndex { $0.stripped.contains("Export ▾") })
        click(x: try #require(column(of: "Export", on: y)), y: y)
        let first = try #require(app.screen.firstIndex { $0.stripped.contains("Export Everything") })
        #expect(app.screen[first + 1].stripped.contains("Archive"), "precondition: the item wraps")
        return first
    }

    var ran: String? { app.screen.first { $0.stripped.contains("ran ") }?.stripped.trimmingCharacters(in: .whitespaces) }
}

@MainActor
@Suite("A menu item that wraps is one row on every line it draws")
struct MenuWrappedRowClickTests {
    @Test("A click on either line of a wrapped item runs it", arguments: [0, 1])
    func clickEitherLine(_ line: Int) throws {
        let harness = Harness()
        let first = try harness.open()
        let x = try #require(harness.column(of: "│ ", on: first)) + 2
        harness.click(x: x, y: first + line)
        #expect(harness.ran == "ran archive", "a click on line \(line) of the wrapped item: \(harness.ran ?? "-")")
    }

    @Test("The pointer over the first line of a wrapped item highlights it")
    func hoverFirstLine() throws {
        let harness = Harness()
        let first = try harness.open()
        let x = try #require(harness.column(of: "│ ", on: first)) + 2
        let unlit = harness.app.screen[first]
        harness.app.send(MouseEvent(button: .none, phase: .moved, x: x, y: first))
        harness.frame()
        #expect(harness.app.screen[first] != unlit, "the pointer over the first line lit nothing")
    }
}
