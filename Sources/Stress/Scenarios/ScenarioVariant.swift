//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenarioVariant.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Variants

/// One point in an API's space, inside a single ``Scenario``.
///
/// The catalogue's scenarios are hand-written, registered, and translated into
/// seven languages, which is right for a shape worth a name — `deep`, `menus`,
/// `gradients`. It is the wrong unit for asking "how does a `Table` behave
/// across every way an app can build one": there are dozens of those, they
/// differ by a line each, and none of them wants a title a translator will ever
/// read.
///
/// So a MATRIX scenario is one registered id whose `make` picks a variant by
/// name. One registry entry, one set of translations, and as many points in the
/// space as are worth measuring — listed with `--variants`, selected with
/// `--variant`, and all of them rendered by `--selfcheck`.
struct ScenarioVariant: Sendable {
    /// Stable id, used by `--variant` and printed by `--variants`.
    let id: String
    /// One line, in English. A development tool's own listing; not translated,
    /// for the same reason the `--bench` diagnostics are not.
    let summary: String
    /// Which axis of the API this point is varying, so the listing groups.
    let axis: String
    let make: @MainActor (StressConfig) -> AnyView
}

/// The matrix scenarios, by scenario id.
///
/// A registry rather than a property on ``Scenario`` so that `--variants` and
/// `--selfcheck` can enumerate the whole space without building any of it.
@MainActor
enum ScenarioVariants {
    static let byScenario: [String: [ScenarioVariant]] = [
        TableAPIMatrix.scenarioID: TableAPIMatrix.variants,
        AppShapeMatrix.scenarioID: AppShapeMatrix.variants,
    ]

    /// The variants of `scenario`, or an empty array for an ordinary scenario.
    static func variants(of scenario: String) -> [ScenarioVariant] {
        byScenario[scenario] ?? []
    }

    /// The variant a config selects, or the matrix's first as the default.
    static func resolve(_ config: StressConfig, in scenario: String) -> ScenarioVariant? {
        let variants = self.variants(of: scenario)
        guard !variants.isEmpty else { return nil }
        guard let wanted = config.variant else { return variants.first }
        return variants.first { $0.id == wanted } ?? variants.first
    }

    /// Every `scenario/variant` pair, for `--variants` and `--selfcheck`.
    static var all: [(scenario: String, variant: ScenarioVariant)] {
        byScenario.keys.sorted().flatMap { scenario in
            variants(of: scenario).map { (scenario, $0) }
        }
    }
}
