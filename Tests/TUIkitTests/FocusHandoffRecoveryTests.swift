//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusHandoffRecoveryTests.swift
//
//  The focus manager's half of a focus handoff: a control that names where its
//  focus goes when it can no longer hold it, followed along a chain of such names,
//  before the neighbour rule in FocusRecoveryTests applies.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A handoff names its target by `@FocusState` value. These drive the manager
/// directly: every control is bound in one store under its own id as the value, so
/// "right hands off to left" is `handoffs: ["right": "left"]`.
///
/// The case that motivated it is the gradient editor's ◀ and ▶: when ▶ disables
/// itself it wants ◀, its neighbour on the LEFT, and no rule based on position can
/// give ▶ that and ◀ its right-hand neighbour at the same time.
@MainActor
@Suite("A control's focus handoff")
struct FocusHandoffRecoveryTests {

    private static let store = "focusstate::handoff-test::0"

    /// One pass registering `controls` in `section`, in order.
    ///
    /// Each registered control is bound under its own id, and declares its entry in
    /// `handoffs` if it has one. `during` runs after registration and before the
    /// pass ends, for anything else the pass should declare.
    private func pass(
        _ manager: FocusManager, _ controls: [MockFocusable], handoffs: [String: String] = [:],
        section: String = "dialog", during: (FocusManager) -> Void = { _ in }
    ) {
        manager.beginRenderPass()
        register(manager, controls, handoffs: handoffs, section: section)
        during(manager)
        manager.endRenderPass()
    }

    private func register(
        _ manager: FocusManager, _ controls: [MockFocusable], handoffs: [String: String],
        section: String
    ) {
        manager.registerSection(id: section)
        for control in controls {
            manager.register(control, inSection: section)
            manager.registerFocusBinding(
                store: Self.store, value: AnyHashable(control.focusID), focusID: control.focusID)
            if let target = handoffs[control.focusID] {
                manager.registerFocusHandoff(
                    from: control.focusID, store: Self.store, value: AnyHashable(target))
            }
        }
    }

    // MARK: - One hop

    @Test("A control that disables itself hands focus to its declared target")
    func disabledHandsOffToTarget() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        let preset = MockFocusable(id: "preset")
        let handoffs = ["right": "left"]
        pass(manager, [top, left, right, preset], handoffs: handoffs)
        manager.focus(id: "right")

        right.canBeFocused = false
        pass(manager, [top, left, right, preset], handoffs: handoffs)

        #expect(manager.currentFocusedID == "left", "its target, not its neighbour")
        #expect(left.focusReceivedCount == 1, "the target is told it has the focus")
        #expect(manager.focusedValue(forStore: Self.store) == AnyHashable("left"), "and @FocusState reads it")
        #expect(preset.focusReceivedCount == 0, "the neighbour never had it on the way")
    }

    @Test("A control that left the tree hands focus to its declared target")
    func departedHandsOffToTarget() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        let preset = MockFocusable(id: "preset")
        pass(manager, [top, left, right, preset], handoffs: ["right": "left"])
        manager.focus(id: "right")

        pass(manager, [top, left, preset])

        #expect(manager.currentFocusedID == "left", "last frame's declaration still names it")
    }

    @Test("Unregistering the focused control honours its handoff")
    func unregisterHonoursHandoff() {
        let manager = FocusManager()
        let first = MockFocusable(id: "first")
        let second = MockFocusable(id: "second")
        let third = MockFocusable(id: "third")
        pass(manager, [first, second, third], handoffs: ["second": "first"])
        manager.focus(id: "second")

        manager.unregister(second)

        #expect(manager.currentFocusedID == "first", "the target, not the successor")
    }

    // MARK: - Chains

    /// The owner's decision: follow the chain rather than stop after one hop.
    @Test("A chain of three handoffs reaches the one control that can take focus")
    func threeLinkChain() {
        let manager = FocusManager()
        let controls = ["top", "d", "x", "b", "c", "a", "after"].map { MockFocusable(id: $0) }
        let handoffs = ["a": "b", "b": "c", "c": "d"]
        pass(manager, controls, handoffs: handoffs)
        manager.focus(id: "a")

        for id in ["a", "b", "c"] { controls.first { $0.focusID == id }?.canBeFocused = false }
        pass(manager, controls, handoffs: handoffs)

        #expect(manager.currentFocusedID == "d", "a → b → c → d, past two unfocusable links")
    }

    /// ◀ and ▶ naming each other, both disabled at once.
    @Test("Handoffs that name each other fall back to the neighbour instead of looping")
    func twoCycleFallsBack() {
        let manager = FocusManager()
        let top = MockFocusable(id: "top")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        let after = MockFocusable(id: "after")
        let handoffs = ["left": "right", "right": "left"]
        pass(manager, [top, left, right, after], handoffs: handoffs)
        manager.focus(id: "right")

        left.canBeFocused = false
        right.canBeFocused = false
        pass(manager, [top, left, right, after], handoffs: handoffs)

        #expect(manager.currentFocusedID == "after", "right's neighbour, walked from right")
        #expect(manager.pendingFocusID == nil, "and no intent left waiting for either")
    }

    @Test("A chain passes through a control that left the tree, using its last declaration")
    func chainThroughDepartedControl() {
        let manager = FocusManager()
        let top = MockFocusable(id: "top")
        let c = MockFocusable(id: "c")
        let a = MockFocusable(id: "a")
        let b = MockFocusable(id: "b")
        let after = MockFocusable(id: "after")
        pass(manager, [top, c, a, b, after], handoffs: ["a": "b", "b": "c"])
        manager.focus(id: "a")

        a.canBeFocused = false
        pass(manager, [top, c, a, after], handoffs: ["a": "b"])

        #expect(manager.currentFocusedID == "c", "a → b (gone) → c, by b's declaration from last frame")
    }

    // MARK: - When it does not apply

    @Test("A target bound to nothing falls back to the neighbour and leaves no intent")
    func missingTargetFallsBack() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let right = MockFocusable(id: "right")
        let preset = MockFocusable(id: "preset")
        let handoffs = ["right": "nowhere"]
        pass(manager, [top, right, preset], handoffs: handoffs)
        manager.focus(id: "right")

        right.canBeFocused = false
        pass(manager, [top, right, preset], handoffs: handoffs)

        #expect(manager.currentFocusedID == "preset")
        #expect(manager.pendingFocusID == nil)
    }

    /// A present control that no longer declares a handoff has none, even though last
    /// frame's declaration is still on the manager until the end of this pass.
    @Test("A control that stopped declaring its handoff falls back to the neighbour")
    func withdrawnDeclarationIsIgnored() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        let preset = MockFocusable(id: "preset")
        pass(manager, [top, left, right, preset], handoffs: ["right": "left"])
        manager.focus(id: "right")

        right.canBeFocused = false
        pass(manager, [top, left, right, preset])

        #expect(manager.currentFocusedID == "preset")
    }

    @Test("Tab and the arrows still move to the next control")
    func userMovesAreNotRedirected() {
        let manager = FocusManager()
        let controls = ["toggle", "left", "right", "preset"].map { MockFocusable(id: $0) }
        pass(manager, controls, handoffs: ["right": "left"])

        manager.focus(id: "right")
        manager.focusNext()
        #expect(manager.currentFocusedID == "preset", "Tab")

        manager.focus(id: "right")
        manager.focusNextInSection()
        #expect(manager.currentFocusedID == "preset", "Down")
    }

    @Test("A .userInitiated default focus still wins over a handoff")
    func defaultFocusWins() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        let preset = MockFocusable(id: "preset")
        let handoffs = ["right": "left"]
        pass(manager, [top, left, right, preset], handoffs: handoffs)
        manager.focus(id: "right")

        right.canBeFocused = false
        pass(manager, [top, left, right, preset], handoffs: handoffs) {
            $0.setDefaultFocusValue(AnyHashable("preset"), priority: .userInitiated, forStore: Self.store)
        }

        #expect(manager.currentFocusedID == "preset")
        #expect(left.focusReceivedCount == 0, "the handoff target never held it on the way")
    }

    // MARK: - Sections

    /// Two sections, `page` and `dialog`, with `right` focused in `dialog` and handing
    /// off to `left` in `page`.
    private func twoSectionPass(_ manager: FocusManager, modal: Bool, _ controls: [MockFocusable]) {
        manager.beginRenderPass()
        register(manager, [controls[0]], handoffs: [:], section: "page")
        register(manager, Array(controls.dropFirst()), handoffs: ["right": "left"], section: "dialog")
        if modal { manager.markSectionModal(id: "dialog") }
        manager.endRenderPass()
    }

    @Test("A target in another section activates that section")
    func targetInOtherSectionActivatesIt() {
        let manager = FocusManager()
        let controls = ["left", "right", "other"].map { MockFocusable(id: $0) }
        twoSectionPass(manager, modal: false, controls)
        manager.focus(id: "right")
        #expect(manager.activeSectionIdentifier == "dialog", "sanity")

        controls[1].canBeFocused = false
        twoSectionPass(manager, modal: false, controls)

        #expect(manager.currentFocusedID == "left")
        #expect(manager.activeSectionIdentifier == "page")
    }

    @Test("A modal section refuses a target outside it")
    func modalRefusesOutsideTarget() {
        let manager = FocusManager()
        let controls = ["left", "right", "other"].map { MockFocusable(id: $0) }
        twoSectionPass(manager, modal: true, controls)
        manager.focus(id: "right")

        controls[1].canBeFocused = false
        twoSectionPass(manager, modal: true, controls)

        #expect(manager.currentFocusedID == "other", "the neighbour inside the modal")
        #expect(manager.activeSectionIdentifier == "dialog")
    }

    // MARK: - Lifetime

    /// Pruned at the end of the pass, like the `@FocusState` bindings, and read before
    /// that: a control that stops rendering still has last frame's declaration while
    /// this pass recovers its focus, and nothing after.
    @Test("A declaration outlives its control by exactly the pass it stops rendering in")
    func declarationLifetime() {
        let manager = FocusManager()
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        pass(manager, [left, right], handoffs: ["right": "left"])
        #expect(manager.focusHandoffs["right"] != nil, "declared")

        var readableDuringPass = false
        pass(manager, [left]) { readableDuringPass = $0.focusHandoffs["right"] != nil }
        #expect(readableDuringPass, "still there while the pass it stopped rendering in runs")
        #expect(manager.focusHandoffs["right"] == nil, "gone once that pass has ended")
    }
}
