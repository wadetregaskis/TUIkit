//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressConfig.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Run configuration

/// Everything a scenario needs to size and seed itself, parsed once at launch
/// from environment variables (so a profiler can pin a run) and/or CLI args
/// (which override the environment).
///
/// Environment:
/// - `TUIKIT_STRESS_SCENARIO` — id to boot directly into (skips the menu).
/// - `TUIKIT_STRESS_SCALE`    — integer multiplier on every scenario's size.
/// - `TUIKIT_STRESS_SEED`     — RNG seed for synthetic data.
/// - `TUIKIT_STRESS_AUTOPILOT`— `1`/`true` to self-drive continuous re-renders.
///
/// CLI (see `main.swift`): `--scenario`, `--scale`, `--seed`, `--autopilot`,
/// plus the headless modes `--selfcheck` and `--bench`.
struct StressConfig {
    /// Multiplier applied to each scenario's base size. `1` is already heavy;
    /// `10`/`100` push into pathological territory for profiling.
    var scale: Int = 1

    /// Seed for all synthetic data. Fixed by default for reproducibility.
    var seed: UInt64 = 0x5715_2025

    /// When set, the app bumps a tick every frame to keep the demand-driven
    /// render loop busy (so a static screen still produces a steady workload to
    /// profile under `drive.py`). Scenarios may also weave the tick into their
    /// content to force cache misses.
    var autopilot: Bool = false

    /// A monotonically increasing frame counter (driven by autopilot, or by
    /// real input). Scenarios read it to animate / churn.
    var tick: Int = 0

    /// Scenario id to start in, or `nil` for the menu.
    var initialScenario: String?

    /// Which VARIANT of a matrix scenario to build.
    ///
    /// A matrix scenario is one `Scenario` covering many shapes of one API —
    /// every way a `Table` can be given its data, sized, truncated, aligned,
    /// selected and updated — rather than one scenario per shape. One id keeps
    /// the registry and its seven translation tables the size they are; the
    /// variant picks the point in the space, and `--variants` lists them.
    ///
    /// `nil` builds the variant the matrix nominates as its default, so
    /// `--bench --scenario table-api` works without one.
    var variant: String?

    /// Scales a base count by `scale`, clamped to at least 1.
    func sized(_ base: Int) -> Int { max(1, base * scale) }

    // MARK: Parsing

    /// Builds a config from the environment, then applies CLI overrides.
    static func fromEnvironmentAndArgs(_ args: [String]) -> Self {
        var config = Self()
        config.applyEnvironment(ProcessInfo.processInfo.environment)
        config.applyArguments(args)
        return config
    }

    /// The environment half, split from the argument half only to keep each
    /// under the complexity limit — every option is readable in one of them.
    private mutating func applyEnvironment(_ env: [String: String]) {
        if let s = env["TUIKIT_STRESS_SCALE"], let value = Int(s) { scale = max(1, value) }
        if let s = env["TUIKIT_STRESS_SEED"], let value = UInt64(s) { seed = value }
        if let s = env["TUIKIT_STRESS_AUTOPILOT"] { autopilot = (s == "1" || s.lowercased() == "true") }
        if let s = env["TUIKIT_STRESS_SCENARIO"], !s.isEmpty { initialScenario = s }
        if let s = env["TUIKIT_STRESS_VARIANT"], !s.isEmpty { variant = s }
    }

    /// The CLI half, which overrides the environment.
    private mutating func applyArguments(_ args: [String]) {
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--scale": if let value = it.next().flatMap(Int.init) { scale = max(1, value) }
            case "--seed": if let value = it.next().flatMap(UInt64.init) { seed = value }
            case "--autopilot": autopilot = true
            case "--scenario": if let value = it.next() { initialScenario = value }
            case "--variant": if let value = it.next() { variant = value }
            default: break  // headless flags are handled in main.swift
            }
        }
    }
}
