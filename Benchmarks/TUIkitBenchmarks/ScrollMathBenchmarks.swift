//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollMathBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks for the `ScrollableOffsetState` arithmetic.
///
/// Distinct from the `scrollview/*` benchmarks (which render a
/// `ScrollView` view and are `@MainActor`-gated): this targets
/// the pure scroll-offset math shared by `ScrollViewHandler`
/// and `ItemListHandler` via the `ScrollableOffsetState`
/// protocol — clamping, visible-range computation, and wheel
/// handling. `ScrollViewHandler` is deliberately not
/// `@MainActor` (it's only ever touched from the already-
/// isolated render loop), so its arithmetic is benchmarkable
/// off the main actor here.
///
/// Each benchmark drives a tight loop of operations against a
/// tall (10k-line) content area so per-call costs accumulate
/// into a measurable signal.
enum ScrollMathBenchmarks {

    static func register() {
        registerOffsetMath()
        registerWheel()
    }

    // MARK: - Test inputs

    private static func makeHandler() -> ScrollViewHandler {
        let handler = ScrollViewHandler(focusID: "bench-scroll")
        handler.contentHeight = 10_000
        handler.viewportHeight = 40
        return handler
    }

    private static let wheelDown = MouseEvent(button: .scrollDown, phase: .scrolled, x: 10, y: 10)
    private static let wheelUp = MouseEvent(button: .scrollUp, phase: .scrolled, x: 10, y: 10)

    private static let iterations = 2_000

    // MARK: - Offset math

    private static func registerOffsetMath() {
        Benchmark("scroll-math/scroll(by:) + clamp ×2000") { benchmark in
            let handler = makeHandler()
            for _ in benchmark.scaledIterations {
                for step in 0..<iterations {
                    handler.scroll(by: (step & 1) == 0 ? 3 : -2)
                }
                blackHole(handler.scrollOffset)
            }
        }

        Benchmark("scroll-math/visibleRange + predicates ×2000") { benchmark in
            let handler = makeHandler()
            handler.scrollOffset = 500
            for _ in benchmark.scaledIterations {
                var accumulator = 0
                for _ in 0..<iterations {
                    accumulator += handler.visibleRange.count
                    accumulator += handler.maxOffset
                    if handler.hasContentAbove { accumulator += 1 }
                    if handler.hasContentBelow { accumulator += 1 }
                }
                blackHole(accumulator)
            }
        }
    }

    // MARK: - Wheel handling

    private static func registerWheel() {
        Benchmark("scroll-math/handleWheelEvent ×2000") { benchmark in
            let handler = makeHandler()
            for _ in benchmark.scaledIterations {
                for step in 0..<iterations {
                    _ = handler.handleWheelEvent((step & 1) == 0 ? wheelDown : wheelUp)
                }
                blackHole(handler.scrollOffset)
            }
        }
    }
}
