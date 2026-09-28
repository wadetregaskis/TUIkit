//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationLeaseTests.swift
//
//  When an observation scope may be cancelled. A reader drawn every frame of
//  a property nobody writes left a registration behind every frame; leases
//  bound that by what is kept. And the rule "cancel a reader's scopes when it
//  arms again" has three holes, each planted here: every hole is RED under the
//  naive rule that has it and GREEN under leases, and the tree before (never
//  cancelling) is GREEN on all three but grows without bound. The oracle is
//  the twin: the frame a warm cache draws after an observed write must be the
//  frame a cold one draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Fixtures

@Observable
private final class LeaseModel {
    var hugged = "hug"
    var drawn = "d"
    var wide = "AAAA"
    var narrow = "BBBBBBBBBB"
    var cells = 60
    var shared = 0
    var fit = String(repeating: "w", count: 30)
}

/// A `TUIContext` whose cache cancels scopes under `rule`, with `readers`
/// already known to read — so the first scope of each is as cancellable as
/// every later one, as it is for a type the app has drawn before — and a
/// census.
@MainActor
private func leaseContext(_ rule: ObservationLeases.Retirement, readers: [Any.Type]) -> (TUIContext, ObservationCensus) {
    let tui = TUIContext()
    tui.renderCache.leases.retirement = rule
    for reader in readers { tui.renderCache.noteReads(reader) }
    let census = ObservationCensus()
    tui.renderCache.observationCensus = census
    return (tui, census)
}

/// A user `Renderable` that is not `Layoutable`: measured by ONE render
/// (`measureChild`'s fallback), so its content's body is evaluated — and
/// observed — while it is measured, at the proposal.
private struct MeasuredByRendering<Content: View>: View, Renderable {
    let content: Content
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: context)
    }
}

// MARK: Hole 1 — one reader, two contexts, kept separately

/// Reads `hugged` where the `List`'s hug walks it and `drawn` where the list
/// draws it. The two contexts differ in the edit restrictions the draw
/// installs for its rows (`_ListCore`'s row context) and the hug does not —
/// internal, read here through `@testable`. The fixed-size flag, the
/// difference the hug is known for, is cleared on both paths, so a row cannot
/// tell them apart by it; the difference that reaches user code is the width
/// each offers, which is hole 2.
private struct HugLabel: View {
    let model: LeaseModel
    @Environment(\.listRowEditRestrictions) private var restrictions
    var body: some View {
        Text(verbatim: restrictions == nil ? model.hugged : model.drawn)
    }
}

/// A hugging `List` beside a marker, under a tint that alternates: a tint
/// drops buffers and keeps sizes, so every frame draws the rows again while
/// the hug's kept width is served.
private struct HugPage: View {
    let model: LeaseModel
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(0..<3, id: \.self) { _ in HugLabel(model: model) }
            }
            .fixedSize(horizontal: true)
            Text(verbatim: "|")
        }
        .tint(tint)
    }
}

// MARK: Hole 2 — one reader, one context, two proposals

/// Reads `wide` when offered 20 cells or more and `narrow` below.
private struct AdaptiveLabel: View {
    let wide: Bool
    let model: LeaseModel
    var body: some View {
        Text(verbatim: wide ? model.wide : model.narrow)
    }
}

/// A user view that adapts to the width it is offered: measured at the
/// proposal, drawn at what it was allocated.
private struct WidthAdaptive: View, Renderable {
    let model: LeaseModel
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(AdaptiveLabel(wide: context.availableWidth >= 20, model: model), context: context)
    }
}

/// `.equatable()` content, so its sizes are kept across frames by proposal.
private struct AdaptiveHolder: View, @MainActor Equatable {
    let model: LeaseModel
    var body: some View { WidthAdaptive(model: model) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

private struct AdaptivePage: View {
    let model: LeaseModel
    let tint: Color
    var body: some View {
        HStack(spacing: 0) {
            AdaptiveHolder(model: model).equatable()
            Text(verbatim: "|")
        }
        .tint(tint)
    }
}

// MARK: Hole 3 — a size kept above a reader that has left the pass

/// Row 300's label reads `cells`; every other row is eight cells.
private struct LadderLabel: View {
    let index: Int
    let model: LeaseModel
    var body: some View {
        Text(String(repeating: "\(index % 10)", count: index == 300 ? model.cells : 8))
    }
}

// MARK: Readers that come and go, and one drawn every frame

private struct SharedReader: View {
    let index: Int
    let model: LeaseModel
    var body: some View { Text(verbatim: "\(index) \(model.shared)") }
}

/// Ten rows starting at `first`: one arrives and one leaves each frame.
private struct SlidingWindow: View {
    let first: Int
    let model: LeaseModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(first..<(first + 10), id: \.self) { index in SharedReader(index: index, model: model) }
        }
    }
}

private struct DrawnReader: View {
    let model: LeaseModel
    var body: some View { Text(verbatim: "shared \(model.shared)") }
}

/// A reader kept by the buffer memo, served every frame.
private struct HeldReader: View, @MainActor Equatable {
    let model: LeaseModel
    var body: some View { DrawnReader(model: model) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

// MARK: Drawn, then only measured

/// Reads `fit`: a `ViewThatFits` candidate that fits a wide terminal and not
/// a narrow one.
private struct FitCandidate: View {
    let model: LeaseModel
    var body: some View { Text(verbatim: model.fit) }
}

private struct FitHolder: View, @MainActor Equatable {
    let model: LeaseModel
    var body: some View {
        ViewThatFits(in: .horizontal) {
            FitCandidate(model: model)
            Text(verbatim: "narrow")
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
}

// MARK: - Tests

@MainActor
@Suite("Observation leases: when a scope may be cancelled")
struct ObservationLeaseTests {
    typealias Rule = ObservationLeases.Retirement

    // MARK: Build-up

    @Test(
        "A reader drawn every frame of a never-written property leaves a bounded number alive",
        arguments: Rule.allCases)
    func drawnEveryFrame(rule: Rule) {
        let model = LeaseModel()
        let (tui, census) = leaseContext(rule, readers: [DrawnReader.self])
        for _ in 0..<200 { _ = observedFrame(DrawnReader(model: model), tui: tui) }
        let live = census.snapshot.live
        if rule == .never {
            #expect(live == 200, "never cancelling keeps every frame's: \(live)")
        } else {
            #expect(live <= 2, "\(rule): \(live) alive after 200 frames")
            #expect(census.snapshot.cancelled(.bodyRender) >= 198)
        }
        model.shared += 1
        #expect(census.snapshot.live == 0)
        #expect(census.snapshot.unleased(.bodyRender) == 0, "the type was known before the first frame")
    }

    @Test(
        "Readers that come and go leave a bounded number alive only when a gone reader's scopes go too",
        arguments: Rule.allCases)
    func readersComeAndGo(rule: Rule) {
        let model = LeaseModel()
        let (tui, census) = leaseContext(rule, readers: [SharedReader.self])
        for first in 0..<300 { _ = observedFrame(SlidingWindow(first: first, model: model), tui: tui, height: 12) }
        let live = census.snapshot.live
        switch rule {
        case .never, .perReader:
            #expect(live >= 300, "\(rule): one per row ever drawn, \(live)")
        case .perReaderAndPrune, .leases:
            #expect(live <= 25, "\(rule): bounded by the window, \(live)")
        }
    }

    /// The type's first scope, before the cache knew it reads, is the one no
    /// lease can cancel: counted, and never more than one.
    @Test("The first scope of a type not yet known to read is the only one left unleased")
    func firstScopeUnleased() {
        let model = LeaseModel()
        let (tui, census) = leaseContext(.leases, readers: [])
        for _ in 0..<50 { _ = observedFrame(DrawnReader(model: model), tui: tui) }
        #expect(census.snapshot.unleased(.bodyRender) == 1)
        #expect(census.snapshot.live <= 3, "\(census.snapshot.live)")
    }

    @Test(
        "A memo served for many frames keeps its scope: the write still reaches it",
        arguments: [Rule.never, .leases])
    func servedMemoKeepsItsScope(rule: Rule) {
        let model = LeaseModel()
        let (tui, census) = leaseContext(rule, readers: [DrawnReader.self])
        for _ in 0..<50 { _ = observedFrame(HeldReader(model: model).equatable(), tui: tui) }
        if rule == .leases { #expect(census.snapshot.live == 1, "the served entry's one scope: \(census.snapshot.live)") }
        model.shared = 7
        let warm = observedFrame(HeldReader(model: model).equatable(), tui: tui)
        #expect(warm.first?.hasPrefix("shared 7") == true, "\(rule): \(warm)")
    }

    // MARK: The three holes

    /// Frames of `page` through a warm cache, then an observed write, then the
    /// warm frame against a cold one of the same page.
    private func twin<V: View>(
        rule: Rule, readers: [Any.Type], frames: Int = 6, width: Int = 40, height: Int = 8,
        page: @escaping (Int) -> V, write: () -> Void
    ) -> (warm: [String], cold: [String], census: ObservationCensus) {
        let (tui, census) = leaseContext(rule, readers: readers)
        for frame in 0..<frames { _ = observedFrame(page(frame), tui: tui, width: width, height: height) }
        write()
        let warm = observedFrame(page(frames), tui: tui, width: width, height: height)
        let cold = observedFrame(page(frames), tui: TUIContext(), width: width, height: height)
        return (warm, cold, census)
    }

    /// HOLE 1. The hug walks each row under its own context and keeps the
    /// width; the rows are drawn under the list's. A later frame that draws the
    /// rows but is served the hug re-arms only the drawn reads, so the naive
    /// rule cancels the hug's — and a write to what only the hug read is lost.
    @Test(
        "Hole 1: a reader evaluated in two contexts whose results are kept separately",
        arguments: [(Rule.never, true), (.perReader, false), (.leases, true)])
    func twoContexts(rule: Rule, sound: Bool) {
        let model = LeaseModel()
        let result = twin(
            rule: rule, readers: [HugLabel.self],
            page: { HugPage(model: model, tint: $0.isMultiple(of: 2) ? .red : .blue) },
            write: { model.hugged = "the hug is much wider now" })
        #expect(result.census.snapshot.armed(.bodyMeasure) > 0, "the hug's walk observes the labels it measures")
        #expect((result.warm == result.cold) == sound, "\(rule):\nwarm \(result.warm)\ncold \(result.cold)")
    }

    /// HOLE 2. The kept size is measured at the proposal (20 or more, so the
    /// label reads `wide`); the view is drawn at its allocation (4 cells, so it
    /// reads `narrow`). Same identity, same environment, different read set.
    @Test(
        "Hole 2: a reader whose reads depend on the proposal, a size kept at another",
        arguments: [(Rule.never, true), (.perReader, false), (.leases, true)])
    func twoProposals(rule: Rule, sound: Bool) {
        let model = LeaseModel()
        let result = twin(
            rule: rule, readers: [AdaptiveLabel.self],
            page: { AdaptivePage(model: model, tint: $0.isMultiple(of: 2) ? .red : .blue) },
            write: { model.wide = "AAAAAAAAAAAA" })
        #expect((result.warm == result.cold) == sound, "\(rule):\nwarm \(result.warm)\ncold \(result.cold)")
    }

    /// HOLE 3. The content-width ladder keeps the widest row's width in
    /// `@State`, above rows it does not draw. Row 300 is off the window: its
    /// reader was evaluated by the walk, never again, and leaves the pass. A
    /// cancel at that prune loses the write that narrows it; the record, which
    /// learns a row moved only from the size clear the write's scope makes,
    /// keeps the old extent and the horizontal bar stays.
    @Test(
        "Hole 3: a size kept above a reader that left the pass (measured by rendering)",
        arguments: [(Rule.never, true), (.perReader, true), (.perReaderAndPrune, false), (.leases, true)])
    func keptAbovePruned(rule: Rule, sound: Bool) {
        ladder(rule: rule, sound: sound) { index, model in
            AnyView(MeasuredByRendering(content: LadderLabel(index: index, model: model)))
        }
    }

    /// The same with the rows plain composite views, measured through their
    /// bodies — observed because the type is known to read.
    @Test(
        "Hole 3: a size kept above a reader that left the pass (measured through its body)",
        arguments: [(Rule.never, true), (.perReaderAndPrune, false), (.leases, true)])
    func keptAbovePrunedComposite(rule: Rule, sound: Bool) {
        ladder(rule: rule, sound: sound) { index, model in AnyView(LadderLabel(index: index, model: model)) }
    }

    private func ladder(rule: Rule, sound: Bool, row: @escaping (Int, LeaseModel) -> AnyView) {
        let model = LeaseModel()
        let (tui, census) = leaseContext(rule, readers: [LadderLabel.self])
        let frame = twoAxisFrames(tuiContext: tui) { row($0, model) }
        for _ in 0..<4 { _ = frame() }
        model.cells = 8  // row 300 narrows to the rest: no row needs the bar any more
        let warm = frame()
        let cold = twoAxisFrames(tuiContext: TUIContext()) { row($0, model) }()
        #expect(census.snapshot.armed(.bodyMeasure) > 0, "the walk's measure of row 300 is observed")
        #expect((warm == cold) == sound, "\(rule):\nwarm \(warm)\ncold \(cold)")
    }

    // MARK: What leases need of the measure path

    /// A candidate drawn while it fit, then only measured once the terminal
    /// narrowed. Its draw's scopes go with the frames that drew it; what
    /// watches it afterwards is its measure, observed because its type is
    /// known to read. Never cancelling covers it by accident, with the scope
    /// its last draw left behind.
    @Test("A view drawn once and then only measured still sees the write", arguments: [Rule.never, .leases])
    func drawnThenOnlyMeasured(rule: Rule) {
        let model = LeaseModel()
        let (tui, _) = leaseContext(rule, readers: [FitCandidate.self])
        let page = { FitHolder(model: model).equatable() }
        for _ in 0..<3 { _ = observedFrame(page(), tui: tui, width: 40) }
        #expect(observedFrame(page(), tui: tui, width: 40).first?.hasPrefix("www") == true)
        for _ in 0..<4 { _ = observedFrame(page(), tui: tui, width: 20) }
        #expect(observedFrame(page(), tui: tui, width: 20).first?.hasPrefix("narrow") == true)
        model.fit = "fits"
        let warm = observedFrame(page(), tui: tui, width: 20)
        let cold = observedFrame(page(), tui: TUIContext(), width: 20)
        #expect(cold.first?.hasPrefix("fits") == true)
        #expect(warm == cold, "\(rule):\nwarm \(warm)\ncold \(cold)")
    }

    // MARK: The lease graph

    /// A size measured once in a pass and served later in the same pass, into
    /// a computation whose result is kept, hands that computation the
    /// measure's own lease — never the frame's, which no kept result may hold.
    @Test("A per-pass measure served into a kept computation hands it the measure's lease")
    func perPassLease() throws {
        let cache = RenderCache()
        cache.leases.retirement = .leases
        cache.noteReads(DrawnReader.self)
        cache.beginRenderPass()
        let key = RenderCache.MeasureKey(
            identityHash: 1, effectiveWidth: 10, availableWidth: 10, hasExplicitWidth: false,
            hasExplicitHeight: false, viewType: ObjectIdentifier(DrawnReader.self), valueHash: 0)
        let measured = cache.leases.beginComputation()
        _ = cache.leases.sentinel(at: ViewIdentity(rootType: DrawnReader.self))
        let measureLease = try #require(cache.leases.endComputation(measured), "the measure armed a scope")
        cache.storeMeasure(
            key: key, proposalWidthWasSpecified: false, proposalHeight: nil, availableHeight: 5,
            size: .fixed(3, 1), lease: measureLease)
        let kept = cache.leases.beginComputation()
        _ = cache.lookupMeasure(
            key: key, proposalWidthWasSpecified: false, proposalHeight: nil, availableHeight: 5,
            verticalBudget: 5)
        let keptLease = try #require(cache.leases.endComputation(kept), "serving the size made the computation a lease")
        #expect(keptLease.holds(measureLease), "the kept computation holds what it was served")
        let frame = try #require(cache.leases.frameLease)
        #expect(frame.holds(measureLease), "the frame holds the measure it enclosed")
        #expect(frame.holds(keptLease))
        #expect(!keptLease.holds(frame), "and nothing kept holds the frame")
    }

    /// The same through `measureChild`, which opens the per-pass slot itself:
    /// a reader measured at the frame's level, and measured again — served
    /// from this pass's memo — inside a computation whose result is kept. The
    /// kept computation keeps the measure's scope past the frame that armed
    /// it, and lets it go when it is let go of.
    @Test("measureChild's per-pass slot hands a kept computation the scope its measure armed")
    func perPassLeaseThroughMeasureChild() throws {
        let model = LeaseModel()
        let (tui, census) = leaseContext(.leases, readers: [DrawnReader.self])
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(availableWidth: 30, availableHeight: 3, environment: environment, tuiContext: tui)
        let leases = tui.renderCache.leases
        let unproposed = ProposedSize(width: nil, height: nil)
        tui.renderCache.beginRenderPass()
        _ = measureChild(DrawnReader(model: model), proposal: unproposed, context: context)
        #expect(census.snapshot.armed(.bodyMeasure) == 1, "measured at the frame's level, observed")
        let kept = leases.beginComputation()
        _ = measureChild(DrawnReader(model: model), proposal: unproposed, context: context)
        #expect(census.snapshot.armed(.bodyMeasure) == 1, "served from this pass's memo, not measured again")
        var keptLease = leases.endComputation(kept)
        #expect(keptLease != nil, "the serve handed the kept computation the measure's lease")
        tui.renderCache.removeInactive()
        tui.renderCache.beginRenderPass()
        tui.renderCache.removeInactive()
        #expect(census.snapshot.live(.bodyMeasure) == 1, "held past the frame that armed it, by what kept it")
        keptLease = nil
        #expect(census.snapshot.cancelled(.bodyMeasure) == 1, "and let go of with it")
        withExtendedLifetime(keptLease) {}
    }

    /// A kept entry keeps its computation's lease; the frame that served it
    /// holds it too; and a detached computation's lease is held by nothing.
    @Test("A stored entry keeps its computation's lease, and a detached one is held by nothing")
    func storedAndDetached() throws {
        let cache = RenderCache()
        cache.leases.retirement = .leases
        cache.noteReads(DrawnReader.self)
        cache.beginRenderPass()
        let identity = ViewIdentity(rootType: DrawnReader.self)
        let mark = cache.leases.beginComputation()
        _ = cache.leases.sentinel(at: identity)
        let lease = try #require(cache.leases.endComputation(mark))
        cache.store(
            identity: identity, view: 1, buffer: FrameBuffer(text: "x"), contextWidth: 1, contextHeight: 1,
            gradientFrame: nil, surfaceBackground: nil, recorded: (effects: [], scope: .none, lease: lease))
        cache.markActive(identity)
        cache.removeInactive()
        #expect(cache.leases.displayedLease?.holds(lease) == true, "the frame on screen holds what it drew")
        cache.beginRenderPass()
        let served = cache.lookupEntry(
            identity: identity, view: 1, contextWidth: 1, contextHeight: 1, gradientFrame: nil,
            surfaceBackground: nil, effectScope: .none, animationMustBeCurrent: false)
        #expect(served?.lease === lease)
        #expect(cache.leases.frameLease?.holds(lease) == true, "serving it is using it")
        let check = cache.leases.beginDetachedComputation()
        _ = cache.leases.sentinel(at: identity)
        weak let checkLease = cache.leases.endComputation(check)
        #expect(checkLease == nil, "nothing holds a detached computation's lease: it retired as it closed")
        #expect(cache.leases.frameLease?.heldCount == 1)
    }

    // MARK: The verifiers do not heal

    /// Hole 2 under the naive rule loses the write and serves the stale size.
    /// The measure verifier must say so. Had its fresh measure observed the
    /// reader under the frame, the write would have been seen and cleared the
    /// size before the next serve, and the verifier would report nothing.
    @Test("The measure verifier reports a size a cancelled scope left stale")
    func verifierDoesNotHeal() {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        RenderCache.verifiesMeasureMemo = true
        let model = LeaseModel()
        let (tui, _) = leaseContext(.perReader, readers: [AdaptiveLabel.self])
        let page = { (frame: Int) in AdaptivePage(model: model, tint: frame.isMultiple(of: 2) ? .red : .blue) }
        for frame in 0..<6 { _ = observedFrame(page(frame), tui: tui) }
        #expect(tui.renderCache.measureMemoMismatches.isEmpty, "\(tui.renderCache.measureMemoMismatches)")
        model.wide = "AAAAAAAAAAAA"
        for frame in 6..<8 { _ = observedFrame(page(frame), tui: tui) }
        #expect(!tui.renderCache.measureMemoMismatches.isEmpty, "the stale size was served and not reported")
    }
}
