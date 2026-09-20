//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationItemIdentityTests.swift
//
//  What the `item:` form of a presentation promises over the `isPresented:`
//  form: the presented content is ABOUT something, and when that something
//  changes the content is a DIFFERENT view — fresh `@State`, fresh lifecycle.
//  These renders drive `StateStorage`'s pass boundaries the way the run loop
//  does (as `ModalBackdropStateTests` does), because the prune at the end of a
//  pass is what makes a dismissed presentation forget; without the bracketing
//  the question of what survives an item change is invisible.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The thing a presentation is about.
private struct Row: Identifiable, Equatable {
    let id: Int
}

/// The presented content: a draft that only its own Button writes to. The
/// draft is the state an editing sheet holds — a half-typed rename — and
/// `row=` beside it says which item the content was BUILT for, so one line
/// carries both halves of the question.
private struct DraftEditor: View {
    let row: Row
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("row=\(row.id) draft=[\(draft)]")
            Button("Type") { draft = "edit-\(row.id)" }.focusID("draft")
        }
    }
}

@MainActor
@Suite("Presentation: item identity")
struct PresentationItemIdentityTests {

    private final class ItemBox {
        var value: Row?
        var binding: Binding<Row?> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    /// One frame, bracketed the way the run loop brackets it, returning every
    /// line drawn — the page's own plus each overlay's, recursively, since a
    /// sheet, a cover and a popover all land in an overlay (a popover's panel
    /// carries a dismiss backdrop of its own).
    ///
    /// The view is rebuilt for every frame — hence `@autoclosure`, which is
    /// here for re-evaluation, not for brevity — because that is what a real
    /// render does: the page's `body` re-runs and the presentation rebuilds its
    /// content from the CURRENT item. Built once and reused, the presented
    /// content would be frozen at whatever the item was when the test
    /// constructed the view, and every one of these tests would present
    /// nothing at all.
    private func frame(
        _ view: @autoclosure () -> some View, tui: TUIContext, fm: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = fm
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        environment.overlayContentHeight = 14
        let context = RenderContext(
            availableWidth: 40, availableHeight: 14, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(view(), context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        return Self.allLines(of: buffer)
    }

    private static func allLines(of buffer: FrameBuffer) -> [String] {
        buffer.lines.map(\.stripped) + buffer.overlays.flatMap { allLines(of: $0.content) }
    }

    /// The drafted line, stripped of the chrome around it — a popover draws its
    /// content inside a bordered panel, so the same assertion can serve all
    /// three presentations.
    private static func draftLine(_ lines: [String]) -> String? {
        lines.first { $0.contains("draft=") }?
            .drop { $0 == " " || $0 == "│" }
            .reversed().drop { $0 == " " || $0 == "│" }.reversed()
            .map(String.init).joined()
    }

    /// Drives the presented editor's Button, so its `@State` holds something
    /// other than its default when the item changes underneath it.
    private func typeIntoTheDraft(
        _ view: @escaping @autoclosure () -> some View, tui: TUIContext, fm: FocusManager
    ) {
        _ = frame(view(), tui: tui, fm: fm)
        fm.focus(id: "draft")
        _ = frame(view(), tui: tui, fm: fm)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .enter))
    }

    @Test("A sheet re-presented for a different item does not inherit the first item's state")
    func sheetItemChangeResetsState() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").sheet(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        let typed = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(typed) == "row=1 draft=[edit-1]",
            "sanity: the draft landed for row 1: \(typed)")

        // The list selection moves to another row while the sheet is up — the
        // `item:` form's whole reason to exist. SwiftUI re-creates the content.
        item.value = Row(id: 2)
        let switched = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(switched) == "row=2 draft=[]",
            "row 2's sheet opened holding row 1's draft: \(switched)")
    }

    @Test("A full-screen cover re-presented for a different item starts fresh")
    func coverItemChangeResetsState() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").fullScreenCover(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        let typed = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(typed) == "row=1 draft=[edit-1]",
            "sanity: the draft landed for row 1: \(typed)")

        item.value = Row(id: 2)
        let switched = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(switched) == "row=2 draft=[]",
            "row 2's cover opened holding row 1's draft: \(switched)")
    }

    @Test("A popover re-presented for a different item starts fresh")
    func popoverItemChangeResetsState() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").popover(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        let typed = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(typed) == "row=1 draft=[edit-1]",
            "sanity: the draft landed for row 1: \(typed)")

        item.value = Row(id: 2)
        let switched = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(switched) == "row=2 draft=[]",
            "row 2's popover opened holding row 1's draft: \(switched)")
    }

    /// The same item must NOT be re-keyed on every frame: an identity that
    /// changed while the item stood still would throw the draft away between
    /// keystrokes, which is the opposite defect.
    @Test("A sheet kept open for one item holds its state across frames")
    func sheetKeepsStateForTheSameItem() {
        let item = ItemBox()
        let tui = TUIContext()
        let fm = FocusManager()
        func view() -> some View {
            Text("page").sheet(item: item.binding) { row in DraftEditor(row: row) }
        }

        item.value = Row(id: 1)
        typeIntoTheDraft(view(), tui: tui, fm: fm)
        _ = frame(view(), tui: tui, fm: fm)
        let later = frame(view(), tui: tui, fm: fm)
        #expect(
            Self.draftLine(later) == "row=1 draft=[edit-1]",
            "the draft survived the frames after it was typed: \(later)")
    }
}
