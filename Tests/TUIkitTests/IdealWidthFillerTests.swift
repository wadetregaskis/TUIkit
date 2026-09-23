//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IdealWidthFillerTests.swift
//
//  A row that fills its width, asked how wide it would be if nothing stopped
//  it. A `.frame(maxWidth: .infinity)` answers with its content, as SwiftUI's
//  does under an unspecified proposal; a view with nothing to answer with — a
//  `TextEditor`, greedy on both axes — has no width of its own, and every
//  stack that adds up its rows' widths for that ask leaves it out.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Row 50 is 120 cells of text — inside a `.frame(maxWidth: .infinity)` when
/// `framed` — and the rest are eight.
private struct FramedWideRow: View {
    let index: Int
    let framed: Bool

    var body: some View {
        if index == 50 {
            if framed {
                Text(String(repeating: "5", count: 120)).frame(maxWidth: .infinity)
            } else {
                Text(String(repeating: "5", count: 120))
            }
        } else {
            Text(String(repeating: "\(index % 10)", count: 8))
        }
    }
}

/// One row of `aFrameAnswersWithItsContent`'s table: `cells` of text in a
/// `.frame(minWidth:idealWidth:maxWidth: .infinity)`, measured at a 4,096-cell
/// offer under `proposal`, with or without the ideal-width mark.
struct IdealFrameCase: Sendable, CustomTestStringConvertible {
    var cells: Int
    var minWidth: Int?
    var idealWidth: Int?
    var marked = true
    var proposal: Int?
    var width: Int
    var flexible: Bool

    var testDescription: String {
        "\(cells) cells, min \(minWidth.map(String.init) ?? "-"), ideal \(idealWidth.map(String.init) ?? "-"), "
            + "\(marked ? "marked" : "unmarked"), proposal \(proposal.map(String.init) ?? "nil")"
    }
}

/// How many times a `TallySpy` was measured.
private final class MeasureTally: @unchecked Sendable {
    var count = 0
}

/// A leaf `width` cells wide that counts its measures.
private struct TallySpy: View, Renderable, Layoutable {
    let tally: MeasureTally
    let width: Int

    var body: Never { fatalError("TallySpy renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: [String(repeating: "0", count: width)], width: width)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        tally.count += 1
        return ViewSize.fixed(width, 1)
    }
}

/// The horizontal natural extent of `view`, asked as a two-axis `ScrollView`
/// asks it of its content.
@MainActor
private func horizontalExtent(of view: some View) -> ViewSize {
    let tuiContext = TUIContext()
    var environment = EnvironmentValues()
    environment.applyRuntimeServices(from: tuiContext)
    return measureNaturalExtent(
        view, along: .horizontal, proposal: ProposedSize(width: nil, height: nil),
        context: RenderContext(
            availableWidth: 40, availableHeight: 4_096,
            environment: environment, tuiContext: tuiContext),
        startingBudget: 4_096)
}

@MainActor
@Suite("A row that fills its width, asked for its ideal one")
struct IdealWidthFillerTests {
    /// What a filling frame tells the ideal-width ask, and what it tells
    /// everything else. Under the ask it is its content's width — floored by a
    /// minimum, replaced by an ideal — and flexible, because it still fills
    /// whatever it is later given; a CAPPED answer is flexible only if the
    /// content itself fills, since the ladder stops climbing at a flexible
    /// answer that reached its budget. Anything else is filled as before.
    @Test(
        "A filling frame answers the ideal-width ask with its content",
        arguments: [
            IdealFrameCase(cells: 30, width: 30, flexible: true),
            IdealFrameCase(cells: 30, marked: false, width: 4_096, flexible: true),
            IdealFrameCase(cells: 30, proposal: 50, width: 50, flexible: true),
            IdealFrameCase(cells: 30, minWidth: 50, width: 50, flexible: true),
            IdealFrameCase(cells: 30, idealWidth: 70, width: 70, flexible: true),
            IdealFrameCase(cells: 30, minWidth: 5_000, width: 4_096, flexible: false),
            IdealFrameCase(cells: 6_000, width: 4_096, flexible: false),
        ])
    func aFrameAnswersWithItsContent(_ frame: IdealFrameCase) {
        let view = Text(String(repeating: "0", count: frame.cells))
            .frame(minWidth: frame.minWidth, idealWidth: frame.idealWidth, maxWidth: .infinity)
        let context = RenderContext(
            availableWidth: 4_096, availableHeight: 4_096, tuiContext: TUIContext())
        let size = measureChild(
            view, proposal: ProposedSize(width: frame.proposal, height: nil),
            context: context.askingIdealWidth(frame.marked))
        #expect(size.width == frame.width)
        #expect(size.isWidthFlexible == frame.flexible)
    }

    /// A frame around content that fills whatever it is given has nothing
    /// narrower to answer with, and says so: flexible at the cap, so the
    /// ladder stops rather than climbing after it forever.
    @Test("A filling frame around a filler stays a filler")
    func aFrameAroundAFillerStaysOne() {
        let size = measureChild(
            TextEditor(text: .constant("hello")).frame(maxWidth: .infinity),
            proposal: ProposedSize(width: nil, height: nil),
            context: RenderContext(
                availableWidth: 4_096, availableHeight: 4_096, tuiContext: TUIContext()
            ).askingIdealWidth())
        #expect(size.width == 4_096)
        #expect(size.isWidthFlexible)
    }

    /// Row 50's text is the widest thing in the content whether or not it is
    /// framed to fill, and the canvas must reach its end either way. The lazy
    /// arms left a filler out of the maximum entirely — the extent was the
    /// eight-cell rows and row 50 was cut at the viewport — and the eager
    /// stack counted it at the ladder's rung, a canvas 4,096 cells wide. Every
    /// frame's bar must be the unframed control's.
    @Test(
        "A framed row's own width reaches the extent",
        arguments: [(false, 100), (false, 400), (true, 100)])
    func aFramedRowReachesTheExtent(eager: Bool, rows: Int) {
        func frames(framed: Bool) -> () -> String {
            twoAxisFrames(
                tuiContext: TUIContext(), rows: { rows }, eager: eager,
                row: { index in FramedWideRow(index: index, framed: framed) })
        }
        let framed = frames(framed: true)
        let control = frames(framed: false)
        let controlFirst = control()
        #expect(controlFirst.stripped.contains("\u{25C0}"), "precondition: row 50 needs the bar")
        #expect(framed() == controlFirst, "the first frame lost row 50's width")
        #expect(framed() == control(), "the second frame lost row 50's width")
    }

    /// A widest row framed to fill holds the kept width through a write like
    /// any other row: re-measured the way the walk measured it, it answers with
    /// its content and the record stands. Measured under a concrete proposal,
    /// or ruled out for being flexible, it fell every time, and every write
    /// cost a walk of all four hundred rows. Frame after frame, because that is
    /// where a write lands: one pass's asks share its measure memo, which
    /// serves the walk after a fall for nothing and hides it.
    @Test("A framed widest row holds the kept width through a write")
    func aFramedWidestRowHoldsTheRecord() {
        let tuiContext = TUIContext()
        let tally = MeasureTally()
        let frame = twoAxisFrames(tuiContext: tuiContext) { index in
            TallySpy(tally: tally, width: index == 50 ? 120 : 8).frame(maxWidth: .infinity)
        }
        let first = frame()
        let walked = tally.count
        #expect(first.stripped.contains("\u{25C0}"), "precondition: the framed row's content needs the bar")
        #expect(walked >= 400, "precondition: the first frame walked every row")

        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(frame() == first)
        let afterWrite = tally.count - walked
        #expect(afterWrite < walked / 2, "the challenge fell and walked: \(afterWrite) measures")
    }

    /// The eager column's twin of `aGuidedFillerDoesNotRunTheLadderAway`: a
    /// flexible row fixed the guide run's extent at the limit, which under
    /// the ideal ask is the ladder's rung, so every answer came back capped
    /// and the ladder climbed after it to the edge of `Int`.
    @Test("A guided filler does not run an eager column's ladder away")
    func aGuidedFillerInAnEagerColumn() {
        let size = horizontalExtent(
            of: VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<50, id: \.self) { index in
                    Text(index == 10 ? String(repeating: "0", count: 120) : "x")
                        .frame(maxWidth: index == 10 ? nil : .infinity, alignment: .leading)
                        .alignmentGuide(.leading) { $0[.leading] }
                }
            })
        #expect(size.width == 120, "the ladder ran to \(size.width)")
    }

    /// An eager column's width for the ideal ask is its widest row's, and a
    /// row with no width of its own — a greedy `TextEditor` — neither adds
    /// the ladder's rung to it nor, at a capped answer, stops the ladder short
    /// of the row that capped it.
    @Test("An eager column leaves a greedy row out of its width", arguments: [120, 6_000])
    func anEagerColumnLeavesAGreedyRowOut(cells: Int) {
        let size = horizontalExtent(
            of: VStack(alignment: .leading, spacing: 0) {
                Text(String(repeating: "0", count: cells))
                TextEditor(text: .constant("hello"))
            })
        #expect(size.width == cells)
    }
}
