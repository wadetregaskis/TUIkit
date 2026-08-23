//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HiddenAndHitTestingPresentationTests.swift
//
//  Two modifiers, one rule: a modifier that takes a subtree's PICTURE away
//  takes its powers with it; one that only redirects the mouse leaves a
//  presentation the subtree hosts alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Hidden and non-hit-testable subtrees, and what they host")
struct HiddenAndHitTestingPresentationTests {

    private struct Probe {
        let overlays: [OverlayLayer]
        let dialogRegions: Int
        let modalSectionActive: Bool
        let reachable: [String]
    }

    private func probe(_ view: some View) -> Probe {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        environment.terminalHeight = 12
        environment.overlayContentHeight = 10
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tui)
        var buffer = FrameBuffer(lines: [])
        for _ in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        let screen = buffer.compositingOverlays(
            maxWidth: 40, maxHeight: 10, palette: environment.palette)
        return Probe(
            overlays: buffer.overlays,
            dialogRegions: screen.hitTestRegions.count,
            modalSectionActive: focusManager.activeSectionIsModal,
            reachable: focusManager.registeredFocusIDsInActiveSection())
    }

    private func presenting() -> some View {
        Text("t").modal(isPresented: .constant(true)) {
            Dialog(title: "D") { Button("ok") {} }
        }
    }

    // MARK: - .hidden() takes the powers with the picture

    @Test("A hidden subtree still presents its sheet, as SwiftUI does")
    func hiddenStillPresents() {
        // A sheet is not drawn by the view that presents it — in SwiftUI the
        // window hosts it, so hiding the presenter cannot un-present it. TUIkit
        // matches that: the panel is a screen-level layer, and hiding a view
        // takes away that view's own picture.
        let hidden = probe(presenting().hidden())
        #expect(
            hidden.overlays.contains { $0.level == .modal },
            "hiding the presenter un-presented the sheet")
        #expect(hidden.modalSectionActive, "the sheet drew with nothing able to reach it")
        #expect(hidden.dialogRegions > 0, "the sheet's own buttons were not clickable")
    }

    @Test("…and an ANCHORED pop-up goes with the view that anchored it")
    func hiddenTakesAnchoredLayers() {
        // The other half of the same rule. A popover is this view's drawing,
        // displaced — there is nothing left for it to hang off.
        let hidden = probe(
            Text("anchor")
                .popover(isPresented: .constant(true)) { Text("in") }
                .hidden())
        #expect(
            hidden.overlays.allSatisfy { $0.isScreenLevel },
            "a hidden view kept its anchored pop-up: \(hidden.overlays.count)")
    }

    @Test("A hidden control is not a Tab stop")
    func hiddenIsNotFocusable() {
        // The one thing hiding DOES take away besides the picture: there is
        // nothing to land on.
        #expect(probe(VStack { Button("in") {} }.hidden()).reachable.isEmpty)
        #expect(!probe(VStack { Button("in") {} }).reachable.isEmpty)
    }

    @Test("A hidden button's keyboard shortcut still fires")
    func hiddenKeepsItsShortcut() {
        // SwiftUI's hidden-button-as-shortcut-holder is a real idiom, and it is
        // the clearest case for suppressing FOCUS rather than isolating: full
        // isolation sends the registration to a throwaway registry and the
        // shortcut silently stops working.
        let tui = TUIContext()
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4,
            environment: environment, tuiContext: tui)
        let fired = Counter()

        tui.keyboardShortcuts.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(
            Button("Save") { fired.value += 1 }.keyboardShortcut("s", modifiers: []).hidden(),
            context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()

        #expect(
            tui.keyboardShortcuts.trigger(for: KeyEvent(key: .character("s"))),
            "a hidden button's shortcut was not registered")
        #expect(fired.value == 1, "the shortcut registered but did not run the action")
    }

    private final class Counter: @unchecked Sendable { var value = 0 }

    // MARK: - .allowsHitTesting(false) redirects the mouse and nothing else

    @Test("A presented dialog's own buttons stay clickable")
    func hitTestingSparesThePresentation() {
        // `.allowsHitTesting(false)` is about the page. The dialog it opens is
        // a panel over the whole screen with its own buttons, and clearing the
        // regions inside the floated overlay produced a dialog that drew
        // perfectly and whose every button was dead.
        let inert = probe(presenting().allowsHitTesting(false))
        #expect(inert.overlays.contains { $0.level == .modal }, "the dialog stopped drawing")
        #expect(inert.dialogRegions > 0, "the dialog's own buttons were disarmed")
    }

    @Test("The screen-level flag is what the three modifiers agree on")
    func screenLevelMatchesPlacement() {
        // `isScreenLevel` reads `centered`, and this is what says the two
        // coincide — a modal is screen-level, an anchored popover is not. If
        // that ever stops being true, the three modifiers change behaviour
        // silently, so it is pinned rather than assumed.
        let modal = probe(presenting()).overlays.filter { $0.level == .modal }
        #expect(!modal.isEmpty, "precondition: a modal layer")
        #expect(modal.allSatisfy { $0.isScreenLevel }, "a modal is not screen-level")

        let popover = probe(
            Text("anchor").popover(isPresented: .constant(true)) { Text("in") }
        ).overlays
        #expect(!popover.isEmpty, "precondition: a popover layer")
        #expect(
            popover.allSatisfy { !$0.isScreenLevel },
            "an anchored popover claimed to be screen-level")
    }

    @Test("…while an anchored pop-up from the same subtree is still disarmed")
    func hitTestingStillDisarmsAnchoredPopups() {
        // The reason the overlay sweep exists: a drop-down is carried in
        // `overlays` rather than in the buffer's lines, so clearing only the
        // top level would leave it clickable under a view that just said it
        // was not. Anchored layers keep that treatment; only screen-level ones
        // are exempt.
        let menu = probe(
            Text("anchor")
                .popover(isPresented: .constant(true)) { Button("in-popover") {} }
                .allowsHitTesting(false))
        let anchored = menu.overlays.filter { !$0.isScreenLevel }
        #expect(!anchored.isEmpty, "precondition: the popover floated an anchored layer")
        #expect(
            anchored.allSatisfy { $0.content.hitTestRegions.isEmpty },
            "an anchored pop-up stayed clickable")
    }
}
