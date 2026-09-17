//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusSectionIndicatorMemoTests.swift
//
//  A focus section hands the subtree below it a breathing ● when it is the
//  active one, by assigning `EnvironmentValues.focusIndicator` straight into the
//  child context. Nothing in a value memo's key can see that assignment, so a
//  subtree stored while its section was INACTIVE is served unchanged once the
//  section becomes active — a section that says nowhere that it holds the
//  keyboard.
//
//  `FocusSectionModifier` guards the other direction already: while a section is
//  active it declines to store at all. This is the half that was missing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A bordered card, memoized by title alone: nothing in its value changes when
/// the section around it becomes the active one, which is what lets the memo
/// hit and what made the stale picture possible.
private struct IndicatorCard: View, @MainActor Equatable {
    let title: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Box {
            Text(title)
        }
    }
}

/// Renders frames the way `RenderLoop` brackets them, with the focus ring
/// emptied before every walk.
@MainActor
private final class LoopHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()

    var cache: RenderCache { tui.renderCache }

    /// Renders one frame and returns what it drew, one line per row with the
    /// styling stripped so the indicator is compared as a character.
    @discardableResult
    func frame(_ view: some View) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        // No mouse dispatcher: the box carries no control, and a region would
        // only bring a second gate into a test about the indicator.
        environment.mouseEventDispatcher = nil
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        focusManager.beginSceneRender()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        cache.removeInactive()
        return buffer.lines.map(\.stripped)
    }

    /// How many memo lookups the frame missed — zero when every memoized
    /// subtree was served.
    func misses(_ view: some View) -> Int {
        let before = cache.stats.misses
        frame(view)
        return cache.stats.misses - before
    }
}

@MainActor
@Suite("A focus section's indicator through the render memo")
struct FocusSectionIndicatorMemoTests {

    /// Two sections. The first registered becomes the active one, so the
    /// memoized card in the second renders with no indicator and can be stored.
    @MainActor
    private static func page() -> some View {
        VStack {
            Text("ahead").focusable().focusSection("first")
            IndicatorCard(title: "card").equatable().focusSection("second")
        }
    }

    @Test("A memoized subtree draws the section indicator once its section becomes active")
    func indicatorArrivesOnAServedSubtree() {
        let harness = LoopHarness()
        harness.frame(Self.page())
        let inactive = harness.frame(Self.page())
        #expect(
            !inactive.contains { $0.contains("●") },
            "the inactive section drew an indicator: \(inactive)")
        #expect(!harness.cache.isEmpty, "the inactive section's card was never stored")

        // The section now holds the keyboard, so its border must say so. The
        // card's value is unchanged and nothing cleared its entry, so a served
        // buffer is the one drawn while the section was inactive.
        harness.focusManager.activateSection(id: "second")
        let active = harness.frame(Self.page())
        #expect(
            active.contains { $0.contains("●") },
            """
            the section became active and its memoized subtree was served the \
            buffer drawn while it was inactive: \(active)
            """)
    }

    @Test("A memoized subtree drops the section indicator once its section stops being active")
    func indicatorLeavesAServedSubtree() {
        let harness = LoopHarness()
        harness.frame(Self.page())
        harness.focusManager.activateSection(id: "second")
        let active = harness.frame(Self.page())
        #expect(
            active.contains { $0.contains("●") }, "the active section drew no indicator: \(active)")

        // And back again: whatever was stored while the section was active must
        // not be served once it is not.
        harness.focusManager.activateSection(id: "first")
        let inactive = harness.frame(Self.page())
        #expect(
            !inactive.contains { $0.contains("●") },
            "the section stopped being active and its subtree still drew the indicator: \(inactive)")
    }
}
