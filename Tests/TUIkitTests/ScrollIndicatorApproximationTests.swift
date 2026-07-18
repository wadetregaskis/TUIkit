//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollIndicatorApproximationTests.swift
//
//  "N more above/below" honesty: on the anchored (variable-height) windowed
//  path the counts are LINES of the ESTIMATED absolute space — measured band
//  plus unmeasured-remainder × running pitch average — so the top-of-list
//  "below" count and the bottom-of-list "above" count come from two slightly
//  different refinements and need not agree (the §3 trade: estimates may
//  move the chrome, never the content). Such counts must READ as estimates:
//  "~10K more below", not a false-precision "10003 more below". Exact
//  counts (uniform path, eager content, List/Table rows) stay exact.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("scroll indicator approximation")
struct ScrollIndicatorApproximationTests {
    private static let viewport = 6

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Approximate labels compress magnitude with a tilde")
    func approximateLabels() {
        #expect(approximateCountLabel(7) == "~7")
        #expect(approximateCountLabel(897) == "~897")
        #expect(approximateCountLabel(1_000) == "~1K")
        #expect(approximateCountLabel(5_432) == "~5.4K")
        #expect(approximateCountLabel(9_949) == "~9.9K")
        #expect(approximateCountLabel(9_950) == "~10K", "ten of a unit drops the decimal")
        #expect(approximateCountLabel(54_321) == "~54K")
        #expect(approximateCountLabel(999_499) == "~999K")
        #expect(approximateCountLabel(999_500) == "~1M", "rounding to a unit's ceiling promotes")
        #expect(approximateCountLabel(200_000_903) == "~200M", "the reported 100M-row case")
        #expect(approximateCountLabel(1_500_000_000) == "~1.5B")
        #expect(approximateCountLabel(2_000_000_000_000) == "~2T")
    }

    @Test("Anchored-path indicators read approximate; uniform stay exact")
    func anchoredApproximateUniformExact() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        // Variable heights, above the anchored threshold: the content total
        // is an estimate, so the indicator must say so.
        let anchored = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<5_000, id: \.self) { i in
                    Text("row \(i)").frame(height: i % 3 + 1)
                }
            }
        }
        .frame(height: Self.viewport)
        renderFrame(anchored, tuiContext: tuiContext, focusManager: focusManager)
        let settled = renderFrame(anchored, tuiContext: tuiContext, focusManager: focusManager)
        let below = settled.last ?? ""
        #expect(below.contains("more below"), "the below indicator renders: \(settled)")
        #expect(below.contains("~"), "an estimated count reads as approximate: '\(below)'")
        let digitRun = below.reduce(into: (longest: 0, current: 0)) { acc, ch in
            acc.current = ch.isNumber ? acc.current + 1 : 0
            acc.longest = max(acc.longest, acc.current)
        }.longest
        #expect(
            digitRun <= 4,
            "estimated counts are compressed, not full digit runs: '\(below)'")

        // Uniform heights: the total is hypothesis-exact — full precision,
        // no tilde.
        let tuiContext2 = TUIContext()
        let focusManager2 = FocusManager()
        let uniform = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<5_000, id: \.self) { i in Text("row \(i)") }
            }
        }
        .frame(height: Self.viewport)
        renderFrame(uniform, tuiContext: tuiContext2, focusManager: focusManager2)
        let uniformSettled = renderFrame(
            uniform, tuiContext: tuiContext2, focusManager: focusManager2)
        let uniformBelow = uniformSettled.last ?? ""
        #expect(
            uniformBelow.contains("4994 more below"),
            "a uniform total is exact and stays fully precise: '\(uniformBelow)'")
        #expect(!uniformBelow.contains("~"), "no tilde on an exact count: '\(uniformBelow)'")
    }
}
