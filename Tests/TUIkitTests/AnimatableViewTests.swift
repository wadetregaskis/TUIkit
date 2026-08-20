//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableViewTests.swift
//
//  What `withAnimation` has to actually DO: render a view at values it was
//  never given, for exactly as long as the animation lasts, and then stop.
//  Everything here drives a real view through a real render context at
//  successive frame times, because the interesting failures — a picture that
//  freezes, a measure that disagrees with its render, an animation that never
//  ends — are all invisible to a single render.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A view with one continuous thing about it, drawn coarsely enough that the
/// assertions read as pictures.
private struct Bar: View, Animatable {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Text(String(repeating: "#", count: max(0, Int((fraction * 10).rounded()))))
    }
}

/// One place in the tree, rendered again and again as the frame clock advances
/// — the only way to see an animation at all.
@MainActor
private final class Screen {
    private var context: RenderContext

    init(animation: Animation?) {
        context = makeRenderContext(width: 20, height: 3)
        // What the run loop publishes: a change can animate only where more
        // frames can follow it.
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: animation)
    }

    /// The animation in force for subsequent changes.
    func setAnimation(_ animation: Animation?) {
        context.environment.transaction = Transaction(animation: animation)
    }

    /// Renders `fraction` as of `millis` on the frame clock, and reports the
    /// bar's width in cells.
    func render(_ fraction: Double, atMillis millis: Int) -> Int {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let buffer = renderToBuffer(Bar(fraction: fraction), context: context)
        return buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces).count ?? 0
    }

    /// Measures `fraction` as of `millis`, without rendering it.
    func measure(_ fraction: Double, atMillis millis: Int) -> Int {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        return measureChild(
            Bar(fraction: fraction), proposal: ProposedSize(width: 20, height: 3),
            context: context
        ).width
    }

    /// Whether the run loop would still be rendering for this.
    func isAnimating(atMillis millis: Int) -> Bool {
        context.environment.stateStorage!.animations.hasLiveAnimations(
            at: Int64(millis) * 1_000_000)
    }
}

@MainActor
@Suite("Animating a value")
struct AnimatableViewTests {

    @Test("A change under an animation is rendered on its way, not on arrival")
    func changeIsRenderedInBetween() {
        let screen = Screen(animation: .linear(duration: 1))
        #expect(screen.render(0, atMillis: 0) == 0)

        // The frame the change lands on still shows the OLD value: the
        // animation has run for no time at all.
        #expect(screen.render(1, atMillis: 0) == 0)
        #expect(screen.render(1, atMillis: 250) == 3)
        #expect(screen.render(1, atMillis: 500) == 5)
        #expect(screen.render(1, atMillis: 750) == 8)
        #expect(screen.render(1, atMillis: 1000) == 10)
    }

    @Test("It arrives exactly, and stops")
    func itFinishes() {
        let screen = Screen(animation: .linear(duration: 1))
        _ = screen.render(0, atMillis: 0)
        _ = screen.render(1, atMillis: 0)
        #expect(screen.isAnimating(atMillis: 500))

        #expect(screen.render(1, atMillis: 1000) == 10)
        // Past the end the picture is the value itself, and the loop is told
        // there is nothing left to render for. An animation that never retires
        // is a screen that never stops re-rendering.
        #expect(screen.render(1, atMillis: 5000) == 10)
        #expect(!screen.isAnimating(atMillis: 5000))
    }

    @Test("A view does not animate into existence")
    func firstSightIsNotAChange() {
        let screen = Screen(animation: .linear(duration: 1))
        // The very first render shows the value it was given, whatever
        // transaction is in force — otherwise every view would fade in from
        // zero as it scrolled into view.
        #expect(screen.render(1, atMillis: 0) == 10)
        #expect(!screen.isAnimating(atMillis: 0))
    }

    @Test("Without an animation the change is immediate")
    func unanimatedChangesSnap() {
        let screen = Screen(animation: nil)
        #expect(screen.render(0, atMillis: 0) == 0)
        #expect(screen.render(1, atMillis: 0) == 10)
        #expect(!screen.isAnimating(atMillis: 0))
    }

    @Test("Outside a run loop, changes snap rather than freeze")
    func noRunLoopMeansNoAnimation() {
        // A one-off render — a frame dump, `ViewRenderer` — gets exactly one
        // frame. An animation started there would show its FIRST value and
        // never advance, which is worse than not animating: the picture would
        // be wrong and stay wrong.
        var context = makeRenderContext(width: 20, height: 3)
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
        context.environment.canAnimate = false

        _ = renderToBuffer(Bar(fraction: 0), context: context)
        let buffer = renderToBuffer(Bar(fraction: 1), context: context)
        #expect(buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces).count == 10)
    }

    @Test("Retargeting mid-flight starts from where the picture is")
    func retargetingDoesNotSnapBack() {
        let screen = Screen(animation: .linear(duration: 1))
        _ = screen.render(0, atMillis: 0)
        _ = screen.render(1, atMillis: 0)
        #expect(screen.render(1, atMillis: 500) == 5)

        // Halfway there, the target moves. The new animation must begin at 0.5
        // — where the picture actually is — not at the old target, which would
        // jump the bar to full and then walk it back down.
        #expect(screen.render(0, atMillis: 500) == 5)
        #expect(screen.render(0, atMillis: 1000) == 3)
        #expect(screen.render(0, atMillis: 1500) == 0)
    }

    @Test("An unanimated change mid-flight abandons the animation where it is")
    func unanimatedChangeInterrupts() {
        let screen = Screen(animation: .linear(duration: 1))
        _ = screen.render(0, atMillis: 0)
        _ = screen.render(1, atMillis: 0)
        #expect(screen.render(1, atMillis: 500) == 5)

        screen.setAnimation(nil)
        #expect(screen.render(0.2, atMillis: 500) == 2)
        #expect(!screen.isAnimating(atMillis: 500))
    }

    @Test("Measuring agrees with rendering, on every frame")
    func measureMatchesRender() {
        // A measure that used the TARGET would lay the view out for a frame
        // that is not on screen yet — the whole class of measure/render parity
        // bug, arriving here by a new route.
        let screen = Screen(animation: .linear(duration: 1))
        _ = screen.render(0, atMillis: 0)

        // Measure BEFORE the render of the same frame — the order a layout pass
        // actually uses — and again after.
        #expect(screen.measure(1, atMillis: 0) == 0)
        #expect(screen.render(1, atMillis: 0) == 0)
        #expect(screen.measure(1, atMillis: 0) == 0)

        for millis in stride(from: 0, through: 1000, by: 125) {
            let measured = screen.measure(1, atMillis: millis)
            #expect(screen.render(1, atMillis: millis) == measured, "at \(millis)ms")
        }
    }

    @Test("Measuring does not start, advance or end an animation")
    func measuringHasNoSideEffects() {
        let screen = Screen(animation: .linear(duration: 1))
        _ = screen.render(0, atMillis: 0)

        // Measure the change a dozen times, at times all over the animation.
        for millis in [0, 500, 1000, 250, 5000] {
            _ = screen.measure(1, atMillis: millis)
        }
        #expect(!screen.isAnimating(atMillis: 0), "a measure started an animation")

        // The render that follows must still see a change, and animate it from
        // the beginning — not from wherever the measures pretended it was.
        #expect(screen.render(1, atMillis: 0) == 0)
        #expect(screen.render(1, atMillis: 500) == 5)
    }

    @Test("An easing animation is not linear")
    func theCurveIsUsed() {
        // The animation is a curve, not a duration with a lerp: at the quarter
        // point an ease-in must be measurably behind a linear one.
        let eased = Screen(animation: .easeIn(duration: 1))
        _ = eased.render(0, atMillis: 0)
        _ = eased.render(1, atMillis: 0)
        let quarter = eased.render(1, atMillis: 250)

        let linear = Screen(animation: .linear(duration: 1))
        _ = linear.render(0, atMillis: 0)
        _ = linear.render(1, atMillis: 0)
        #expect(quarter < linear.render(1, atMillis: 250))
    }

    @Test("A repeating animation never stops asking for frames")
    func repeatForeverNeverSettles() {
        let screen = Screen(animation: .linear(duration: 0.5).repeatForever(autoreverses: true))
        _ = screen.render(0, atMillis: 0)
        _ = screen.render(1, atMillis: 0)
        #expect(screen.render(1, atMillis: 500) == 10)
        #expect(screen.render(1, atMillis: 1000) == 0)
        #expect(screen.render(1, atMillis: 1500) == 10)
        // This is the expensive shape, and the store says so honestly: the run
        // loop will keep rendering this subtree for as long as it is on screen.
        #expect(screen.isAnimating(atMillis: 100_000))
    }
}

// MARK: - The static witness

/// Conforms to `Animatable` in a SEPARATE extension rather than on the type
/// declaration, which is the spelling that could pick the wrong witness for
/// `View._isAnimatable` — a wrong answer here means the view silently never
/// animates, which is exactly the failure that looks like a success.
private struct SplitConformanceBar: View {
    var fraction: Double

    var body: some View {
        Text(String(repeating: "#", count: max(0, Int((fraction * 10).rounded()))))
    }
}

extension SplitConformanceBar: Animatable {
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
}

@MainActor
@Suite("The animatable witness")
struct AnimatableWitnessTests {

    @Test("A conformance declared in an extension still animates")
    func retroactiveConformanceIsSeen() {
        var context = makeRenderContext(width: 20, height: 3)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))

        func render(_ fraction: Double, atMillis: Int) -> Int {
            context.environment.frameNowNanos = Int64(atMillis) * 1_000_000
            let buffer = renderToBuffer(SplitConformanceBar(fraction: fraction), context: context)
            return buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces).count ?? 0
        }

        #expect(SplitConformanceBar._isAnimatable, "the constrained witness was not chosen")
        #expect(render(0, atMillis: 0) == 0)
        #expect(render(1, atMillis: 0) == 0)
        #expect(render(1, atMillis: 500) == 5)
    }

    @Test("An ordinary view says it has nothing to animate")
    func plainViewIsNotAnimatable() {
        #expect(!Text._isAnimatable)
        #expect(!EmptyView._isAnimatable)
        #expect(!VStack<Text>._isAnimatable)
    }
}
