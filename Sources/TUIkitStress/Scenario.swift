//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scenario.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Scenario

/// One stress scenario: a heavy, scalable, deterministic view tree plus the
/// metadata the menu and the headless runners need.
///
/// `make` is type-erased to `AnyView` only at this registry boundary — each
/// scenario's *internal* tree keeps its concrete types (where the real
/// `measureChild`/`Layoutable` dispatch cost lives), so the single erasure at
/// the root is negligible against the thousands of concrete nodes beneath it.
/// (For AnyView-free micro-profiling of a specific shape, add a tree to
/// `Tools/Profiling/RenderHarness/Trees.swift` instead.)
struct Scenario {
    /// Stable id used by `--scenario` / `TUIKIT_STRESS_SCENARIO`.
    let id: String
    /// Menu title.
    let title: String
    /// One-line description.
    let blurb: String
    /// Which part of the pipeline this is built to stress.
    let stresses: String
    /// Builds the scenario's view for the given configuration.
    let make: @MainActor (StressConfig) -> AnyView
}

// MARK: - Registry

/// The full scenario catalogue, in a deliberate order (cheap → pathological).
enum Scenarios {
    @MainActor
    static let all: [Scenario] = [
        MegaListScenario.descriptor,
        WideTableScenario.descriptor,
        MultiLineTableScenario.descriptor,
        TablesInScrollViewScenario.descriptor,
        TablesInVStackScenario.descriptor,
        DeepRecursionScenario.descriptor,
        WideFanoutScenario.descriptor,
        ModifierChainsScenario.descriptor,
        TextWallScenario.descriptor,
        AnyViewStormScenario.descriptor,
        DashboardScenario.descriptor,
        ChurnUpdateScenario.descriptor,
        KitchenSinkScenario.descriptor,
    ]

    @MainActor
    static func byID(_ id: String) -> Scenario? {
        all.first { $0.id == id }
    }
}
