//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContextMenuRevealTests.swift
//
//  A `.contextMenu` makes the view it is on a focus stop, so that Shift+F10
//  can open it — and a focus stop in a scroll view is scrolled into view when
//  the focus lands on it, which is how the ScrollView finds it: by the hit
//  region the stop publishes under its focus id. The context menu's region
//  carried no id, so Tab walked the focus down a list of documents and off
//  the bottom of the scroll view, onto rows nobody could see; Shift+F10 then
//  opened the menu of a row that was not on the screen. Found by the Stress
//  `menus` session in a 13-line terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct DocumentsApp: App {
    let lazy: Bool

    init() { lazy = true }

    init(lazy: Bool) { self.lazy = lazy }

    var body: some Scene {
        WindowGroup { DocumentsPage(lazy: lazy) }
    }
}

private struct DocumentsPage: View {
    let lazy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                if lazy {
                    LazyVStack(alignment: .leading, spacing: 0) { rows }
                } else {
                    VStack(alignment: .leading, spacing: 0) { rows }
                }
            }
            .frame(height: 4)
            Spacer()
        }
    }

    private var rows: some View {
        ForEach(0..<20, id: \.self) { id in
            DocumentRow(id: id).contextMenu { Button("Rename #\(id)") {} }
        }
    }
}

/// A document that says when its context menu's focus stop holds the focus.
private struct DocumentRow: View {
    let id: Int
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(verbatim: "\(isFocused ? "▶" : " ") document #\(id)")
    }
}

@MainActor
@Suite("A context menu's focus stop in a scroll view")
struct ContextMenuRevealTests {
    @Test("Tab down a list of rows with context menus keeps the focused row on the screen", arguments: [true, false])
    func tabKeepsTheFocusedRowVisible(lazy: Bool) {
        let app = HeadlessApp(DocumentsApp(lazy: lazy), width: 30, height: 12)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        #expect(app.screen.contains { $0.stripped.contains("▶ document #0") }, "precondition: the first row has the focus")
        for tab in 1...8 {
            app.send(KeyEvent(key: .tab))
            frame()
            frame()
            #expect(
                app.screen.contains { $0.stripped.contains("▶ document #\(tab)") },
                "after \(tab) Tabs the focused row, #\(tab), is not on the screen: \(app.screen.map(\.stripped))")
        }
    }
}
