//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SessionRunner.swift
//
//  Plays a session and reports what each kind of step cost and whether any
//  frame came out wrong. "Wrong" has one definition here, and it needs no
//  expected pictures: a frame drawn through the render cache must be the
//  frame drawn with the cache emptied first. A second instance plays the same
//  script with its cache cleared before every frame, and the two screens are
//  compared step by step.
//
//  Created by Wade Tregaskis
//  License: MIT

import Dispatch
import TUIkit
import TUIkitCore

enum SessionRunner {
    /// How a session is played.
    struct Options {
        /// How many steps to play.
        var steps = 400
        /// The terminal's starting size.
        var width = 120
        var height = 40
        /// Whether to play a cache-cleared twin and compare every frame.
        var verify = false
        /// Resize the terminal every this many steps; `0` never does. The sizes
        /// cycle through three, narrower and shorter then wider and taller than
        /// the start, as a window dragged about does.
        var resizeEvery = 0
        /// Print the last frame, styling stripped — what a session is doing,
        /// for the person writing one.
        var show = false
        /// Print every step as it is played: its action and input, what its
        /// frame cost, and how many bytes it wrote.
        var trace = false
        /// Ask the session whether each frame shows what it should (see
        /// ``StressSession/check(_:after:)``). Outside the timed region, but
        /// off for `--bench`, which measures and nothing else.
        var checks = true
    }

    /// What one kind of step cost, over every step of that kind.
    struct ActionCost {
        var count = 0
        var cpuNanos: [UInt64] = []
        var bytes = 0

        var totalNanos: UInt64 { cpuNanos.reduce(0, &+) }

        /// The `fraction` quantile, in microseconds.
        func quantileMicros(_ fraction: Double) -> Double {
            guard !cpuNanos.isEmpty else { return 0 }
            let sorted = cpuNanos.sorted()
            let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))
            return Double(sorted[index]) / 1_000
        }
    }

    /// What a run found.
    struct Report {
        var costs: [String: ActionCost] = [:]
        var steps = 0
        var wallNanos: UInt64 = 0
        var cpuNanos: UInt64 = 0
        var bytes = 0
        /// Every step whose frame differed from the cache-cleared twin's.
        var divergentSteps: [Int] = []
        /// The first few of those, described.
        var divergences: [String] = []
        /// Whether `TUIKIT_VERIFY_RENDER_MEMO` was set, and what it found on the
        /// warm instance: served buffers that a fresh render disagreed with.
        var memoVerified = false
        var staleServes: [String] = []
        /// The steps whose frames served them.
        var staleServeSteps: [Int] = []
        /// Whether `TUIKIT_VERIFY_MEASURE_MEMO` was set, and what it found on
        /// the warm instance: served sizes that a fresh measure disagreed with.
        var sizesVerified = false
        var staleSizes: [String] = []
        /// The steps whose frames served them.
        var staleSizeSteps: [Int] = []
        /// Every step whose frame did not show what the session said it must.
        var brokenSteps: [Int] = []
        /// The first few of those, described.
        var brokenExpectations: [String] = []
        /// A step whose twin chose a different action: the SCRIPT is not
        /// deterministic, and nothing it found can be trusted.
        var scriptMismatch: String?
        /// What the warm instance's render cache did over the steps, the page's
        /// opening frame left out: the value memos' hits, misses and stores, and
        /// the memoized rows composed against those served. Deterministic — the
        /// same script at the same instants does the same work — so, unlike the
        /// timings, two builds' counts can be compared on any machine.
        var cacheStats = RenderCache.Stats()
        var rowWork = RenderCache.RowWork()

        /// Whether the run found nothing wrong: no divergence from the twin, no
        /// frame that failed the session's own check, and a deterministic script.
        var passed: Bool {
            divergentSteps.isEmpty && brokenSteps.isEmpty && staleServes.isEmpty && staleSizes.isEmpty
                && scriptMismatch == nil
        }
        /// The last frame, when asked for (``Options/show``).
        var lastScreen: [String] = []
    }

    /// The sizes a resizing run cycles through.
    private static func resizeSizes(_ options: Options) -> [(width: Int, height: Int)] {
        [
            (max(20, options.width - 24), max(8, options.height - 10)),
            (options.width + 16, options.height + 6),
            (options.width, options.height),
        ]
    }

    /// The instant of step `index`'s frame: a steady sixty a second, the same
    /// for both instances, so what the clock animates is drawn alike.
    private static func instant(_ index: Int) -> Int64 {
        Int64(index + 1) * 16_666_667
    }

    /// Plays `descriptor`'s session and reports.
    @MainActor
    static func run(
        _ descriptor: SessionDescriptor, config: StressConfig, options: Options
    ) -> Report {
        let warm = descriptor.make(config, options.width, options.height, false)
        let cold = options.verify ? descriptor.make(config, options.width, options.height, true) : nil
        var report = Report()
        let sizes = resizeSizes(options)

        // The page as it opens, drawn before the clock starts, as an app's
        // first frame is drawn before anyone touches it.
        warm.frame(0)
        cold?.frame(0)
        if options.checks { checkFrame(of: warm, after: -1, action: "open", into: &report) }

        let countsAtOpen = warm.cacheCounts()
        var staleSoFar = warm.staleServes().count
        var staleSizesSoFar = warm.staleSizes().count
        for index in 0..<options.steps {
            var step = warm.step(index)
            if options.resizeEvery > 0, index > 0, index.isMultiple(of: options.resizeEvery) {
                step.resize = sizes[(index / options.resizeEvery) % sizes.count]
                step.action = "resize"
            }
            let bytesBefore = warm.bytesWritten()
            let cpuStart = threadCPUNanoseconds()
            let wallStart = DispatchTime.now().uptimeNanoseconds
            play(step, on: warm, at: index)
            let wall = DispatchTime.now().uptimeNanoseconds &- wallStart
            let cpu = threadCPUNanoseconds().flatMap { end in cpuStart.map { end &- $0 } } ?? wall
            let bytes = warm.bytesWritten() &- bytesBefore
            if options.trace {
                let keys = step.keys.map { "\($0.key)" }.joined(separator: " ")
                let micros = String(format: "%.1f", Double(cpu) / 1_000)
                Swift.print(
                    "  step \(index): \(step.action)\(keys.isEmpty ? "" : " [\(keys)]") — \(micros) µs, \(bytes) bytes")
            }

            report.steps += 1
            report.wallNanos &+= wall
            report.cpuNanos &+= cpu
            report.bytes &+= bytes
            report.costs[step.action, default: ActionCost()].count += 1
            report.costs[step.action, default: ActionCost()].cpuNanos.append(cpu)
            report.costs[step.action, default: ActionCost()].bytes += bytes
            if options.checks { checkFrame(of: warm, after: index, action: step.action, into: &report) }
            if RenderCache.verifiesRenderMemo, warm.staleServes().count > staleSoFar {
                report.staleServeSteps.append(index)
                staleSoFar = warm.staleServes().count
            }
            if RenderCache.verifiesMeasureMemo, warm.staleSizes().count > staleSizesSoFar {
                report.staleSizeSteps.append(index)
                staleSizesSoFar = warm.staleSizes().count
            }

            guard let cold else { continue }
            var twin = cold.step(index)
            if options.resizeEvery > 0, index > 0, index.isMultiple(of: options.resizeEvery) {
                twin.resize = step.resize
                twin.action = "resize"
            }
            if twin.action != step.action, report.scriptMismatch == nil {
                report.scriptMismatch =
                    "step \(index): the twin chose \(twin.action) where the session chose \(step.action)"
            }
            play(twin, on: cold, at: index)
            let (seen, expected) = (warm.screen(), cold.screen())
            if seen != expected {
                report.divergentSteps.append(index)
                if report.divergences.count < 5 {
                    report.divergences.append(describe(index, step.action, seen: seen, expected: expected))
                }
            }
        }
        if options.show { report.lastScreen = warm.screen().map(\.stripped) }
        let counts = warm.cacheCounts()
        report.cacheStats = counts.stats.delta(since: countsAtOpen.stats)
        report.rowWork = counts.rows.delta(since: countsAtOpen.rows)
        report.memoVerified = RenderCache.verifiesRenderMemo
        report.staleServes = warm.staleServes()
        report.sizesVerified = RenderCache.verifiesMeasureMemo
        report.staleSizes = warm.staleSizes()
        return report
    }

    /// Asks `session` whether the frame drawn after step `index` shows what it
    /// should, and files what it says if not.
    @MainActor
    private static func checkFrame(
        of session: DrivenSession, after index: Int, action: String, into report: inout Report
    ) {
        guard let problem = session.check(session.screen().map(\.stripped), index) else { return }
        report.brokenSteps.append(index)
        if report.brokenExpectations.count < 5 {
            report.brokenExpectations.append("step \(index) (\(action)): \(problem)")
        }
    }

    /// Delivers one step's input to `session` and draws its frame.
    @MainActor
    private static func play(_ step: SessionStep, on session: DrivenSession, at index: Int) {
        for key in step.keys { session.send(key) }
        for event in step.mouse { session.sendMouse(event) }
        if let size = step.resize { session.resize(size.width, size.height) }
        session.frame(instant(index))
    }

    /// Where two screens first differ, stripped of styling, with the lines
    /// either side: enough to see what went wrong without a terminal.
    private static func describe(
        _ index: Int, _ action: String, seen: [String], expected: [String]
    ) -> String {
        guard seen.count == expected.count else {
            return "step \(index) (\(action)): \(seen.count) lines drawn, \(expected.count) expected"
        }
        let line = seen.indices.first { seen[$0] != expected[$0] } ?? 0
        let drawn = seen[line].stripped
        let wanted = expected[line].stripped
        let differs = drawn == wanted ? "  (the same text, styled differently)" : ""
        return """
            step \(index) (\(action)): line \(line) differs\(differs)
                drawn:    \(drawn)
                expected: \(wanted)
            """
    }

    /// One verifier's verdict, when it was armed: a line saying it found
    /// nothing, or what it found and the steps whose frames served it.
    private static func printVerdict(
        armed: Bool, findings: [String], steps: [Int], clean: String, failure: String
    ) {
        guard armed else { return }
        guard !findings.isEmpty else {
            Swift.print("  " + clean)
            return
        }
        Swift.print(
            "  FAIL: \(findings.count) \(failure), "
                + "on steps \(steps.prefix(8).map(String.init).joined(separator: ", "))")
        for finding in findings.prefix(5) { Swift.print("    " + finding) }
    }

    /// Prints `report` in the shape `--bench` prints a scenario's, so
    /// `ab_bench.py` reads a session as it reads a scenario: `per-frame=` is
    /// the wall clock per step and `cpu-per-frame=` the thread's CPU per step,
    /// each covering the step's input and its frame.
    static func print(_ report: Report, id: String, options: Options, config: StressConfig) {
        let steps = Double(max(1, report.steps))
        Swift.print(
            "bench session=\(id) scale=\(config.scale) size=\(options.width)x\(options.height) "
                + "steps=\(report.steps) resize-every=\(options.resizeEvery) verify=\(options.verify)")
        Swift.print(
            String(
                format: "  per-frame=%.1fµs  cpu-per-frame=%.1fµs  bytes/frame=%.0f",
                Double(report.wallNanos) / 1_000 / steps, Double(report.cpuNanos) / 1_000 / steps,
                Double(report.bytes) / steps))
        if let peak = ProcessMemory.peakResidentBytes() {
            Swift.print(String(format: "  rss-peak=%.1fMB", Double(peak) / 1_048_576))
        }
        Swift.print("  action          steps     mean µs      p50      p95      max   bytes/step")
        for (action, cost) in report.costs.sorted(by: { $0.value.totalNanos > $1.value.totalNanos }) {
            let mean = Double(cost.totalNanos) / 1_000 / Double(max(1, cost.count))
            Swift.print(
                String(
                    format: "  %@ %6d  %10.1f %8.1f %8.1f %8.1f %12.0f",
                    action.padding(toLength: max(14, action.count), withPad: " ", startingAt: 0),
                    cost.count, mean, cost.quantileMicros(0.5), cost.quantileMicros(0.95),
                    cost.quantileMicros(1), Double(cost.bytes) / Double(max(1, cost.count))))
        }
        let rows = report.rowWork
        let stats = report.cacheStats
        Swift.print(
            String(
                format: "  memoized rows: %d composed, %d served (%.1f/step, %.1f/step); "
                    + "value memos: %d hits, %d misses, %d stores",
                rows.rendered, rows.served, Double(rows.rendered) / steps, Double(rows.served) / steps,
                stats.hits, stats.misses, stats.stores))
        if !report.lastScreen.isEmpty {
            Swift.print("  last frame:")
            for line in report.lastScreen { Swift.print("  | " + line) }
        }
        if let mismatch = report.scriptMismatch {
            Swift.print("  FAIL: the script is not deterministic — \(mismatch)")
        }
        printVerdict(
            armed: report.memoVerified, findings: report.staleServes, steps: report.staleServeSteps,
            clean: "memo-verified: every served buffer matched a fresh render of it",
            failure: "served buffers differed from a fresh render")
        printVerdict(
            armed: report.sizesVerified, findings: report.staleSizes, steps: report.staleSizeSteps,
            clean: "sizes-verified: every served size matched a fresh measure",
            failure: "served sizes differed from a fresh measure")
        if options.checks {
            if report.brokenSteps.isEmpty {
                Swift.print("  checked: every frame showed what the session expected")
            } else {
                Swift.print(
                    "  FAIL: \(report.brokenSteps.count) frames did not show what the session expected "
                        + "(first after step \(report.brokenSteps[0]))")
                for problem in report.brokenExpectations { Swift.print("    " + problem) }
            }
        }
        if options.verify {
            if report.divergentSteps.isEmpty {
                Swift.print("  verified: every frame matched a frame drawn with the render cache emptied")
            } else {
                Swift.print(
                    "  FAIL: \(report.divergentSteps.count) of \(report.steps) frames differed from the "
                        + "cache-cleared twin's (first at step \(report.divergentSteps[0]))")
                for divergence in report.divergences { Swift.print("    " + divergence) }
            }
        }
    }
}
