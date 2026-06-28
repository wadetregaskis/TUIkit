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
    @State private var selectedID: UInt32?

    // The corpus is small (~1.9k entries) and immutable, so building it
    // once at page load and filtering inline is fine — no need for a
    // separate model layer.
    private static let allEmoji: [EmojiEntry] = Self.buildCorpus()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.emoji.bugCasesSection")) {
                VStack(alignment: .leading) {
                    BugCaseRow(label: L("page.emoji.bugNormalLabel"),
                               description: L("page.emoji.bugNormalDesc"),
                               clusters: ["🤙", "🥳", "😀", "👋", "🔥", "🎉", "💩"])

                    BugCaseRow(label: L("page.emoji.bugVS16Label"),
                               description: L("page.emoji.bugVS16Desc"),
                               clusters: ["🖥️", "🛡️", "🚸", "📞", "✏️", "❤️"])

                    BugCaseRow(label: L("page.emoji.bugFitzpatrickLabel"),
                               description: L("page.emoji.bugFitzpatrickDesc"),
                               clusters: ["🤙🏽", "✊🏻", "👍🏼", "👋🏿", "👨🏽", "🙏🏼"])

                    BugCaseRow(label: L("page.emoji.bugBMPSkinToneLabel"),
                               description: L("page.emoji.bugBMPSkinToneDesc"),
                               clusters: ["☝🏻", "✌🏼", "✍🏽", "⛹🏾", "✊🏿"])

                    BugCaseRow(label: L("page.emoji.bugTerminalWidthLabel"),
                               description: L("page.emoji.bugTerminalWidthDesc"),
                               clusters: ["⌚", "⌛", "⏩", "⏪", "⏫", "⏬", "⏰", "⏳"])
                }
            }

            HStack(spacing: 1) {
                Text(L("page.emoji.filterLabel")).foregroundStyle(.palette.foregroundSecondary)
                TextField(L("page.emoji.filterField"), text: $filter,
                          prompt: Text(L("page.emoji.filterPrompt")))
            }

            List("\(filteredEmoji.count) \(L("page.emoji.ofCount")) \(Self.allEmoji.count) \(L("page.emoji.emojiCountSuffix"))",
                 selection: $selectedID)
            {
                ForEach(filteredEmoji) { entry in
                    EmojiRow(entry: entry)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 1)
        // Not wrapped in a page ScrollView: the List below is the scrollable
        // content and is greedy in height (it fills the viewport and scrolls
        // itself). Nesting it in a page ScrollView would defeat both.
        .appHeader {
            DemoAppHeader(L("page.emoji.title"),
                          subtitle: L("page.emoji.subtitle"))
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

private struct EmojiEntry: Identifiable, Equatable {
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
