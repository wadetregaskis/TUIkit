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
        /// Print every step's action and input as it is played.
        var trace = false
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
        /// A step whose twin chose a different action: the SCRIPT is not
        /// deterministic, and nothing it found can be trusted.
        var scriptMismatch: String?
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

        for index in 0..<options.steps {
            var step = warm.step(index)
            if options.resizeEvery > 0, index > 0, index.isMultiple(of: options.resizeEvery) {
                step.resize = sizes[(index / options.resizeEvery) % sizes.count]
                step.action = "resize"
            }
            if options.trace {
                let keys = step.keys.map { "\($0.key)" }.joined(separator: " ")
                Swift.print("  step \(index): \(step.action)\(keys.isEmpty ? "" : " [\(keys)]")")
            }
            let bytesBefore = warm.bytesWritten()
            let cpuStart = threadCPUNanoseconds()
            let wallStart = DispatchTime.now().uptimeNanoseconds
            play(step, on: warm, at: index)
            let wall = DispatchTime.now().uptimeNanoseconds &- wallStart
            let cpu = threadCPUNanoseconds().flatMap { end in cpuStart.map { end &- $0 } } ?? wall
            let bytes = warm.bytesWritten() &- bytesBefore

            report.steps += 1
            report.wallNanos &+= wall
            report.cpuNanos &+= cpu
            report.bytes &+= bytes
            report.costs[step.action, default: ActionCost()].count += 1
            report.costs[step.action, default: ActionCost()].cpuNanos.append(cpu)
            report.costs[step.action, default: ActionCost()].bytes += bytes

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
        return report
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
        if !report.lastScreen.isEmpty {
            Swift.print("  last frame:")
            for line in report.lastScreen { Swift.print("  | " + line) }
        }
        if let mismatch = report.scriptMismatch {
            Swift.print("  FAIL: the script is not deterministic — \(mismatch)")
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
