//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackdropMemoTests.swift
//
//  The page beneath a sheet, and a navigation stack's covered root, render as
//  a BACKDROP: against a throwaway focus manager that focuses nothing. Their
//  registrations used to decline the memo, so every control behind a sheet was
//  drawn afresh on every frame it stayed up. They are stored now, as a
//  backdrop's, kept beside the live page's entries rather than over them, and
//  never served across that line.
//
//  Through the real render loop: modals are hosted by the app's root, so a
//  direct render of a view with a `.sheet` does not present it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// Whether the sheet is up. A plain box: every `frame` renders, so nothing has
/// to observe it.
@MainActor
private final class SheetSwitch {
    var isUp = false
}

/// A column of buttons — each a focus stop, registering on every render —
/// under a sheet with no focus stops of its own.
private struct ButtonsUnderSheetApp: App {
    let sheet: SheetSwitch

    init() { sheet = SheetSwitch() }
    init(sheet: SheetSwitch) { self.sheet = sheet }

    var body: some Scene {
        WindowGroup {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in Button("button \(index)") {} }
                }
            }
            .sheet(isPresented: Binding(get: { sheet.isUp }, set: { sheet.isUp = $0 })) {
                Text("no focus stops here")
            }
        }
    }
}

/// A row that draws whether its focus stop holds the focus.
private struct FocusMarkedRow: View, @preconcurrency Equatable {
    let index: Int
    @Environment(\.isFocused) private var isFocused

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.index == rhs.index }

    var body: some View {
        Text((isFocused ? "* row " : "- row ") + "\(index)")
    }
}

/// Rows that mark their own focus, under the same sheet.
private struct MarkedRowsUnderSheetApp: App {
    let sheet: SheetSwitch

    init() { sheet = SheetSwitch() }
    init(sheet: SheetSwitch) { self.sheet = sheet }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<6, id: \.self) { index in FocusMarkedRow(index: index).focusable() }
            }
            .sheet(isPresented: Binding(get: { sheet.isUp }, set: { sheet.isUp = $0 })) {
                Text("no focus stops here")
            }
        }
    }
}

@MainActor
@Suite("What a backdrop stores")
struct BackdropMemoTests {
    /// Rows drawn and rows served by one frame.
    private func rowWork(_ app: HeadlessApp<ButtonsUnderSheetApp>, atNanos nanos: Int64) -> (drawn: Int, served: Int) {
        let before = app.renderCache.rowWork
        app.frame(atNanos: nanos)
        let after = app.renderCache.rowWork
        return (after.rendered - before.rendered, after.served - before.served)
    }

    /// Typing into a sheet over the Stress `notes` list cost 3.5 ms a key, all of
    /// it the list behind.
    @Test("The page behind a sheet is served while the sheet stays up")
    func thePageBehindASheetIsServed() {
        let sheet = SheetSwitch()
        let app = HeadlessApp(ButtonsUnderSheetApp(sheet: sheet), width: 40, height: 16)
        sheet.isUp = true
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        let steady = rowWork(app, atNanos: 33_333_334)
        #expect(steady.served > 0, "no row behind the sheet was served")
        #expect(steady.drawn == 0, "\(steady.drawn) rows behind the sheet were drawn again")
    }

    /// With one entry per identity, presenting the sheet overwrote every row the
    /// page had stored with the backdrop's, and dismissing it drew them all
    /// again: an alert answered in one keystroke cost more than it did when
    /// nothing behind it was stored at all.
    @Test("Dismissing a sheet serves the page it left")
    func dismissingASheetServesThePage() {
        let sheet = SheetSwitch()
        let app = HeadlessApp(ButtonsUnderSheetApp(sheet: sheet), width: 40, height: 16)
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        sheet.isUp = true
        app.frame(atNanos: 33_333_334)
        app.frame(atNanos: 50_000_000)
        sheet.isUp = false
        let dismissed = rowWork(app, atNanos: 66_666_667)
        // The focused row and its neighbour draw every frame; the rest are served.
        #expect(dismissed.drawn <= 2, "\(dismissed.drawn) rows of the page it left were drawn again")
        #expect(dismissed.served > 0)
        #expect(app.screen.contains { $0.stripped.contains("button 1") }, "the page is back")
    }

    /// Behind the sheet every row draws unfocused, and those pictures are
    /// stored. A sheet with no focus stops of its own moves no focused id, so
    /// when it goes nothing invalidates them: served to the live page, the row
    /// the focus returned to would draw as if it had none.
    @Test("The focus is drawn again when the sheet goes")
    func theFocusIsDrawnAgainWhenTheSheetGoes() {
        let sheet = SheetSwitch()
        let app = HeadlessApp(MarkedRowsUnderSheetApp(sheet: sheet), width: 40, height: 16)
        func screen() -> [String] { app.screen.map(\.stripped) }
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        #expect(screen().contains { $0.contains("* row 0") }, "the first row holds the focus: \(screen())")
        sheet.isUp = true
        app.frame(atNanos: 33_333_334)
        app.frame(atNanos: 50_000_000)
        #expect(screen().contains { $0.contains("no focus stops here") }, "the sheet is up: \(screen())")
        #expect(screen().contains { $0.contains("- row 0") }, "and the row behind it unfocused: \(screen())")
        sheet.isUp = false
        app.frame(atNanos: 66_666_667)
        #expect(
            screen().contains { $0.contains("* row 0") },
            "the row the focus returned to was served the picture from behind the sheet: \(screen())")
    }
}
