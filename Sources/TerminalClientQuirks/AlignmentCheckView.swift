//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentCheckView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The visual proof, and the only part of this app that does not take TUIkit's
/// word for anything: every row closes its bar at the same column, so a bar out
/// of line is a cluster this terminal handles in a way TUIkit does not yet know
/// about.
///
/// Why it is worth looking at rather than reading a table: the table on the
/// previous screen is what TUIkit *believes*, assembled from measurements taken
/// on other machines. This is what your terminal, your font and your settings
/// actually do — and those settings matter (iTerm2's Unicode-version and
/// ambiguous-width options change the answer).
struct AlignmentCheckView: View {
    let client: TerminalClient

    /// The column every closing bar should sit in: the widest cluster claim
    /// (2), so a one-cell cluster is padded by one.
    private static let field = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            explanation
            VStack(alignment: .leading, spacing: 0) {
                ruler
                ForEach(Clusters.all) { cluster in
                    Text(card(for: cluster))
                }
            }
            reporting
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Alignment check").bold()
            Text("Every ‘│’ below should form two straight vertical lines.")
                .foregroundStyle(.palette.foregroundSecondary)
            Text(
                "A bar pushed left or right marks a cluster this terminal measures differently "
                    + "from TUIkit — that row is the bug report."
            )
            .foregroundStyle(.palette.foregroundSecondary)
        }
    }

    private var ruler: some View {
        Text("│" + String(repeating: "─", count: Self.field) + "│  (target)")
            .foregroundStyle(.palette.foregroundTertiary)
    }

    /// One row: bars around the cluster, padded to the shared field width by
    /// the SAME measurement the layout engine uses, then the class name.
    ///
    /// Deliberately one `Text` rather than an `HStack` of three: a stack would
    /// let the layout place each piece by its own measurement, which would hide
    /// exactly the disagreement this screen exists to expose. One string means
    /// the terminal, not TUIkit, decides where the closing bar lands.
    private func card(for cluster: Cluster) -> String {
        let width = cluster.character.terminalWidth
        let padding = String(repeating: " ", count: max(0, Self.field - width))
        return "│\(cluster.text)\(padding)│  \(cluster.name)"
    }

    private var reporting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reporting a misalignment").bold()
            Text("Include the terminal and version, and the row's codepoints:")
                .foregroundStyle(.palette.foregroundSecondary)
            ForEach(Clusters.all.filter(isContentious)) { cluster in
                HStack(spacing: 1) {
                    Text("   \(cluster.text)")
                    Text(cluster.codepoints).foregroundStyle(.palette.foregroundSecondary)
                    Text(cluster.note).foregroundStyle(.palette.foregroundTertiary)
                }
            }
            Text("Tools/TerminalProbes/advance_probe.py measures all of these numerically.")
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// The classes some measured terminal gets wrong — the ones worth listing
    /// for a report. A cluster every host agrees on is not evidence of anything.
    private func isContentious(_ cluster: Cluster) -> Bool {
        TerminalClient.Program.allCases.contains { program in
            TerminalClient.cursorAdvance(of: cluster.character, on: program)
                != cluster.character.terminalWidth
        }
    }
}
