//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionTallHeaderTests.swift
//
//  A lazy stack under a section's header at least as tall as the viewport,
//  with the viewport inside the header: the section relays the scroll window
//  moved below the header (`ScrollWindowRelay`), so the stack is handed an
//  offset a screen or more above its first row. The exact walk under 256 rows
//  drew no row there and named no drawn lines, where the uniform and anchored
//  windows draw row 0 as the margin row below the viewport.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// The header: ten lines, taller than the eight-line viewport.
private let tallHeader = (0..<10).map { "head \($0)" }.joined(separator: "\n")

/// A chat log under a ten-line header, glued to the bottom: `count` messages
/// of one and two lines, alternately, which is not uniform, so under 256 rows
/// the stack takes the exact walk. With `flat`, the same lines in one eager
/// column.
private struct TallHeaderChat: View {
    let count: Int
    let flat: Bool

    var body: some View {
        ScrollView {
            if flat {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tallHeader)
                    ForEach(0..<count, id: \.self) { message($0) }
                }
            } else {
                Section {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<count, id: \.self) { message($0) }
                    }
                } header: {
                    Text(tallHeader)
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 8)
    }

    private func message(_ index: Int) -> Text {
        Text((["msg \(index)"] + Array(repeating: "  more", count: index % 2)).joined(separator: "\n"))
    }
}

/// A button in a ten-line header, over forty rows that each hold a button —
/// one line each, or with `variable` one and two lines alternately (the exact
/// walk).
private struct TallHeaderButtons: View {
    let variable: Bool

    var body: some View {
        ScrollView {
            Section {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            Button("row \(index)") {}.focusID("row-\(index)")
                            if variable, index.isMultiple(of: 2) { Text("  more") }
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Button("top") {}.focusID("top")
                    Text((1..<10).map { "head \($0)" }.joined(separator: "\n"))
                }
            }
        }
        .frame(height: 8)
    }
}

@MainActor
@Suite("A lazy stack under a section header taller than the viewport")
struct SectionTallHeaderTests {
    @Test("Rows arriving while the viewport is inside a tall header are drawn when the view follows them")
    func followDrawsTheArrivingRows() {
        // Six messages, nine lines, arrive in one frame. That frame renders at
        // the offset the header alone gave — two, the viewport on "head 2" to
        // "head 9" — and the stack, handed that less the header's ten, drew
        // no row and named no drawn lines. So when the scroll view followed
        // the rows to the new end it could not see that the lines it moved to
        // were never drawn, and showed blank placeholders where the messages
        // belong, until something else drew again.
        func run(flat: Bool) -> (before: [String], after: [String]) {
            let (tui, focusManager) = (TUIContext(), FocusManager())
            _ = scrollFrame(TallHeaderChat(count: 0, flat: flat), tui: tui, focusManager: focusManager)
            let before = scrollFrame(
                TallHeaderChat(count: 0, flat: flat), tui: tui, focusManager: focusManager)
            let after = scrollFrame(
                TallHeaderChat(count: 6, flat: flat), tui: tui, focusManager: focusManager)
            return (before, after)
        }
        let lazy = run(flat: false)
        let flat = run(flat: true)
        #expect(
            lazy.before.first == "head 2" && lazy.before.last == "head 9",
            "precondition: glued inside the header: \(lazy.before)")
        #expect(flat.after.last == "  more", "precondition: the column follows the messages: \(flat.after)")
        #expect(lazy.after == flat.after, "\(lazy.after) vs \(flat.after)")
    }

    @Test(
        "Tab from a control in a header taller than the viewport goes to the first row's control",
        arguments: [false, true])
    func tabFromTheHeaderReachesTheFirstRow(variable: Bool) {
        // At the top the viewport is all header, and the stack is handed an
        // offset a screen above its first row. The uniform window draws row 0
        // as its margin row below the viewport, so its control joins the focus
        // ring; the exact walk drew none, and Tab went past the rows.
        let view = TallHeaderButtons(variable: variable)
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let screen = scrollFrame(view, tui: tui, focusManager: focusManager)
        _ = scrollFrame(view, tui: tui, focusManager: focusManager)
        #expect(
            focusManager.currentFocusedID == "top" && !screen.contains { $0.contains("row 0") },
            "precondition: the header's control is focused, the rows off screen: \(screen)")
        focusManager.focusNext()
        _ = scrollFrame(view, tui: tui, focusManager: focusManager)
        #expect(focusManager.currentFocusedID == "row-0")
    }
}
