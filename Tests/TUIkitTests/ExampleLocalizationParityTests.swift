//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ExampleLocalizationParityTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Every language in the **Example app** carries the whole English key set.
///
/// `LocalizationKeyConsistencyTests` checks the *framework's* JSON tables. The
/// demo app's strings live somewhere else entirely — generated Swift
/// dictionaries under `Sources/Example/Localization/Generated/` — and nothing
/// checked them, because the Example is an executable target that no test can
/// import. The gap that hid there: one whole fragment (`Strings_g8`) shipped
/// English-only, so six languages silently fell back to English for 31 strings,
/// and three other fragments had drifted by another 13.
///
/// A missing key does not crash and does not fail a build — it renders in
/// English next to correctly-translated neighbours, which is exactly the kind of
/// defect that survives a review. Hence a test that reads the source.
@Suite("Example localization parity")
struct ExampleLocalizationParityTests {

    /// `[language: [key: value]]` parsed from the generated fragments.
    ///
    /// Parsing source text rather than importing it is the trade the target
    /// graph forces; the format is machine-generated and uniform, so it is a
    /// stable thing to parse. `filesRead` guards the vacuous pass: if the path
    /// resolution ever breaks, the suite fails instead of finding nothing and
    /// declaring victory.
    private static func loadTables() -> (tables: [String: [String: String]], filesRead: Int) {
        let root = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("Sources/Example/Localization/Generated")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return ([:], 0)
        }

        var tables: [String: [String: String]] = [:]
        var filesRead = 0
        for name in names.sorted() where name.hasSuffix(".swift") {
            let path = (root as NSString).appendingPathComponent(name)
            guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            filesRead += 1
            var language: String?
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let code = languageHeader(trimmed) {
                    language = code
                } else if let language, let (key, value) = entry(trimmed) {
                    tables[language, default: [:]][key] = value
                }
            }
        }
        return (tables, filesRead)
    }

    /// `"de": [` → `de`.
    private static func languageHeader(_ line: String) -> String? {
        guard line.hasSuffix("\": ["), line.hasPrefix("\"") else { return nil }
        let code = line.dropFirst().dropLast(4)
        guard code.count == 2, code.allSatisfy(\.isLowercase) else { return nil }
        return String(code)
    }

    /// `"some.key": "some value",` → `(some.key, some value)`.
    private static func entry(_ line: String) -> (String, String)? {
        guard line.hasPrefix("\""), let separator = line.range(of: "\": \"") else { return nil }
        let key = String(line[line.index(after: line.startIndex)..<separator.lowerBound])
        var value = String(line[separator.upperBound...])
        if value.hasSuffix(",") { value.removeLast() }
        if value.hasSuffix("\"") { value.removeLast() }
        return (key, value)
    }

    @Test("Every Example language has exactly the English key set")
    func everyLanguageMatchesEnglish() {
        let (tables, filesRead) = Self.loadTables()
        #expect(filesRead > 0, "no generated localization fragments were read")
        guard let english = tables["en"] else {
            Issue.record("no English table found in the generated fragments")
            return
        }
        #expect(english.count > 500, "the English table looks truncated")
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

    @Test("No Example translation was left as its English text")
    func translationsAreNotCopies() {
        // A key present but untranslated is the same defect wearing a disguise,
        // and copy-pasting the English block is the obvious way to "fix" a
        // parity failure. Proper nouns and API spellings legitimately match, so
        // this bounds the *proportion* rather than forbidding any single one.
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
