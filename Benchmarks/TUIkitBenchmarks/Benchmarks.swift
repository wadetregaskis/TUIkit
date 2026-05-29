//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Benchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import Foundation
import TUIkit

/// `true` when view-using benchmarks should be skipped.
/// Defaults to `true` because TUIkit's `View` API is
/// `@MainActor`-isolated and package-benchmark blocks the
/// main thread on a `DispatchSemaphore` while async
/// benchmark closures run. Calling `await MainActor.run`
/// from those closures deadlocks against the blocked main
/// thread → SIGTRAP. Set `TUIKIT_BENCH_RUN_VIEW=1` to
/// attempt the view benchmarks anyway (they will crash
/// until #31 — moving TUIkit's render pipeline off
/// MainActor onto a dedicated global actor — lands).
let skipViewBenchmarks =
    ProcessInfo.processInfo.environment["TUIKIT_BENCH_RUN_VIEW"] != "1"

/// Configuration helper for view-using benchmarks. Stamps
/// the default config with `skip: skipViewBenchmarks` so
/// the suite can run cleanly under the current
/// MainActor-deadlock constraint. `nonisolated(unsafe)` is
/// safe here: the configuration is built once during
/// benchmark registration on the main thread before any
/// async benchmark closures run.
func viewBenchmarkConfiguration() -> Benchmark.Configuration {
    var config = Benchmark.defaultConfiguration
    config.skip = skipViewBenchmarks
    return config
}

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
        // 1 s per benchmark when run via the Plugin from
        // macOS. Override with TUIKIT_BENCH_MAX_DURATION_MS
        // when running under a tighter wallclock budget (CI
        // smoke tests, sandboxed environments where 24
        // benchmarks × 1 s is too long).
        maxDuration: .milliseconds(
            Int(ProcessInfo.processInfo.environment["TUIKIT_BENCH_MAX_DURATION_MS"] ?? "1000") ?? 1000
        )
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
