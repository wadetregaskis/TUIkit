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

    @Test("A hidden subtree floats no presentation AND grabs no keyboard")
    func hiddenIsInert() {
        // The overlay was already dropped — the contract says a hidden view
        // "takes no clicks and floats no pop-ups". What was NOT dropped is
        // everything the presentation did on its way to being discarded: it
        // activated its focus section and grabbed the keyboard, so the app sat
        // there held by a dialog nobody could see.
        let hidden = probe(presenting().hidden())
        #expect(hidden.overlays.isEmpty, "a hidden subtree floated a pop-up")
        #expect(!hidden.modalSectionActive, "an invisible dialog grabbed the keyboard")

        // The control: visible, it does both.
        let visible = probe(presenting())
        #expect(visible.overlays.contains { $0.level == .modal })
        #expect(visible.modalSectionActive)
    }

    @Test("A hidden control is not a Tab stop")
    func hiddenIsNotFocusable() {
        #expect(probe(VStack { Button("in") {} }.hidden()).reachable.isEmpty)
        #expect(!probe(VStack { Button("in") {} }).reachable.isEmpty)
    }

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
