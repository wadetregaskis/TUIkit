//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AlertDismissalTests.swift
//
//  How a presented `.alert` / `.confirmationDialog` gets CLOSED — the two
//  routes a user actually has, both of which were missing.
//
//  Every other alert test in the suite binds `isPresented` to `.constant(…)`,
//  which cannot observe a dismissal at all: writing to a constant binding is a
//  no-op, so the dialog can never close and no test could tell. These use real
//  bindings, and drive the same layers the run loop does — for Escape that
//  means the whole `InputHandler`, because the defect was entirely in WHICH
//  layer got the key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Alert dismissal")
struct AlertDismissalTests {

    /// A stand-in theme item: `ThemeManager` requires at least one, and this
    /// suite never cycles themes.
    private struct StubTheme: Cyclable {
        let id = "stub"
        let name = "Stub"
    }

    /// A mutable flag reachable from an escaping action closure.
    @MainActor
    private final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
        var binding: Binding<Bool> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    private func harness(width: Int = 60, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// Renders a frame, arms the dispatcher with the COMPOSITED regions as the
    /// run loop does, and returns the composited buffer — which is the only
    /// thing whose coordinates are the screen's. An alert overlay is `centered`,
    /// so its own `offsetX`/`offsetY` are 0 and mean nothing until the
    /// compositor has placed it.
    @discardableResult
    private func renderArmed(_ view: some View, tui: TUIContext, context: RenderContext)
        -> FrameBuffer
    {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return composited
    }

    /// Where the action button labelled `label` sits on the composited screen.
    ///
    /// The LAST line carrying the word, because the buttons are at the bottom
    /// and an alert's title routinely repeats it ("Delete this item?" /
    /// "Delete") — a first-match search clicks the title bar and nothing
    /// happens, which is a very convincing way to fake this test failing.
    private func actionRow(_ screen: FrameBuffer, _ label: String) throws -> (x: Int, y: Int) {
        let row = try #require(
            screen.lines.lastIndex { $0.stripped.contains(label) },
            "\(label) is on screen: \(screen.lines.map(\.stripped))")
        let text = screen.lines[row].stripped
        let column = try #require(text.range(of: label)).lowerBound
        return (text.distance(from: text.startIndex, to: column), row)
    }

    // MARK: - Choosing an action

    /// SwiftUI closes an alert when ANY of its action buttons is chosen — the
    /// alert asked a question and the button answered it. TUIkit made every
    /// caller flip the binding by hand, and a caller that forgot (as the
    /// Example's own confirmation dialog did) got a dialog that ran its action
    /// and then sat there, unclosable.
    @Test("Choosing an action closes the dialog as well as running it")
    func actionDismissesTheDialog() throws {
        let (tui, context) = harness()
        let presented = Flag(true)
        var chose = "—"
        let view = Text("Page").confirmationDialog(
            "Delete this item?", isPresented: presented.binding,
            actions: {
                Button("Delete", role: .destructive) { chose = "Delete" }
                Button("Cancel", role: .cancel) { chose = "Cancel" }
            },
            message: { Text("This cannot be undone.") })

        let open = renderArmed(view, tui: tui, context: context)
        let target = try actionRow(open, "Delete")
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: target.x, y: target.y))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: target.x, y: target.y))

        #expect(chose == "Delete", "the caller's action still runs")
        #expect(!presented.value, "…and the dialog closes behind it")
        let after = renderArmed(view, tui: tui, context: context)
        #expect(
            !after.lines.contains { $0.stripped.contains("Delete this item?") },
            "so the next frame no longer draws it: \(after.lines.map(\.stripped))")
    }

    /// The dismissal is scoped to the ALERT's own subtree. A button on the page
    /// beneath must not inherit it — it would close a dialog it has nothing to
    /// do with, and the page renders from a different context precisely so that
    /// its state and focus stay separate.
    @Test("A button on the page beneath does not inherit the dismissal")
    func pageButtonsDoNotDismiss() throws {
        let (tui, context) = harness()
        let presented = Flag(false)
        var pageRuns = 0
        let view = Button("On the page") { pageRuns += 1 }
            .confirmationDialog(
                "Sure?", isPresented: presented.binding,
                actions: { Button("Yes") {} })

        let closed = renderArmed(view, tui: tui, context: context)
        let region = try #require(closed.hitTestRegions.last)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: region.offsetX, y: region.offsetY))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: region.offsetX, y: region.offsetY))

        #expect(pageRuns == 1, "the page button ran")
        #expect(!presented.value, "and nothing was presented to dismiss")
    }

    // MARK: - One identity per action

    /// Every action button needs its OWN focus identity. Rendered from one
    /// shared context they all resolved to a single id, and the focus system
    /// treated the dialog as having one control: both buttons drew focused, Tab
    /// could not move between them, and Return ran whichever action that id
    /// resolved to — always the same one, whatever the user had highlighted.
    /// (The mouse was unaffected: a click routes by hit region to a per-button
    /// handler, which is why clicking Cancel worked while Return did not.)
    @Test(
        "Each action button gets its own focus identity",
        arguments: [true, false])
    func actionsHaveDistinctFocusIDs(verticalButtons: Bool) throws {
        let (tui, context) = harness()
        let presented = Flag(true)
        // `.confirmationDialog` stacks its buttons; `.alert` puts them in a row.
        // Both build the same modifier, and both had the defect.
        let view: any View =
            verticalButtons
            ? Text("Page").confirmationDialog(
                "Sure?", isPresented: presented.binding,
                actions: {
                    Button("Delete", role: .destructive) {}
                    Button("Cancel", role: .cancel) {}
                })
            : Text("Page").alert(
                "Sure?", isPresented: presented.binding,
                actions: {
                    Button("Delete", role: .destructive) {}
                    Button("Cancel", role: .cancel) {}
                }, message: { Text("Really?") })

        let screen = renderArmed(AnyView(view), tui: tui, context: context)
        let focusIDs = Set(screen.hitTestRegions.compactMap(\.focusID))
        #expect(
            focusIDs.count == 2,
            "two buttons, two identities — got \(focusIDs.count): \(focusIDs.sorted())")
    }

    /// The consequence the user actually feels: Return runs the action of the
    /// button that has focus, not a fixed one.
    @Test("Return activates the focused action, not always the first")
    func returnActivatesTheFocusedAction() throws {
        let (tui, context) = harness()
        let presented = Flag(true)
        var chose = "—"
        let view = Text("Page").confirmationDialog(
            "Sure?", isPresented: presented.binding,
            actions: {
                Button("Delete", role: .destructive) { chose = "Delete" }
                Button("Cancel", role: .cancel) { chose = "Cancel" }
            })

        renderArmed(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        // Move off whatever auto-focused, onto the second (Cancel) button.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .tab))
        renderArmed(view, tui: tui, context: context)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))

        #expect(chose == "Cancel", "Return ran the focused button's action, got \(chose)")
    }

    // MARK: - Escape

    /// The whole input stack a running app has: a status bar already carrying
    /// the page's own "⎋ back" item, and the `InputHandler` that runs in front
    /// of it. Escape has to be driven through this, not straight at the key
    /// dispatcher: layer 1 (the bar) is the layer that decides, and a narrower
    /// test skips it and passes against broken code.
    private func inputHarness(pageEscape: @escaping () -> Void = {}) -> (
        tui: TUIContext, context: RenderContext, statusBar: StatusBarState,
        handler: InputHandler
    ) {
        let tui = TUIContext()
        let focus = FocusManager()
        let statusBar = StatusBarState()
        statusBar.focusManager = focus
        statusBar.setItemsSilently([
            StatusBarItem(shortcut: Shortcut.escape, label: "back", action: pageEscape)
        ])

        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = statusBar
        let context = RenderContext(
            availableWidth: 60, availableHeight: 24, environment: environment, tuiContext: tui)

        let handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tui.keyEventDispatcher,
            focusManager: focus,
            paletteManager: ThemeManager(items: [StubTheme()]),
            appearanceManager: ThemeManager(items: [StubTheme()]),
            keyboardShortcuts: tui.keyboardShortcuts,
            dragAndDropSession: nil,
            onQuit: {},
            onSuspend: {})
        return (tui, context, statusBar, handler)
    }

    /// The crux of the reported bug, and the reason no existing test caught it:
    /// the alert DID register an Escape handler, on the key dispatcher — but
    /// `InputHandler` runs the status bar FIRST, so a page carrying its own
    /// "⎋ back" item ate the key and navigated away with the dialog still up.
    @Test("Escape closes the dialog instead of the page's own ⎋ item")
    func escapeClosesTheDialogNotThePage() {
        var wentBack = 0
        let harness = inputHarness { wentBack += 1 }

        let presented = Flag(true)
        let view = Text("Page").confirmationDialog(
            "Delete this item?", isPresented: presented.binding,
            actions: { Button("Delete", role: .destructive) {} })

        renderArmed(view, tui: harness.tui, context: harness.context)
        #expect(harness.handler.handle(KeyEvent(key: .escape)), "the key is consumed by something")

        #expect(!presented.value, "Escape closed the dialog")
        #expect(wentBack == 0, "…and did NOT also run the page's ⎋ back item")
    }

    /// And the status bar says so. A bar still advertising "back" while a modal
    /// dialog owns the key is telling the user something false, which is how
    /// this went unnoticed: the label and the behaviour agreed — both wrong.
    @Test("The status bar advertises the dialog's Escape, not the page's")
    func statusBarLabelsTheDialogsEscape() {
        let harness = inputHarness()
        let presented = Flag(true)
        let view = Text("Page").confirmationDialog(
            "Sure?", isPresented: presented.binding, actions: { Button("Yes") {} })

        renderArmed(view, tui: harness.tui, context: harness.context)
        let escapeLabels: [String] = harness.statusBar.currentItems
            .filter { $0.shortcut == Shortcut.escape }
            .map { $0.label }
        #expect(escapeLabels == ["dismiss"], "one ESC item, and it is the dialog's: \(escapeLabels)")
    }

    // MARK: - Escape is the cancel button

    /// Escape ANSWERS the dialog rather than just closing it: it chooses the
    /// `.cancel`-role button, running that action exactly as clicking it would.
    /// macOS gives Cancel the Escape key equivalent for the same reason, and
    /// ``ButtonRole/cancel`` documented it long before it was true. Closing
    /// without it is a different outcome — the caller is never told what the
    /// user chose, so a dialog escaped rather than clicked silently reported
    /// nothing at all.
    @Test("Escape runs the cancel button's action")
    func escapeChoosesTheCancelAction() {
        let harness = inputHarness()
        let presented = Flag(true)
        var chose = "—"
        let view = Text("Page").confirmationDialog(
            "Delete this item?", isPresented: presented.binding,
            actions: {
                Button("Delete", role: .destructive) { chose = "Delete" }
                Button("Cancel", role: .cancel) { chose = "Cancel" }
            })

        renderArmed(view, tui: harness.tui, context: harness.context)
        _ = harness.handler.handle(KeyEvent(key: .escape))

        #expect(chose == "Cancel", "Escape chose Cancel, got \(chose)")
        #expect(!presented.value, "…and the dialog closed")
    }

    /// No cancel role, nothing to run: Escape still closes, and no other action
    /// is conscripted into the job. Escaping a dialog whose only buttons are
    /// destructive must not perform one.
    @Test("With no cancel button, Escape closes and runs nothing")
    func escapeWithoutACancelActionJustCloses() {
        let harness = inputHarness()
        let presented = Flag(true)
        var runs = 0
        let view = Text("Page").confirmationDialog(
            "Delete this item?", isPresented: presented.binding,
            actions: { Button("Delete", role: .destructive) { runs += 1 } })

        renderArmed(view, tui: harness.tui, context: harness.context)
        _ = harness.handler.handle(KeyEvent(key: .escape))

        #expect(runs == 0, "no action ran")
        #expect(!presented.value, "but the dialog closed")
    }

    /// A disabled Cancel cannot be chosen by pointer or keyboard, so Escape
    /// does not choose it either — the keyboard shortcut for a button must obey
    /// the same gate the button does.
    @Test("A disabled cancel button is not run by Escape")
    func escapeSkipsADisabledCancelAction() {
        let harness = inputHarness()
        let presented = Flag(true)
        var cancelled = 0
        let view = Text("Page").confirmationDialog(
            "Sure?", isPresented: presented.binding,
            actions: {
                Button("Delete", role: .destructive) {}
                Button("Cancel", role: .cancel) { cancelled += 1 }.disabled(true)
            })

        renderArmed(view, tui: harness.tui, context: harness.context)
        _ = harness.handler.handle(KeyEvent(key: .escape))

        #expect(cancelled == 0, "the disabled action stayed disabled")
        #expect(!presented.value, "and the dialog still closed")
    }
}
