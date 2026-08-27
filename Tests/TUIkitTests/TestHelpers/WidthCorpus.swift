//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WidthCorpus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

// MARK: - The shared width corpus

/// The tests' view of ``TerminalWidthCorpus`` — the Swift twin of
/// `Tools/TerminalProbes/data/width-corpus.json`, which the Python probes
/// measure on real terminals.
///
/// The two copies are pinned identical by ``WidthCorpusParityTests`` below, so
/// "the probes measured it" and "the tests assert on it" can never quietly be
/// about different lists.
enum WidthCorpus {

    typealias Entry = TerminalWidthCorpus.Entry

    static var clusters: [Entry] { TerminalWidthCorpus.all }

    static func clusters(in category: String) -> [Entry] {
        TerminalWidthCorpus.entries(in: category)
    }
}

// MARK: - Parity with the JSON the probes measure

/// The corpus exists twice — JSON for the Python probes, Swift for everything
/// else — and this is the pin that keeps "twice" from becoming "two".
@Suite("Width corpus parity")
struct WidthCorpusParityTests {

    private struct JSONEntry: Decodable {
        let id: String
        let `class`: String
        let text: String
        let scalars: [String]
    }

    private struct Document: Decodable {
        let clusters: [JSONEntry]
    }

    @Test("The Swift corpus and the probes' JSON are the same list")
    func swiftMatchesJSON() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestHelpers/
            .deletingLastPathComponent()  // TUIkitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data/width-corpus.json")
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))

        try #require(document.clusters.count == TerminalWidthCorpus.all.count)
        for (json, swift) in zip(document.clusters, TerminalWidthCorpus.all) {
            #expect(json.id == swift.id)
            #expect(json.class == swift.category)
            #expect(json.text == swift.text, "\(json.id): text differs")
            let spelled = json.scalars.map { scalar -> Unicode.Scalar in
                guard scalar.hasPrefix("U+"),
                    let value = UInt32(scalar.dropFirst(2), radix: 16),
                    let unicode = Unicode.Scalar(value)
                else { fatalError("\(json.id): malformed scalar \(scalar)") }
                return unicode
            }
            #expect(String(String.UnicodeScalarView(spelled)) == swift.text,
                    "\(json.id): scalars and text disagree")
        }
    }

    @Test("Every category carries a note for the Quirks app")
    func everyCategoryHasANote() {
        for category in Set(TerminalWidthCorpus.all.map(\.category)) {
            #expect(TerminalWidthCorpus.categoryNotes[category] != nil,
                    "\(category) has no note")
        }
    }
}
