//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarRegionShiftTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Drives the probe header's height from outside the app: `App` requires a bare
/// `init()`, so it cannot carry test state itself. Same trick as
/// `RenderPassScopeTests.ProbeState`, whose own copy is `private` to that file.
private final class HeaderLines: @unchecked Sendable {
    static let shared = HeaderLines()
    var count = 1
}

private struct ShiftProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .appHeader {
                    VStack(spacing: 0) {
                        ForEach(0..<HeaderLines.shared.count, id: \.self) { i in
                            Text("header \(i)")
                        }
                    }
                }
        }
    }
}

@MainActor
@Suite("Status-bar hit regions follow the drawn header height", .serialized)
struct StatusBarRegionShiftTests {

    /// A one-row bar whose item regions sit at local y = 0, so the content y a
    /// click on the bar translates to is exactly the content height — no bar
    /// chrome to add. System items off so the only clickable thing in the bar
    /// is the probe item.
    private func makeHarness(itemFired: @escaping () -> Void) -> RenderLoopHarness {
        let harness = RenderLoopHarness()
        harness.statusBar.style = .compact
        harness.statusBar.showSystemItems = false
        harness.statusBar.setItems([
            StatusBarItem(shortcut: "x", label: "run", action: itemFired)
        ])
        return harness
    }

    /// The content y that a click on the bar's row arrives as, translated
    /// exactly as `App.drainTerminalEvents` translates it: terminal y minus the
    /// DRAWN header height.
    private func barContentRow(_ harness: RenderLoopHarness) -> Int {
        contentAreaHeight(
            terminalHeight: harness.terminal.size.height,
            statusBarHeight: harness.statusBar.height,
            headerHeight: harness.appHeader.height)
    }

    /// Presses and releases at every column of one content row — a click is a
    /// press AND a release (an unpaired release is deliberately not routed),
    /// and sweeping the row avoids depending on where `.justified` alignment
    /// happens to place the item.
    private func clickRow(_ harness: RenderLoopHarness, y: Int) {
        let dispatcher = harness.tuiContext.mouseEventDispatcher
        for x in 0..<harness.terminal.size.width {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }
    }

    @Test("A frame whose header grew still routes a click on the status bar")
    func statusBarStaysClickableAfterHeaderGrows() {
        HeaderLines.shared.count = 1
        var fired = 0
        let harness = makeHarness { fired += 1 }
        let loop = harness.loop(ShiftProbeApp())

        _ = loop.render()  // frame 1: measure walk + draw
        _ = loop.render()  // frame 2: estimate == actual

        // Sanity, so the test fails loudly rather than passing vacuously if the
        // bar ever stops emitting regions at all: 24 - 1 - 3 = 20.
        #expect(barContentRow(harness) == 20)
        clickRow(harness, y: barContentRow(harness))
        #expect(fired >= 1, "pre-condition: the bar is clickable on a steady frame")

        // Grow the header by one line. The frame lays out against the previous
        // height (3) and re-renders at the real one (4).
        HeaderLines.shared.count = 2
        let headerBefore = harness.appHeader.height
        _ = loop.render()
        #expect(
            harness.appHeader.height == headerBefore + 1,
            "pre-condition: the header must change height, or nothing is under test")
        #expect(barContentRow(harness) == 19)

        fired = 0
        clickRow(harness, y: barContentRow(harness))
        #expect(fired >= 1, "a click on the bar's row must reach the item after the header grew")
    }

    @Test("A frame whose header shrank does not park status-bar regions on a content row")
    func statusBarRegionsLeaveContentRowsAloneAfterHeaderShrinks() {
        HeaderLines.shared.count = 3
        var fired = 0
        let harness = makeHarness { fired += 1 }
        let loop = harness.loop(ShiftProbeApp())

        _ = loop.render()
        _ = loop.render()
        #expect(barContentRow(harness) == 18)  // 24 - 1 - 5

        HeaderLines.shared.count = 1
        let headerBefore = harness.appHeader.height
        _ = loop.render()
        #expect(
            harness.appHeader.height == headerBefore - 2,
            "pre-condition: the header must shrink by two rows")

        let barRow = barContentRow(harness)
        #expect(barRow == 20)  // 24 - 1 - 3

        // The stale estimate put the regions at 18 — a real page row, two above
        // the bar. `matchingRegions` searches reversed and the status-bar
        // regions are appended last, so they would beat the page's own control.
        fired = 0
        clickRow(harness, y: barRow - 2)
        #expect(fired == 0, "a click on a page row must not reach a status-bar item")

        fired = 0
        clickRow(harness, y: barRow)
        #expect(fired >= 1, "a click on the bar's own row must reach the item")
    }
}
