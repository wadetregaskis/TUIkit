//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Benchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

// MARK: - Benchmark Defaults

/// Default configuration. Locks in a tight set of metrics so
/// regression runs comparing against a baseline are signal,
/// not noise:
///
///   - `.cpuTotal` and `.wallClock` for the headline timing.
///   - `.mallocCountTotal` and `.peakMemoryResident` to catch
///     allocation regressions that don't move the clock yet.
///   - `.throughput` for the for-loop style benchmarks where
///     "renders per second" is more readable than "ms per
///     render".
///
/// `maxDuration: 1.0` keeps the full suite runtime reasonable
/// — most benchmarks here are cheap enough that one second
/// gives plenty of samples.
private let defaultConfiguration = Benchmark.Configuration(
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

// MARK: - Top-level benchmarks closure

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = defaultConfiguration

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
