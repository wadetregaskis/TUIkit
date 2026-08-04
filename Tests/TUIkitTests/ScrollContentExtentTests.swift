//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollContentExtentTests.swift
//
//  A ScrollView's scrollable extent has NO ceiling.
//
//  Sizing the content used to offer it one fixed, enormous budget
//  (`max(viewport * 64, 4096)`). That does not remove the clamp every measure
//  applies — it relocates it. Content taller than the budget measured EXACTLY
//  the budget, so a ScrollView stopped 4,096 lines in: the rows past it existed,
//  rendered nowhere, and no amount of scrolling reached them. The budget is now
//  the first rung of a ladder that grows while the content keeps filling it
//  (``measureNaturalExtent``), so what bounds the answer is the content.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("ScrollView content extent is unbounded")
struct ScrollContentExtentTests {
    private static let viewport = 10

    /// Taller than the old 4,096-line budget by enough that a capped measure and
    /// an honest one cannot be confused for each other.
    private static let tallRowCount = 5_000

    private func context(width: Int = 40, height: Int = viewport) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
            .isolatingRenderCache()
    }

    private func lines<V: View>(_ view: V, width: Int = 40, height: Int = viewport) -> [String] {
        renderToBuffer(view, context: context(width: width, height: height))
            .lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The count out of an "N more lines above/below" indicator, taken as digits
    /// so the assertion doesn't depend on the locale's grouping separator.
    private func indicatorCount(in rendered: [String], containing marker: String) -> Int? {
        guard let line = rendered.first(where: { $0.contains(marker) }) else { return nil }
        return Int(String(line.filter(\.isNumber)))
    }

    // MARK: - The extent itself

    @Test("Eager content past the old budget is measured in full, not cut off at it")
    func eagerContentPastTheBudget() {
        let rendered = lines(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.tallRowCount, id: \.self) { Text("row \($0)") }
                }
            })
        // One viewport is on screen; everything else is below. Pre-fix this read
        // 4,086 — the 4,096-line canvas less the viewport — no matter how many
        // rows the content actually had.
        #expect(
            indicatorCount(in: rendered, containing: "more lines below")
                == Self.tallRowCount - Self.viewport,
            "the whole content is scrollable: \(rendered.last ?? "")")
    }

    @Test("The rows past the old budget can actually be reached")
    func lastRowIsReachable() {
        // Counting them is not the same as being able to get to them: this
        // renders the tail directly. The last row is the one furthest past the
        // old ceiling, so it is exactly the row that used to render nowhere.
        let rendered = lines(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.tallRowCount, id: \.self) { Text("row \($0)") }
                }
            }
            .defaultScrollAnchor(.bottom))
        #expect(
            rendered.contains { $0.hasPrefix("row \(Self.tallRowCount - 1)") },
            "the tail is reachable: \(rendered)")
    }

    @Test("Content that measures by RENDERING is unbounded too")
    func renderBasedMeasurePastTheBudget() {
        // A `Form` reports the height of a buffer it builds inside
        // `availableHeight` (`measureFixedByRendering`) rather than summing its
        // children analytically like a stack. Both clamp to the budget, so both
        // have to grow past it — a fix that only taught the stacks would leave
        // every control that measures this way capped.
        let rows = 6_000
        let rendered = lines(
            ScrollView { Form { ForEach(0..<rows, id: \.self) { Text("r \($0)") } } })
        #expect(
            indicatorCount(in: rendered, containing: "more lines below") == rows - Self.viewport,
            "\(rendered.last ?? "")")
    }

    // MARK: - The ladder

    @Test("The ladder converges on the natural extent along either axis")
    func ladderConvergesOnBothAxes() {
        let tall = VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.tallRowCount, id: \.self) { Text("row \($0)") }
        }
        let height = measureNaturalExtent(
            tall, along: .vertical,
            proposal: ProposedSize(width: 40, height: nil),
            context: context(), startingBudget: 4_096
        ).height
        #expect(height == Self.tallRowCount, "vertical extent is the content's, not the budget's")

        // The width axis had the identical cap (`max(contentWidth * 64, 4096)`)
        // for horizontal scrolling, and gets the identical ladder.
        let wide = HStack(spacing: 0) {
            ForEach(0..<Self.tallRowCount, id: \.self) { _ in Text("x") }
        }
        let width = measureNaturalExtent(
            wide, along: .horizontal,
            proposal: ProposedSize(width: nil, height: nil),
            context: context(), startingBudget: 4_096
        ).width
        #expect(width == Self.tallRowCount, "horizontal extent is the content's, not the budget's")
    }

    @Test("Content that fills whatever it is offered ends the ladder instead of inflating it")
    func flexibleContentTerminatesTheLadder() {
        // `.frame(maxHeight: .infinity)` reports every budget it is ever handed,
        // so "it filled the budget, offer more" would climb until the budget
        // overflowed `Int`. Reporting height-flexible is how such a view says the
        // question has no answer — the ladder stops at the first rung. (If this
        // ever regresses, it hangs rather than fails, which is why the assertion
        // is on the rung and not merely on reaching the end of the test.)
        let size = measureNaturalExtent(
            Text("F").frame(maxHeight: .infinity), along: .vertical,
            proposal: ProposedSize(width: 40, height: nil),
            context: context(), startingBudget: 4_096)
        #expect(size.height == 4_096, "stopped at the first rung: \(size.height)")
        #expect(size.isHeightFlexible, "…because the content said it fills what it is given")
    }

    @Test("Content that fits inside the first rung is unaffected")
    func shortContentUnchanged() {
        // The ladder must be invisible to ordinary content: a page that fits in
        // one rung resolves there, with the same extents (and the same single
        // measure) as before.
        let rendered = lines(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { Text("row \($0)") }
                }
            })
        #expect(rendered.first == "row 0")
        #expect(indicatorCount(in: rendered, containing: "more lines below") == 20 - Self.viewport)
    }
}
