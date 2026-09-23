//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  A performance stress harness for TUIkit, shaped like an app. Its PRIMARY
//  purpose is to be a reproducible instrument for profiling and optimisation:
//  large, deep, wide view hierarchies over pseudo-randomly synthesised data
//  (seeded, so nothing is stored on disk and runs are comparable). It can also
//  be run interactively to show off complex TUIs — but that is secondary.
//
//  Modes:
//    (no flags)     interactive — a menu of scenarios (needs a terminal)
//    --selfcheck    render every scenario once headlessly; non-zero exit on empty
//    --bench        timed render loop of one scenario (no PTY; for xctrace --launch)
//
//  Common options (env var | flag):
//    TUIKIT_STRESS_SCENARIO | --scenario <id>   pick a scenario
//    TUIKIT_STRESS_VARIANT  | --variant <id>     pick a variant of a matrix scenario
//    --variants                                  list every matrix scenario's variants
//    TUIKIT_STRESS_SCALE    | --scale <n>        size multiplier (1 is already heavy)
//    TUIKIT_STRESS_SEED     | --seed <n>         synthetic-data seed
//    TUIKIT_STRESS_AUTOPILOT| --autopilot        self-drive continuous re-renders
//    --bench options: --iterations <n> --cols <c> --rows <r> --cold
//
//  Sessions (interaction scripts played over time — see Sessions/Session.swift):
//    --sessions                                  list them
//    --session <id> [--steps N] [--verify] [--resize-every N] [--cols C] [--rows R]
//    --bench --scenario session/<id> ...         a session as a benchmark

import Dispatch
import Foundation
import TUIkit

// Register the harness's own localized strings with the shared
// LocalizationService before any UI renders, so `L(_:)` resolves them. Harmless
// in the headless `--bench` / `--selfcheck` modes (they never read the result).
registerStressLocalizations()

let rawArgs = Array(CommandLine.arguments.dropFirst())
let config = StressConfig.fromEnvironmentAndArgs(rawArgs)

/// Value following a `--flag`, if present.
func flagValue(_ name: String) -> String? {
    guard let i = rawArgs.firstIndex(of: name), i + 1 < rawArgs.count else { return nil }
    return rawArgs[i + 1]
}

// From the registry, not a literal: the literal listed twelve of twenty ids
// and said the interactive menu shows the rest, which shows titles only.
let scenarioIDs = await MainActor.run { Scenarios.all.map(\.id).joined(separator: ", ") }
let usageText = """
    Stress — a performance stress harness for TUIkit.

    Interactive:  Stress
    Self-check:   Stress --selfcheck [--scale N]
    Benchmark:    Stress --bench --scenario <id> [--variant V] [--iterations N] [--cols C] [--rows R] [--cold]
    Variants:     Stress --variants
    Sessions:     Stress --sessions
    Session:      Stress --session <id> [--steps N] [--verify] [--resize-every N] [--cols C] [--rows R]
                  (and Stress --bench --scenario session/<id>, which ab_bench.py can A/B)

    Scenario ids (the interactive menu shows titles, not ids):
    \(scenarioIDs)
    """

if rawArgs.contains("--help") || rawArgs.contains("-h") {
    print(usageText)
} else if rawArgs.contains("--variants") {
    // A matrix scenario is one id covering many shapes of one API; this is the
    // only listing of what those shapes are. Grouped by the axis each varies,
    // because reading them in axis order is how you notice the one that is
    // missing.
    await MainActor.run {
        for scenario in Scenarios.all {
            let variants = ScenarioVariants.variants(of: scenario.id)
            guard !variants.isEmpty else { continue }
            print("\(scenario.id) — \(scenario.title), \(variants.count) variants")
            var axis = ""
            // Padded to the WIDEST id, never to a constant: `padding(toLength:)`
            // truncates as readily as it pads, and this listing is machine-read
            // — `Tools/Profiling/sweep.py` takes the first word of each line as
            // the id to hand back with `--variant`. A constant 18 silently cut
            // `code-editor-tailing` to `code-editor-tailin`, which the sweep
            // then asked for and did not get.
            let column = variants.map(\.id.count).max() ?? 0
            for variant in variants {
                if variant.axis != axis {
                    axis = variant.axis
                    print("  [\(axis)]")
                }
                let pad = String(repeating: " ", count: max(0, column - variant.id.count))
                print("    \(variant.id)\(pad) \(variant.summary)")
            }
        }
    }
} else if rawArgs.contains("--sessions") {
    await MainActor.run {
        let column = Sessions.all.map(\.id.count).max() ?? 0
        for session in Sessions.all {
            let pad = String(repeating: " ", count: max(0, column - session.id.count))
            print("\(session.id)\(pad)  \(session.summary)")
            print("\(String(repeating: " ", count: column))  exercises: \(session.exercises)")
        }
    }
} else if let id = flagValue("--session") {
    var options = SessionRunner.Options()
    options.steps = flagValue("--steps").flatMap(Int.init) ?? options.steps
    options.width = flagValue("--cols").flatMap(Int.init) ?? options.width
    options.height = flagValue("--rows").flatMap(Int.init) ?? options.height
    options.verify = rawArgs.contains("--verify")
    options.resizeEvery = flagValue("--resize-every").flatMap(Int.init) ?? 0
    let code = await MainActor.run { () -> Int32 in
        guard let descriptor = Sessions.byID(id) else {
            print("session: unknown session '\(id)'. Known: \(Sessions.all.map(\.id).joined(separator: ", "))")
            return 1
        }
        let report = SessionRunner.run(descriptor, config: config, options: options)
        SessionRunner.print(report, id: id, options: options, config: config)
        return report.divergentSteps.isEmpty && report.scriptMismatch == nil ? 0 : 1
    }
    exit(code)
} else if rawArgs.contains("--selfcheck") {
    let failures = await MainActor.run { Headless.selfcheck(config) }
    exit(failures == 0 ? 0 : 1)
} else if rawArgs.contains("--bench") {
    let iterations = flagValue("--iterations").flatMap(Int.init) ?? 2_000
    let cols = flagValue("--cols").flatMap(Int.init) ?? 120
    let rows = flagValue("--rows").flatMap(Int.init) ?? 40
    let cold = rawArgs.contains("--cold")
    let code = await MainActor.run { () -> Int in
        let id = config.initialScenario ?? Scenarios.all.first?.id ?? "megalist"
        // A session where a scenario is expected — `session/<id>` — so the
        // tools built around `--bench --scenario` play sessions unchanged. One
        // step per iteration; `--cold` has no meaning for a session, whose
        // oracle is `--verify`.
        if id.hasPrefix(Sessions.scenarioPrefix) {
            let sessionID = String(id.dropFirst(Sessions.scenarioPrefix.count))
            guard let descriptor = Sessions.byID(sessionID) else {
                print("bench: unknown session '\(sessionID)'. Known: \(Sessions.all.map(\.id).joined(separator: ", "))")
                return 1
            }
            var options = SessionRunner.Options()
            options.steps = iterations
            options.width = cols
            options.height = rows
            let report = SessionRunner.run(descriptor, config: config, options: options)
            SessionRunner.print(report, id: sessionID, options: options, config: config)
            return 0
        }
        return Headless.bench(id, config: config, iterations: iterations, cols: cols, rows: rows, cold: cold)
    }
    exit(Int32(code))
} else {
    await StressApp.main()
}
