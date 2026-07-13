//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TablePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

// MARK: - Demo Data

/// A file entry for the table demo.
private struct FileEntry: Identifiable, Sendable {
    let id: String
    let name: String
    let size: String
    let modified: String
    let type: String

    /// A longer, wrappable description used to demo multi-line cells.
    var details: String { "\(type), \(size), last modified \(modified)" }

    static let sampleFiles: [Self] = [
        Self(id: "1", name: "README.md", size: "4.2 KB", modified: "2026-02-07", type: "Markdown"),
        Self(id: "2", name: "Package.swift", size: "1.8 KB", modified: "2026-02-06", type: "Swift"),
        Self(id: "3", name: "Sources/", size: "128 KB", modified: "2026-02-07", type: "Directory"),
        Self(id: "4", name: "Tests/", size: "64 KB", modified: "2026-02-05", type: "Directory"),
        Self(id: "5", name: ".gitignore", size: "0.5 KB", modified: "2026-01-15", type: "Config"),
        Self(id: "6", name: "LICENSE", size: "1.1 KB", modified: "2026-01-01", type: "Text"),
        Self(id: "7", name: "docs/", size: "256 KB", modified: "2026-02-04", type: "Directory"),
        Self(id: "8", name: "plans/", size: "32 KB", modified: "2026-02-07", type: "Directory"),
        Self(id: "9", name: ".swiftlint.yml", size: "1.2 KB", modified: "2026-02-02", type: "YAML"),
        Self(id: "10", name: ".github/", size: "8 KB", modified: "2026-01-20", type: "Directory"),
        Self(id: "11", name: "Makefile", size: "0.8 KB", modified: "2026-02-01", type: "Makefile"),
        Self(id: "12", name: ".claude/", size: "16 KB", modified: "2026-02-07", type: "Directory"),
    ]
}

/// A tiny deterministic PRNG (SplitMix64) so the large-table corpus below is
/// identical on every launch rather than reshuffling each run.
private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A note row for the large multi-line table demo: hundreds of rows whose text
/// wraps to a pseudo-random (but deterministic) number of lines, deliberately
/// exercising every wrapping/truncation path — short one-liners, multi-line
/// word-wrap, `.lineLimit` fold-with-ellipsis when a note is too tall, a single
/// over-long "word" truncated mid-token, and explicit `\n` line breaks.
private struct NoteEntry: Identifiable, Sendable {
    let id: Int
    let note: String

    /// The row number, for the fixed-width leading column.
    var index: String { String(id) }

    static let bigNotes: [Self] = {
        let words = [
            "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
            "terminal", "buffer", "render", "wrap", "truncate", "ellipsis",
            "column", "cell", "line", "glyph", "unicode", "cascade", "layout",
            "scroll", "viewport", "measure", "fraction", "width", "height",
        ]
        var rng = SplitMix64(state: 0x7ABC_DEF0_1234_5678)
        func word() -> String { words[Int(rng.next() % UInt64(words.count))] }
        return (1...300).map { i in
            let text: String
            switch rng.next() % 10 {
            case 0:
                // Short — comfortably fits one line.
                text = word().capitalized
            case 1:
                // A single over-long "word" (wider than the column) → truncated
                // mid-token with an ellipsis.
                text = "supercalifragilistic" + String(repeating: "expialidocious", count: 4)
            case 2:
                // Explicit line breaks (honoured up to the line limit; the 4th
                // line folds into the 3rd with an ellipsis).
                text = "First line.\nSecond line.\nThird line.\nFourth (folded)."
            default:
                // N words → wraps to a variable number of lines; the taller ones
                // exceed `.lineLimit(3)` and fold their tail with an ellipsis.
                let count = Int(rng.next() % 45) + 2
                text = (0..<count).map { _ in word() }.joined(separator: " ")
            }
            return Self(id: i, note: text)
        }
    }()
}

/// A simulated live transfer for the animated-cells demo. Table cells are
/// string-valued, so animation here means *deriving the strings from a tick*:
/// the page advances a `@State` counter four times a second and every cell
/// value below is a pure function of it.
private struct TransferEntry: Identifiable, Sendable {
    let id: Int
    let name: String
    let status: String
    let elapsed: String

    /// Braille spinner frames (the same set as `Spinner`'s `.dots`), stepped
    /// once per tick and offset per row so the rows spin independently.
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    static func liveTransfers(tick: Int) -> [Self] {
        let jobs = [
            (name: "assets.tar.gz", rate: 3),
            (name: "photos-2026/", rate: 2),
            (name: "backup.sqlite", rate: 1),
        ]
        let seconds = tick / 4
        let elapsed = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return jobs.enumerated().map { index, job in
            // Progress climbs at a per-row rate, holds at 100% for a stretch,
            // then wraps and starts over — so the demo never goes static.
            let pct = min(100, (tick * job.rate + index * 17) % 130)
            let status = pct >= 100
                ? "✓ 100%"
                : "\(frames[(tick + index) % frames.count]) \(pct)%"
            return Self(id: index, name: job.name, status: status, elapsed: elapsed)
        }
    }
}

// MARK: - Table Page

/// Table component demo page.
///
/// Shows interactive table features including:
/// - Column definitions with key paths
/// - Column alignment (leading, center, trailing)
/// - Column width modes (fixed, flexible, ratio, fit)
/// - Single and multi-selection
/// - Keyboard navigation
/// - Scroll indicators
struct TablePage: View {
    @State var singleSelection: String?
    @State var multiSelection: Set<String> = []
    @State var ratioSelection: String?
    @State var notesSelection: Int?
    @State var multiLineByLine = true
    @State var fixedHeightByLine = true
    @State var browserURL: URL = FileBrowser.seedDirectory()
    @State var liveSelection: Int?
    /// Drives the animated-cells table: bumped by a `.task` loop (250 ms).
    @State var liveTick: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // A real file browser: single-click (or Space) selects; double-click
            // OR Return/Enter on the focused row activates it (via
            // `.onRowActivate`) — opening a folder in place; the ".." row (↰)
            // navigates up. Reads the live filesystem starting at $HOME.
            Text(L("page.table.fileBrowserCaption"))
                .foregroundStyle(.palette.foregroundSecondary)
            Text(browserURL.path).dim()
            Table(
                FileBrowser.entries(at: browserURL),
                selection: $singleSelection
            ) {
                TableColumn("", value: \BrowserEntry.icon)
                    .width(.fixed(2))
                // `.fit` sizes the Name column to its widest entry.
                TableColumn(L("page.table.column.name"), value: \BrowserEntry.name)
                    .width(.fit)
                TableColumn(L("page.table.column.size"), value: \BrowserEntry.size)
                    .width(.fixed(10))
                    .alignment(.trailing)
                TableColumn(L("page.table.column.modified"), value: \BrowserEntry.modified)
                    .width(.fixed(12))
                TableColumn(L("page.table.column.type"), value: \BrowserEntry.typeLabel)
                    .width(.flexible)
            }
            // `.onRowActivate` is a `Table` modifier, so it chains before the
            // generic view modifiers below.
            .onRowActivate { id in
                if let entry = FileBrowser.entries(at: browserURL).first(where: { $0.id == id }),
                    entry.isDirectory
                {
                    browserURL = entry.url
                }
            }
            // A short height so the rows overflow, plus an opt-in scrollbar that
            // tracks the visible region (sub-cell-precise thumb, ▲/▼ end arrows).
            .frame(height: 8)
            .scrollbarVisibility(.visible)

            // Two multi-line tables side by side: the small original (12 rows,
            // 2-line Details) on the left, and a fixed-height table of hundreds
            // of rows with pseudo-random line counts on the right. Each has
            // its OWN line/row scrolling toggle, so the two granularities can
            // be compared side by side.
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("page.table.multiSelectionCaption"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("component.multiSelectHint"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(L("demo.scrollGranularity.line"), isOn: $multiLineByLine)
                    Table(
                        FileEntry.sampleFiles,
                        selection: $multiSelection
                    ) {
                        TableColumn(L("page.table.column.name"), value: \FileEntry.name)
                            .width(.fit)
                        // A narrow column with .lineLimit(2): the Details value wraps
                        // onto a second line, growing the row, and clips the rest.
                        TableColumn(L("page.table.column.details"), value: \FileEntry.details)
                            .width(.fixed(22))
                            .lineLimit(2)
                    }
                    .scrollGranularity(multiLineByLine ? .line : .row)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    Text(L("page.table.wrappingCaption"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(L("demo.scrollGranularity.line"), isOn: $fixedHeightByLine)
                    // 300 rows in a fixed 20-row viewport → it scrolls. The Note
                    // column is `.flexible` with `.lineLimit(3)`, so each row's
                    // height varies: short notes stay one line, longer ones wrap
                    // to two or three, and the tallest fold their tail with an
                    // ellipsis (plus mid-word truncation and explicit breaks).
                    Table(NoteEntry.bigNotes, selection: $notesSelection) {
                        TableColumn("#", value: \NoteEntry.index)
                            .width(.fixed(5))
                            .alignment(.trailing)
                        TableColumn(L("page.table.column.details"), value: \NoteEntry.note)
                            .width(.flexible)
                            .lineLimit(3)
                    }
                    .frame(height: 20)
                    .scrollbarVisibility(.visible)
                    .scrollGranularity(fixedHeightByLine ? .line : .row)
                }
                .frame(maxWidth: .infinity)
            }

            Text(L("page.table.ratioCaption"))
                .foregroundStyle(.palette.foregroundSecondary)
            Table(FileEntry.sampleFiles, selection: $ratioSelection) {
                // `.ratio` sizes each column to a fraction of the table's
                // width: Name takes half, Size and Type split the rest.
                TableColumn(L("page.table.column.name"), value: \FileEntry.name)
                    .width(.ratio(0.5))
                TableColumn(L("page.table.column.size"), value: \FileEntry.size)
                    .width(.ratio(0.25))
                    .alignment(.trailing)
                TableColumn(L("page.table.column.type"), value: \FileEntry.type)
                    .width(.ratio(0.25))
            }
            .frame(height: 6)

            // Animated cells: every string below derives from `liveTick`, which
            // a `.task` loop advances four times a second — spinner frames,
            // climbing percentages and a running clock, all in plain cells.
            Text(L("page.table.liveCaption"))
                .foregroundStyle(.palette.foregroundSecondary)
            Table(TransferEntry.liveTransfers(tick: liveTick), selection: $liveSelection) {
                TableColumn(L("page.table.column.name"), value: \TransferEntry.name)
                    .width(.fit)
                TableColumn(L("page.table.column.status"), value: \TransferEntry.status)
                    .width(.flexible)
                TableColumn(L("page.table.column.elapsed"), value: \TransferEntry.elapsed)
                    .width(.fixed(8))
                    .alignment(.trailing)
            }
            .frame(height: 5)

            DemoSection(L("page.table.currentSelections")) {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow(L("page.table.single"), singleSelection ?? L("page.table.none"))
                    ValueDisplayRow(L("page.table.multi"), multiSelection.isEmpty ? L("page.table.none") : multiSelection.sorted().joined(separator: ", "))
                }
            }

            KeyboardHelpSection(
                L("page.table.navigation"),
                shortcuts: [
                    L("page.table.help.navigate"),
                    L("page.table.help.jump"),
                    L("page.table.help.fastScroll"),
                    L("page.table.help.select"),
                    L("page.table.help.switch"),
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .task {
            await runLiveTicker()
        }
        .appHeader {
            DemoAppHeader(L("page.table.title"))
        }
    }

    /// The animated-cells ticker. Cancelled automatically when the page goes
    /// away; every tick re-derives the live table's cell strings.
    private func runLiveTicker() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            liveTick += 1
        }
    }
}
