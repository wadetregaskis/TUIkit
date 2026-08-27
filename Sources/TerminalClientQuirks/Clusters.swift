//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Clusters.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit
import TUIkitCore

/// One grapheme cluster worth showing, and why it is worth showing.
///
/// The list IS ``TUIkitCore/TerminalWidthCorpus`` — the same 69 clusters the
/// probes in `Tools/TerminalProbes/` measure on real terminals, pinned
/// identical to their JSON by `WidthCorpusParityTests`. The app deliberately
/// shows every entry rather than a summary battery: a hand-picked battery only
/// contains what somebody already thought to doubt, and the whole point of
/// this app is meeting the terminal nobody measured yet.
struct Cluster: Identifiable {
    var id: String { name }

    /// What to call this cluster — the corpus id, which is also the key a
    /// probe records its measurement under, so a bug report and a measurement
    /// name the same thing.
    let name: String

    /// The defect class it exemplifies.
    let category: String

    /// The cluster itself.
    let text: String

    /// What goes wrong with its class, in one line.
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

    /// Every corpus cluster, in corpus order.
    static let all: [Cluster] = TerminalWidthCorpus.all.map { entry in
        Cluster(
            name: entry.id,
            category: entry.category,
            text: entry.text,
            note: TerminalWidthCorpus.categoryNotes[entry.category] ?? "")
    }

    /// One representative per category — for screens where 69 rows would bury
    /// the signal, like the class-by-class quirk table. The representative is
    /// the category's first corpus entry.
    static let representatives: [Cluster] = {
        var seen = Set<String>()
        return all.filter { seen.insert($0.category).inserted }
    }()
}
