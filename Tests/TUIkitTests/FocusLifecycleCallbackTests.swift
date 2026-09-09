//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// A PROBE render must be able to ask "did this subtree contribute a focus
    /// stop?" without focusing anything to find out.
    ///
    /// `_VStackCore.nearestFocusableRow` renders candidate rows against a
    /// throwaway `FocusManager` — but the same `StateStorage`, so each row
    /// resolves the app's REAL persisted handler. It then read
    /// `currentFocusedID != nil`, which works only because `register`
    /// auto-focuses the first focusable element on an empty manager. So the
    /// probe fired `onFocusReceived()` on the real handler of a row nobody had
    /// focused, every frame, for as many rows as it walked — and that callback
    /// is where a control hangs its transient state: a text field's editing
    /// session, a multi-select's extend latch.
    ///
    /// Both halves are asserted, because either alone would let the bug back:
    /// the suppression must silence the callback, and the accessor must still
    /// answer the question the auto-focus was standing in for.
    @Test("A suppressed manager answers what registered without focusing it")
    func suppressedManagerDoesNotFocusWhileProbing() {
        let manager = FocusManager()
        manager.suppressesAutoFocus = true
        let element = MockFocusable(id: "probed")

        // No `endRenderPass`: the probe renders and reads, exactly this much.
        // (That call has its own auto-focus, for resolving `.defaultFocus`,
        // which is why suppressing only `register`'s is enough here and would
        // not be for a manager driven through a whole frame.)
        manager.beginRenderPass()
        manager.register(element)

        #expect(element.focusReceivedCount == 0, "the probe focused a row it was only counting")
        #expect(manager.currentFocusedID == nil)
        #expect(manager.hasFocusableElement, "the probe could not tell that a stop registered")
    }

    /// The discriminator must not answer "yes" to a DISABLED control: it still
    /// registers, with `canBeFocused` false, so the ring can filter it at move
    /// time. Reading "registered anything" instead would make the probe stop
    /// walking at the first disabled row.
    @Test("A registered but unfocusable element is not a focus stop")
    func disabledElementIsNotAFocusStop() {
        let manager = FocusManager()
        manager.suppressesAutoFocus = true
        let element = MockFocusable(id: "disabled")
        element.canBeFocused = false

        manager.beginRenderPass()
        manager.register(element)

        #expect(!manager.hasFocusableElement)
        #expect(element.focusReceivedCount == 0)
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
    /// `unregister` is the app-facing teardown — the framework's own is the
    /// per-frame ring — and it owed the departing element the same
    /// notification every other clearing path gives it. `onFocusLost()` is
    /// documented as where a pending edit is committed and a caret stops
    /// blinking, so skipping it leaves that state live forever.
    @Test("Unregistering the focused element fires its onFocusLost")
    func unregisterFiresFocusLost() {
        let manager = FocusManager()
        let first = MockFocusable(id: "first")
        let second = MockFocusable(id: "second")

        manager.register(first)  // the first registrant auto-focuses
        manager.register(second)
        #expect(manager.currentFocusedID == "first", "sanity: the departing element is focused")

        manager.unregister(first)

        #expect(first.focusLostCount == 1, "the departing element's focus session ends")
        #expect(manager.currentFocusedID == "second", "focus moves on")
        #expect(second.focusReceivedCount == 1, "and the successor is told it arrived")
    }

    /// …and when the unregistered element was the LAST focusable, nothing
    /// moves in after it, so the focus goes nil with no move to announce it —
    /// the same repaint `relinquishFocus()` asks for, for the same reason: the
    /// frame on screen still shows a focus indicator that is now a lie.
    @Test("Unregistering the only focusable asks for the repaint")
    func unregisteringTheLastFocusableRepaints() {
        let manager = FocusManager()
        let only = MockFocusable(id: "only")
        manager.register(only)
        #expect(manager.currentFocusedID == "only", "sanity: it holds the focus")

        var repaints = 0
        manager.onFocusChange = { repaints += 1 }
        manager.unregister(only)

        #expect(only.focusLostCount == 1, "it is still told, with nothing to hand focus to")
        #expect(manager.currentFocusedID == nil)
        #expect(repaints == 1, "or the indicator that just went away stays on screen")
    }

    /// The restore target that came back DISABLED. `deactivateSection` assigns
    /// focus straight from section memory — the page has not re-registered yet,
    /// so it cannot check `canBeFocused` — and defers the arrival to
    /// `endRenderPass`. When the remembered control re-registers unfocusable
    /// (some state independent of `isPresented` disabled it while the modal was
    /// up), end-of-pass validation drops it and the deferred arrival is rightly
    /// never delivered. Announcing the LOSS as well leaves a text field with two
    /// `onEditingChanged(false)` for one `true`.
    @Test("A restore invalidated before its deferred arrival fires no onFocusLost")
    func invalidatedRestoreFiresNoFocusLost() {
        let manager = FocusManager()
        let field = MockFocusable(id: "field")
        let other = MockFocusable(id: "other")

        // Frame 1: the page. The field takes focus and is told so.
        manager.beginRenderPass()
        manager.register(field)
        manager.register(other)
        manager.endRenderPass()
        #expect(manager.currentFocusedID == "field")
        #expect(field.focusReceivedCount == 1)

        // Frame 2: a modal presents. The page renders isolated behind it
        // (`isolatedForBackground`), so only the modal's control is in the ring.
        let modalControl = MockFocusable(id: "modal-control")
        manager.beginRenderPass()
        manager.registerSection(id: "modal")
        manager.register(modalControl, inSection: "modal")
        manager.activateSection(id: "modal")
        manager.endRenderPass()
        #expect(field.focusLostCount == 1, "entering the modal ended the field's session")
        #expect(manager.currentFocusedID == "modal-control")

        // Frame 3: dismissed — and the field is disabled now. It registers,
        // unfocusable, so the restore assigned mid-pass is invalidated.
        field.canBeFocused = false
        manager.beginRenderPass()
        manager.deactivateSection(id: "modal")
        manager.register(field)
        manager.register(other)
        manager.endRenderPass()

        #expect(field.focusReceivedCount == 1, "the deferred arrival was never delivered")
        #expect(
            field.focusLostCount == 1,
            "so no loss may be announced for it either")
        #expect(manager.currentFocusedID == "other", "focus lands on what can take it")
        #expect(other.focusReceivedCount == 1)
        #expect(modalControl.focusLostCount == 1, "the modal's own control still hears its loss")
    }

    /// `clear()` is the other app-facing teardown, and `App.cleanup` calls it
    /// at quit one step ahead of the `StorageDefaults.backend.synchronize()`
    /// that exists to flush late writes. A focused field's `onFocusLost()` IS
    /// one of those late writes — `TextFieldHandler` fires
    /// `onEditingChanged(false)` there, which is what commits a value the user
    /// typed and never submitted — so a `clear()` that nils the focus in
    /// silence drops it.
    @Test("Clearing the manager fires the focused element's onFocusLost")
    func clearFiresFocusLost() {
        let manager = FocusManager()
        let first = MockFocusable(id: "first")
        let second = MockFocusable(id: "second")

        manager.register(first)  // the first registrant auto-focuses
        manager.register(second)
        #expect(manager.currentFocusedID == "first", "sanity: the departing element is focused")

        manager.clear()

        #expect(first.focusLostCount == 1, "the hard reset ends the focused element's session")
        #expect(second.focusLostCount == 0, "and only the focused one is told")
        #expect(manager.currentFocusedID == nil)

        // Self-guarding: a second clear has no focus left to notify.
        manager.clear()
        #expect(first.focusLostCount == 1, "a clear with nothing focused notifies nobody")
    }
}
