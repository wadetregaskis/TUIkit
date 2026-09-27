//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListBadgedLineRunAlphaTests.swift
//
//  A List row carrying a `.badge(_:)` re-lays its first line's columns to make
//  room — and keeps the line. It dropped every child run on that line, and a run
//  that states its alpha per frame took the only statement about its cells with
//  it, so a several-alpha border drew an opaque top rule above its faded walls
//  (§69.4). A run is cut now to the content the badge keeps, as far as the columns
//  mean what the child drew there, and only what the badge cuts off is dropped: a
//  run dropped whole froze, a spinner at the glyph it was drawn with.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// A list whose rows are badged, a spinner on each first line — the focus on a
/// button above it, so its cursor row does not breathe (a breathing row repaints its
/// whole line, and asks for renders for the runs it drops for that).
private struct BadgedSpinnerApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                List {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) { Text("row \(row) "); Spinner() }.badge(3)
                    }
                }
                .frame(width: 24, height: 4)
            }
        }
    }
}

/// A list whose rows are badged and truncated, a breathing border around each row's
/// label: the top rule is cut by the badge, and the ellipsis it ends in is drawn in the
/// rule's colour, which breathes.
private struct TruncatedBreathingBorderApp: App {
    init() {}
    var body: some Scene { WindowGroup { TruncatedBreathingBorder() } }
}

private struct TruncatedBreathingBorder: View {
    @Environment(\.selectionEmphasis) private var emphasis
    var body: some View {
        VStack(spacing: 0) {
            Button("focus") {}
            List {
                ForEach(0..<2, id: \.self) { _ in
                    Text(String(repeating: "x", count: 40))
                        .border(emphasis.animatedColor(true, dim: .rgb(200, 40, 40), bright: .rgb(40, 200, 40)))
                        .badge(3)
                }
            }
            .frame(width: 24, height: 6)
        }
    }
}

/// A run at a badged row's cut whose second frame ends on a blank: the cut drops it,
/// and the ellipsis moves a column left in that frame.
private struct BlankAtTheCut: View, Renderable {
    var body: Never { fatalError("renders via Renderable") }
    static let plainFrames = ["ab", "a "]
    /// The same two frames, coloured, as a styled glyph renders: each ends in the reset
    /// that closes it, never in its blank.
    static let colouredFrames = ["\u{1B}[31mab\u{1B}[0m", "\u{1B}[31ma \u{1B}[0m"]

    /// Two frames alike but for their colour, which a run starting in the column the
    /// ellipsis takes gives the ellipsis: the cut keeps the frame's opening escape.
    static let recolouredFrames = ["\u{1B}[31mab\u{1B}[0m", "\u{1B}[32mab\u{1B}[0m"]

    var frames = Self.plainFrames
    var frameTicks = AnimationClock.standardFrameTicks
    /// How many cells of the line come before the run.
    var lead = 15

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let run = AnimatedCellRun(
            offsetX: lead, offsetY: 0, width: 2, frames: frames, frameTicks: frameTicks, clock: .content)
        let elapsed = Double(context.environment.frameNowNanos) / 1_000_000_000
        var buffer = FrameBuffer(lines: [String(repeating: "x", count: lead) + run.frame(atElapsed: elapsed) + "cdef"])
        guard !context.isMeasuring else { return buffer }
        buffer.animatedCells = [run]
        return buffer
    }
}

private struct BlankAtTheCutApp: App {
    var frames = BlankAtTheCut.plainFrames
    /// Each row's step, in ticks.
    var frameTicks = [AnimationClock.standardFrameTicks, AnimationClock.standardFrameTicks]
    var lead = 15
    init() {}
    init(frames: [String], frameTicks: [Int], lead: Int = 15) {
        self.frames = frames
        self.frameTicks = frameTicks
        self.lead = lead
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                List {
                    ForEach(0..<2, id: \.self) { row in
                        BlankAtTheCut(frames: frames, frameTicks: frameTicks[row], lead: lead).badge(3)
                    }
                }
                .frame(width: 24, height: 4)
            }
        }
    }
}

/// A real spinner with a blank among its frames, `.shade`, in badged rows of a list
/// `width` cells wide.
private struct ShadeAtTheCutApp: App {
    var width = 12
    init() {}
    init(width: Int) { self.width = width }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("focus") {}
                List {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 1) { Text("Job"); Spinner(style: .shade); Text("running") }.badge(3)
                    }
                }
                .frame(width: width, height: 4)
            }
        }
    }
}

@MainActor
@Suite("A badged List row's first-line runs")
struct ListBadgedLineRunAlphaTests {

    private struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private let rows = (0..<3).map { Row(id: $0, name: "row\($0)") }

    /// One colour at two alphas, drawn at the faded frame, for the reason
    /// `ListBreathingRowRunAlphaTests` gives: at the opaque one there is nothing to leave.
    private var border: AnimatedColor {
        AnimatedColor(frames: [Color.rgb(200, 40, 40), Color.rgb(200, 40, 40).opacity(0.5)], step: 1)
    }

    private func draw<V: View>(_ list: V, height: Int) -> FrameBuffer {
        renderToBuffer(
            list,
            context: RenderContext(availableWidth: 30, availableHeight: height, tuiContext: TUIContext())
                .isolatingRenderCache())
    }

    /// The column the badge's glyph landed on, on buffer line `line`.
    private func badgeColumn(in drawn: FrameBuffer, line: Int) throws -> Int {
        let text = drawn.lines.count > line ? drawn.lines[line].stripped : ""
        return try #require(Array(text).lastIndex(of: "3"), "no badge on line \(line): \(text)")
    }

    /// No focus manager and no selection, so no row breathes: this is the ordinary
    /// return, and the badge is the only thing on a first line that could cut a run.
    /// Each row is three lines inside the list's border, so their first lines — their
    /// top rules — are 1, 4 and 7, and the badge sits far enough right that nothing
    /// is truncated: each top rule is carried whole, its alpha on it, clear of the
    /// badge, and nothing is left behind for it. Dropped, as a badged first line's
    /// runs were until 2026-09-26, it left its drawn alpha behind and froze.
    @Test("A badged row's several-alpha top rule is carried with its alpha, short of the badge")
    func badgedLineCarriesItsRun() throws {
        let drawn = draw(
            List {
                ForEach(rows) { row in Text(row.name).border(border).badge(3) }
            },
            height: 14)
        let runs = drawn.animatedCells.map { "y=\($0.offsetY) w=\($0.width) alpha=\($0.alpha != nil)" }
        let firstLines: Set<Int> = [1, 4, 7]

        let badge = try badgeColumn(in: drawn, line: 1)
        let onFirstLines = drawn.animatedCells.filter { $0.alpha != nil && firstLines.contains($0.offsetY) }
        #expect(Set(onFirstLines.map(\.offsetY)) == firstLines, "a top rule was dropped: \(runs)")
        #expect(onFirstLines.allSatisfy { $0.offsetX + $0.width <= badge }, "a top rule reaches the badge at \(badge): \(runs)")
        let owed = drawn.opacityRegions.filter { $0.inkOpacity < 1 && firstLines.contains($0.offsetY) }
        #expect(owed.isEmpty, "a carried top rule left its alpha behind as well: \(owed)")
    }

    /// A spinner on a badged row's first line, through the run loop: carried, it turns
    /// between renders. Dropped, nothing asked for the render that would have moved it,
    /// and it held the glyph it was drawn with while a render moved it on.
    @Test("A spinner on a badged row keeps turning between renders")
    func aSpinnerOnABadgedRowTurns() throws {
        let found = ReplayOracle.compare({ BadgedSpinnerApp() }, ticks: 24, size: (30, 6))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        #expect(found.movedGlyphs > 0, "no replay moved the spinner")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// The ellipsis a truncated badged line ends in is drawn in the state its cut leaves
    /// open, which is the rule's own colour where the rule is at the cut: through the run
    /// loop, every tick shows it in the colour a render at that instant draws. Cut short
    /// of it, the rule breathed and the ellipsis held the colour it was drawn in (23
    /// ticks of 24).
    @Test("The ellipsis a truncated badged row ends in breathes with the rule it cuts")
    func theEllipsisBreathesWithTheRule() throws {
        let found = ReplayOracle.compare({ TruncatedBreathingBorderApp() }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// A run whose frames move the ellipsis — one ends on a blank the cut drops — cannot
    /// say it: it is cut short, and the row asks for a render at each of its steps, which
    /// draws the ellipsis where that frame puts it. Carried as it was, the ellipsis stayed
    /// where the frame drawn put it (24 mismatches in 24 ticks).
    @Test("A run whose frames move the ellipsis asks for a render at each step")
    func aRunThatMovesTheEllipsis() throws {
        let found = ReplayOracle.compare({ BlankAtTheCutApp() }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        #expect(found.scheduledRenders > 0, "no render was asked for")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// The same frames coloured, as every styled glyph is drawn: each ends in its reset
    /// after the blank, and the cut keeps the reset — it keeps every escape before the
    /// cell it stops at — which shields the blank from the trailing blanks it drops. So
    /// no frame moves the ellipsis, and the run replays as it is carried. A guard: it
    /// passed before, and a check that read the frames' last VISIBLE cell instead of
    /// their last byte would cut the run short and ask for renders it needs not.
    @Test("A coloured run ending in its reset leaves the ellipsis where it is")
    func aColouredRunLeavesTheEllipsis() throws {
        let found = ReplayOracle.compare(
            { BlankAtTheCutApp(frames: BlankAtTheCut.colouredFrames, frameTicks: [3, 3]) }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        #expect(found.scheduledRenders == 0, "\(found.scheduledRenders) renders were asked for")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// A run that starts in the column the cut gives the ellipsis: none of its cells is
    /// kept, but the cut keeps its opening escape, and the ellipsis is drawn in each
    /// frame's colour. Taken for one the cut leaves alone, the run was dropped and the
    /// ellipsis held the drawn frame's colour.
    @Test("A run starting at the ellipsis recolours it frame by frame")
    func aRunStartingAtTheEllipsis() throws {
        let found = ReplayOracle.compare(
            { BlankAtTheCutApp(frames: BlankAtTheCut.recolouredFrames, frameTicks: [3, 3], lead: 17) },
            ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// Two rows whose runs move the ellipsis, stepping apart: each asks for a render at
    /// its own steps. Asked under one token for the whole list, the second row's request
    /// replaced the first's, and the first row's ellipsis held between the second's steps.
    @Test("Two rows whose runs move the ellipsis each ask for a render at their own steps")
    func twoRowsThatMoveTheEllipsis() throws {
        let found = ReplayOracle.compare(
            { BlankAtTheCutApp(frames: BlankAtTheCut.plainFrames, frameTicks: [3, 7]) }, ticks: 24, size: (30, 8))
        try #require(found.compared >= 24, "only \(found.compared) rows were compared")
        #expect(found.scheduledRenders > 0, "no render was asked for")
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: mismatch)) }
    }

    /// A real `.shade` spinner, whose first frame is a blank, in a badged row, at every
    /// width that puts it at the cut — the ellipsis in its cell, then just after it —
    /// or a cell short of it: every tick shows what a render at that instant draws.
    @Test("A shade spinner at a badged row's cut replays as it renders", arguments: 10...13)
    func aShadeSpinnerAtTheCut(width: Int) throws {
        let found = ReplayOracle.compare({ ShadeAtTheCutApp(width: width) }, ticks: 24, size: (30, 8))
        for mismatch in found.mismatches { Issue.record(Comment(rawValue: "width \(width): \(mismatch)")) }
    }

    /// A row the badge actually TRUNCATES, which the row above never is. Its top rule
    /// is as wide as the row lets content be, so it fits the row's geometry and is cut
    /// only for the badge: carried as far as the content the badge keeps, the ellipsis
    /// the truncation draws included — drawn in the state the cut leaves open, which is
    /// the rule's own colour, frame by frame — and what is cut off, past the content,
    /// leaves nothing to claim there, so none of it runs on over the fill and the
    /// badge. Cut short of the ellipsis, the rule turned and the ellipsis kept the
    /// colour it was drawn in.
    @Test("A truncated badged row's top rule is carried to the ellipsis it ends in")
    func truncatedBadgedLineStopsAtTheContent() throws {
        let drawn = draw(
            List {
                Text(String(repeating: "x", count: 40)).border(border).badge(3)
            },
            height: 10)
        let badge = try badgeColumn(in: drawn, line: 1)
        let ellipsis = try #require(Array(drawn.lines[1].stripped).firstIndex(of: "…"), "the line is not truncated")
        let rule = try #require(drawn.animatedCells.first { $0.offsetY == 1 && $0.alpha != nil }, "the top rule was dropped")
        #expect(rule.offsetX + rule.width == ellipsis + 1, "the rule runs to \(rule.offsetX + rule.width), the ellipsis is at \(ellipsis)")
        // Every frame ends in the ellipsis, in that frame's own ink.
        for (index, frame) in rule.frames.enumerated() {
            let cells = paintedCells(frame)
            #expect(cells.last?.glyph == "…", "frame \(index) ends in \(cells.last?.shown ?? "nothing")")
            #expect(cells.last?.ink == cells.dropLast().last?.ink, "frame \(index): \(cells.suffix(2).map(\.shown))")
        }
        let owed = drawn.opacityRegions.filter { $0.inkOpacity < 1 && $0.offsetY == 1 }
        let reach = owed.map { $0.offsetX + $0.width }.max() ?? 0
        #expect(reach < badge, "a region reaches column \(reach), at or past the badge at \(badge): \(owed)")
    }
}
