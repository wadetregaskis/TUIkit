//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationValueModifierTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A bar whose width is its one continuous property. See `AnimatableViewTests`.
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

/// `Bar` under `.animation(_:value:)`, with a second value the modifier is NOT
/// watching — the distinction the whole modifier exists to draw.
private struct Watched: View {
    let fraction: Double
    let trigger: Int
    let animation: Animation?

    var body: some View {
        Bar(fraction: fraction).animation(animation, value: trigger)
    }
}

@MainActor
@Suite("Animating one value")
struct AnimationValueModifierTests {

    /// The same place in the tree, rendered again as the frame clock advances.
    @MainActor
    private final class Screen {
        var context = makeRenderContext(width: 20, height: 3)

        init(ambient: Animation? = nil) {
            context.environment.canAnimate = true
            context.environment.transaction = Transaction(animation: ambient)
        }

        func render(_ fraction: Double, trigger: Int, animation: Animation?, atMillis: Int) -> Int {
            context.environment.frameNowNanos = Int64(atMillis) * 1_000_000
            let buffer = renderToBuffer(
                Watched(fraction: fraction, trigger: trigger, animation: animation),
                context: context)
            return buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces).count ?? 0
        }
    }

    @Test("A change to the watched value animates")
    func watchedValueAnimates() {
        let screen = Screen()
        let animation = Animation.linear(duration: 1)
        #expect(screen.render(0, trigger: 0, animation: animation, atMillis: 0) == 0)
        #expect(screen.render(1, trigger: 1, animation: animation, atMillis: 0) == 0)
        #expect(screen.render(1, trigger: 1, animation: animation, atMillis: 500) == 5)
        #expect(screen.render(1, trigger: 1, animation: animation, atMillis: 1000) == 10)
    }

    @Test("A change the modifier is not watching snaps")
    func unwatchedChangeSnaps() {
        // This is the point of the value-scoped form: the subtree animates for
        // ITS value and for nothing else. Here the bar moves while the trigger
        // stands still, so it must jump.
        let screen = Screen()
        let animation = Animation.linear(duration: 1)
        #expect(screen.render(0, trigger: 0, animation: animation, atMillis: 0) == 0)
        #expect(screen.render(1, trigger: 0, animation: animation, atMillis: 0) == 10)
    }

    @Test("An explicit withAnimation still reaches the subtree")
    func ambientAnimationIsNotMasked() {
        // This modifier ADDS an animation; it does not mask one. `withAnimation`
        // is a deliberate act at a call site that has said nothing about this
        // subtree, and a modifier left in place here must not quietly veto it.
        // Refusing outright is `.transaction { $0.disablesAnimations = true }`.
        let screen = Screen(ambient: .linear(duration: 1))
        let animation = Animation.linear(duration: 1)
        #expect(screen.render(0, trigger: 0, animation: animation, atMillis: 0) == 0)
        #expect(screen.render(1, trigger: 0, animation: animation, atMillis: 0) == 0)
        #expect(screen.render(1, trigger: 0, animation: animation, atMillis: 500) == 5)
    }

    @Test("Watching with a nil animation makes that value's changes snap")
    func nilAnimationRefuses() {
        let screen = Screen(ambient: .linear(duration: 1))
        #expect(screen.render(0, trigger: 0, animation: nil, atMillis: 0) == 0)
        #expect(screen.render(1, trigger: 1, animation: nil, atMillis: 0) == 10)
    }

    @Test("A subtree can refuse to animate at all")
    func transactionCanDisable() {
        var context = makeRenderContext(width: 20, height: 3)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
        func render(_ fraction: Double) -> Int {
            let buffer = renderToBuffer(
                Bar(fraction: fraction).transaction { $0.disablesAnimations = true },
                context: context)
            return buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces).count ?? 0
        }
        #expect(render(0) == 0)
        #expect(render(1) == 10)
    }

    @Test("The first render is not a change")
    func firstRenderDoesNotAnimate() {
        let screen = Screen()
        // The trigger has no previous value to differ from, so a view appearing
        // with `.animation(_:value:)` on it shows what it was given.
        #expect(screen.render(1, trigger: 7, animation: .linear(duration: 1), atMillis: 0) == 10)
    }

    @Test("Two of them at one place keep separate records")
    func nestedModifiersDoNotCollide() {
        // `.animation(a, value: x).animation(b, value: y)` renders at one
        // identity — modifiers do not descend it — so the two must be told
        // apart by something else. Their generic types differ, because each
        // one's `Content` is the other.
        struct Doubled: View {
            let fraction: Double
            let outer: Int
            let inner: Int

            var body: some View {
                Bar(fraction: fraction)
                    .animation(.linear(duration: 1), value: inner)
                    .animation(.linear(duration: 1), value: outer)
            }
        }

        var context = makeRenderContext(width: 20, height: 3)
        context.environment.canAnimate = true
        func render(_ fraction: Double, outer: Int, inner: Int, atMillis: Int) -> Int {
            context.environment.frameNowNanos = Int64(atMillis) * 1_000_000
            let buffer = renderToBuffer(
                Doubled(fraction: fraction, outer: outer, inner: inner), context: context)
            return buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces).count ?? 0
        }

        #expect(render(0, outer: 0, inner: 0, atMillis: 0) == 0)
        // Only the INNER trigger moves. If the two shared a record, the outer
        // one would have seen a change too — and the result is the same either
        // way, so the interesting half is the next assertion.
        #expect(render(1, outer: 0, inner: 1, atMillis: 0) == 0)
        #expect(render(1, outer: 0, inner: 1, atMillis: 500) == 5)
        // Now the outer one moves and the inner one does not. A shared record
        // would have been overwritten by the inner trigger and would report no
        // change here, snapping the bar.
        #expect(render(1, outer: 1, inner: 1, atMillis: 1000) == 10)
        #expect(render(0, outer: 2, inner: 1, atMillis: 1000) == 10)
        #expect(render(0, outer: 2, inner: 1, atMillis: 1500) == 5)
    }
}
