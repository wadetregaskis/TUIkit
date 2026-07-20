//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Headless.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch
import TUIkit

// MARK: - Headless runners

/// No-PTY entry points: render scenarios via `renderToBuffer` without a
/// terminal. `--selfcheck` is a smoke test (renders each scenario once);
/// `--bench` is the profiling instrument — a counted render loop suitable for
/// `xctrace --launch` (no debugger attach needed), mirroring the existing
/// `Tools/Profiling/RenderHarness`.
enum Headless {

    /// Builds a render environment. Each call is independent (fresh state +
    /// cache) so `--bench --cold` can reset between frames to measure the cold
    /// measure+render cost rather than the cache-warm steady state.
    @MainActor
    private static func makeContext(cols: Int, rows: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        environment.renderCache = RenderCache()
        return RenderContext(availableWidth: cols, availableHeight: rows, environment: environment)
    }

    /// Renders every scenario once at a fixed size; prints dimensions. Returns
    /// the number that produced an empty buffer (a failure).
    @MainActor
    static func selfcheck(_ config: StressConfig) -> Int {
        let clock = StressClock()
        var failures = 0
        print("selfcheck — scale \(config.scale) seed \(config.seed) @ 120x40")
        for scenario in Scenarios.all {
            let context = makeContext(cols: 120, rows: 40)
            let view = AnyView(scenario.make(config).environment(clock))
            let buffer = renderToBuffer(view, context: context)
            let ok = buffer.width > 0 && buffer.height > 0
            if !ok { failures += 1 }
            let id = scenario.id.padding(toLength: 12, withPad: " ", startingAt: 0)
            print("  \(ok ? "ok  " : "FAIL") \(id) \(buffer.width)x\(buffer.height)  \(scenario.title)")
        }
        print(failures == 0 ? "selfcheck: all \(Scenarios.all.count) scenarios rendered" : "selfcheck: \(failures) FAILED")
        return failures
    }

    /// Renders one scenario `iterations` times and reports timing + a checksum
    /// (so the optimiser can't elide the loop). With `cold == true` a fresh
    /// state/cache is used each frame (worst-case measure+render); otherwise the
    /// cache stays warm across frames (steady state). The shared clock is bumped
    /// each frame so tick-driven scenarios (e.g. `churn`) actually churn.
    @MainActor
    static func bench(
        _ id: String,
        config: StressConfig,
        iterations: Int,
        cols: Int,
        rows: Int,
        cold: Bool
    ) -> Int {
        guard let scenario = Scenarios.byID(id) else {
            print("bench: unknown scenario '\(id)'. Known: \(Scenarios.all.map(\.id).joined(separator: ", "))")
            return 1
        }
        let clock = StressClock()
        let view = AnyView(scenario.make(config).environment(clock))

        // Warm up (build lazy state, prime caches) outside the timed region.
        var warm = makeContext(cols: cols, rows: rows)
        _ = renderToBuffer(view, context: warm)

        var checksum = 0
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            if cold { warm = makeContext(cols: cols, rows: rows) }
            clock.tick &+= 1
            let buffer = renderToBuffer(view, context: warm)
            checksum = checksum &+ buffer.width &+ buffer.height &+ buffer.lines.count
        }
        let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds

        let totalMs = Double(ns) / 1_000_000
        let perFrameUs = Double(ns) / 1_000 / Double(max(1, iterations))
        print("bench scenario=\(id) scale=\(config.scale) size=\(cols)x\(rows) "
            + "iters=\(iterations) cold=\(cold)")
        print(String(format: "  total=%.1fms  per-frame=%.1fµs  (%.0f fps-equiv)  checksum=%d",
            totalMs, perFrameUs, 1_000_000 / max(0.001, perFrameUs), checksum))
        return 0
    }
}
