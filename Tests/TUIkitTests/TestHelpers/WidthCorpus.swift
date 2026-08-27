//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WidthCorpus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - The shared width corpus

/// The curated list of grapheme clusters every width question in this project
/// is asked about — `Tools/TerminalProbes/data/width-corpus.json`.
///
/// It lives in a file rather than in Swift because the Python probes measure
/// the same list on the real terminals, and the whole value of a measurement is
/// that it answers the question a test is going to ask. Two hand-kept lists
/// drift, and the drift is invisible: the probe reports on a cluster no test
/// checks, and the test checks a cluster nothing measured.
///
/// A hand-picked battery only contains what somebody already thought to doubt,
/// so the classes here are deliberately wider than the known defects — ASCII,
/// CJK and plain emoji are in it precisely because nothing is supposed to
/// happen to them.
enum WidthCorpus {

    struct Entry: Decodable, CustomStringConvertible, Sendable {
        /// Stable key, and the name the probe records its measurement under.
        let id: String
        /// The defect class this exemplifies — `vs16_pictograph`, `zwj`,
        /// `skin_tone_bmp_narrow`. Terminals are wrong by class, not by
        /// character.
        let `class`: String
        /// The cluster, spelled for review.
        let text: String
        /// The same cluster as `U+XXXX` scalars. Authoritative: `text` is a
        /// convenience that ``load()`` checks against this, because an emoji
        /// pasted into a JSON file is exactly the kind of thing that silently
        /// loses a variation selector.
        let scalars: [String]

        var description: String { "\(id) (\(`class`))" }

        /// The cluster as one `Character`, which is what every width and
        /// advance model takes.
        var character: Character { Character(text) }
    }

    private struct Document: Decodable {
        let version: Int
        let clusters: [Entry]
    }

    /// Every entry, loaded once.
    static let clusters: [Entry] = load()

    /// Entries of one class.
    static func clusters(in klass: String) -> [Entry] {
        clusters.filter { $0.class == klass }
    }

    private static func load() -> [Entry] {
        let url =
            URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestHelpers/
            .deletingLastPathComponent()  // TUIkitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data/width-corpus.json")
        guard let data = try? Data(contentsOf: url),
            let document = try? JSONDecoder().decode(Document.self, from: data)
        else {
            fatalError("Cannot read the width corpus at \(url.path)")
        }
        for entry in document.clusters {
            let spelled = entry.scalars.map { scalar -> Unicode.Scalar in
                guard scalar.hasPrefix("U+"),
                    let value = UInt32(scalar.dropFirst(2), radix: 16),
                    let unicode = Unicode.Scalar(value)
                else { fatalError("\(entry.id): malformed scalar \(scalar)") }
                return unicode
            }
            guard String(String.UnicodeScalarView(spelled)) == entry.text else {
                fatalError("\(entry.id): `text` and `scalars` disagree")
            }
        }
        return document.clusters
    }
}
