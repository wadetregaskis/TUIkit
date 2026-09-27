//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// Builds a DRIVEN scenario — a view over a model the harness writes
    /// between frames — or `nil` for a scenario that is only a view. See
    /// ``DrivenScenario``.
    var drive: (@MainActor (StressConfig) -> DrivenScenario?)?

    /// The menu title for the current language.
    ///
    /// There is no fallback to ``title``: a table without the key shows the KEY
    /// (`L` returns what it was given), which is what the source-parity test
    /// over the string tables exists to catch. The English fields on this
    /// struct are the source text the tables are written from.
    var localizedTitle: String { L("stress.scenario.\(id).title") }
    /// The one-line description for the current language; see ``localizedTitle``.
    var localizedBlurb: String { L("stress.scenario.\(id).blurb") }
    /// The "stresses" summary for the current language; see ``localizedTitle``.
    var localizedStresses: String { L("stress.scenario.\(id).stresses") }
}

// MARK: - Driven scenarios

/// A scenario's view and what moves its model between frames.
///
/// A scenario at rest reads the shared `StressClock` and derives what it
/// shows from the tick, which is a pure function of the frame. A model an app
/// reads is not: it is WRITTEN, outside any render, and what a write
/// invalidates is part of what a frame costs. So a driven scenario hands the
/// harness the write to make before each frame, with the frame's tick.
/// `--bench` and `--selfcheck` make it; the interactive shell shows the view
/// at rest.
struct DrivenScenario {
    let view: AnyView
    let advance: @MainActor (_ tick: Int) -> Void
}

// MARK: - Registry

/// The full scenario catalogue, in a deliberate order (cheap → pathological).
enum Scenarios {
    @MainActor
    static let all: [Scenario] = [
        MegaListScenario.descriptor,
        ScrollFollowScenario.descriptor,
        ScrollEagerScenario.descriptor,
        WideTableScenario.descriptor,
        MultiLineTableScenario.descriptor,
        TruncatingTableScenario.descriptor,
        ChurningTableScenario.descriptor,
        ChurningWrappedTableScenario.descriptor,
        TailingTableScenario.descriptor,
        TableAPIMatrix.descriptor,
        AppShapeMatrix.descriptor,
        TablesInScrollViewScenario.descriptor,
        TablesInVStackScenario.descriptor,
        DeepRecursionScenario.descriptor,
        WideFanoutScenario.descriptor,
        ModifierChainsScenario.descriptor,
        PreferenceRowsScenario.descriptor,
        CustomLayoutScenario.descriptor,
        TextWallScenario.descriptor,
        AnyViewStormScenario.descriptor,
        DashboardScenario.descriptor,
        FramedColumnsScenario.descriptor,
        ChurnUpdateScenario.descriptor,
        AnimatingScenario.descriptor,
        TranslucentScenario.descriptor,
        GradientsScenario.descriptor,
        AlphaRampsScenario.descriptor,
        MenuBarScenario.descriptor,
        KeyRowsScenario.descriptor,
        KitchenSinkScenario.descriptor,
    ]

    @MainActor
    static func byID(_ id: String) -> Scenario? {
        all.first { $0.id == id }
    }
}
