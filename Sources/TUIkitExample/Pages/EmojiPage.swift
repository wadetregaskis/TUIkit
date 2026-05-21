//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmojiPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Emoji rendering demo / inspector page.
///
/// Showcases all the Terminal.app emoji rendering quirks TUIkit has to
/// work around, and provides a searchable browse-everything view of the
/// emoji corpus.  Built using ``Unicode.Scalar.Properties`` so the list
/// stays accurate against whatever Unicode version the running toolchain
/// knows about — no bundled data.
///
/// Page structure:
///   1. "Bug cases" header — one row per distinct rendering class, each
///      showing exemplar clusters so it's obvious whether your terminal
///      handles them.
///   2. Search field — type a name fragment ("grinning"), a hex
///      codepoint ("1F600"), or paste a literal emoji to filter the
///      browse list.
///   3. Browse list — every codepoint with default emoji presentation,
///      shown alongside its name and hex codepoint.
struct EmojiPage: View {
    @State private var filter: String = ""
    @State private var selectedID: UInt32? = nil

    // The corpus is small (~1.9k entries) and immutable, so building it
    // once at page load and filtering inline is fine — no need for a
    // separate model layer.
    private static let allEmoji: [EmojiEntry] = Self.buildCorpus()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Bug cases (the rows TUIkit has to compensate)") {
                VStack(alignment: .leading) {
                    BugCaseRow(label: "Normal",
                               description: "advance matches glyph width",
                               clusters: ["🤙", "🥳", "😀", "👋", "🔥", "🎉", "💩"])

                    BugCaseRow(label: "VS-16 under-advance (Bug A)",
                               description: "<base>+U+FE0F: paints 2, advances 1",
                               clusters: ["🖥️", "🛡️", "🚸", "📞", "✏️", "❤️"])

                    BugCaseRow(label: "Fitzpatrick over-advance (Bug B)",
                               description: "<base>+skin-tone: paints 2, advances 4",
                               clusters: ["🤙🏽", "✊🏻", "👍🏼", "👋🏿", "👨🏽", "🙏🏼"])

                    BugCaseRow(label: "BMP skin-tone bases (Bug B variant)",
                               description: "BMP base + skin-tone: paints 2, advances 3",
                               clusters: ["☝🏻", "✌🏼", "✍🏽", "⛹🏾", "✊🏿"])

                    BugCaseRow(label: "Our terminalWidth is wrong (claim 1, paint 2)",
                               description: "BMP emoji-presentation codepoints",
                               clusters: ["⌚", "⌛", "⏩", "⏪", "⏫", "⏬", "⏰", "⏳"])
                }
            }

            HStack(spacing: 1) {
                Text("Filter:").foregroundStyle(.palette.foregroundSecondary)
                TextField("Filter", text: $filter,
                          prompt: Text("type a name, hex codepoint, or paste an emoji…"))
            }

            List("\(filteredEmoji.count) of \(Self.allEmoji.count) emoji",
                 selection: $selectedID)
            {
                ForEach(filteredEmoji) { entry in
                    EmojiRow(entry: entry)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 1)
        .appHeader {
            DemoAppHeader("Emoji",
                          subtitle: "Rendering quirks + searchable corpus")
        }
    }

    // MARK: - Filtering

    private var filteredEmoji: [EmojiEntry] {
        let needle = filter.trimmingWhitespace()
        if needle.isEmpty { return Self.allEmoji }

        // Literal emoji match — if the filter contains a non-ASCII
        // character, treat the entire filter as a literal cluster and
        // look for entries whose cluster matches by prefix.  Lets users
        // paste 🤙 and see only that emoji (and any variants).
        if needle.unicodeScalars.contains(where: { !$0.isASCII }) {
            return Self.allEmoji.filter { entry in
                entry.cluster.hasPrefix(needle) || needle.hasPrefix(entry.cluster)
            }
        }

        // Hex codepoint match — accept "1F600", "U+1F600", "0x1F600".
        let hexCandidate = needle
            .uppercased()
            .replacingOccurrences(of: "U+", with: "")
            .replacingOccurrences(of: "0X", with: "")
        if !hexCandidate.isEmpty,
           hexCandidate.allSatisfy({ $0.isHexDigit }),
           let value = UInt32(hexCandidate, radix: 16)
        {
            return Self.allEmoji.filter { $0.codepoint == value }
        }

        // Name match — case-insensitive substring against the Unicode
        // name.  Splits the needle on whitespace so "smiling face"
        // matches "SMILING FACE WITH HEART-EYES" etc.
        let words = needle.uppercased().split(whereSeparator: { $0.isWhitespace })
        return Self.allEmoji.filter { entry in
            words.allSatisfy { entry.name.contains($0) }
        }
    }

    // MARK: - Corpus

    private static func buildCorpus() -> [EmojiEntry] {
        var out: [EmojiEntry] = []
        // Same range the scanner sweeps.  Filtered by
        // `isEmojiPresentation` so we get exactly the codepoints
        // Terminal.app should be painting as 2-cell colour emoji.
        for cp: UInt32 in 0x0023...0x1FBFF {
            guard let scalar = Unicode.Scalar(cp) else { continue }
            guard scalar.properties.isEmojiPresentation else { continue }
            let name = scalar.properties.name ?? "U+\(String(cp, radix: 16, uppercase: true))"
            out.append(EmojiEntry(codepoint: cp,
                                  cluster: String(scalar),
                                  name: name))
        }
        return out
    }
}

// MARK: - Subviews

/// One row in the "bug cases" section: a label, a horizontal strip of
/// example clusters, then a description.  The clusters are wrapped in
/// square brackets so any extra/missing cells from a Terminal.app bug
/// are obvious — well-aligned brackets means the row rendered cleanly.
private struct BugCaseRow: View {
    let label: String
    let description: String
    let clusters: [String]

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .foregroundStyle(.palette.accent)
            Text(clusters.map { "[\($0)]" }.joined(separator: " "))
            Text("— \(description)")
                .foregroundStyle(.palette.foregroundSecondary)
                .dim()
        }
    }
}

/// One row in the browse list: cluster, codepoint, name.
private struct EmojiRow: View {
    let entry: EmojiEntry

    var body: some View {
        HStack(spacing: 2) {
            Text(entry.cluster)
            Text(entry.codepointLabel)
                .foregroundStyle(.palette.foregroundSecondary)
                .dim()
            Text(entry.name)
        }
    }
}

// MARK: - Model

private struct EmojiEntry: Identifiable {
    let codepoint: UInt32
    let cluster: String
    let name: String

    var id: UInt32 { codepoint }
    var codepointLabel: String {
        "U+" + String(codepoint, radix: 16, uppercase: true).leftPadded(to: 5, with: "0")
    }
}

// MARK: - Helpers

extension String {
    fileprivate func trimmingWhitespace() -> String {
        var start = self.startIndex
        var end = self.endIndex
        while start < end, self[start].isWhitespace { start = self.index(after: start) }
        while end > start, self[self.index(before: end)].isWhitespace { end = self.index(before: end) }
        return String(self[start..<end])
    }

    fileprivate func leftPadded(to width: Int, with padding: Character) -> String {
        if self.count >= width { return self }
        return String(repeating: padding, count: width - self.count) + self
    }
}
