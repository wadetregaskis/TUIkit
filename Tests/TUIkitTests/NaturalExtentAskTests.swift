//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NaturalExtentAskTests.swift
//
//  Which question a width ask is — the horizontal probe, a whole-content
//  serve, or the ordinary prefix — decided by marks rather than by how big the
//  offer happens to be.
//
//  It used to be the size: an offer of at least half the ladder's floor with
//  no proposal meant "the probe", and an ordinary layout ask inside content
//  over two thousand cells on both axes met that test at render. The probe now
//  marks itself (bit 7 of `RenderContext.measureGeneration`), a two-axis
//  `ScrollView` says its content's width means every row
//  (`asksWholeContentWidth`), and `RenderContext.contentWidthAsk` reads the two.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What a `MarkSpy` saw.
private final class MarkLog: @unchecked Sendable {
    var measuredUnderMark = 0
    var committedRenders = 0
    var committedRendersUnderMark = 0
}

/// A leaf that records whether the ideal-width mark reached it, and on which
/// kind of pass.
private struct MarkSpy: View, Renderable, Layoutable {
    let log: MarkLog

    var body: Never { fatalError("MarkSpy renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            log.committedRenders += 1
            if context.asksIdealWidth { log.committedRendersUnderMark += 1 }
        }
        return FrameBuffer(lines: ["spy"], width: 3)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        if context.asksIdealWidth { log.measuredUnderMark += 1 }
        return ViewSize.fixed(3, 1)
    }
}

@MainActor
@Suite("Which question a width ask is")
struct NaturalExtentAskTests {
    /// The mark changes what a filler answers — its content rather than the
    /// offer — which is a measure's question and never a drawn frame's. So the
    /// probe carries it and the committed render must not.
    @Test("The probe carries the ideal-width mark and a committed render never does")
    func theMarkNeverReachesACommittedRender() {
        let log = MarkLog()
        _ = renderToBuffer(
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    MarkSpy(log: log)
                    Text(String(repeating: "0", count: 120))
                }
            },
            context: RenderContext(
                availableWidth: 40, availableHeight: 12, tuiContext: TUIContext()
            ).isolatingRenderCache())
        #expect(log.measuredUnderMark > 0, "the horizontal probe did not mark its ask")
        #expect(log.committedRenders > 0, "precondition: the spy was drawn")
        #expect(log.committedRendersUnderMark == 0, "a committed render carried the mark")
    }

    /// The vertical ladder asks for a height, and a height is its own
    /// question, so it clears a mark an enclosing horizontal probe set.
    @Test("The horizontal ladder sets the mark and the vertical one clears it")
    func eachLadderSaysWhatItAsks() {
        let base = RenderContext(availableWidth: 40, availableHeight: 12, tuiContext: TUIContext())
            .isolatingRenderCache()
        let horizontal = MarkLog()
        _ = measureNaturalExtent(
            MarkSpy(log: horizontal), along: .horizontal,
            proposal: ProposedSize(width: nil, height: nil), context: base, startingBudget: 4_096)
        #expect(horizontal.measuredUnderMark > 0)

        let vertical = MarkLog()
        _ = measureNaturalExtent(
            MarkSpy(log: vertical), along: .vertical,
            proposal: ProposedSize(width: 40, height: nil), context: base.askingIdealWidth(),
            startingBudget: 4_096)
        #expect(vertical.measuredUnderMark == 0, "the vertical ladder kept an outer probe's mark")
    }

    /// Bit 7 of the generation is the mark, and the generation is the other
    /// seven: a bump must neither set nor clear it, and a record kept across
    /// passes compares the generation without it.
    @Test("A generation bump neither sets nor clears the mark")
    func aBumpKeepsTheMark() {
        let plain = RenderContext(availableWidth: 40, availableHeight: 12)
        // Checked after EVERY bump, through a wrap of the seven bits: a bump
        // that carried into bit 7 would set the mark at the 128th and clear it
        // again at the 256th.
        var bumped = plain
        var marked = plain.askingIdealWidth()
        var setByABump = false
        var clearedByABump = false
        for _ in 0..<300 {
            bumped = bumped.invalidatingMeasureMemo()
            marked = marked.invalidatingMeasureMemo()
            if bumped.asksIdealWidth { setByABump = true }
            if !marked.asksIdealWidth { clearedByABump = true }
        }
        #expect(!setByABump, "a bump set the mark")
        #expect(!clearedByABump, "a bump cleared the mark")
        #expect(marked.generationIgnoringIdealWidth == bumped.generationIgnoringIdealWidth)
        #expect(plain.askingIdealWidth().generationIgnoringIdealWidth == plain.measureGeneration)
        #expect(!plain.askingIdealWidth().askingIdealWidth(false).asksIdealWidth)
    }

    /// The classifier's table: the mark and an unproposed, unbounded offer
    /// make the probe; the mark under a real bound, or a two-axis canvas
    /// without the mark, may only read the kept answer; everything else is the
    /// ordinary prefix question.
    @Test("The classifier reads marks, and the offer's size only as a bound")
    func theClassifier() {
        let plain = RenderContext(availableWidth: 40, availableHeight: 12)
        let marked = plain.askingIdealWidth()
        var wholeContent = plain
        wholeContent.environment.asksWholeContentWidth = true
        let open = ProposedSize(width: nil, height: nil)

        #expect(marked.contentWidthAsk(proposal: open, widthLimit: 4_096, heightLimit: 4_096) == .probe)
        #expect(
            marked.contentWidthAsk(
                proposal: ProposedSize(width: 50, height: nil), widthLimit: 50, heightLimit: 4_096)
                == .serve, "a probe under a width proposal walked")
        #expect(
            marked.contentWidthAsk(proposal: open, widthLimit: 96, heightLimit: 4_096) == .serve,
            "a probe under a terminal-width bound walked")
        #expect(
            marked.contentWidthAsk(proposal: open, widthLimit: 4_096, heightLimit: 100) == .serve,
            "a probe under a height bound walked")
        #expect(
            marked.contentWidthAsk(
                proposal: ProposedSize(width: nil, height: 10), widthLimit: 4_096, heightLimit: 10)
                == .prefix)
        #expect(
            wholeContent.contentWidthAsk(proposal: open, widthLimit: 4_096, heightLimit: 4_096)
                == .serve, "an unmarked ask walked because its offer was large")
        #expect(
            plain.contentWidthAsk(proposal: open, widthLimit: 4_096, heightLimit: 4_096) == .prefix,
            "a large offer alone was read as the probe")
    }

    /// A record the probe filed is the answer a render asks for too: the
    /// generation it was filed under is compared without the mark.
    @Test("A record filed at the probe serves an unmarked whole-content ask")
    func aRecordFiledAtTheProbeServesARender() {
        let tuiContext = TUIContext()
        let state = StackWindowState()
        let stack = _VStackCore(
            alignment: .leading, spacing: 0, overflow: .window,
            content: ForEach(0..<400, id: \.self) { index in
                Text(String(repeating: "0", count: index == 200 ? 120 : 8))
            })
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let open = ProposedSize(width: nil, height: nil)
        func ask(_ context: RenderContext) -> Int? {
            let children = resolveChildViewCollection(from: stack.content, context: context)
            return stack.contentWidthOverAllRows(
                children, widthLimit: context.availableWidth,
                ask: context.contentWidthAsk(
                    proposal: open, widthLimit: context.availableWidth,
                    heightLimit: context.availableHeight),
                state: state, context: context)?.width
        }

        let probe = RenderContext(
            availableWidth: 4_096, availableHeight: 4_096,
            environment: environment, tuiContext: tuiContext
        ).askingIdealWidth()
        #expect(ask(probe) == 120, "the probe did not walk")

        var render = RenderContext(
            availableWidth: 121, availableHeight: 400,
            environment: environment, tuiContext: tuiContext)
        render.environment.asksWholeContentWidth = true
        #expect(ask(render) == 120, "the render was not served the probe's record")
    }

    /// With the stack's width meaning every row at render too, a sibling beside
    /// it sits where the canvas was sized for it — past the widest row. Asked
    /// the ordinary prefix question at render instead, the stack reported the
    /// rows on screen, and the sibling sat right after them, inside the widest
    /// row's span.
    @Test("A sibling of a lazy stack sits where the extent put it")
    func aSiblingSitsWhereTheExtentPutIt() {
        let buffer = renderToBuffer(
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<400, id: \.self) { index in
                            Text(String(repeating: "0", count: index == 200 ? 120 : 8))
                        }
                    }
                    Text("|")
                }
            },
            context: RenderContext(
                availableWidth: 40, availableHeight: 12, tuiContext: TUIContext()
            ).isolatingRenderCache())
        let top = buffer.lines.first?.stripped ?? ""
        #expect(
            !top.contains("|"),
            "the sibling sat beside the rows on screen, not past row 200: \(top)")
    }
}
