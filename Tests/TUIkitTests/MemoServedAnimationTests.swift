//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoServedAnimationTests.swift
//
//  A buffer the render cache serves shows every animated cell run in it at the
//  frame the run would show NOW, not the one it showed when the buffer was drawn.
//
//  A run's cells in a buffer hold the frame of the instant that buffer was
//  rendered; the run loop moves them on only at its next tick. So a memo that
//  served such a buffer at a later instant put the old frame back on screen for
//  as long as it took the next tick to come round — every spinner in a memoized
//  row stepping back to wherever it stood when its row was stored, at every
//  render. On the Example's Spinners page a click on the Frame stepper renders,
//  and the catalogue "shuddered".
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A catalogue row, `Equatable` so `ForEach` memoizes it as the Spinners page's
/// rows are.
private struct CatalogueRow: Identifiable, Equatable {
    let name: String
    let style: SpinnerStyle
    var id: String { name }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
}

/// Spinners in memoized rows, the Spinners page's shape.
private struct Catalogue: View {
    let rows: [CatalogueRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 1) {
                    Spinner(style: row.style)
                    Text(row.name)
                }
            }
        }
    }
}

/// Spinners at four different rates.
private struct CatalogueApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Catalogue(rows: [
                CatalogueRow(name: "line", style: .line), CatalogueRow(name: "pie", style: .pie),
                CatalogueRow(name: "dots", style: .dots), CatalogueRow(name: "earth", style: .earth),
            ])
        }
    }
}

@MainActor
@Suite("A served buffer shows its animations as they stand now")
struct MemoServedAnimationTests {
    /// Every tick for two seconds, rendering each time — which is what an app
    /// does while something else on the page changes — against an instance
    /// with no cache: the ticks whose screens differed, and the warm instance.
    private func staleTicks<A: App>(_ make: () -> A) -> (ticks: [Int], warm: HeadlessApp<A>) {
        let warm = HeadlessApp(make(), width: 30, height: 8)
        let cold = HeadlessApp(make(), width: 30, height: 8)
        cold.clearsRenderCacheEachFrame = true
        var stale: [Int] = []
        for tick in 0..<120 {
            let now = AnimationClock.nanoseconds(atTick: Int64(tick))
            warm.frame(atNanos: now)
            cold.frame(atNanos: now)
            if warm.screen != cold.screen { stale.append(tick) }
        }
        return (stale, warm)
    }

    /// The rows are served whenever nothing in them has moved, so the cache
    /// still does its job.
    @Test("Spinners in memoized rows draw what an uncached app draws at every tick")
    func memoizedSpinnersDrawTheCurrentFrame() {
        let (stale, warm) = staleTicks(CatalogueApp.init)
        #expect(stale.isEmpty, "the cache drew an old frame at ticks \(stale)")
        #expect(warm.renderCache.rowWork.served > 0, "no row was ever served, so this proved nothing")
    }

    /// Where the tests below stand the two clocks: `clock` at the instant tick
    /// `tick` begins, as the loop reads it, in whole nanoseconds —
    /// `seconds(forTicks:)` is the nearest Double to k/60, a nanosecond short of
    /// the tick's first instant two ticks in three — and the OTHER clock three
    /// ticks on, at a time that would move the run, so a check that read the
    /// wrong one fails.
    private static func instant(atTick tick: Int, on clock: AnimationClock) -> AnimationInstant {
        func seconds(atTick tick: Int) -> Double {
            Double(AnimationClock.nanoseconds(atTick: Int64(tick))) / 1_000_000_000
        }
        let own = seconds(atTick: tick)
        let other = seconds(atTick: tick + 3)
        return clock == .content
            ? AnimationInstant(content: own, cursor: other) : AnimationInstant(content: other, cursor: own)
    }

    /// The cache's half on its own, on each clock. A run of two ticks a frame
    /// showing A, B, B, C: stored at tick 0 it is served while A is showing and
    /// again a whole cycle later, and missed in between. Stored at tick 2 it is
    /// served at tick 4, a different frame INDEX showing the same picture, and
    /// missed at C. A measure is served whatever the time, as it draws nothing.
    @Test("A stored buffer is served only while each of its runs shows what it showed", arguments: AnimationClock.allCases)
    func servedOnlyWhileTheRunsShowTheSame(_ clock: AnimationClock) {
        let cache = RenderCache()
        let identity = ViewIdentity(path: "Probe")
        var buffer = FrameBuffer(text: "A")
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 1, frames: ["A", "B", "B", "C"], frameTicks: 2, clock: clock)
        ]
        func store(atTick tick: Int) {
            cache.frameInstant = Self.instant(atTick: tick, on: clock)
            cache.store(identity: identity, view: 1, buffer: buffer, contextWidth: 10, contextHeight: 1)
        }
        func served(atTick tick: Int, measuring: Bool = false) -> Bool {
            cache.frameInstant = Self.instant(atTick: tick, on: clock)
            return cache.lookupEntry(
                identity: identity, view: 1, contextWidth: 10, contextHeight: 1,
                gradientFrame: nil, surfaceBackground: nil, effectScope: .none,
                animationMustBeCurrent: !measuring) != nil
        }

        store(atTick: 0)
        #expect(served(atTick: 0), "A, at the instant it was drawn")
        #expect(served(atTick: 1), "A, a tick later")
        #expect(!served(atTick: 2), "B")
        #expect(!served(atTick: 6), "C")
        #expect(served(atTick: 8), "A, a cycle later")
        #expect(served(atTick: 6, measuring: true), "C, but for a measure")

        store(atTick: 2)
        #expect(served(atTick: 4), "B again, from the next frame")
        #expect(!served(atTick: 6), "C")
    }

    /// A buffer drawn where no frame said when — a snapshot, a bench harness —
    /// keeps no instant, and is served as before.
    @Test("A buffer stored with no instant is served whatever the instant later")
    func noInstantIsServedAsBefore() {
        let cache = RenderCache()
        let identity = ViewIdentity(path: "Probe")
        var buffer = FrameBuffer(text: "A")
        buffer.animatedCells = [
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 1, frames: ["A", "B"], frameTicks: 2, clock: .content)
        ]
        cache.store(identity: identity, view: 1, buffer: buffer, contextWidth: 10, contextHeight: 1)
        cache.frameInstant = AnimationInstant(
            content: Double(AnimationClock.nanoseconds(atTick: 2)) / 1_000_000_000, cursor: 0)
        #expect(cache.lookup(identity: identity, view: 1, contextWidth: 10, contextHeight: 1) != nil)
    }
}
