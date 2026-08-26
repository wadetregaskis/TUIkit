//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Clusters.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// One grapheme cluster worth showing, and why it is worth showing.
///
/// The battery mirrors `Tools/TerminalProbes/advance_probe.py`, which is what
/// measured the models in `Documentation/Terminal-compatibility.md`. Each entry
/// is a class of thing terminals disagree about, not an arbitrary character:
/// the point of the app is that you can see *which* class your terminal gets
/// wrong, and report that rather than "emoji look funny".
struct Cluster: Identifiable {
    var id: String { name }

    /// What to call this class of cluster.
    let name: String

    /// The cluster itself.
    let text: String

    /// What goes wrong with it, in one line.
    let note: String

    /// The cluster as codepoints, for a bug report.
    var codepoints: String {
        text.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
    }

    /// The single `Character` — every entry is one grapheme cluster, which is
    /// the unit both the width tables and the advance models are defined over.
    var character: Character { text.first ?? " " }
}

enum Clusters {

    /// The classes that terminals actually disagree about, in the order a
    /// reader should meet them: the ones that always work, then the ones that
    /// break.
    static let battery: [Cluster] = [
        Cluster(
            name: "ASCII", text: "a",
            note: "One cell everywhere. The control."),
        Cluster(
            name: "Box drawing", text: "─",
            note: "One cell everywhere. TUIkit's chrome is built from these."),
        Cluster(
            name: "East Asian wide", text: "中",
            note: "Two cells, two advance. Wide, but not contentious."),
        Cluster(
            name: "Decomposed é (NFD)", text: "e\u{0301}",
            note: "One cell: a base plus a combining mark. macOS hands filenames back this way."),
        Cluster(
            name: "Emoji presentation", text: "👍",
            note: "Two cells by default. Usually agreed on."),
        Cluster(
            name: "BMP emoji presentation", text: "⌚",
            note: "Two cells despite being in the BMP — the range checks alone miss these."),
        Cluster(
            name: "VS-16 pictograph", text: "🖥️",
            note: "Base + U+FE0F. Apple Terminal and iTerm2 (alternate screen) paint 2, advance 1."),
        Cluster(
            name: "VS-16, BMP base", text: "❤️",
            note: "Same quirk from a text-presentation base."),
        Cluster(
            name: "Bare pictograph", text: "🛡",
            note: "No selector at all: painted 2 via emoji fallback, advanced 1."),
        Cluster(
            name: "VS-15 chrome glyph", text: "⬛\u{FE0E}",
            note: "Text presentation forced. Ghostty under-advances these; tmux re-emits them oddly."),
        Cluster(
            name: "Fitzpatrick skin tone", text: "🤙🏽",
            note: "Base + modifier. Apple Terminal advances 4 where 2 was claimed, stranding cells."),
        Cluster(
            name: "Fitzpatrick, BMP base", text: "✊🏻",
            note: "Advances 3 rather than 4 — the base's own width shifts the whole model."),
        Cluster(
            name: "Lone regional indicator", text: "🇦",
            note: "Half a flag. Paints 2, advances 1 on Apple Terminal."),
        Cluster(
            name: "Flag (indicator pair)", text: "🇺🇸",
            note: "Paints 2 AND advances 2 — the pair is fine where the lone one is not."),
        Cluster(
            name: "Keycap sequence", text: "1️⃣",
            note: "Base + U+FE0F + U+20E3. Under-advances on iTerm2."),
        Cluster(
            name: "ZWJ sequence", text: "👩‍🚀",
            note: "Two emoji joined. Mostly agreed at 2 cells."),
    ]

    /// The battery plus an SF Symbol, when one can be resolved.
    ///
    /// SF Symbols live in the Plane-16 Private Use Area and render only where
    /// the font is installed — Apple platforms, in a terminal using SF Mono.
    /// They paint two cells and advance one, exactly like a VS-16 pictograph,
    /// which is why they belong in this list rather than in a footnote.
    static var all: [Cluster] {
        guard let glyph = SFSymbol.glyph(named: "apple.terminal") else { return battery }
        return battery + [
            Cluster(
                name: "SF Symbol (PUA)", text: glyph,
                note: "Plane-16 private use. Paints 2, advances 1 where the font exists.")
        ]
    }
}
