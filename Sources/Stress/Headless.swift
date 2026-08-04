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

    /// A checksum over the frame's *content*, not merely its dimensions.
    ///
    /// The dimensions are a constant for a given viewport — 120 + 40 + 40 for
    /// every scenario, at every scale — so a checksum built from them cannot
    /// tell a fully rendered frame from an empty one. That is exactly how this
    /// harness came to report healthy-looking numbers on Linux while rendering
    /// nothing at all: only a top-level buffer collapsing to 0x0 showed up, and
    /// any partial collapse would not have.
    ///
    /// Hashing the bytes keeps the optimiser from eliding the render loop (the
    /// checksum's original job) *and* makes the printed number a correctness
    /// signal: identical output hashes identically, on every run and every
    /// platform. Deliberately not `String.hashValue`, which is seeded per
    /// process and so differs between two runs of the same work.
    private static func contentChecksum(_ buffer: FrameBuffer) -> Int {
        var hash = 5381
        for line in buffer.lines {
            for byte in line.utf8 { hash = (hash &* 33) ^ Int(byte) }
        }
        return hash
    }

    /// Whether a frame carries anything a reader would see. A frame of nothing
    /// but spaces and escape sequences is not a rendered scenario.
    private static func isBlank(_ buffer: FrameBuffer) -> Bool {
        !buffer.lines.contains { line in
            line.unicodeScalars.contains { $0 != " " && $0 != "\u{1b}" && !($0.value < 0x20) }
        }
    }

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
            let trimmedBefore = StackGuard.truncationCount
            let buffer = renderToBuffer(view, context: context)
            let trimmed = StackGuard.truncationCount - trimmedBefore
            // Dimensions alone are too weak a check: a frame of the right size
            // holding nothing passes it, which is exactly what a tripped stack
            // guard produces. Require visible content, and a whole tree.
            let ok = buffer.width > 0 && buffer.height > 0 && !isBlank(buffer) && trimmed == 0
            if !ok { failures += 1 }
            let id = scenario.id.padding(toLength: 12, withPad: " ", startingAt: 0)
            let why =
                trimmed > 0
                ? "  (stack guard stopped \(trimmed) descents)"
                : (isBlank(buffer) ? "  (blank)" : "")
            print("  \(ok ? "ok  " : "FAIL") \(id) \(buffer.width)x\(buffer.height)"
                + "  \(scenario.title)\(why)")
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
        var blankFrames = 0
        let trimmedBefore = StackGuard.truncationCount
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            if cold { warm = makeContext(cols: cols, rows: rows) }
            clock.tick &+= 1
            let buffer = renderToBuffer(view, context: warm)
            checksum = checksum &+ contentChecksum(buffer)
            if isBlank(buffer) { blankFrames += 1 }
        }
        let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let trimmed = StackGuard.truncationCount - trimmedBefore

        let totalMs = Double(ns) / 1_000_000
        let perFrameUs = Double(ns) / 1_000 / Double(max(1, iterations))
        print("bench scenario=\(id) scale=\(config.scale) size=\(cols)x\(rows) "
            + "iters=\(iterations) cold=\(cold)")
        print(String(format: "  total=%.1fms  per-frame=%.1fµs  (%.0f fps-equiv)  checksum=%d",
            totalMs, perFrameUs, 1_000_000 / max(0.001, perFrameUs), checksum))

        // A timing is only a measurement of the scenario if the scenario was
        // actually drawn. Reporting these as a failure rather than a note is
        // the point: this harness spent its Linux life timing an empty render
        // loop and exiting 0, so nothing downstream ever noticed.
        if blankFrames > 0 {
            print("  FAIL: \(blankFrames)/\(iterations) frames rendered nothing — "
                + "the timing above measures an empty loop, not \(id)")
        }
        if trimmed > 0 {
            // Worth failing loudly rather than noting: truncation makes the
            // render *faster*, so it reads as a good result. Measured here —
            // `deep` at scale 200 on a 512 KB stack came back in 4.9 ms/frame
            // against 2317 ms/frame for the same scenario on 8 MB.
            print("  FAIL: the stack guard stopped \(trimmed) descents — the tree was cut "
                + "short, so this is not a profile of \(id) at scale \(config.scale). "
                + "Raise the stack (ulimit -s) or lower --scale.")
        }
        return blankFrames > 0 || trimmed > 0 ? 1 : 0
    }
}
