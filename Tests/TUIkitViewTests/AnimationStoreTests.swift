//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationStoreTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

/// The store's settling behaviour: what a finished animation leaves on screen
/// must be what every later frame keeps showing.
@Suite("AnimationStore settling")
struct AnimationStoreTests {

    private struct Owner {}

    private func makeKey() -> AnimationStore.Key {
        AnimationStore.Key(
            identity: ViewIdentity(path: "Root"), owner: ObjectIdentifier(Owner.self))
    }

    /// The frame timestamps, in nanoseconds.
    private let second: Int64 = 1_000_000_000

    @Test("An even-count autoreverse settles where it ended — no later snap to the target")
    func evenAutoreverseSettlesAtItsEnd() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        // First sight does not animate.
        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)

        // Out and back: 0 → 1 → 0 over 0.2 s.
        let animation = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: false)

        // Mid-flight sanity: the first pass heads out.
        let mid = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second / 20, isMeasuring: false)
        #expect(mid > 0.0)

        // The finish frame: fraction 0, back at the start.
        let finished = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second / 2, isMeasuring: false)
        #expect(finished == 0.0)

        // An unrelated render much later must keep showing what the last
        // animated frame showed — the retirement used to store the TARGET,
        // snapping the picture from 0 to 1 here.
        let later = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 60 * second, isMeasuring: false)
        #expect(later == 0.0, "the settled picture snapped to the target")

        // And an unchanged re-declaration must NOT restart the animation.
        let evenLater = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 61 * second, isMeasuring: false)
        #expect(evenLater == 0.0)
    }

    @Test("A plain animation settles at its target")
    func plainAnimationSettlesAtTarget() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)
        let animation = Animation.linear(duration: 0.1)
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: false)

        let finished = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second, isMeasuring: false)
        #expect(finished == 1.0)
        let later = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 60 * second, isMeasuring: false)
        #expect(later == 1.0)
    }

    @Test("A new value after an even-autoreverse settle animates from the settled picture")
    func retargetAfterSettleStartsFromSettled() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)
        let bounce = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: 0, isMeasuring: false)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: second / 2, isMeasuring: false)

        // Retarget to 2.0 with a fresh linear fade: the first frame presents
        // the settled 0.0 (retargeting starts from where the picture IS), and
        // the midpoint is 1.0 — from 0, not from the old target 1.
        let start = store.value(
            for: key, target: 2.0, animation: .linear(duration: 0.1),
            nowNanos: second, isMeasuring: false)
        #expect(start == 0.0)
        let mid = store.value(
            for: key, target: 2.0, animation: .linear(duration: 0.1),
            nowNanos: second + second / 20, isMeasuring: false)
        #expect(abs(mid - 1.0) < 0.0001)
    }
}
