//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationSourceTables.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Reads `[String: [String: String]]` translation tables straight out of
/// Swift source, for the targets the test graph cannot import: the Example
/// and Stress executables.
///
/// Parsing source rather than importing it is the trade the target graph
/// forces; the formats are uniform (one entry per line, one of two header
/// shapes), so they are stable things to parse.
enum LocalizationSourceTables {
    /// The tables under `roots` (paths relative to the package root), merged
    /// by language code, plus how many files were read — the guard against a
    /// vacuous pass when a path stops resolving.
    static func load(under roots: [String]) -> (tables: [String: [String: String]], filesRead: Int) {
        let cwd = FileManager.default.currentDirectoryPath as NSString
        var tables: [String: [String: String]] = [:]
        var filesRead = 0
        for root in roots {
            let directory = cwd.appendingPathComponent(root)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for name in names.sorted() where name.hasSuffix(".swift") {
                let path = (directory as NSString).appendingPathComponent(name)
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
        }
        return (tables, filesRead)
    }

    /// `"de": [` (a nested table) or `static let de: [String: String] = [`
    /// (a per-language constant) → `de`.
    static func languageHeader(_ line: String) -> String? {
        let code: Substring
        if line.hasPrefix("\""), line.hasSuffix("\": [") {
            code = line.dropFirst().dropLast(4)
        } else if line.hasPrefix("static let "), line.hasSuffix(": [String: String] = [") {
            code = line.dropFirst("static let ".count).dropLast(": [String: String] = [".count)
        } else {
            return nil
        }
        guard code.count == 2, code.allSatisfy(\.isLowercase) else { return nil }
        return String(code)
    }

    /// `"some.key": "some value",` → `(some.key, some value)`.
    static func entry(_ line: String) -> (String, String)? {
        guard line.hasPrefix("\""), let separator = line.range(of: "\": \"") else { return nil }
        let key = String(line[line.index(after: line.startIndex)..<separator.lowerBound])
        var value = String(line[separator.upperBound...])
        if value.hasSuffix(",") { value.removeLast() }
        if value.hasSuffix("\"") { value.removeLast() }
        return (key, value)
    }
}
