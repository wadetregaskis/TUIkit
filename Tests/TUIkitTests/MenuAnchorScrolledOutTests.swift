//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuAnchorScrolledOutTests.swift
//
//  A menu stays up while the content under it changes: a document arrives
//  above the one whose context menu is open, a log that follows its end grows.
//  Its anchor can leave the scroll view it sits in while it is open, and the
//  menu went with it but stayed OPEN: unseen, it kept the keyboard or came
//  back when its row did and took it again — a Return meant for one menu ran
//  a row of another. Found by the Stress `menus` session.
//
//  An eager stack draws every row, and the scroll view culls whatever falls
//  outside its viewport — the open menu's pop-up with its anchor, while the
//  row that presents it, still drawn, kept the menu's section and its keys.
//  The pop-up is a window over the page rather than a piece of what the view
//  scrolls, so it stays on the screen, at the edge its anchor left by, and
//  works.
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
    var ids: [Int] = Array(0..<40)
    var ran: [String] = []
}

private struct DocumentsApp: App {
    let documents: Documents?
    let lazy: Bool
    let followsEnd: Bool

    init() {
        documents = nil
        lazy = true
        followsEnd = false
    }

    init(_ documents: Documents, lazy: Bool, followsEnd: Bool = false) {
        self.documents = documents
        self.lazy = lazy
        self.followsEnd = followsEnd
    }

    var body: some Scene {
        WindowGroup {
            if let documents { DocumentsPage(documents: documents, lazy: lazy, followsEnd: followsEnd) }
        }
    }
}

private struct DocumentsPage: View {
    let documents: Documents
    let lazy: Bool
    let followsEnd: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "ran \(documents.ran.joined(separator: ","))")
            ScrollView {
                if lazy {
                    LazyVStack(alignment: .leading, spacing: 0) { rows }
                } else {
                    VStack(alignment: .leading, spacing: 0) { rows }
                }
            }
            .defaultScrollAnchor(followsEnd ? .bottom : .top)
            .frame(height: 8)
            Text("below the list")
        }
    }

    private var rows: some View {
        ForEach(documents.ids, id: \.self) { id in
            Text(verbatim: "document #\(id)")
                .contextMenu {
                    Button("Rename #\(id)") { documents.ran.append("rename \(id)") }
                    Button("Delete #\(id)") { documents.ran.append("delete \(id)") }
                }
        }
    }
}

@MainActor
private final class Harness {
    let documents = Documents()
    let app: HeadlessApp<DocumentsApp>
    private var now: Int64 = 0

    init(lazy: Bool, followsEnd: Bool = false) {
        app = HeadlessApp(DocumentsApp(documents, lazy: lazy, followsEnd: followsEnd), width: 40, height: 16)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    /// Opens the context menu of the document on the list's last line (or its
    /// first) with a right-click, and returns its number.
    func openMenu(onFirstRow: Bool) throws -> Int {
        let lines = app.screen.map(\.stripped)
        let y = try #require(
            onFirstRow ? lines.firstIndex { $0.contains("document #") } : lines.lastIndex { $0.contains("document #") })
        let id = try #require(Int(lines[y].split(separator: "#")[1].prefix { $0.isNumber }))
        app.send(MouseEvent(button: .right, phase: .pressed, x: 2, y: y))
        app.send(MouseEvent(button: .right, phase: .released, x: 2, y: y))
        frame()
        #expect(shows("Rename #\(id)"), "precondition: the menu opened")
        return id
    }

    /// Down to the first row and Return.
    func chooseFirst() {
        app.send(KeyEvent(key: .down))
        frame()
        app.send(KeyEvent(key: .enter))
        frame()
    }
}

@MainActor
@Suite("A menu whose anchor scrolls out of view while it is open")
struct MenuAnchorScrolledOutTests {
    @Test("In an eager stack, the menu of a row pushed below the viewport stays on the screen, and works")
    func eagerRowPushedBelow() throws {
        let harness = Harness(lazy: false)
        let id = try harness.openMenu(onFirstRow: false)
        harness.documents.ids.insert(contentsOf: 100..<103, at: 0)
        harness.frame()
        #expect(!harness.shows("document #\(id)"), "precondition: the anchor left the list")
        #expect(harness.shows("Rename #\(id)"), "the open menu went from the screen with its anchor")
        harness.chooseFirst()
        #expect(harness.documents.ran == ["rename \(id)"], "Down and Return in the menu ran \(harness.documents.ran)")
        #expect(!harness.shows("Rename #"), "the menu is still up after choosing")
    }

    @Test("In an eager stack following its end, the menu of a row pushed above the viewport stays on the screen")
    func eagerRowPushedAbove() throws {
        let harness = Harness(lazy: false, followsEnd: true)
        let id = try harness.openMenu(onFirstRow: true)
        harness.documents.ids.append(contentsOf: 200..<212)
        harness.frame()
        harness.frame()
        #expect(!harness.shows("document #\(id)"), "precondition: the anchor left the list")
        #expect(harness.shows("Rename #\(id)"), "the open menu went from the screen with its anchor")
        harness.app.send(KeyEvent(key: .escape))
        harness.frame()
        #expect(!harness.shows("Rename #"), "Escape left the menu up")
    }
}

// MARK: - What is NOT pinned

/// Thirty rows, each with help text, four lines apart — room for its
/// tooltip's three-line panel and a blank, so no panel covers another row —
/// in an eight-line scroll view, and every tooltip shown
/// (`.tooltips(.always)`).
private struct TooltipRowsApp: App {
    let followsEnd: Bool

    init() { followsEnd = false }
    init(followsEnd: Bool) { self.followsEnd = followsEnd }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<30, id: \.self) { row in
                        Text(verbatim: "row \(row)").help("tip \(row)")
                    }
                }
            }
            .defaultScrollAnchor(followsEnd ? .bottom : .top)
            .frame(height: 8)
            .tooltips(.always)
        }
    }
}

@MainActor
@Suite("A pop-up that holds no input goes with its anchor")
struct UnheldPopUpScrolledOutTests {
    /// Only a surface that holds the input is pinned when its anchor scrolls
    /// away. A tooltip holds none, so the tooltip of a row outside the viewport
    /// is culled with its row. Pinned, every hidden row's panel was stacked at
    /// the viewport's edge, over the rows that ARE on the screen.
    ///
    /// At the start, rows 0 and 1 are in view. At the end, rows 28 and 29 are,
    /// and the bottom line of 27's panel: a panel any of which is in the
    /// viewport is drawn whole, as it always was. Pinned, the hidden rows'
    /// panels showed "tip 29" at the bottom edge, or "tip 26" at the top.
    @Test("A tooltip whose row is out of the viewport is not drawn", arguments: [false, true])
    func tooltipOfAnUnseenRow(followsEnd: Bool) {
        let app = HeadlessApp(TooltipRowsApp(followsEnd: followsEnd), width: 40, height: 16)
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        let lines = app.screen.map(\.stripped)
        let rows = Set(lines.flatMap { $0.matches(of: /row (\d+)/).compactMap { Int($0.output.1) } })
        let inView = followsEnd ? 27..<30 : 0..<2
        #expect(rows.isSubset(of: Set(inView)), "precondition: the rows in view: \(lines)")
        let tips = Set(lines.flatMap { $0.matches(of: /tip (\d+)/).compactMap { Int($0.output.1) } })
        #expect(!tips.isEmpty, "precondition: the tooltips are drawn: \(lines)")
        let unseen = tips.filter { !inView.contains($0) }.sorted()
        #expect(unseen.isEmpty, "the tooltips of rows \(unseen), out of the viewport, are drawn: \(lines)")
    }
}
