//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks targeting ``ScrollView``. The windowing logic
/// is the hot path — content gets rendered at the full
/// natural height, then the visible window is sliced out and
/// hit-test regions are filtered. Both halves of that have
/// O(content_height) and O(regions) cost respectively, so
/// regressions tend to surface as the content gets taller.
///
/// All benchmark bodies hop to `MainActor` via
/// `await MainActor.run { … }` — see the comment in
/// ``LayoutBenchmarks`` for the rationale.
enum ScrollViewBenchmarks {

    static func register() {
        registerLongTextBenchmarks()
        registerMixedContentBenchmarks()
    }

    // MARK: - Long text

    private static func registerLongTextBenchmarks() {
        Benchmark("scrollview/100 Text rows", configuration: viewBenchmarkConfiguration()) { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let lines = (0..<100).map { "Row \($0)" }
                let view = ScrollView {
                    VStack {
                        ForEach(lines, id: \.self) { Text($0) }
                    }
                }
                .frame(height: 10)
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("scrollview/1000 Text rows", configuration: viewBenchmarkConfiguration()) { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let lines = (0..<1000).map { "Row \($0)" }
                let view = ScrollView {
                    VStack {
                        ForEach(lines, id: \.self) { Text($0) }
                    }
                }
                .frame(height: 10)
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }

        Benchmark("scrollview/100 rows, indicators off", configuration: viewBenchmarkConfiguration()) { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let lines = (0..<100).map { "Row \($0)" }
                let view = ScrollView(showsIndicators: false) {
                    VStack {
                        ForEach(lines, id: \.self) { Text($0) }
                    }
                }
                .frame(height: 10)
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }

    // MARK: - Mixed-widget content

    /// A ScrollView wrapping mixed-widget content (the demo
    /// page's middle section) — exercises the hit-test region
    /// filtering path, which has to scan every region in the
    /// content buffer and decide whether to keep it.
    private static func registerMixedContentBenchmarks() {
        Benchmark("scrollview/Mixed-widget content", configuration: viewBenchmarkConfiguration()) { benchmark async in
            let iterations = benchmark.scaledIterations
            await MainActor.run {
                let view = ScrollView {
                    VStack(alignment: .leading) {
                        Text("Heading").bold()
                        TextField("Filter", text: .constant(""))
                        HStack {
                            Button("-1") { }
                            Button("+1") { }
                            Button("Reset") { }
                        }
                        Slider(value: .constant(0.5))
                        ForEach(0..<30, id: \.self) { Text("Row \($0)") }
                    }
                }
                .frame(height: 10)
                let context = standardContext()
                for _ in iterations {
                    blackHole(renderToBuffer(view, context: context))
                }
            }
        }
    }
}
