//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Benchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Top-level benchmarks closure. The configuration value
/// lives inside the closure (rather than a top-level `let`)
/// because `Benchmark.Configuration` is not `Sendable` and
/// the benchmarks closure itself is `@Sendable`; building
/// the value at call time sidesteps the
/// non-concurrency-safe global-state warning.
let benchmarks: @Sendable () -> Void = {
    // Default configuration. Locks in a tight set of metrics
    // so regression runs comparing against a baseline are
    // signal, not noise:
    //
    //   - `.cpuTotal` and `.wallClock` for the headline timing.
    //   - `.mallocCountTotal` and `.peakMemoryResident` to catch
    //     allocation regressions that don't move the clock yet.
    //   - `.throughput` for the for-loop style benchmarks where
    //     "renders per second" is more readable than "ms per
    //     render".
    //
    // `maxDuration: 1.0` keeps the full suite runtime
    // reasonable — most benchmarks here are cheap enough that
    // one second gives plenty of samples.
    Benchmark.defaultConfiguration = Benchmark.Configuration(
        metrics: [
            .cpuTotal,
            .wallClock,
            .mallocCountTotal,
            .peakMemoryResident,
            .throughput,
        ],
        timeUnits: .microseconds,
        maxDuration: .seconds(1)
    )

    // Each suite lives in its own file (LayoutBenchmarks,
    // RenderBenchmarks, ListTableBenchmarks, ImageBenchmarks)
    // and registers via a static `register()` entry point —
    // keeps this file as a manifest of what's being measured.
    LayoutBenchmarks.register()
    RenderBenchmarks.register()
    ListTableBenchmarks.register()
    ScrollViewBenchmarks.register()
    ImageBenchmarks.register()
}
