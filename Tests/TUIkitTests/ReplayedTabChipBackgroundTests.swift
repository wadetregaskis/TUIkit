//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayedTabChipBackgroundTests.swift
//
//  A focused compact tab chip breathes, and every tick of that breath is a
//  replay: its frame spliced into the row already on screen. Both of the chip's
//  caps are ink with no field of their own, so the replay has to leave them on
//  whatever the render drew them on — the page for a top-level strip, the
//  enclosing tab's surface for a nested one.
//
//  Driven through `RenderLoop` rather than through `FrameBuffer`'s splice,
//  because the fault was in front of the splice: the replay put the PAGE's
//  background back after every reset in the frame before handing it over, and a
//  background the frame names is one the splice keeps. The left cap comes before
//  the frame's first reset and survived; the right cap comes after two, and was
//  drawn in the page's colour inside the outer tab. Every headless replay
//  assertion (`expectReplayIsIdentity`) calls the splice directly, which is why
//  none of them could see it. The replay now paints each cap over the field the
//  outer tab's `.background` recorded beneath it (`AnimatedCellRun.ground`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Two compact chips, the first selected: its left cap sits on whatever the
/// strip is drawn over, and its right cap between its own label and the
/// inactive chip.
@MainActor
private func chips() -> some View {
    TabView(selection: .constant(0)) {
        Tab("Appearance", value: 0) { Text("inner body text") }
        Tab("Behaviour", value: 1) { Text("b") }
    }
    .tabViewStyle(.compact)
    .tabViewHeaderAlignment(.leading)
}

/// The same chips inside a tab of an outer strip of `style`, the Example's
/// "Nested" demo in miniature.
@MainActor
private func nested(in style: TabViewStyle) -> some View {
    TabView(selection: .constant(0)) {
        Tab("General", value: 0) { VStack(alignment: .leading, spacing: 0) { chips() } }
        Tab("Network", value: 1) { Text("n") }
    }
    .tabViewStyle(style)
}

private struct TopLevelChipsApp: App {
    init() {}
    var body: some Scene { WindowGroup { chips() } }
}

private struct ChipsInBorderedTabApp: App {
    init() {}
    var body: some Scene { WindowGroup { nested(in: .bordered) } }
}

private struct ChipsInCompactTabApp: App {
    init() {}
    var body: some Scene { WindowGroup { nested(in: .compact) } }
}

@MainActor
@Suite("A replayed tab chip keeps both caps on what it is drawn over")
struct ReplayedTabChipBackgroundTests {

    enum Placement: String, CaseIterable, Sendable {
        case topLevel, inBorderedTab, inCompactTab
    }

    /// Renders `app` with the chips' strip focused, then replays every frame of
    /// the active chip's breath through the loop. Returns the row as rendered and
    /// the row after each tick, with the run that was replayed and the page's
    /// background escape.
    private func replayedRows<A: App>(
        _ app: A, focusSteps: Int
    ) throws -> (run: AnimatedCellRun, rendered: String, ticks: [String], page: String) {
        let harness = RenderLoopHarness()
        let loop = harness.loop(app)
        _ = loop.render()
        // The first strip to register takes the focus; a nested strip is the
        // second, so the focus is moved on to it before the frame under test.
        for _ in 0..<focusSteps { harness.focusManager.focusNext() }
        _ = loop.render()

        let frame = try #require(loop.replayable, "the render kept no frame to replay")
        let run = try #require(
            frame.runs.first { $0.frame(atIndex: 0).stripped.contains("Appearance") },
            "the focused chip left no run: \(frame.runs)")
        var ticks: [String] = []
        for index in run.frames.indices {
            // Half a tick into the frame's first tick, so no rounding at a step
            // boundary can land the replay on its neighbour.
            let elapsed =
                AnimationClock.seconds(forTicks: index * run.frameTicks)
                + AnimationClock.seconds(forTicks: 1) / 2
            _ = loop.replayAnimations(elapsed: [run.clock: elapsed])
            let patched = try #require(
                loop.replayable?.lastPatched[run.offsetY]?.line, "tick \(index) patched nothing")
            ticks.append(patched)
        }
        return (run, frame.contentLines[run.offsetY], ticks, frame.backgroundCode)
    }

    @Test("Both caps of a breathing chip keep their background on every tick", arguments: Placement.allCases)
    func capsKeepTheirBackground(placement: Placement) throws {
        let (run, rendered, ticks, page) =
            switch placement {
            case .topLevel: try replayedRows(TopLevelChipsApp(), focusSteps: 0)
            case .inBorderedTab: try replayedRows(ChipsInBorderedTabApp(), focusSteps: 1)
            case .inCompactTab: try replayedRows(ChipsInCompactTabApp(), focusSteps: 1)
            }
        #expect(!page.isEmpty, "the palette paints no page, so nothing here can tell the two apart")

        let drawn = paintedCells(rendered)
        let left = run.offsetX
        let right = run.offsetX + run.width - 1
        try #require(drawn.indices.contains(right), "the run runs off its row")
        #expect(drawn[left].glyph == "▐" && drawn[right].glyph == "▌", "the run is not the chip")

        // What the render drew the caps on, which every tick must keep. A cap is
        // ink with no field of its own, so both are on the same ground: the page
        // at the top level, and the enclosing tab's surface — NOT the page — when
        // nested.
        let ground = drawn[left].background
        #expect(drawn[right].background == ground, "the render itself drew the caps on two grounds")
        if placement == .topLevel {
            #expect(ground == page, "a top-level strip sits on the page")
        } else {
            #expect(ground != page, "the nested strip's ground is the page, so this cannot catch the fault")
        }

        for (index, tick) in ticks.enumerated() {
            let cells = paintedCells(tick)
            try #require(cells.count == drawn.count, "tick \(index) changed the row's width")
            #expect(
                cells[left].background == ground,
                "tick \(index): the left cap is on \(cells[left].background.debugDescription), not \(ground.debugDescription)")
            #expect(
                cells[right].background == ground,
                "tick \(index): the right cap is on \(cells[right].background.debugDescription), not \(ground.debugDescription)")
            // And nothing else the run covers moved field either: a breath is in
            // the label's ink.
            for column in left...right where cells[column].background != drawn[column].background {
                Issue.record(
                    "tick \(index): column \(column) went from \(drawn[column].background.debugDescription) to \(cells[column].background.debugDescription)")
            }
        }
    }
}
