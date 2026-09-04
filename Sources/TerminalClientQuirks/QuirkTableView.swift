//  🖥️ TUIkit — Terminal UI Kit for Swift
//  QuirkTableView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The measured model for the terminal in front of you: for each class of
/// cluster, how wide TUIkit lays it out and how far this terminal actually
/// moves the cursor over it.
///
/// Where those two disagree, everything after the cluster on that row lands in
/// the wrong column unless something intervenes — and the last column says
/// whether something does.
struct QuirkTableView: View {
    let client: TerminalClient

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            VStack(alignment: .leading, spacing: 0) {
                columnHeadings
                ForEach(Clusters.all) { cluster in
                    row(for: cluster)
                }
            }
            legend
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cursor advance on \(describe(client.program))").bold()
            Text(
                client.program == .unidentified
                    ? "No model: an unidentified terminal is assumed to advance the way it paints."
                    : "Measured with DSR — see Documentation/Terminal-compatibility.md."
            )
            .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: 1) {
            Text(pad("", 3)).foregroundStyle(.palette.foregroundTertiary)
            Text(pad("Class", 24)).foregroundStyle(.palette.foregroundTertiary)
            Text(pad("Glyph", 7)).foregroundStyle(.palette.foregroundTertiary)
            Text(pad("Wide", 5)).foregroundStyle(.palette.foregroundTertiary)
            Text(pad("Moves", 6)).foregroundStyle(.palette.foregroundTertiary)
            Text("Workaround").foregroundStyle(.palette.foregroundTertiary)
        }
    }

    private func row(for cluster: Cluster) -> some View {
        let width = cluster.character.terminalWidth
        let advance = TerminalClient.cursorAdvance(of: cluster.character, on: client.program)
        let diverges = width != advance
        return HStack(spacing: 1) {
            Text(pad(diverges ? "!" : "ok", 3))
                .foregroundStyle(diverges ? .palette.warning : .palette.success)
            Text(pad(cluster.name, 24))
            // The glyph column is padded to its CLAIMED width and no further,
            // so a terminal that advances differently visibly ragged-edges this
            // column — the table is itself a test.
            Text(pad(cluster.text, 7))
            Text(pad("\(width)", 5)).foregroundStyle(.palette.foregroundSecondary)
            Text(pad("\(advance)", 6))
                .foregroundStyle(diverges ? .palette.warning : .palette.foregroundSecondary)
            Text(workaround(for: cluster, diverges: diverges))
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// What TUIkit does about a divergence — named rather than described, so a
    /// reader can find it in the source.
    private func workaround(for cluster: Cluster, diverges: Bool) -> String {
        guard client.program != .unidentified else {
            return diverges ? "none — terminal not identified" : ""
        }
        guard diverges else { return "" }
        let hasSkinTone = cluster.text.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
        if hasSkinTone {
            // What `TerminalClient.compensating` does with the tone on each
            // host — not a two-way switch: only tmux still strips.
            switch client.program {
            case .ghostty: return "kept — Ghostty merges them correctly"
            case .appleTerminal: return "separated — base, ZWNJ, modifier (withTerminalAppCursorCompensation)"
            case .iTerm2, .warp: return "kept, detached — advance measured per host"
            case .tmux: return "modifier stripped (withSkinToneFallback)"
            case .unidentified: return "none — terminal not identified"
            }
        }
        return advanceIsShort(cluster) ? "CUF after the glyph" : "cursor pulled back"
    }

    private func advanceIsShort(_ cluster: Cluster) -> Bool {
        TerminalClient.cursorAdvance(of: cluster.character, on: client.program)
            < cluster.character.terminalWidth
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wide  = cells TUIkit lays the cluster out as (Character.terminalWidth).")
                .foregroundStyle(.palette.foregroundTertiary)
            Text("Moves = cells this terminal actually advances the cursor by.")
                .foregroundStyle(.palette.foregroundTertiary)
            Text("Where they differ, the row after the glyph would shift — hence the workaround.")
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.strippedLength))
    }

    private func describe(_ program: TerminalClient.Program) -> String {
        switch program {
        case .appleTerminal: "Apple Terminal"
        case .iTerm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .tmux: "tmux"
        case .unidentified: "an unidentified terminal"
        }
    }
}
