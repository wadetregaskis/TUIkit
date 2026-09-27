//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenarioVariant.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
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
    /// A driven variant's view and the write it wants made before each frame
    /// (see ``DrivenScenario``); `nil` for a variant that is only a view.
    var drive: (@MainActor (StressConfig) -> DrivenScenario)?
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
    ///
    /// A NAMED variant that does not exist exits rather than falling back. The
    /// fallback was silent, and silence is the whole problem: a sweep that asked
    /// for `code-editor-tailing` and was handed `file-browser` printed the file
    /// browser's microseconds under the editor's name, in a tool whose entire job
    /// is to be read down a column for the row that does not belong.
    static func resolve(_ config: StressConfig, in scenario: String) -> ScenarioVariant? {
        let variants = self.variants(of: scenario)
        guard !variants.isEmpty else { return nil }
        guard let wanted = config.variant else { return variants.first }
        guard let found = variants.first(where: { $0.id == wanted }) else {
            let known = variants.map(\.id).joined(separator: ", ")
            FileHandle.standardError.write(
                Data("error: \(scenario) has no variant '\(wanted)'\n       known: \(known)\n".utf8))
            exit(2)
        }
        return found
    }

    /// Every `scenario/variant` pair, for `--variants` and `--selfcheck`.
    static var all: [(scenario: String, variant: ScenarioVariant)] {
        byScenario.keys.sorted().flatMap { scenario in
            variants(of: scenario).map { (scenario, $0) }
        }
    }
}
