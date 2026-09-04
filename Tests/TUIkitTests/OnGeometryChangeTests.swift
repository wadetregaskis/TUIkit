//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnGeometryChangeTests.swift
//
//  `.onGeometryChange(for:of:action:)` — a view reporting its own size.
//
//  Two properties carry the feature and neither is obvious from the signature:
//  that it reports the size the view actually came out at (a `GeometryReader`
//  would report what was OFFERED, and would change the layout to do it), and
//  that it fires once per real change rather than once per pass — a frame
//  contains several measures, and a modifier that fired on each would report
//  sizes the view was only being asked about.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("onGeometryChange")
struct OnGeometryChangeTests {

    /// A live context across frames, so the last-value memory persists the way
    /// it does in the run loop.
    @MainActor
    private final class Fixture {
        let tui = TUIContext()

        @discardableResult
        func frame(_ view: some View, width: Int = 30, height: Int = 8) -> FrameBuffer {
            var env = EnvironmentValues()
            env.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            tui.stateStorage.endRenderPass()
            return buffer
        }
    }

    @Test("It shares an identity with onChange without stealing its slot")
    func coexistsWithOnChange() {
        // onChange and its siblings allocate tracked-value indices from a
        // per-identity counter; a FIXED index here landed on the first
        // sibling's slot. The overwrite made onChange read a geometry value
        // where it stored its own — a type mismatch reads as "no previous
        // value", so a real change fired nothing, every frame.
        let fixture = Fixture()
        var changes = 0

        func view(_ value: String) -> some View {
            Text("x")
                .onGeometryChange(for: Int.self) { $0.size.width } action: { _, _ in }
                .onChange(of: value) { _, _ in changes += 1 }
        }

        fixture.frame(view("a"))
        fixture.frame(view("b"))
        #expect(changes == 1, "onChange missed a real change beside onGeometryChange")
    }

    @Test("It reports the view's own size, not the space it was offered")
    func reportsTheViewsSize() {
        let fixture = Fixture()
        var seen: [CellSize] = []

        fixture.frame(
            Text("hi")
                .onGeometryChange(for: CellSize.self) { $0.size } action: { seen.append($0) },
            width: 30, height: 8)

        #expect(seen.count == 1)
        // Two cells of text on one line — not the 30×8 it was offered, which is
        // what a GeometryReader in this position would have said.
        #expect(seen.first == CellSize(width: 2, height: 1), "\(seen)")
    }

    @Test("It fires once on the first render and then only on a change")
    func firesOnceThenOnChange() {
        let fixture = Fixture()
        var seen: [Int] = []
        var width = 4

        func view() -> some View {
            Text(String(repeating: "x", count: width))
                .onGeometryChange(for: Int.self) { $0.size.width } action: { seen.append($0) }
        }

        fixture.frame(view())
        #expect(seen == [4])

        // Same size, several frames: silence.
        fixture.frame(view())
        fixture.frame(view())
        #expect(seen == [4], "a re-render at the same size is not a change: \(seen)")

        width = 9
        fixture.frame(view())
        #expect(seen == [4, 9])
    }

    @Test("The two-argument form carries the previous value")
    func twoArgumentForm() {
        let fixture = Fixture()
        var pairs: [(Int, Int)] = []
        var width = 3

        func view() -> some View {
            Text(String(repeating: "x", count: width))
                .onGeometryChange(for: Int.self) { $0.size.width } action: { old, new in
                    pairs.append((old, new))
                }
        }

        fixture.frame(view())
        #expect(pairs.count == 1)
        #expect(pairs[0].0 == 3 && pairs[0].1 == 3, "the first report is old == new: \(pairs)")

        width = 7
        fixture.frame(view())
        #expect(pairs.count == 2)
        #expect(pairs[1].0 == 3 && pairs[1].1 == 7, "\(pairs)")
    }

    /// The layout must be exactly what it would be without the modifier — the
    /// failure mode being a greedy wrapper that fills the space it was
    /// measuring.
    @Test("It does not change the layout it observes")
    func layoutIsUntouched() {
        let fixture = Fixture()
        let plain = fixture.frame(VStack { Text("one"); Text("two") })
        let observed = fixture.frame(
            VStack {
                Text("one").onGeometryChange(for: Int.self) { $0.size.width } action: { _ in }
                Text("two")
            })
        #expect(plain.lines.map(\.stripped) == observed.lines.map(\.stripped))
    }

    /// One report per frame, through a control that MEASURES BY RENDERING —
    /// `_CollapsingLabel` (a `Slider`'s, `Picker`'s or `Stepper`'s label) sizes
    /// itself by drawing, so the observed view reaches `renderToBuffer` twice
    /// in one frame, once with `isMeasuring` set.
    ///
    /// Honest about what this proves: it does NOT fail if the `isMeasuring`
    /// guard is deleted, because the two passes here derive the same width and
    /// the change detection swallows the second report anyway. The guard is
    /// still right — `OnChangeModifier` carries the same one, for a bug that
    /// was real there — and a pass measuring at a different proposal than the
    /// render would report a size the view never had. What this pins is the
    /// observable contract: a frame yields one report.
    @Test("A frame yields one report, even through a measure-by-rendering label")
    func oneReportPerFrame() {
        let fixture = Fixture()
        var count = 0
        fixture.frame(
            Slider(value: .constant(0.5)) {
                Text("a").onGeometryChange(for: Int.self) { $0.size.width } action: { _ in
                    count += 1
                }
            })
        #expect(count == 1, "one report per frame, not one per pass: \(count)")
    }

    /// A claimant that comes and goes INSIDE the content must not move the
    /// slot of the observer wrapped around it.
    @ViewBuilder
    private func conditionalObserver(_ expanded: Bool, _ selection: Int, _ fired: Counter)
        -> some View
    {
        // `buildOptional` yields an `Optional`, which renders its `.some` at the
        // PARENT identity — so this `.onChange` claims from the same
        // per-identity counter as the `.onGeometryChange` wrapped around it,
        // and stops claiming when `expanded` goes false.
        if expanded {
            Text("xxxx").onChange(of: selection) { _, _ in fired.value += 1 }
        }
    }

    /// A box so the `@ViewBuilder` helper above can report back.
    @MainActor
    private final class Counter {
        var value = 0
    }

    @Test("A claimant that vanishes from the content must not shift the slot")
    func slotSurvivesConditionalContent() {
        let fixture = Fixture()
        let fired = Counter()
        let selection = 999  // never changes across the three frames

        func view(_ expanded: Bool) -> some View {
            conditionalObserver(expanded, selection, fired)
                .onGeometryChange(for: Int.self) { $0.size.width } action: { _ in }
        }

        fixture.frame(view(true))  // onChange claims 0 (stores 999); geometry claims 1
        fixture.frame(view(false))  // content gone: geometry must not take slot 0
        fixture.frame(view(true))  // onChange reads slot 0 again

        #expect(fired.value == 0, "onChange fired though its value never changed")
    }
}
