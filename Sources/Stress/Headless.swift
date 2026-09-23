//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Headless.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch
import TUIkit
import TUIkitCore

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
        !buffer.lines.contains { hasVisibleContent($0) }
    }

    /// Whether one line paints something visible, ignoring ANSI sequences.
    ///
    /// Skipping only the `ESC` byte is not enough, and getting this wrong
    /// defeats the check entirely: the *parameter* bytes of `ESC[48;5;236m`
    /// are ordinary printable characters, so a frame consisting of nothing but
    /// background fill would count as content and a blank render would sail
    /// through. The whole sequence has to be consumed — CSI parameters run
    /// until a final byte in 0x40...0x7E.
    private static func hasVisibleContent(_ line: String) -> Bool {
        var scalars = line.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1b}" else {
                // Above 0x20 is printable and not a space; 0x20 and below are
                // spaces, control characters, or the sequence remnants.
                if scalar.value > 0x20 { return true }
                continue
            }
            guard let introducer = scalars.next() else { break }
            // Only CSI (`ESC[`) carries parameter bytes that could be mistaken
            // for content; the two-byte escapes end at the introducer.
            if introducer == "[" {
                while let byte = scalars.next(), !(0x40...0x7E).contains(byte.value) {}
            }
        }
        return false
    }

    /// Builds a render environment. Each call is independent (fresh state +
    /// cache) so `--bench --cold` can reset between frames to measure the cold
    /// measure+render cost rather than the cache-warm steady state.
    @MainActor
    private static func makeContext(
        cols: Int, rows: Int, channels: HeadlessInputChannels
    ) -> RenderContext {
        var environment = EnvironmentValues()
        // The per-walk input registries the app wires: a key dispatcher, a
        // shortcut registry, a status bar and a mouse dispatcher. Without them a
        // bench measures a tree with its input half removed — a `Button`'s
        // `.keyboardShortcut` registered nothing and declared nothing, an
        // `onKeyPress` trapped on its missing dispatcher, and every control that
        // answers the pointer skipped the hit-test handler, the feature request
        // and the region it emits in an app. Shared across `--cold` contexts,
        // because the frame loop empties them before every walk as `RenderLoop`
        // does.
        channels.install(into: &environment)
        environment.stateStorage = StateStorage()
        environment.renderCache = RenderCache()
        // Route through a real `TUIContext` so EVERY service the render pass
        // may reach is wired, not just the two the scenarios happened to need.
        // `.preference` force-unwraps its storage, so the `preferences`
        // scenario trapped on a context that had none — and nothing had
        // published a preference here before, which is how it stayed missing.
        // `.preference` force-unwraps its storage, so the `preferences`
        // scenario trapped without this. Nothing here had published a
        // preference before, which is how it stayed missing.
        environment.preferenceStorage = PreferenceStorage()
        // Through the installer, so the measure memo's gate — which reads the
        // tracker off the render cache, not out of the environment — is open
        // here as it is in the app. Getting this wrong is §27's disaster
        // verbatim: with the memo unreachable the bench measured a flat ~10%
        // regression of nothing at all. `beginRenderPass()` in the frame loop
        // does not clear the mirror, so installing once per context is enough,
        // warm and `--cold` alike.
        environment.installVolatileReadTracker(VolatileReadTracker())
        // Rooted at a TYPE, as `RenderLoop` roots the app, not at the
        // context's default raw path string. Every identity below a raw root
        // is raw-rooted, and for those `ViewIdentity.isAncestor(of:)` has to
        // render both full path strings and compare prefixes — so the end-of-
        // pass prune, which asks that of every retained root against every
        // unvisited entry, was 88–95% of a frame here and nothing in the app.
        return RenderContext(
            availableWidth: cols, availableHeight: rows, environment: environment,
            identity: ViewIdentity(rootType: BenchRoot.self))
    }

    /// The type the bench's identity tree is rooted at — a stand-in for the
    /// `App` type `RenderLoop` roots a real tree at.
    private enum BenchRoot {}

    /// One thing `--selfcheck` renders: a scenario, or one variant of a matrix
    /// scenario.
    ///
    /// A matrix scenario contributes one case per variant rather than one case,
    /// because the variant a config happens to select is not what wants
    /// checking — the whole space is. Thirty-odd `Table` shapes cost a second of
    /// wall clock here and are the only thing that renders every one of them.
    struct SelfcheckCase {
        let id: String
        let title: String
        let make: @MainActor () -> AnyView
    }

    /// Every scenario, with matrix scenarios expanded into their variants.
    @MainActor
    static func selfcheckCases(_ config: StressConfig) -> [SelfcheckCase] {
        Scenarios.all.flatMap { scenario -> [SelfcheckCase] in
            let variants = ScenarioVariants.variants(of: scenario.id)
            guard !variants.isEmpty else {
                return [SelfcheckCase(id: scenario.id, title: scenario.title,
                    make: { scenario.make(config) })]
            }
            return variants.map { variant in
                var scoped = config
                scoped.variant = variant.id
                return SelfcheckCase(
                    id: "\(scenario.id)/\(variant.id)",
                    title: variant.summary,
                    make: { scenario.make(scoped) })
            }
        }
    }

    /// Renders every scenario (and every variant) once at a fixed size; prints
    /// dimensions. Returns the number that produced an empty buffer (a failure).
    @MainActor
    static func selfcheck(_ config: StressConfig) -> Int {
        let clock = StressClock()
        var failures = 0
        let cases = selfcheckCases(config)
        print("selfcheck — scale \(config.scale) seed \(config.seed) @ 120x40")
        for scenario in cases {
            let channels = HeadlessInputChannels()
            let context = makeContext(cols: 120, rows: 40, channels: channels)
            let view = AnyView(scenario.make().environment(clock))
            let trimmedBefore = StackGuard.truncationCount
            // TWICE, with the pass lifecycle between, because a memo only
            // SERVES on a second render — so a one-render check never exercised
            // the buffer memo at all, and `TUIKIT_VERIFY_RENDER_MEMO` had
            // nothing to verify. The second render is what the verifier reads.
            channels.beginWalk()
            context.environment.stateStorage?.beginRenderPass()
            context.environment.renderCache?.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            context.environment.stateStorage?.endRenderPass()
            context.environment.renderCache?.removeInactive()
            channels.beginWalk()
            context.environment.stateStorage?.beginRenderPass()
            context.environment.renderCache?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            context.environment.stateStorage?.endRenderPass()
            let staleServes = context.environment.renderCache?.renderMemoMismatches ?? []
            let trimmed = StackGuard.truncationCount - trimmedBefore
            // Dimensions alone are too weak a check: a frame of the right size
            // holding nothing passes it, which is exactly what a tripped stack
            // guard produces. Require visible content, and a whole tree.
            let ok =
                buffer.width > 0 && buffer.height > 0 && !isBlank(buffer) && trimmed == 0
                && staleServes.isEmpty
            if !ok { failures += 1 }
            // Padded, never TRUNCATED: `padding(toLength:)` cuts a longer
            // string, which silently turned `size-wrapped-1000` into
            // `size-wrapped-100` — the id of a case that does not exist, beside
            // the one that does.
            let id = scenario.id.count >= 26
                ? scenario.id
                : scenario.id.padding(toLength: 26, withPad: " ", startingAt: 0)
            let why =
                trimmed > 0
                ? "  (stack guard stopped \(trimmed) descents)"
                : (isBlank(buffer)
                    ? "  (blank)"
                    : (staleServes.isEmpty
                        ? "" : "  (STALE MEMO: \(staleServes.count))"))
            print("  \(ok ? "ok  " : "FAIL") \(id) \(buffer.width)x\(buffer.height)"
                + "  \(scenario.title)\(why)")
            for line in staleServes.prefix(3) { print("      \(line)") }
        }
        // Every session, played a short way with its cache-cleared twin and
        // the terminal resized under it: the one check here that a UI IN USE
        // draws what it should, frame after frame, and not only at rest.
        var sessionOptions = SessionRunner.Options()
        sessionOptions.steps = 150
        sessionOptions.verify = true
        sessionOptions.resizeEvery = 37
        for session in Sessions.all {
            let report = SessionRunner.run(session, config: config, options: sessionOptions)
            let ok = report.divergentSteps.isEmpty && report.scriptMismatch == nil
            if !ok { failures += 1 }
            let id = "session/\(session.id)".padding(toLength: 26, withPad: " ", startingAt: 0)
            print("  \(ok ? "ok  " : "FAIL") \(id) \(report.steps) steps  \(session.summary)")
            if let mismatch = report.scriptMismatch { print("      \(mismatch)") }
            for divergence in report.divergences.prefix(3) { print("      " + divergence) }
        }
        print(
            failures == 0
                ? "selfcheck: all \(cases.count) cases rendered (\(Scenarios.all.count) scenarios), "
                    + "and every session verified (\(Sessions.all.count))"
                : "selfcheck: \(failures) FAILED")
        return failures
    }

    /// Prints the memos' totals and what the last walk left registered.
    ///
    /// The value-memo line is `RenderCache.stats`, which counts the buffer half
    /// AND the size half of `.equatable()` and the `ForEach` row memo together,
    /// so a scenario whose rows never store a buffer can still show stores and
    /// hits there. `TUIKIT_DEBUG_RENDER=1` logs the buffer half alone. The totals
    /// include the warm-up (under `--cold`, they are the last frame's context
    /// only). Beside the key-handler count they say whether a scenario's
    /// registrations keep its rows out of the cache, which nothing else printed
    /// here can.
    @MainActor
    private static func printMemoTotals(
        _ cache: RenderCache?, channels: HeadlessInputChannels, frames: Int = 1
    ) {
        let memo = cache?.measureMemoTotals ?? (hits: 0, misses: 0)
        let lookups = memo.hits + memo.misses
        print(String(format: "  measure memo: %d hits / %d lookups (%.1f%%)",
            memo.hits, lookups, lookups > 0 ? Double(memo.hits) / Double(lookups) * 100 : 0))
        let render = cache?.stats ?? RenderCache.Stats()
        print("  value memos (buffer + size): \(render.hits) hits / \(render.lookups) lookups, "
            + "\(render.stores) stores; handlers (last frame): \(channels.keyHandlerCount) key, "
            + "\(channels.mouseHandlerCount) mouse")
        // What the ROWS cost, which the line above cannot say: it sums the
        // buffer memo, the size memo and the row memo together, so a control
        // that composes every row from scratch and one that serves them all
        // look the same in it. Per frame, because the totals are cumulative
        // over the run and a per-frame number is the one worth comparing.
        let work = cache?.rowWork ?? RenderCache.RowWork()
        let divisor = Double(max(1, frames))
        print(
            String(
                format: "  rows/frame: %.1f composed, %.1f served (%.0f%%); "
                    + "cell values/frame: %.1f; clears: %d whole, %d subtree",
                Double(work.rendered) / divisor, Double(work.served) / divisor,
                work.rendered + work.served > 0
                    ? Double(work.served) / Double(work.rendered + work.served) * 100 : 0,
                Double(work.cellValues) / divisor, render.clears, render.subtreeClears))
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
        let channels = HeadlessInputChannels()
        var warm = makeContext(cols: cols, rows: rows, channels: channels)
        _ = renderToBuffer(view, context: warm)

        var checksum = 0
        var blankFrames = 0
        let trimmedBefore = StackGuard.truncationCount
        // Accumulate only the render itself. Checking the frame is this
        // harness's own bookkeeping, and it is not cheap next to a cheap
        // scenario: measured at 6.0% of `dashboard`'s per-frame time against
        // 0.2% of `deep`'s. Timing it would tax the fast scenarios hardest and
        // show up as a regression that never happened.
        //
        // Timed twice, over the same region: the wall clock (what this always
        // reported) and the thread's CPU clock. Only the second is comparable
        // across runs on a machine that is doing anything else — see
        // ``threadCPUNanoseconds()``. The CPU reads bracket the wall reads so
        // the wall number still measures exactly the render.
        var ns: UInt64 = 0
        var cpuNs: UInt64 = 0
        var cpuMeasured = false
        // Resident size, sampled rather than integrated. Every 64th frame is
        // often enough to characterise a run that is thousands of frames long
        // and rare enough that the syscall does not land in the per-frame
        // number — and it is deliberately OUTSIDE the timed region, so the
        // CPU and wall figures still measure exactly the render.
        var memory = ProcessMemory.Samples()
        for iteration in 0..<iterations {
            if iteration.isMultiple(of: 64) { memory.sample() }
            if cold { warm = makeContext(cols: cols, rows: rows, channels: channels) }
            clock.tick &+= 1
            let cpuStart = threadCPUNanoseconds()
            let frameStart = DispatchTime.now()
            // The live loop's per-pass lifecycle, timed as part of the frame
            // because it IS part of the frame: `RenderLoop` opens every pass
            // with these and closes it by pruning whatever the pass did not
            // mark alive. Without them this bench rendered into a cache that
            // was never pruned and a measure memo that was never emptied — so
            // an off-screen row's size was a hit here and a miss in the app,
            // and the per-pass measure memo grew by every miss forever (2,400
            // entries a frame on `kitchensink`; millions over a profile),
            // which put dictionary resizes in profiles of code that has none.
            // The key channels are emptied first, as `RenderLoop` empties them
            // before each walk, so every frame re-registers into empty ones.
            channels.beginWalk()
            warm.stateStorage?.beginRenderPass()
            warm.renderCache?.beginRenderPass()
            let buffer = renderToBuffer(view, context: warm)
            warm.stateStorage?.endRenderPass()
            warm.renderCache?.removeInactive()
            ns &+= DispatchTime.now().uptimeNanoseconds - frameStart.uptimeNanoseconds
            if let cpuStart, let cpuEnd = threadCPUNanoseconds() {
                cpuNs &+= cpuEnd &- cpuStart
                cpuMeasured = true
            }
            checksum = checksum &+ contentChecksum(buffer)
            if isBlank(buffer) { blankFrames += 1 }
        }
        let trimmed = StackGuard.truncationCount - trimmedBefore

        let totalMs = Double(ns) / 1_000_000
        let perFrameUs = Double(ns) / 1_000 / Double(max(1, iterations))
        print("bench scenario=\(id) scale=\(config.scale) size=\(cols)x\(rows) "
            + "iters=\(iterations) cold=\(cold)")
        print(String(format: "  total=%.1fms  per-frame=%.1fµs  (%.0f fps-equiv)  checksum=%d",
            totalMs, perFrameUs, 1_000_000 / max(0.001, perFrameUs), checksum))
        if cpuMeasured {
            let cpuPerFrameUs = Double(cpuNs) / 1_000 / Double(max(1, iterations))
            print(String(format: "  cpu-per-frame=%.1fµs  (%.1f%% of wall)",
                cpuPerFrameUs, perFrameUs > 0 ? cpuPerFrameUs / perFrameUs * 100 : 0))
        }
        memory.sample()
        // Peak is what has to FIT; mean is what the process typically holds.
        // A cache that buys CPU by keeping buffers shows up here and nowhere
        // else, which is why this is printed beside `cpu-per-frame` rather
        // than in a separate tool. `rss-peak` is the process high-water mark
        // (`ru_maxrss`), so it includes the build-up before the loop; the
        // sampled pair describe the loop itself.
        if let peak = ProcessMemory.peakResidentBytes() {
            let mb = { (bytes: UInt64) in Double(bytes) / 1_048_576 }
            if let mean = memory.meanBytes {
                print(String(format: "  rss-peak=%.1fMB  rss-mean=%.1fMB  rss-sampled-peak=%.1fMB",
                    mb(peak), mb(mean), mb(memory.peakSampled)))
                // The footprint is the number a freed buffer actually moves —
                // see `ProcessMemory.currentFootprintBytes()`. Printed beside
                // the resident figures rather than instead of them, because
                // they answer different questions and only one of them exists
                // on Linux.
                if let meanFootprint = memory.meanFootprintBytes {
                    print(String(format: "  footprint-mean=%.1fMB  footprint-peak=%.1fMB",
                        mb(meanFootprint), mb(memory.peakFootprint)))
                }
            } else {
                print(String(format: "  rss-peak=%.1fMB", mb(peak)))
            }
        }
        printMemoTotals(warm.renderCache, channels: channels, frames: iterations)
        // `TUIKIT_VERIFY_MEASURE_MEMO=1` re-measures every memo hit and reports
        // any the fresh measurement disagrees with — the direct check on the
        // memo's cross-budget claim, run over whichever scenario is at hand.
        let mismatches = warm.renderCache?.measureMemoMismatches ?? []
        if !mismatches.isEmpty {
            print("  MEASURE MEMO MISMATCHES (\(mismatches.count)):")
            for line in mismatches { print("    \(line)") }
        }
        if let prune = warm.renderCache?.lastPruneSummary {
            print("  prune (last frame): \(prune)")
        }

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
