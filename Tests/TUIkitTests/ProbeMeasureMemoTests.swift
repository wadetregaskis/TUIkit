//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProbeMeasureMemoTests.swift
//
//  A probe is a measure made to learn one thing about a subtree that is drawn,
//  and so measured, somewhere else. The pass's measure memo kept every node a
//  probe passed through, though nothing else in the pass measures there — dead
//  entries in a dictionary that keeps its capacity from pass to pass. A probe
//  keeps its own answer, which a repeat of it is served, and nothing it found
//  on the way — but it READS what the pass stored, all the way down: the
//  subtree it asks about has usually just been measured where it is drawn.
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

    /// A probe asks about a subtree that is drawn somewhere else, and so
    /// measured there — often earlier in the same pass, where the render laid
    /// it out. What that measure stored answers the probe's subtree as it
    /// answers anyone: only STORING stops at a probe.
    @Test("Beneath a probe, what an ordinary measure stored is served, not measured again")
    func probeSubtreeReadsTheMemo() throws {
        let context = probeMemoisedContext(width: Self.width)
        let cache = try #require(context.renderCache)
        // Where `Prober` measures its content: one child identity in.
        let measured = measureChild(
            ProbedFillingLabel(), proposal: Self.proposal,
            context: context.withChildIdentity(type: ProbedFillingLabel.self))
        let entries = cache.measureEntryCount
        let before = cache.measureMemoTotals
        let probed = measureChildRememberingOnlyItself(
            Prober(content: ProbedFillingLabel()), proposal: Self.proposal, context: context)
        #expect(probed == measured)
        // The prober itself misses and keeps its answer; its content is served.
        #expect(cache.measureMemoTotals.misses == before.misses + 1)
        #expect(cache.measureMemoTotals.hits == before.hits + 1, "the probe's subtree was measured again")
        #expect(cache.measuresBeneathProbes == 0)
        #expect(cache.measureEntryCount == entries + 1)
    }

    /// The other half of the rule: beneath a probe, a miss is measured and
    /// NOT kept — a probe inside a probe, which reads the memo too, stores
    /// nothing either.
    @Test("Beneath a probe, a miss is measured and kept nowhere")
    func probeSubtreeStoresNothing() throws {
        let context = probeMemoisedContext(width: Self.width)
        let cache = try #require(context.renderCache)
        _ = measureChildRememberingOnlyItself(
            Prober(content: Prober(content: ProbedFillingLabel())), proposal: Self.proposal,
            context: context)
        #expect(cache.measureEntryCount == 1)
        // Measured, though: the inner prober, the label, and what is in it.
        #expect(cache.measuresBeneathProbes > 2)
        #expect(!cache.isProbing, "the memo was left read-only")
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

    /// The button's own probe, end to end: a button learns whether its
    /// `@ViewBuilder` label fills by asking it. A plain button draws its label
    /// at the width it is offered, so the two buttons measure the same nodes
    /// on the way to drawing — a `Spacer` is laid out, not measured — and the
    /// only difference the memo can see is the probe the filling one makes,
    /// which must be one entry: its answer.
    ///
    /// Plain only because the standard variant's chrome is an `HStack` that
    /// gives a filling label the rest of the row and measures it again at that
    /// width, which is layout, not probe, and differs between the two for that
    /// reason alone. The probe is the same call for both.
    @Test("A button whose label fills keeps one memo entry more than one whose label does not")
    func buttonProbeCostsOneEntry() throws {
        func entries(measuring button: Button) throws -> (count: Int, size: ViewSize) {
            let context = probeMemoisedContext(width: Self.width)
            let size = measureChild(
                ButtonStyleCase.plain.apply(to: button), proposal: Self.proposal, context: context)
            return (try #require(context.renderCache).measureEntryCount, size)
        }
        let filling = try entries(measuring: Button(action: {}, label: { ProbedFillingLabel() }))
        let hugging = try entries(measuring: Button(action: {}, label: { ProbedHuggingLabel() }))
        #expect(filling.size.isWidthFlexible, "precondition: the filling label's button probed")
        #expect(!hugging.size.isWidthFlexible)
        #expect(filling.count == hugging.count + 1, "filling \(filling.count), hugging \(hugging.count)")
    }

    /// What drawing a button measures inside its label, and what measuring it
    /// does: the same leaves, the same number of times. A button that fills
    /// its offer measures by drawing and then probes its label, and the probe
    /// is asked about a label the drawing has just laid out — so everything
    /// inside it is the memo's to serve, and the probe measures none of it
    /// again.
    @Test(
        "A button's probe measures nothing inside its label that drawing it measured",
        arguments: [ButtonStyleCase.default, .plain])
    func buttonProbeMeasuresNoLeafAgain(style: ButtonStyleCase) {
        let counter = LeafMeasureCounter()
        let button = style.apply(
            to: Button(action: {}, label: { HStack(spacing: 1) { CountedLeaf(counter: counter); Spacer() } }))
        _ = measureFixedByRendering(button, proposal: Self.proposal, context: probeMemoisedContext(width: Self.width))
        let drawing = counter.measures
        #expect(drawing > 0, "precondition: drawing the button measures its leaf")
        counter.measures = 0
        let size = measureChild(button, proposal: Self.proposal, context: probeMemoisedContext(width: Self.width))
        #expect(size.isWidthFlexible, "precondition: the filling label's button probed")
        #expect(counter.measures == drawing, "\(style): drawn \(drawing), measured \(counter.measures)")
    }

    /// The standard variants draw a row — cap, label on its face, cap — and
    /// the probe asks the row it drew: the same value, so every child of it is
    /// one the drawing has just laid out, and the memo serves them all. What
    /// the probe measures beneath itself is the row's own layout — `HStack` is
    /// a composite, and its body, `_HStackCore`, is one measure — and nothing
    /// in the row: no cap, no wrapper of the label, nothing of the label's own.
    /// In every colour the row can be drawn in, which is what its children's
    /// values carry.
    @Test(
        "A standard button's probe measures its row's layout and nothing in the row",
        arguments: [ButtonStyleCase.default, .primary, .success, .destructive], [false, true])
    func standardProbeMeasuresOnlyTheRow(style: ButtonStyleCase, disabled: Bool) throws {
        let context = probeMemoisedContext(width: Self.width)
        let cache = try #require(context.renderCache)
        // Linux measured 2 or 3 here where macOS measures 1, varying from run
        // to run, and nothing on macOS reproduces it; the log says which view
        // missed and what the memo held for it.
        cache.probeMissLog = []
        let button = style.apply(to: Button(action: {}, label: { ProbedFillingLabel() }))
        let size = measureChild(AnyView(button.disabled(disabled)), proposal: Self.proposal, context: context)
        #expect(size.isWidthFlexible, "precondition: the filling label's button probed")
        #expect(cache.measuresBeneathProbes == 1, "\((cache.probeMissLog ?? []).joined(separator: "\n"))")
    }
}

/// How often a ``CountedLeaf`` has been measured — a class, so the count
/// survives the view values the walk copies.
@MainActor
private final class LeafMeasureCounter {
    var measures = 0
}

/// A four-cell leaf that counts its measures.
private struct CountedLeaf: View, Renderable, Layoutable {
    let counter: LeafMeasureCounter

    var body: Never { fatalError("CountedLeaf renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer { FrameBuffer(text: "leaf") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        counter.measures += 1
        return ViewSize.fixed(4, 1)
    }
}
