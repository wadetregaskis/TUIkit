//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContextMenuRowMemoTests.swift
//
//  A row carrying a `.contextMenu` is served from the row memo like any
//  other, and still opens, still shows the focus and still tears its section
//  down. The context menu declared a render side effect on EVERY frame — for
//  the section a just-closed menu may leave to tear down — so no row holding
//  one was ever stored: the Stress `menus` session composed all 6,318 of its
//  document rows over 300 steps and served none. Only the first closed frame
//  after a menu has a section to tear down; every other registers only what
//  a memo replays.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@Observable
@MainActor
private final class Documents {
    var ids: [Int] = Array(0..<6)
    var ran: [String] = []
}

private struct DocumentsApp: App {
    let documents: Documents?

    init() { documents = nil }

    init(_ documents: Documents) { self.documents = documents }

    var body: some Scene {
        WindowGroup {
            if let documents { DocumentsPage(documents: documents) }
        }
    }
}

private struct DocumentsPage: View {
    let documents: Documents

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "ran \(documents.ran.joined(separator: ","))")
            ForEach(documents.ids, id: \.self) { id in
                DocumentRow(id: id)
                    .contextMenu { Button("Rename #\(id)") { documents.ran.append("rename \(id)") } }
            }
        }
    }
}

/// A document that marks itself while its context menu's focus stop holds
/// the focus.
private struct DocumentRow: View, @MainActor Equatable {
    let id: Int
    @Environment(\.isFocused) private var isFocused

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    var body: some View {
        Text(verbatim: "\(isFocused ? "▸" : " ") document #\(id)")
    }
}

@MainActor
private final class Harness {
    let documents = Documents()
    let app: HeadlessApp<DocumentsApp>
    private var now: Int64 = 0

    init() {
        app = HeadlessApp(DocumentsApp(documents), width: 40, height: 16)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    func line(of text: String) -> Int? { app.screen.firstIndex { $0.stripped.contains(text) } }

    var served: Int { app.renderCache.rowWork.served }
}

@MainActor
@Suite("Rows carrying a context menu, served from the row memo")
struct ContextMenuRowMemoTests {
    @Test("A row with a context menu is served on a frame where nothing about it changed")
    func rowsAreServed() {
        let harness = Harness()
        let before = harness.served
        harness.frame()
        #expect(harness.served - before >= 5, "served \(harness.served - before) of six rows")
    }

    @Test("A right-click on a served row opens its menu, and choosing runs it")
    func rightClickOnAServedRow() throws {
        let harness = Harness()
        harness.frame()
        let y = try #require(harness.line(of: "document #3"))
        let text = harness.app.screen[y].stripped
        let x = try #require(text.range(of: "document").map { text.distance(from: text.startIndex, to: $0.lowerBound) })
        harness.app.send(MouseEvent(button: .right, phase: .pressed, x: x, y: y))
        harness.app.send(MouseEvent(button: .right, phase: .released, x: x, y: y))
        harness.frame()
        #expect(harness.shows("Rename #3"), "the menu did not open")
        harness.app.send(KeyEvent(key: .down))
        harness.frame()
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.documents.ran == ["rename 3"], "ran \(harness.documents.ran)")
        harness.frame()
        #expect(!harness.shows("Rename #3"), "the menu is still up")
    }

    @Test("Tab moves the focus mark between served rows, and Shift+F10 opens the focused row's menu")
    func keyboardOnServedRows() {
        let harness = Harness()
        #expect(harness.shows("▸ document #0"), "precondition: the first row has the focus")
        for id in 1...3 {
            harness.app.send(KeyEvent(key: .tab))
            harness.frame()
            harness.frame()
            #expect(harness.shows("▸ document #\(id)"), "Tab \(id): the mark is not on #\(id)")
            #expect(!harness.shows("▸ document #\(id - 1)"), "Tab \(id): the mark stayed on #\(id - 1)")
        }
        harness.app.send(KeyEvent(key: .f10, shift: true))
        harness.frame()
        #expect(harness.shows("Rename #3"), "Shift+F10 did not open the focused row's menu")
        harness.app.send(KeyEvent(key: .escape))
        harness.frame()
        harness.frame()
        #expect(!harness.shows("Rename #3"), "Escape left the menu up")
        #expect(harness.shows("▸ document #3"), "the focus did not come back to the row")
    }
}
