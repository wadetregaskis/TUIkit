//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentWidthNaturalAskTests.swift
//
//  One question — how wide are ALL of a windowed stack's rows, asked by a
//  two-axis `ScrollView` of its content — and every arm of the stack that can
//  be the one to answer it: the exact walk (`StackContentWidth.swift`), the
//  anchored sample, the uniform band, the slot walk for small collections.
//  They must give one answer, on every frame, whichever answers: a row that
//  fills what it is offered counts its flexibility and never its width, a
//  capped answer is never flexible, and the ladder only walks at its own
//  widths. Each test was confirmed to fail with the rule it pins removed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Row `filler` fills whatever it is offered (`.frame(maxWidth: .infinity)`,
/// which reports the width it was given — unlike a `Divider`, which reports
/// one cell) or, when `nil`, is the same text unframed; row 50 is `wide`
/// cells; the rest are eight. The fixture of the filler tests.
private struct FillerRow: View {
    let index: Int
    let filler: Int?
    let wide: WidthBox

    var body: some View {
        if index == filler {
            Text("x").frame(maxWidth: .infinity)
        } else if index == 2 {
            Text("x")
        } else {
            Text(String(repeating: "\(index % 10)", count: index == 50 ? wide.cells : 8))
        }
    }
}

/// Row 7 is 6,000 cells, row 300 fills whatever it is offered, and the rest
/// are eight cells — the fixture of `aFillerDoesNotCapTheKeptExtent`.
private struct FillerOrTextRow: View {
    let index: Int

    var body: some View {
        if index == 300 {
            Divider()
        } else {
            Text(String(repeating: "0", count: index == 7 ? 6_000 : 8))
        }
    }
}

@MainActor
@Suite("A windowed stack's answer to the natural-width ask")
struct ContentWidthNaturalAskTests {
    private static let rows = 400
    private static let wideRowWidth = 120

    /// The ladder walks at its own widths and nowhere else. An unbounded ask
    /// can arrive at a terminal's width — an `HStack` measures its children
    /// `.unspecified` against its own, and a dialog probes its body at trial
    /// widths — and a sentence walked there WRAPS to a little under the width,
    /// which is filed as if it were the sentence's. The two-axis view's own
    /// probe at 4,096 then found a whole, current record and was served it:
    /// a 150-cell line laid out wrapped in a view that scrolls sideways.
    @Test("A terminal-width ask does not file a wrapped width")
    func aNarrowAskDoesNotWalk() {
        let ask = contentWidthAsks(
            tuiContext: TUIContext(),
            row: { index in Text(index == 200 ? wideText(150, breakable: true) : "01234567") })
        #expect(ask(96) == nil, "a 96-cell ask walked")
        #expect(ask(4_096) == 150, "the rung was served a wrapped width")
    }

    /// A horizontal inset takes its cells off the probe's width before the
    /// stack sees it, and a vertical one off its height: 4,096 arrives as
    /// 4,094. Recognised at exactly 4,096, a padded stack in any pane up to 64
    /// columns wide stopped answering for its rows out of sight.
    @Test(
        "A padded stack still answers for every row",
        arguments: [Edge.Set.horizontal, Edge.Set.vertical])
    func anInsetStackStillWalks(edges: Edge.Set) {
        let buffer = renderToBuffer(
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.rows, id: \.self) { index in
                        Text(
                            String(
                                repeating: "\(index % 10)",
                                count: index == 200 ? Self.wideRowWidth : 8))
                    }
                }
                .padding(edges, 1)
            },
            context: RenderContext(
                availableWidth: 40, availableHeight: 12, tuiContext: TUIContext()
            ).isolatingRenderCache())
        #expect(
            buffer.lines.last?.stripped.contains("\u{25C0}") == true,
            "no bar for the wide row at 200 under .padding(\(edges), 1)")
    }

    /// A collection of 256 rows or fewer is SEEDED whole — every row's width
    /// noted in the stack's running records — and those records only grow. The
    /// uniform path floored the exact answer with them, so once any row had
    /// been 120 cells the extent was 120 for good, whatever the row became.
    @Test("A small collection's extent follows its widest row down")
    func aSeededCollectionFollowsItsWidestRowDown() {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext, rows: { 100 },
            row: { index in
                Text(String(repeating: "\(index % 10)", count: index == 50 ? wide.cells : 8))
            })
        _ = frame()
        #expect(frame().stripped.contains("\u{25C0}"), "precondition: row 50 needs the bar")

        wide.cells = 8
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(
            !frame().stripped.contains("\u{25C0}"),
            "the records kept row 50's old width in the extent")
    }

    /// The anchored path samples its first sixteen rows for a width, and the
    /// widest row can be one of them. Sampled before the exact answer, the
    /// sample was served that row's old size from its memo — which the
    /// challenge, run just after in the same ask, found stale and dropped — and
    /// the ask answered the larger of the two: the width it had just corrected.
    /// Row 14 is in the sample and below a twelve-line viewport, and the write
    /// that narrows it is not about it, so its memo survives to be served.
    @Test("The ask that corrects the width answers the corrected width")
    func theAnchoredSampleFollowsTheChallenge() {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let tuiContext = TUIContext()
        let stack = { () -> _VStackCore<ForEach<Range<Int>, Int, Text>> in
            _VStackCore(
                alignment: .leading, spacing: 0, overflow: .window,
                content: ForEach(0..<Self.rows, id: \.self) { index in
                    Text(
                        String(
                            repeating: "0",
                            count: index == 14 ? wide.cells : index == 300 ? 60 : 8))
                })
        }
        func ask() -> Int? {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            // Under the probe's mark, as `measureNaturalExtent` asks.
            let context = RenderContext(
                availableWidth: 4_096, availableHeight: 4_096,
                environment: environment, tuiContext: tuiContext
            ).askingIdealWidth()
            let core = stack()
            return core.anchoredSizeThatFits(
                resolveChildViewCollection(from: core.content, context: context),
                proposal: ProposedSize(width: nil, height: nil), context: context)?.width
        }
        #expect(ask() == Self.wideRowWidth)

        wide.cells = 100
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: "Elsewhere"))
        #expect(ask() == 100, "the sample was served row 14's old width")
    }

    /// Nothing changed between the two measures, and the second must be the
    /// first. A capped answer used to carry the record's flexibility — every
    /// filler it had seen, including the `Divider` at row 300 — where the walk
    /// behind the first answer had stopped at row 7 and seen none, and the
    /// natural-extent ladder stops climbing at a capped FLEXIBLE answer. So a
    /// two-axis view's horizontal extent was 6,000 on its first frame and 4,096
    /// on its second, and the last 1,904 cells of row 7 went out of reach on a
    /// frame where nothing happened. (Asked of the ladder directly: at a
    /// 40-cell viewport both extents draw a one-cell thumb, so the bar cannot
    /// tell them apart.)
    @Test("A filler far down does not cap the extent on the second measure")
    func aFillerDoesNotCapTheKeptExtent() {
        let tuiContext = TUIContext()
        func extent() -> Int {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            return measureNaturalExtent(
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.rows, id: \.self) { FillerOrTextRow(index: $0) }
                },
                along: .horizontal, proposal: ProposedSize(width: nil, height: nil),
                context: RenderContext(
                    availableWidth: 40, availableHeight: 4_096,
                    environment: environment, tuiContext: tuiContext),
                startingBudget: 4_096
            ).width
        }
        #expect(extent() == 6_000, "precondition: the first measure finds row 7")
        #expect(extent() == 6_000, "the kept record capped the second at the first rung")
    }

    /// A row that fills whatever it is offered, drawn on screen. Its measured
    /// width is the width it was given — last frame's canvas — so a band floor
    /// that counted it held the extent at last frame's width for good: row 50
    /// shrinks from 120 cells to 8, nothing is wider than the viewport any
    /// more, and the bar stayed. The walk leaves fillers out of its maximum;
    /// the floor does the same.
    @Test("A filler on screen does not hold the extent up")
    func aFillerOnScreenDoesNotHoldTheExtent() {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext,
            row: { index in FillerRow(index: index, filler: 2, wide: wide) })
        _ = frame()
        #expect(frame().stripped.contains("\u{25C0}"), "precondition: row 50 needs the bar")

        wide.cells = 8
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(
            !frame().stripped.contains("\u{25C0}"),
            "the filler on screen held the extent at last frame's canvas")
    }

    /// The first frame and the second must agree, and neither may count a
    /// filler's width: the first frame is answered by the anchored sample (over
    /// 256 rows) or by measuring every row (at or under), and both counted the
    /// filler at the ladder's rung — a canvas thousands of cells wide — where
    /// the second frame's exact walk leaves it out. Same bar as the content
    /// with the filler's frame taken off.
    @Test("A filler does not make the first frame differ from the second", arguments: [100, 400])
    func aFillerCountsTheSameOnEveryFrame(rows: Int) {
        let wide = WidthBox(cells: Self.wideRowWidth)
        let frame = twoAxisFrames(
            tuiContext: TUIContext(), rows: { rows },
            row: { index in FillerRow(index: index, filler: 2, wide: wide) })
        let first = frame()
        let second = frame()
        let inflexible = twoAxisFrames(
            tuiContext: TUIContext(), rows: { rows },
            row: { index in FillerRow(index: index, filler: nil, wide: wide) })
        _ = inflexible()
        let control = inflexible()
        #expect(first == second, "first \(first.debugDescription), second \(second.debugDescription)")
        #expect(
            second == control,
            "the filler widened the canvas: \(second.debugDescription) vs \(control.debugDescription)")
    }

    /// The other half of the walk's rule: a CAPPED answer is never flexible,
    /// because the natural-extent ladder stops climbing at a flexible answer
    /// that reached its budget. At 200 columns the first rung is 12,800 cells
    /// and row 50 is 20,000. Every arm used to call that capped answer flexible
    /// when a filler had been seen — the slot walk and the anchored sample on
    /// the first frame, the band's sticky flag from then on — and the ladder
    /// stopped at 12,800, leaving 7,200 cells of row 50 out of reach. So every
    /// frame must match the same content with the filler's frame taken off.
    @Test("A filler does not stop the ladder short of the widest row", arguments: [100, 400])
    func aFillerDoesNotStopTheLadder(rows: Int) {
        let wide = WidthBox(cells: 20_000)
        func frames(filler: Int?) -> () -> String {
            twoAxisFrames(
                tuiContext: TUIContext(), rows: { rows }, width: 200,
                row: { index in FillerRow(index: index, filler: filler, wide: wide) })
        }
        let withFiller = frames(filler: 2)
        let control = frames(filler: nil)
        let controlFirst = control()
        let controlSecond = control()
        #expect(withFiller() == controlFirst, "the first frame stopped at the filler's rung")
        #expect(withFiller() == controlSecond, "the second frame stopped at the filler's rung")
    }

    /// The same rules for the uniform path's own sample — the branch that
    /// answers while the one-height hypothesis is live but the width records
    /// have not been seeded. No render leaves that state today (the render
    /// that seeds the one seeds the other), so it is built here by hand: the
    /// branch is a fallback, and a fallback that answered differently from
    /// every other arm would be a trap for whatever reaches it next. At the 4,096
    /// rung with a filler among the sampled rows: row 50 at 120 cells is
    /// answered 120, not the width the filler was offered; at 6,000 it is
    /// capped, and a capped answer is NOT flexible, as the walk says.
    @Test("The uniform sample counts a filler as the walk does", arguments: [120, 6_000])
    func theUniformSampleCountsAFillerAsTheWalkDoes(cells: Int) {
        let wide = WidthBox(cells: cells)
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(VolatileReadTracker())
        // Under the probe's mark, as `measureNaturalExtent` asks.
        let context = RenderContext(
            availableWidth: 4_096, availableHeight: 4_096,
            environment: environment, tuiContext: tuiContext
        ).askingIdealWidth()
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: ForEach(0..<Self.rows, id: \.self) { index in
                FillerRow(index: index, filler: 2, wide: wide)
            })
        stack.uniformWindowState(context: context).hypothesisExtent = 1
        let size = stack.uniformSeekSizeThatFits(
            resolveChildViewCollection(from: stack.content, context: context),
            proposal: ProposedSize(width: nil, height: nil), context: context)
        #expect(size?.width == min(cells, 4_096), "the filler's offered width was counted")
        #expect(
            size?.isWidthFlexible == (cells < 4_096),
            "a capped answer called flexible stops the ladder at its first rung")
    }

    /// What a band records of a filler outlives it — the records only grow,
    /// and the band's once was a flag, set the first time any drawn row
    /// filled and never cleared — so the uniform arm, which OR'd it into its
    /// answer, went on calling the stack flexible after the last filler had
    /// left the data, where the walk (over every row, now) said not. With the
    /// exact answer in hand, its flexibility stands alone.
    @Test("A filler that has left the data leaves no flexibility behind")
    func aDepartedFillerLeavesNoFlexibility() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(VolatileReadTracker())
        // Under the probe's mark, as `measureNaturalExtent` asks.
        let context = RenderContext(
            availableWidth: 4_096, availableHeight: 4_096,
            environment: environment, tuiContext: tuiContext
        ).askingIdealWidth()
        let wide = WidthBox(cells: Self.wideRowWidth)
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: ForEach(0..<Self.rows, id: \.self) { index in
                FillerRow(index: index, filler: nil, wide: wide)
            })
        // What a band that once drew a filler leaves behind.
        let state = stack.uniformWindowState(context: context)
        state.hypothesisExtent = 1
        let departed = ViewSize(width: 4_096, height: 1, isWidthFlexible: true)
        state.rowWidths.note(ordinal: 0, size: departed)
        state.rowWidths.markSeeded()
        state.bandFillers = [0]
        state.bandFillReach = departed.width
        let size = stack.uniformSeekSizeThatFits(
            resolveChildViewCollection(from: stack.content, context: context),
            proposal: ProposedSize(width: nil, height: nil), context: context)
        #expect(size?.width == Self.wideRowWidth)
        #expect(size?.isWidthFlexible == false, "the filler's record outlived the filler")
    }

    /// A filler with an alignment guide, in the arm that answers for guided
    /// rows (the uniform and anchored arms decline them). The guide run took
    /// the filler's raw width — the rung it was offered — so the answer came out
    /// at the limit, capped and therefore inflexible, and the ladder climbed
    /// every rung to the edge of `Int`, the filler reporting each new rung: a
    /// canvas about 10^18 cells wide. It must come back as the widest real
    /// row.
    @Test("A guided filler does not run the ladder away")
    func aGuidedFillerDoesNotRunTheLadderAway() {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let size = measureNaturalExtent(
            LazyVStack(alignment: .leading, spacing: 0) {
                // Inline, not wrapped in a row type: the guide has to be the
                // `ForEach` content's own type for the stack to see it (a row
                // type hides it, and `ForEach` memoises the row instead).
                ForEach(0..<50, id: \.self) { index in
                    Text(index == 10 ? String(repeating: "0", count: Self.wideRowWidth) : "x")
                        .frame(maxWidth: index == 10 ? nil : .infinity, alignment: .leading)
                        .alignmentGuide(.leading) { $0[.leading] }
                }
            },
            along: .horizontal, proposal: ProposedSize(width: nil, height: nil),
            context: RenderContext(
                availableWidth: 40, availableHeight: 4_096,
                environment: environment, tuiContext: tuiContext),
            startingBudget: 4_096)
        #expect(size.width == Self.wideRowWidth, "the ladder ran to \(size.width)")
    }
}
