//  🖥️ TUIKit — Terminal UI Kit for Swift
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
//    TUIKIT_STRESS_SCALE    | --scale <n>        size multiplier (1 is already heavy)
//    TUIKIT_STRESS_SEED     | --seed <n>         synthetic-data seed
//    TUIKIT_STRESS_AUTOPILOT| --autopilot        self-drive continuous re-renders
//    --bench options: --iterations <n> --cols <c> --rows <r> --cold

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

let usageText = """
    TUIkitStress — a performance stress harness for TUIkit.

    Interactive:  TUIkitStress
    Self-check:   TUIkitStress --selfcheck [--scale N]
    Benchmark:    TUIkitStress --bench --scenario <id> [--iterations N] [--cols C] [--rows R] [--cold]

    Scenarios are listed in the interactive menu; ids: megalist, table, deep,
    fanout, modifiers, textwall, anyview, dashboard, churn, kitchensink.
    """

if rawArgs.contains("--help") || rawArgs.contains("-h") {
    print(usageText)
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
        return Headless.bench(id, config: config, iterations: iterations, cols: cols, rows: rows, cold: cold)
    }
    exit(Int32(code))
} else {
    await StressApp.main()
}
