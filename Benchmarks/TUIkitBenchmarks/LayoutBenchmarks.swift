//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks targeting the layout pipeline — stack-based
/// containers, modifier propagation, alignment & padding, and
/// the two-pass measure / render cycle.
///
/// What we want to catch with these:
///
///   - Per-frame work in `_VStackCore` / `_HStackCore`
///     ballooning when a child count grows linearly.
///   - The `FrameBuffer.appendVertically` / `appendHorizontally`
///     paths accidentally reverting to per-line work that scales
///     with stack depth.
///   - Modifier-heavy chains adding measurable per-render
///     overhead — modifier infrastructure should be free at
///     idle.
///
/// All benchmark bodies hop to `MainActor` via
/// `await MainActor.run { … }` because every view-construction
/// API in TUIkit is `@MainActor`-isolated. The benchmark
/// library runs each closure in its own subprocess on a
/// worker thread, so `MainActor.assumeIsolated` would fail
/// the precondition at runtime — only an actual main-actor
/// hop works. Each closure is declared `async` so the
/// hop is permitted.
enum LayoutBenchmarks {

    static func register() {
        registerStackBenchmarks()
        registerNestedStackBenchmarks()
        registerModifierBenchmarks()
        registerLazyStackBenchmarks()
    }

    // MARK: - Stack benchmarks

    private static func registerStackBenchmarks() {
        Benchmark("layout/VStack — 10 Text children") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = VStack {
                    ForEach(0..<10, id: \.self) { Text("Item \($0)") }
                }
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("layout/HStack — 10 Text children") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = HStack {
                    ForEach(0..<10, id: \.self) { Text("\($0)") }
                }
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("layout/VStack — 100 Text children") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = VStack {
                    ForEach(0..<100, id: \.self) { Text("Item \($0)") }
                }
                let context = tallContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }

    // MARK: - Nested-stack benchmarks

    /// 50 rows × 3 columns inside a VStack of HStacks. This is
    /// the shape most real pages take — a header strip, a body
    /// of mixed-content rows, a footer — and it's the case
    /// where layout cost compounds.
    private static func registerNestedStackBenchmarks() {
        Benchmark("layout/VStack(HStack(Text x 3)) — 50 rows") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = VStack {
                    ForEach(0..<50, id: \.self) { row in
                        HStack {
                            Text("Col-A \(row)")
                            Text("Col-B \(row)")
                            Text("Col-C \(row)")
                        }
                    }
                }
                let context = tallContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }

    // MARK: - Modifier-chain benchmarks

    /// Tests that long modifier chains don't add measurable
    /// per-render overhead. The 'idle' version is a bare Text;
    /// the 'modifier-heavy' version stacks the same modifiers
    /// real apps reach for: bold, padding, border, frame.
    private static func registerModifierBenchmarks() {
        Benchmark("layout/Modifier chain — bare Text") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = Text("Modifier baseline")
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("layout/Modifier chain — 4 modifiers") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = Text("Modifier baseline")
                    .bold()
                    .padding(1)
                    .border()
                    .frame(width: 30, height: 5)
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }

    // MARK: - Lazy stack benchmarks

    /// `LazyVStack` should outperform `VStack` for large
    /// scrolled lists by skipping off-screen children. The
    /// benchmark below confirms the lazy variant stays bounded
    /// so a regression gets a stack trace.
    private static func registerLazyStackBenchmarks() {
        Benchmark("layout/LazyVStack — 500 Text children") { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = LazyVStack {
                    ForEach(0..<500, id: \.self) { Text("Row \($0)") }
                }
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }
}
