//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationCensusTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// The census counts every observation registration a body arms, every one
/// that fires and every one freed without firing, by kind of reader, exactly.
/// And the facts about `withObservationTracking` it rests on are pinned, so a
/// toolchain that changes them fails here: `onChange` is evaluated only when
/// the scope read something (so counting there counts exactly the
/// registrations armed); a registration on an object that lives stays armed
/// until a property it read is written; and one whose object is
/// deinitialized is freed with it, its `onChange` never run (so what armed
/// and neither fired nor was dropped is what is alive).
@MainActor
@Suite("The census counts live observation scopes")
struct ObservationCensusTests {
    @Observable
    final class Model {
        var count = 0
        var other = 0
    }

    private struct Reader: View {
        let model: Model
        var body: some View { Text(verbatim: "count \(model.count)") }
    }

    private struct NonReader: View {
        var body: some View { Text(verbatim: "nothing observed") }
    }

    /// A frame of `view` in `tui`, with the pass lifecycle around it.
    private static func frame<V: View>(_ view: V, tui: TUIContext) {
        let context = RenderContext(availableWidth: 30, availableHeight: 2, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.renderCache.removeInactive()
        tui.stateStorage.endRenderPass()
    }

    @Test("A drawn reader arms one registration a frame; a write fires it; nothing is left alive")
    func drawnReaderCounted() {
        let model = Model()
        let tui = TUIContext()
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        Self.frame(Reader(model: model), tui: tui)
        #expect(census.snapshot.armed(.bodyRender) == 1)
        #expect(census.snapshot.live(.bodyRender) == 1)
        model.count = 1
        #expect(census.snapshot.fired(.bodyRender) == 1)
        #expect(census.snapshot.dropped(.bodyRender) == 0, "a registration that fired is not dropped as well")
        #expect(census.snapshot.live == 0, "every registration fired")
        Self.frame(Reader(model: model), tui: tui)
        #expect(census.snapshot.armed(.bodyRender) == 2, "drawn again, armed again")
        for kind in ObservationCensus.Kind.allCases where kind != .bodyRender {
            #expect(census.snapshot.armed(kind) == 0, "\(kind)")
        }
    }

    @Test("A body that reads nothing observable arms nothing")
    func nonReaderArmsNothing() {
        let tui = TUIContext()
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        Self.frame(NonReader(), tui: tui)
        #expect(census.snapshot == ObservationCensus.Counts())
    }

    @Test("A body evaluated while measuring counts as measured")
    func measuredBodyCounted() {
        let model = Model()
        let tui = TUIContext()
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        var context = RenderContext(availableWidth: 30, availableHeight: 2, tuiContext: tui)
        context.isMeasuring = true
        _ = evaluateCompositeBody(of: Reader(model: model), context: context)
        #expect(census.snapshot.armed(.bodyMeasure) == 1)
        #expect(census.snapshot.armed(.bodyRender) == 0)
    }

    /// With nothing cancelled — the rule the cache had before observation
    /// leases, kept as the baseline — a body read every frame and never
    /// written adds a registration every frame, and the first write runs
    /// them all.
    @Test("Never cancelling, a body read every frame and never written adds a registration every frame")
    func buildUpCounted() {
        let model = Model()
        let tui = TUIContext()
        tui.renderCache.leases.retirement = .never
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        // Nothing memoizes a bare composite at the root, so its body is
        // evaluated, and armed, on every frame.
        for _ in 0..<50 { Self.frame(Reader(model: model), tui: tui) }
        #expect(census.snapshot.live(.bodyRender) == 50, "\(census.snapshot.live(.bodyRender)) alive")
        model.count = 1
        #expect(census.snapshot.fired(.bodyRender) == 50, "one write fired all fifty")
        #expect(census.snapshot.live == 0)
    }

    /// What a cache does by default: the frame before's scope is cancelled
    /// once the next is drawn, so a body read every frame and never written
    /// leaves a bounded number alive — the one that taught the cache the type
    /// reads, the frame on screen's and the frame being drawn's — and the
    /// first write runs only those.
    @Test("By default, a body read every frame and never written leaves a bounded number alive")
    func buildUpBoundedByDefault() {
        let model = Model()
        let tui = TUIContext()
        #expect(tui.renderCache.leases.retirement == .leases)
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        for _ in 0..<50 { Self.frame(Reader(model: model), tui: tui) }
        #expect(census.snapshot.live(.bodyRender) <= 3, "\(census.snapshot.live(.bodyRender)) alive")
        #expect(census.snapshot.cancelled(.bodyRender) >= 47)
        #expect(census.snapshot.unleased(.bodyRender) == 1, "the first, which taught the cache the type reads")
        model.count = 1
        #expect(census.snapshot.fired(.bodyRender) <= 3)
        #expect(census.snapshot.live == 0)
    }

    @Test("A reader's registration goes with its model: freed unfired, and no longer alive")
    func deinitializedModelFreesItsRegistration() {
        let tui = TUIContext()
        let census = ObservationCensus()
        tui.renderCache.observationCensus = census
        weak var probe: Model?
        do {
            let model = Model()
            probe = model
            Self.frame(Reader(model: model), tui: tui)
            #expect(census.snapshot.live(.bodyRender) == 1, "armed while the model lives")
        }
        #expect(probe == nil, "nothing the frame kept holds the model")
        #expect(census.snapshot.fired(.bodyRender) == 0, "nothing was written, so nothing fired")
        #expect(census.snapshot.dropped(.bodyRender) == 1, "freed with the model")
        #expect(census.snapshot.live == 0, "\(census.snapshot.live) alive after the model has gone")
    }

    @Test("Without a census nothing is counted and nothing breaks")
    func noCensus() {
        let model = Model()
        let tui = TUIContext()
        #expect(tui.renderCache.observationCensus == nil)
        Self.frame(Reader(model: model), tui: tui)
        model.count = 1
        Self.frame(Reader(model: model), tui: tui)
    }

    // MARK: The facts it rests on

    /// A scope that read nothing never evaluates `onChange`; one that read a
    /// property evaluates it once.
    @Test("onChange is evaluated only when the scope read something")
    func onChangeEvaluatedOnlyWhenArmed() {
        let model = Model()
        final class Evaluations: @unchecked Sendable { var times = 0 }
        let evaluations = Evaluations()
        func onChange() -> @Sendable () -> Void {
            evaluations.times += 1
            return {}
        }
        withObservationTracking({ _ = 1 + 1 }, onChange: onChange())
        #expect(evaluations.times == 0, "an empty scope armed nothing")
        withObservationTracking({ _ = model.count }, onChange: onChange())
        #expect(evaluations.times == 1, "a scope that read one property armed once")
    }

    /// Registrations on an object that lives, never fired, stay armed, every
    /// one: one write fires them all, and a second write finds none.
    @Test("While its object lives, a registration stays armed until a property it read is written")
    func registrationsLiveUntilWritten() {
        let model = Model()
        final class Fired: @unchecked Sendable { var times = 0 }
        let fired = Fired()
        for _ in 0..<1_000 {
            withObservationTracking { _ = model.count } onChange: { fired.times += 1 }
        }
        model.other = 1
        #expect(fired.times == 0, "a write to a property no scope read fires none")
        model.count = 1
        #expect(fired.times == 1_000, "the first write of the read property fired every one")
        model.count = 2
        #expect(fired.times == 1_000, "and freed them: the second fires none")
    }

    /// A registration on an object that is deinitialized goes with it: its
    /// closure, and what that captured, is freed, and it never runs.
    @Test("A registration is freed, unfired, when the object it read is deinitialized")
    func registrationFreedWithItsObject() {
        final class Captured: Sendable {}
        final class Fired: @unchecked Sendable { var times = 0 }
        let fired = Fired()
        weak var modelProbe: Model?
        weak var capturedProbe: Captured?
        do {
            let model = Model()
            let captured = Captured()
            modelProbe = model
            capturedProbe = captured
            withObservationTracking { _ = model.count } onChange: { [captured] in
                _ = captured
                fired.times += 1
            }
        }
        #expect(modelProbe == nil)
        #expect(capturedProbe == nil, "the registration's closure was freed with the model")
        #expect(fired.times == 0, "and never ran")
    }
}
