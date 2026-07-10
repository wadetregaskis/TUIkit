//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WheelChainingGraceTests.swift
//
//  The wheel-chaining grace period: a nested scroller that hits its edge
//  consumes further blocked wheel ticks for a short window (default 500 ms)
//  before letting them chain to the enclosing scroller — so momentum
//  finishing a scroll inside a child doesn't immediately fling the parent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Wheel chaining grace period")
struct WheelChainingGraceTests {

    /// A vertical axis with 30 lines of content in a 10-line viewport,
    /// driven by an injected clock.
    private func makeAxis(now: @escaping () -> UInt64, delayNanos: UInt64 = 500_000_000)
        -> ScrollAxis
    {
        let axis = ScrollAxis()
        axis.extent = 30
        axis.viewportHeight = 10
        axis.wheelEdgeHold.delayNanos = delayNanos
        axis.wheelEdgeHold.nowNanos = now
        return axis
    }

    private func wheelDown(_ axis: ScrollAxis) -> Bool {
        axis.handleWheelEvent(MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
    }

    @Test("Blocked ticks at the edge are consumed during the grace, then chain")
    func graceThenChain() {
        var now: UInt64 = 0
        let axis = makeAxis(now: { now })
        axis.scrollOffset = axis.maxOffset  // already at the bottom

        #expect(wheelDown(axis), "first blocked tick starts the grace and is consumed")
        now += 200_000_000
        #expect(wheelDown(axis), "still within the 500 ms grace")
        now += 400_000_000  // 600 ms after arrival
        #expect(!wheelDown(axis), "grace expired — the tick chains to the parent")
        now += 50_000_000
        #expect(!wheelDown(axis), "and keeps chaining until the scroller moves again")
    }

    @Test("A successful scroll re-arms the grace for the next edge hit")
    func movementRearms() {
        var now: UInt64 = 0
        let axis = makeAxis(now: { now })
        axis.scrollOffset = axis.maxOffset

        _ = wheelDown(axis)                 // arm
        now += 600_000_000
        #expect(!wheelDown(axis), "grace expired")

        // Scroll up (moves) — consumed, and the edge state resets.
        #expect(axis.handleWheelEvent(
            MouseEvent(button: .scrollUp, phase: .scrolled, x: 0, y: 0)))

        // Back to the bottom (moves), then hit the edge again: fresh grace.
        #expect(wheelDown(axis), "moving back down to the edge is a real scroll")
        #expect(axis.scrollOffset == axis.maxOffset)
        #expect(wheelDown(axis), "a fresh grace period holds the first blocked tick")
    }

    @Test("A zero delay chains immediately (the original behaviour)")
    func zeroDelayChainsImmediately() {
        var now: UInt64 = 0
        let axis = makeAxis(now: { now }, delayNanos: 0)
        axis.scrollOffset = axis.maxOffset
        #expect(!wheelDown(axis), "no grace: the blocked tick chains at once")
    }

    @Test("A scroller with nothing to scroll never traps the wheel")
    func noOverflowNeverTraps() {
        var now: UInt64 = 0
        let axis = makeAxis(now: { now })
        axis.extent = 5  // fits entirely within the 10-line viewport
        #expect(!wheelDown(axis), "no overflow — the wheel can only mean the parent")
    }

    @Test("Duration → nanoseconds conversion clamps and scales correctly")
    func durationConversion() {
        #expect(Duration.milliseconds(500).wheelDelayNanos == 500_000_000)
        #expect(Duration.zero.wheelDelayNanos == 0)
        #expect(Duration.seconds(2).wheelDelayNanos == 2_000_000_000)
        #expect(Duration.milliseconds(-100).wheelDelayNanos == 0, "negative clamps to zero")
    }
}
