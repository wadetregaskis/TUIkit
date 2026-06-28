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
    /// Stable id used by `--scenario` / `TUIKIT_STRESS_SCENARIO`. Also the key
    /// stem for this scenario's localized strings (`stress.scenario.<id>.*`).
    let id: String
    /// Menu title, in English. The interactive shell shows ``localizedTitle``;
    /// this stays English for the `--selfcheck` stdout listing.
    let title: String
    /// One-line description, in English (see ``localizedBlurb``).
    let blurb: String
    /// Which part of the pipeline this is built to stress, in English
    /// (see ``localizedStresses``).
    let stresses: String
    /// Builds the scenario's view for the given configuration.
    let make: @MainActor (StressConfig) -> AnyView

    /// The menu title for the current language (falls back to ``title``).
    var localizedTitle: String { L("stress.scenario.\(id).title") }
    /// The one-line description for the current language (falls back to ``blurb``).
    var localizedBlurb: String { L("stress.scenario.\(id).blurb") }
    /// The "stresses" summary for the current language (falls back to ``stresses``).
    var localizedStresses: String { L("stress.scenario.\(id).stresses") }
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
