//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TruncatingTable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Truncating Table

/// A `Table` whose every cell is far wider than its column, so every visible
/// cell goes through the clip-and-pad path on every frame.
///
/// The catalogue had no scenario that truncates: `table`'s synthetic cells are
/// short enough to fit their columns, and `table-multiline` *wraps* rather than
/// clipping. So the ANSI-aware clip — `truncatedToWidth` and the
/// `ansiAwarePrefix` family under it, which walk a line cell by cell and are
/// the hottest string path the framework has — was measured by nothing. A user
/// profile of a wide table of long values is what turned that up.
///
/// The shape is deliberate in four ways:
///
/// - **Values overflow by a lot.** A ~90-cell sentence in an ~18-cell column
///   means a clip that keeps a fifth of what it measures, which is where a
///   walk that scans the whole string to produce a short prefix costs the most.
/// - **All three truncation modes appear**, because they take different paths:
///   `.tail` clips a prefix, `.head` takes a suffix, `.middle` does both.
/// - **One column carries ANSI.** A styled cell cannot use the byte-wise fast
///   paths a plain one can, and it is also the case where an unbalanced clip
///   bleeds colour into the next column, so it belongs in a scenario that runs
///   every frame.
/// - **Rows are distinct.** Identical rows collapse to one measure under the
///   row/value memo and read as a wash no matter what changed underneath.
enum TruncatingTableScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "truncate",
        title: "Truncating Table",
        blurb: "N rows × 6 columns of long sentences, every cell clipped to a narrow column.",
        stresses: "ANSI-aware clipping · all three truncation modes · per-cell measure/pad",
        make: { config in AnyView(TruncatingTableView(config: config)) }
    )
}

/// Row model. The strings are synthesised ONCE, in `init` — a scenario that
/// rebuilds them per frame measures the harness's RNG and string joins rather
/// than TUIkit's clip (the mistake `TextWall`'s comment records).
struct TruncatingItem: Identifiable, Sendable, Equatable {
    let id: Int
    let plain: String
    let styled: String
    let path: String
}

private struct TruncatingTableView: View {
    let rows: [TruncatingItem]

    init(config: StressConfig) {
        let count = config.sized(5_000)
        var built = [TruncatingItem]()
        built.reserveCapacity(count)
        for index in 0..<count {
            let h = mix(config.seed, index)
            // ~12 words ≈ 80–95 cells, against columns of roughly 18.
            let sentence = Synth.sentence(h, words: 12)
            // A styled value: three coloured runs, so the clip has escapes to
            // carry and a reset to close wherever it lands.
            let styled =
                "\u{1B}[3\(h % 6 + 1)m\(Synth.slug(h))\u{1B}[0m/"
                + "\u{1B}[1m\(Synth.slug(h >> 8))\u{1B}[0m/"
                + "\u{1B}[2m\(Synth.sentence(h >> 16, words: 6))\u{1B}[0m"
            built.append(
                TruncatingItem(
                    id: index,
                    plain: sentence,
                    styled: styled,
                    path: "/var/lib/\(Synth.slug(h))/\(Synth.slug(h >> 24))/\(Synth.name(h)).log"))
        }
        self.rows = built
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.truncate.heading", rows.count)).bold()
            Divider()
            Table(rows, selection: Binding<Int?>.constant(nil)) {
                TableColumn("ID") { (row: TruncatingItem) in "\(row.id)" }
                    .width(.fit)
                TableColumn("Summary") { (row: TruncatingItem) in row.plain }
                TableColumn("Path") { (row: TruncatingItem) in row.path }
                    .truncationMode(.head)
                TableColumn("Middle") { (row: TruncatingItem) in row.plain }
                    .truncationMode(.middle)
                TableColumn("Styled") { (row: TruncatingItem) in row.styled }
                TableColumn("Tail") { (row: TruncatingItem) in row.path }
            }
        }
    }
}
