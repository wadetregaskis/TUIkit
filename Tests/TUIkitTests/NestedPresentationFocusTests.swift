//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedPresentationFocusTests.swift
//
//  A surface presented from INSIDE another presented surface keeps the focus
//  it is given, across frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Every presenter asks for its focus section on every frame it is up, and
/// activating a section is a transition. With one presentation that is a no-op
/// — the section is already the active one — so nothing here can fail with a
/// single surface. With a second presented from inside the first, the OUTER
/// presenter renders first each frame, found the inner surface's section
/// active, and took it back; the inner one took it back again, and its first
/// control re-registered into an empty focus and took that. Seeing it takes two
/// frames with the focus moved between them, which is why the stacked-modal
/// hit-testing test, rendering one frame, never did.
@MainActor
@Suite("Nested presentation focus")
struct NestedPresentationFocusTests {

    private final class BoolBox {
        var value = false
        var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private struct Item: Hashable {
        let name: String
    }

    private final class PathBox {
        var path = NavigationPath()
        var binding: Binding<NavigationPath> { Binding(get: { self.path }, set: { self.path = $0 }) }
    }

    /// One frame bracketed the way the run loop brackets it. The bracketing is
    /// the point: `beginRenderPass` empties every section, and the defect lived
    /// in the moment an outer presenter re-activated its own before anything had
    /// re-registered into it.
    private func frame(_ view: some View, tui: TUIContext, fm: FocusManager) {
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, environment: env, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        fm.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
    }

    @Test("An alert over a sheet keeps the focus Tab gives it, and hands the sheet's back")
    func alertInsideSheetKeepsItsFocus() {
        let sheet = BoolBox()
        let alert = BoolBox()
        sheet.value = true
        let tui = TUIContext()
        let fm = FocusManager()
        let view = Text("page")
            .sheet(isPresented: sheet.binding) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("Rename") {}.focusID("sheet-rename")
                    Button("Close") {}.focusID("sheet-close")
                }
                .alert("Discard changes?", isPresented: alert.binding) {
                    Button("Keep") {}
                    Button("Discard") {}
                }
            }

        // The sheet alone, focused on the control that is about to ask.
        frame(view, tui: tui, fm: fm)
        fm.focus(id: "sheet-close")
        #expect(fm.currentFocusedID == "sheet-close", "sanity: the sheet's second control is focused")

        alert.value = true
        frame(view, tui: tui, fm: fm)
        let first = fm.currentFocusedID
        #expect(first != nil && first != "sheet-close", "the alert took the focus: \(first ?? "nil")")

        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))
        let second = fm.currentFocusedID
        #expect(second != nil && second != first, "Tab moved within the alert: \(second ?? "nil")")

        // The frame Tab asked for: where the sheet took its section back and the
        // alert's first button re-took the focus.
        frame(view, tui: tui, fm: fm)
        #expect(
            fm.currentFocusedID == second,
            "the next frame undid Tab: \(fm.currentFocusedID ?? "nil")")

        // A frame nothing asked for must ask for nothing. Each of those
        // transitions announced a focus change, which schedules another frame.
        var focusChanges = 0
        fm.onFocusChange = { focusChanges += 1 }
        frame(view, tui: tui, fm: fm)
        #expect(focusChanges == 0, "a steady frame moved the focus \(focusChanges) time(s)")
        fm.onFocusChange = nil

        // Answering the alert returns the focus to the control that opened it,
        // not to the sheet's first control.
        alert.value = false
        frame(view, tui: tui, fm: fm)
        #expect(
            fm.currentFocusedID == "sheet-close",
            "dismissing the alert landed on \(fm.currentFocusedID ?? "nil")")
    }

    @Test("A sheet presented from a popover keeps the focus Tab gives it")
    func sheetInsidePopoverKeepsItsFocus() {
        // The outer section here is focus-OPTIONAL (a popover's), which the
        // walk down the stack has to pass through the same way.
        let popover = BoolBox()
        let sheet = BoolBox()
        popover.value = true
        sheet.value = true
        let tui = TUIContext()
        let fm = FocusManager()
        let view = Button("Details") {}.focusID("opener")
            .popover(isPresented: popover.binding) {
                Button("Edit") {}.focusID("popover-edit")
                    .sheet(isPresented: sheet.binding) {
                        VStack(alignment: .leading, spacing: 0) {
                            Button("Save") {}.focusID("sheet-save")
                            Button("Cancel") {}.focusID("sheet-cancel")
                        }
                    }
            }

        frame(view, tui: tui, fm: fm)
        #expect(
            fm.currentFocusedID == "sheet-save",
            "sanity: the sheet's first control took the focus: \(fm.currentFocusedID ?? "nil")")

        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(fm.currentFocusedID == "sheet-cancel", "sanity: Tab moved within the sheet")

        frame(view, tui: tui, fm: fm)
        #expect(
            fm.currentFocusedID == "sheet-cancel",
            "the next frame undid Tab: \(fm.currentFocusedID ?? "nil")")

        var focusChanges = 0
        fm.onFocusChange = { focusChanges += 1 }
        frame(view, tui: tui, fm: fm)
        #expect(focusChanges == 0, "a steady frame moved the focus \(focusChanges) time(s)")
        fm.onFocusChange = nil
    }

    /// The escape a presented section must not allow. `sectionRevertTarget` also
    /// records a push and a Tab that cycles sections, so a walk that followed it
    /// through anything but presented surfaces let a Tab out of a screen pushed
    /// inside a sheet land on a control beside the sheet's presenter — and the
    /// sheet then never took its section back. It passes at the parent too: the
    /// presenter reclaimed its section every frame there. This pins that it
    /// still does.
    @Test("Tab out of a screen pushed inside a sheet does not leave the focus behind it")
    func tabOutOfAPushInsideASheetComesBack() {
        let sheet = BoolBox()
        sheet.value = true
        let stack = PathBox()
        let tui = TUIContext()
        let fm = FocusManager()
        let view = VStack(alignment: .leading, spacing: 0) {
            Button("Outside") {}.focusID("outside")
            Text("page")
                .sheet(isPresented: sheet.binding) {
                    NavigationStack(path: stack.binding) {
                        Button("Root") {}.focusID("sheet-root")
                            .navigationDestination(for: Item.self) { _ in
                                Button("Pushed") {}.focusID("sheet-pushed")
                            }
                    }
                }
        }

        frame(view, tui: tui, fm: fm)
        stack.path.append(Item(name: "one"))
        frame(view, tui: tui, fm: fm)

        for press in 1...2 {
            _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))
            frame(view, tui: tui, fm: fm)
            #expect(
                fm.currentFocusedID != "outside",
                "Tab \(press) left the focus behind the sheet: \(fm.currentFocusedID ?? "nil")")
            #expect(fm.activeSectionIsModal, "Tab \(press) left the sheet's section inactive")
        }
    }
}
