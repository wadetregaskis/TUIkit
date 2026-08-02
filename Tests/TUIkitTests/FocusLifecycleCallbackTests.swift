//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusLifecycleCallbackTests.swift
//
//  `onFocusReceived` / `onFocusLost` are the contract a control's transient
//  state hangs off: a text field's editing session, a multi-select's
//  extend-mode latch, the reveal that scrolls a focused control on screen.
//  Every path that moves focus must fire them — not just the common
//  `focus(_:)` road, but the restore on modal dismissal and the drop when a
//  focused element stops being focusable.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Focus lifecycle callbacks on the restore and drop paths")
struct FocusLifecycleCallbackTests {

    /// A focused element that becomes unfocusable (a ScrollView whose content
    /// stopped overflowing) is dropped by `endRenderPass` — and must be TOLD,
    /// or whatever its focus began (an editing session, an extend-mode latch)
    /// never ends.
    @Test("Dropping a no-longer-focusable element fires onFocusLost")
    func dropFiresFocusLost() {
        let manager = FocusManager()
        let first = MockFocusable(id: "first")
        let second = MockFocusable(id: "second")

        manager.beginRenderPass()
        manager.register(first)
        manager.register(second)
        manager.endRenderPass()
        #expect(manager.currentFocusedID == "first", "auto-focus lands on the first element")
        #expect(first.focusReceivedCount == 1)

        first.canBeFocused = false
        manager.beginRenderPass()
        manager.register(first)
        manager.register(second)
        manager.endRenderPass()

        #expect(first.focusLostCount == 1, "the dropped element is told it lost focus")
        #expect(manager.currentFocusedID == "second", "focus moves on")
        #expect(second.focusReceivedCount == 1, "and the successor is told it arrived")
    }

    /// An element that leaves the tree entirely while focused: it is only
    /// reachable through LAST frame's ring (this frame never registered it),
    /// which is exactly where the loss notification must find it.
    @Test("An element that leaves the tree while focused still hears onFocusLost")
    func vanishedElementHearsFocusLost() {
        let manager = FocusManager()
        let transient = MockFocusable(id: "transient")
        let survivor = MockFocusable(id: "survivor")

        manager.beginRenderPass()
        manager.register(transient)
        manager.register(survivor)
        manager.endRenderPass()
        #expect(manager.currentFocusedID == "transient")

        // Next frame the element is gone — deleted row, collapsed section.
        manager.beginRenderPass()
        manager.register(survivor)
        manager.endRenderPass()

        #expect(transient.focusLostCount == 1, "its editing session must end")
        #expect(manager.currentFocusedID == "survivor")
    }

    /// The modal round trip. Entering the modal already fired the page
    /// control's `onFocusLost` (via `activateSection`); dismissal must be
    /// symmetric: the modal's control hears `onFocusLost` — even though the
    /// dismissal happens mid-pass, when the sections have been cleared and the
    /// modal will never re-register — and the RESTORED page control hears
    /// `onFocusReceived` once registration completes, so its editing session
    /// (and its reveal) resumes.
    @Test("Modal dismissal fires onFocusLost on the modal and onFocusReceived on the restored control")
    func modalDismissalFiresBothCallbacks() {
        let manager = FocusManager()
        let pageControl = MockFocusable(id: "page-control")
        let modalControl = MockFocusable(id: "modal-control")

        // Frame 1: the page alone.
        manager.beginRenderPass()
        manager.register(pageControl)
        manager.endRenderPass()
        #expect(manager.currentFocusedID == "page-control")
        #expect(pageControl.focusReceivedCount == 1)

        // Frame 2: the modal presents and takes over.
        manager.beginRenderPass()
        manager.register(pageControl)
        manager.registerSection(id: "modal")
        manager.register(modalControl, inSection: "modal")
        manager.activateSection(id: "modal")
        manager.endRenderPass()
        #expect(pageControl.focusLostCount == 1, "entering the modal ended the page control's focus")
        #expect(manager.currentFocusedID == "modal-control")
        #expect(modalControl.focusReceivedCount == 1)

        // Frame 3: dismissed. The presentation modifier deactivates mid-pass —
        // before the page re-registers, and the modal never will again.
        manager.beginRenderPass()
        manager.deactivateSection(id: "modal")
        manager.register(pageControl)
        manager.endRenderPass()

        #expect(modalControl.focusLostCount == 1, "the modal's control is told it lost focus")
        #expect(manager.currentFocusedID == "page-control", "the page's focus is restored")
        #expect(
            pageControl.focusReceivedCount == 2,
            "and the restored control is told it holds focus again")
    }

    /// The no-op guard: a steady frame where nothing changes must not fire
    /// spurious lifecycle events (a lost/received pair every frame would tear
    /// down a text field's editing session per frame).
    @Test("A steady frame fires no lifecycle callbacks")
    func steadyFrameIsSilent() {
        let manager = FocusManager()
        let element = MockFocusable(id: "only")

        manager.beginRenderPass()
        manager.register(element)
        manager.endRenderPass()
        #expect(element.focusReceivedCount == 1)

        for _ in 0..<3 {
            manager.beginRenderPass()
            manager.register(element)
            manager.endRenderPass()
        }
        #expect(element.focusReceivedCount == 1, "no re-arrivals on steady frames")
        #expect(element.focusLostCount == 0, "no losses on steady frames")
    }
}
