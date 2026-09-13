//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EmojiPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
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
    @State private var selectedSymbolID: String?

    /// The column sorts, one per table. Each starts in the order its corpus
    /// is built in — emoji by codepoint, symbols by name — so the first frame
    /// is the list as it always was and a header click is what changes it.
    @State private var emojiSort = [KeyPathComparator(\EmojiEntry.codepoint)]
    @State private var symbolSort = [KeyPathComparator(\SymbolEntry.name)]

    /// Below this terminal width the two tables stack instead of sitting side
    /// by side. `terminalWidth` is stable across measure and render (published
    /// once at the render root), so switching on it never oscillates — unlike
    /// `ViewThatFits`, which can't tell these apart because both tables are
    /// width-greedy and each measures to the probe width.
    ///
    /// Kept low because side by side works at any width (an `HStack` splits its
    /// two greedy lists evenly), so it's preferable down to quite narrow
    /// terminals; stacking is the last resort for the genuinely tiny.
    @Environment(\.terminalWidth) private var terminalWidth
    private static let sideBySideMinWidth = 64

    /// The fewest lines a browse table is worth drawing in: its count line, the
    /// table's top border, its header row, one row of data and its bottom border.
    /// Below that a box would show chrome with nothing in it, so the tables give way
    /// to their count lines instead.
    private static let minimumBrowseLines = 5

    // The corpus is small (~1.9k entries) and immutable, so building it
    // once at page load and filtering inline is fine — no need for a
    // separate model layer.
    private static let allEmoji: [EmojiEntry] = Self.buildCorpus()

    // Every known SF Symbol (name + glyph). Empty off Apple platforms, where
    // `SFSymbol` can't resolve anything — the table below then shows its
    // placeholder. Built once, like the emoji corpus.
    private static let allSymbols: [SymbolEntry] = SFSymbol.all.map { entry in
        SymbolEntry(
            name: entry.name,
            glyph: entry.glyph,
            codepoint: entry.glyph.unicodeScalars.first?.value ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.emoji.bugCasesSection") {
                VStack(alignment: .leading) {
                    BugCaseRow(label: "page.emoji.bugNormalLabel",
                               description: "page.emoji.bugNormalDesc",
                               clusters: ["🤙", "🥳", "😀", "👋", "🔥", "🎉", "💩"])

                    BugCaseRow(label: "page.emoji.bugVS16Label",
                               description: "page.emoji.bugVS16Desc",
                               clusters: ["🖥️", "🛡️", "🚸", "📞", "✏️", "❤️"])

                    BugCaseRow(label: "page.emoji.bugFitzpatrickLabel",
                               description: "page.emoji.bugFitzpatrickDesc",
                               clusters: ["🤙🏽", "✊🏻", "👍🏼", "👋🏿", "👨🏽", "🙏🏼"])

                    BugCaseRow(label: "page.emoji.bugBMPSkinToneLabel",
                               description: "page.emoji.bugBMPSkinToneDesc",
                               clusters: ["☝🏻", "✌🏼", "✍🏽", "⛹🏾", "✊🏿"])

                    // ZWJ: one composed glyph on most hosts, separate
                    // components on Warp — and on BOTH Apple Terminal and Warp
                    // the cluster reserves the sum of its parts, so a row
                    // budgeted at 2 cells wraps. The class TUIkit widened the
                    // claim for; without a row here the page could not show it.
                    BugCaseRow(label: "page.emoji.bugZWJLabel",
                               description: "page.emoji.bugZWJDesc",
                               clusters: ["👩‍🚀", "👨‍👩‍👧‍👦", "❤️‍🔥", "🏳️‍🌈", "🏴‍☠️", "👩🏽‍🚀"])

                    BugCaseRow(label: "page.emoji.bugTerminalWidthLabel",
                               description: "page.emoji.bugTerminalWidthDesc",
                               clusters: ["⌚", "⌛", "⏩", "⏪", "⏫", "⏬", "⏰", "⏳"])
                }
            }

            HStack(spacing: 1) {
                Text("page.emoji.filterLabel").foregroundStyle(.palette.foregroundSecondary)
                TextField("page.emoji.filterField", text: $filter,
                          prompt: Text("page.emoji.filterPrompt"))
            }

            // Emoji on the left, SF Symbols on the right — both filtered by the
            // one field above, each scrolled independently. Side by side when
            // there is room, otherwise stacked.
            //
            // In exactly the rows the layout has LEFT once everything above has
            // wrapped at the real width: a `GeometryReader` is greedy, so this stack
            // hands it the remainder, and it pads to that remainder even where the
            // tables stop short. This used to be a guess, `terminalHeight - 24`,
            // which counted the whole terminal where the page is laid out in the
            // content area and assumed the bug-case rows never wrap. At 140x42 it came
            // out 7 rows short; a short page is centred, so those showed as 3 blank
            // lines under the header and 4 above the status bar. At 80 columns the
            // rows wrap and the same guess ran the tables off the bottom.
            //
            // Held at a height rather than left to hug, still, and for the reason it
            // always was: a `Table` whose rows all fit hugs them, and filtering 1,212
            // emoji to one would collapse the box and jump the page on every
            // keystroke.
            GeometryReader { proxy in
                browseTables(height: proxy.size.height)
            }
        }
        // Not wrapped in a page ScrollView: the tables are the scrollable content,
        // each scrolling itself inside the rows the reader above hands it. Inside a
        // page ScrollView the reader would be offered the whole viewport again.
        .appHeader {
            DemoAppHeader("menu.item.emoji",
                          subtitle: "page.emoji.subtitle")
        }
    }

    // MARK: - Tables

    /// The browse tables, filling exactly `height` lines.
    ///
    /// Side by side, both take the whole height. Stacked, they share it with the
    /// one line between them — two tables in a `VStack` cannot split a height on
    /// their own. Where there is room for one box and not two, the emoji table,
    /// which the page is about, keeps it; where there is not room for any, the
    /// count lines stand in, rather than boxes with nothing in them.
    @ViewBuilder private func browseTables(height: Int) -> some View {
        if terminalWidth >= Self.sideBySideMinWidth {
            if height >= Self.minimumBrowseLines {
                HStack(alignment: .top, spacing: 2) {
                    emojiTable(height: height)
                    symbolTable(height: height)
                }
            } else {
                HStack(alignment: .top, spacing: 2) {
                    emojiCountLine
                    if SFSymbol.isFontAvailable { symbolCountLine }
                }
            }
        } else if height >= 2 * Self.minimumBrowseLines + 1 {
            let first = (height - 1) / 2
            VStack(alignment: .leading, spacing: 1) {
                emojiTable(height: first)
                symbolTable(height: height - 1 - first)
            }
        } else if height >= Self.minimumBrowseLines {
            emojiTable(height: height)
        } else {
            emojiCountLine
        }
    }

    /// How many emoji the filter kept, of how many there are.
    ///
    /// Both counts sit inside one phrase, as `%1$@`/`%2$@`, so a language can order
    /// them its own way (zh and ja put the total first).
    private var emojiCountLine: some View {
        Text("page.emoji.emojiCount \(filteredEmoji.count) \(Self.allEmoji.count)")
            .foregroundStyle(.palette.foregroundSecondary)
    }

    /// As ``emojiCountLine``, for the symbols.
    private var symbolCountLine: some View {
        Text("page.emoji.sfSymbolsCount \(filteredSymbols.count) \(Self.allSymbols.count)")
            .foregroundStyle(.palette.foregroundSecondary)
    }

    /// The emoji browse table — its own selection, sort and scroll position.
    ///
    /// A `Table` rather than a `List` of hand-built rows: the three fields
    /// were already a grid drawn by an `HStack` per row, and a grid that
    /// columns itself can also sort itself. The count line moves above it,
    /// `Table` having no title of its own.
    ///
    /// - Parameter height: The lines this takes, its count line included. Held on
    ///   the TABLE and not on the wrapper: the wrapper also holds the count line,
    ///   and framing IT leaves the table hugging its rows inside a taller box, which
    ///   is the shrink this is here to stop.
    private func emojiTable(height: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            emojiCountLine
            Table(sortedEmoji, selection: $selectedID, sortOrder: $emojiSort) {
                // Two cells: every entry here has emoji presentation, which is
                // what makes it wide, and the page exists to show that.
                TableColumn("page.emoji.column.glyph", value: \EmojiEntry.cluster)
                    .width(.fixed(7))
                // Sorted by the NUMBER, shown as the label. Sorting the label
                // would order it as text, which puts U+FE0F before U+1F600.
                TableColumn("page.emoji.column.code", value: \EmojiEntry.codepoint) {
                    $0.codepointLabel
                }
                .width(.fixed(10))
                TableColumn("page.emoji.column.description", value: \EmojiEntry.name)
                    .width(.flexible)
            }
            // Every row here begins with the glyph the page is about, and a
            // second mark beside it read as one mark too many. The highlight
            // says which row is selected on its own.
            .rowSelectionIndicator(.hidden)
            .heldOpen(to: height)
        }
    }

    /// The SF Symbols browse list — its own selection and scroll position,
    /// independent of the emoji list but filtered by the same field.
    ///
    /// Rendering symbols needs BOTH an Apple platform AND the SF Symbols font
    /// installed (`SFSymbol.isFontAvailable`) — a resolved codepoint alone would
    /// draw a missing-glyph box on a system without the font. When that check
    /// fails, show a placeholder explaining what's missing instead of a list of
    /// broken glyphs; the message distinguishes a non-Apple platform (no symbols
    /// resolve at all) from an Apple system that just lacks the font.
    ///
    /// - Parameter height: As ``emojiTable(height:)``'s.
    @ViewBuilder private func symbolTable(height: Int) -> some View {
        if SFSymbol.isFontAvailable {
            VStack(alignment: .leading, spacing: 0) {
                symbolCountLine
                Table(
                    sortedSymbols, selection: $selectedSymbolID, sortOrder: $symbolSort,
                    emptyPlaceholder: L("page.emoji.sfSymbolsEmpty")
                ) {
                    // Plane-16 Private-Use, two cells wide with Terminal.app
                    // compensation — a cleanly aligned column is the proof.
                    TableColumn("page.emoji.column.glyph", value: \SymbolEntry.glyph)
                        .width(.fixed(7))
                    TableColumn("page.emoji.column.code", value: \SymbolEntry.codepoint) {
                        $0.codepointLabel
                    }
                    .width(.fixed(10))
                    TableColumn("page.emoji.column.description", value: \SymbolEntry.name)
                        .width(.flexible)
                }
                .rowSelectionIndicator(.hidden)
                .heldOpen(to: height)
            }
        } else {
            // Held to its share like the table it stands in for, or a stacked
            // pair would run past the rows it was handed.
            ContentUnavailableView(
                "page.emoji.sfSymbolsUnavailableTitle",
                description: Self.allSymbols.isEmpty
                    ? L("page.emoji.sfSymbolsUnavailablePlatform")
                    : L("page.emoji.sfSymbolsUnavailableFont"))
                .frame(height: height, alignment: .top)
        }
    }

    // MARK: - Filtering

    /// The filtered corpus in the order the headers ask for. Sorted here
    /// rather than in an `onChange` writing back to a `@State` array: the
    /// corpora are `static let`, so there is nothing to mutate, and a
    /// derived value cannot fall out of step with what derives it.
    private var sortedEmoji: [EmojiEntry] { filteredEmoji.sorted(using: emojiSort) }

    private var sortedSymbols: [SymbolEntry] { filteredSymbols.sorted(using: symbolSort) }

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

    /// SF Symbols matching the same filter — by name, since symbols have no
    /// standard Unicode name to key off. Splitting on whitespace and dots lets
    /// "star", "star fill", and "star.fill" all narrow the list.
    private var filteredSymbols: [SymbolEntry] {
        let needle = filter.trimmingWhitespace().lowercased()
        if needle.isEmpty { return Self.allSymbols }
        let words = needle.split { $0.isWhitespace || $0 == "." }
        return Self.allSymbols.filter { entry in
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
///
/// The description is dropped from a row it does not fit on. Squeezed into
/// the width the label and strip leave, it wrapped into a column several lines
/// tall, and every line it took came out of the browse tables below: at 80
/// columns the section took 18 rows and left the tables none. The label and
/// strip are what the row exists to show, so they stay.
///
/// Decided per row by `ViewThatFits` rather than at one terminal width,
/// because the rows differ in length and every language lengthens them
/// differently. Unlike the tables (see `EmojiPage.terminalWidth`) these rows
/// are plain `Text`, whose ideal width does not follow the width it is
/// offered, so `ViewThatFits` can tell a row that fits from one that doesn't.
private struct BugCaseRow: View {
    let label: LocalizedStringKey
    let description: LocalizedStringKey
    let clusters: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                labelAndStrip
                Text("— \(description.localized)")
                    .foregroundStyle(.palette.foregroundSecondary)
                    .dim()
            }
            HStack(spacing: 2) {
                labelAndStrip
            }
        }
    }

    @ViewBuilder private var labelAndStrip: some View {
        Text(label)
            .foregroundStyle(.palette.accent)
        Text(clusters.map { "[\($0)]" }.joined(separator: " "))
    }
}

// MARK: - Model

private struct EmojiEntry: Identifiable, Equatable, Sendable {
    let codepoint: UInt32
    let cluster: String
    let name: String

    var id: UInt32 { codepoint }
    var codepointLabel: String {
        "U+" + String(codepoint, radix: 16, uppercase: true).leftPadded(to: 5, with: "0")
    }
}

private struct SymbolEntry: Identifiable, Equatable, Sendable {
    let name: String
    let glyph: String
    let codepoint: UInt32

    var id: String { name }
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

// MARK: - Holding a box open

extension View {
    /// Holds this view at `height` lines, one of the caller's lines going to the
    /// count line above it.
    ///
    /// A `Table` whose rows all fit hugs them, which is right for a table in a
    /// `VStack` and wrong for a browse table you filter: narrowing 1,212 rows to
    /// one collapsed the box from twenty lines to three and jumped the page under
    /// the cursor, on every keystroke.
    fileprivate func heldOpen(to height: Int) -> some View {
        // No floor: the caller already gave way to count lines below the smallest
        // useful box, and a floor here is what used to run a table past the rows it
        // had.
        frame(height: max(0, height - 1))
    }
}
