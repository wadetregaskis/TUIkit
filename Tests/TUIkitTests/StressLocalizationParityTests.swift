//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressLocalizationParityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The Stress harness's tables, read from source like the Example's.
///
/// The catalogue is the extra check here: a scenario's menu row is built from
/// `stress.scenario.<id>.title/blurb/stresses`, and `L` returns the KEY when a
/// table lacks it — so a scenario added without its strings showed its key in
/// the menu, in every language, and nothing failed.
@Suite("Stress localization parity")
struct StressLocalizationParityTests {
    private static func loadTables() -> (tables: [String: [String: String]], filesRead: Int) {
        LocalizationSourceTables.load(under: ["Sources/Stress/Localization"])
    }

    /// `id: "megalist",` from each scenario's descriptor — the same ids the
    /// registry is built from.
    private static func scenarioIDs() -> [String] {
        let root = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("Sources/Stress/Scenarios")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        var ids: [String] = []
        for name in names.sorted() where name.hasSuffix(".swift") {
            let path = (root as NSString).appendingPathComponent(name)
            guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in source.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("id: \""), trimmed.hasSuffix("\",") else { continue }
                ids.append(String(trimmed.dropFirst(5).dropLast(2)))
            }
        }
        return ids
    }

    @Test("Every Stress language has exactly the English key set")
    func everyLanguageMatchesEnglish() {
        let (tables, filesRead) = Self.loadTables()
        #expect(filesRead > 0, "no Stress string tables were read")
        guard let english = tables["en"] else {
            Issue.record("no English table found")
            return
        }
        #expect(english.count > 50, "the English table looks truncated")
        #expect(tables.count == 7, "expected en + 6 translations")

        let englishKeys = Set(english.keys)
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) where language != "en" {
            let keys = Set(table.keys)
            let missing = englishKeys.subtracting(keys).sorted()
            let extra = keys.subtracting(englishKeys).sorted()
            #expect(missing.isEmpty, "\(language) is missing \(missing.count) keys: \(missing.prefix(5))")
            #expect(extra.isEmpty, "\(language) has \(extra.count) keys English does not: \(extra.prefix(5))")
        }
    }

    @Test("Every scenario has its title, blurb and stresses in every language")
    func everyScenarioIsDescribed() {
        let (tables, _) = Self.loadTables()
        let ids = Self.scenarioIDs()
        #expect(ids.count >= 20, "the catalogue looks truncated: \(ids)")
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) {
            for id in ids {
                for field in ["title", "blurb", "stresses"] {
                    let key = "stress.scenario.\(id).\(field)"
                    #expect(table[key] != nil, "\(language) lacks \(key)")
                }
            }
        }
    }

    @Test("No Stress translation was left as its English text")
    func translationsAreNotCopies() {
        let (tables, _) = Self.loadTables()
        guard let english = tables["en"] else { return }
        for (language, table) in tables.sorted(by: { $0.key < $1.key }) where language != "en" {
            let shared = Set(table.keys).intersection(english.keys)
            let identical = shared.count { table[$0] == english[$0] }
            let ratio = Double(identical) / Double(max(1, shared.count))
            #expect(ratio < 0.5, "\(language): \(identical)/\(shared.count) strings are byte-identical to English")
        }
    }
}
