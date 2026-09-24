//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProbeMeasureMemoTests.swift
//
//  A probe is a measure made to learn one thing about a subtree that is drawn,
//  and so measured, somewhere else. The pass's measure memo kept every node a
//  probe passed through, though nothing else in the pass measures there — dead
//  entries in a dictionary that keeps its capacity from pass to pass. A probe
//  keeps its own answer, which a repeat of it is served, and nothing it found
//  on the way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A navigation row's label: a title at the leading edge, a number at the
/// trailing one, and a `Spacer` between that makes it fill.
struct ProbedFillingLabel: View {
    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "note")
            Spacer()
            Text(verbatim: "#1")
        }
    }
}

/// The same two texts with nothing between them to fill with.
struct ProbedHuggingLabel: View {
    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "note")
            Text(verbatim: "#1")
        }
    }
}

/// A view that learns its size by asking its content one question, as a
/// probe does.
private struct Prober<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never { fatalError("Prober renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context.withChildIdentity(type: Content.self))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChildRememberingOnlyItself(
            content, proposal: proposal, context: context.withChildIdentity(type: Content.self))
    }
}

/// The render loop's shape: an isolated cache, and the volatile-read tracker
/// whose presence is what turns the measure memo on at all.
@MainActor
func probeMemoisedContext(width: Int) -> RenderContext {
    var context = makeRenderContext(width: width, height: 10)
    let storage = StateStorage()
    context.environment.stateStorage = storage
    context.stateStorage = storage
    context.environment.installVolatileReadTracker(VolatileReadTracker())
    return context
}

@MainActor
@Suite("A measure made to ask one thing keeps one answer")
struct ProbeMeasureMemoTests {
    private static let width = 40
    private static let proposal = ProposedSize(width: width, height: nil)

    @Test("A probe keeps its own answer and nothing it found on the way")
    func probeKeepsOneEntry() throws {
        let probing = probeMemoisedContext(width: Self.width)
        let probed = measureChildRememberingOnlyItself(
            ProbedFillingLabel(), proposal: Self.proposal, context: probing)
        #expect(try #require(probing.renderCache).measureEntryCount == 1)

        // The control: the same question as an ordinary measure keeps every
        // node it visited — which is what makes the count above mean anything.
        let measuring = probeMemoisedContext(width: Self.width)
        let measured = measureChild(ProbedFillingLabel(), proposal: Self.proposal, context: measuring)
        #expect(try #require(measuring.renderCache).measureEntryCount > 1)
        #expect(probed == measured)
        #expect(probed.isWidthFlexible)
    }

    @Test("A repeat of the probe is served its answer")
    func repeatIsServed() throws {
        let context = probeMemoisedContext(width: Self.width)
        let cache = try #require(context.renderCache)
        let first = measureChildRememberingOnlyItself(
            ProbedFillingLabel(), proposal: Self.proposal, context: context)
        let before = cache.measureMemoTotals
        let second = measureChildRememberingOnlyItself(
            ProbedFillingLabel(), proposal: Self.proposal, context: context)
        #expect(second == first)
        #expect(cache.measureMemoTotals.hits == before.hits + 1)
        #expect(cache.measureMemoTotals.misses == before.misses)
    }

    @Test("A probe reads what an ordinary measure stored")
    func probeReadsTheMemo() throws {
        let context = probeMemoisedContext(width: Self.width)
        let cache = try #require(context.renderCache)
        let measured = measureChild(ProbedFillingLabel(), proposal: Self.proposal, context: context)
        let before = cache.measureMemoTotals
        let probed = measureChildRememberingOnlyItself(
            ProbedFillingLabel(), proposal: Self.proposal, context: context)
        #expect(probed == measured)
        #expect(cache.measureMemoTotals.hits == before.hits + 1)
    }

    @Test("A probe inside a probe keeps nothing: only the outer answer is kept")
    func nestedProbeKeepsOnlyTheOuterAnswer() throws {
        let nested = probeMemoisedContext(width: Self.width)
        _ = measureChildRememberingOnlyItself(
            Prober(content: ProbedFillingLabel()), proposal: Self.proposal, context: nested)
        #expect(try #require(nested.renderCache).measureEntryCount == 1)

        // Measured plainly, the outer answer and the inner probe's own are kept.
        let plain = probeMemoisedContext(width: Self.width)
        _ = measureChild(Prober(content: ProbedFillingLabel()), proposal: Self.proposal, context: plain)
        #expect(try #require(plain.renderCache).measureEntryCount == 2)
    }

    @Test("Once a probe returns, the measures after it are kept again")
    func holdIsReleased() throws {
        let context = probeMemoisedContext(width: Self.width)
        let cache = try #require(context.renderCache)
        _ = measureChildRememberingOnlyItself(
            ProbedFillingLabel(), proposal: Self.proposal, context: context)
        #expect(cache.volatileReadTracker != nil, "the memo was left detached")
        let afterProbe = cache.measureEntryCount
        _ = measureChild(ProbedHuggingLabel(), proposal: Self.proposal, context: context)
        #expect(cache.measureEntryCount > afterProbe + 1)
    }
}
