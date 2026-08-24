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

/// A playlist row for the drag-to-reorder demo — short, ordinary rows, so the
/// drag itself is what the section is about.
private struct Track: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    /// What the Time column SHOWS.
    let length: String
    /// What the Time column SORTS by — "5:12" sorts before "6:03" as a string
    /// too, but "10:04" would not, which is the whole point of a column that
    /// displays one property and orders by another.
    let seconds: Int

    static let playlist: [Self] = [
        Self(id: "1", title: "Aurora", artist: "Kite Season", length: "3:41", seconds: 221),
        Self(id: "2", title: "Bloom", artist: "Vela", length: "4:07", seconds: 247),
        Self(id: "3", title: "Cinder", artist: "Low Ceiling", length: "2:58", seconds: 178),
        Self(id: "4", title: "Drift", artist: "Kite Season", length: "5:12", seconds: 312),
        Self(id: "5", title: "Ember", artist: "Hollow Coast", length: "10:04", seconds: 604),
        Self(id: "6", title: "Fathom", artist: "Vela", length: "6:03", seconds: 363),
    ]
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
    @State var fixedHeightByLine = true
    @State var fixedHeightFollowMargin = FollowMarginChoice.none.rawValue
    /// Which overflow affordance the "Fixed height" table shows. The two are
    /// alternatives, not layers: a bar spends a column and the "N more
    /// above/below" lines spend a viewport line, so a view draws one or the
    /// other and one toggle picks. That is what `.scrollIndicatorStyle` is —
    /// WHICH indicator, kept separate from `.scrollIndicators`, which is
    /// WHETHER one is shown at all (both are automatic here).
    @State var fixedHeightScrollbar = true
    @State var browserURL: URL = FileBrowser.seedDirectory()
    @State var liveSelection: Int?
    /// Drives the animated-cells table: bumped by a `.task` loop (250 ms).
    @State var liveTick: Int = 0
    /// The reorder demo's selection is a SET, so several rows can travel
    /// together — grab any one of them and they all move.
    @State var playlistSelection: Set<String> = []
    @State var reorderFeedback = ReorderFeedbackChoice.live.rawValue
    /// The reorderable table's rows — `@State`, because `onMove` writes to them.
    @State fileprivate var playlist = Track.playlist
    /// The sortable table's rows. The table publishes the order it was asked
    /// for; sorting these is the app's job (see the `.onChange` below), which
    /// is SwiftUI's division of labour too.
    @State fileprivate var sortedTracks = Track.playlist
    @State fileprivate var trackSort = [KeyPathComparator(\Track.title, order: .forward)]
    @State var sortSelection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // A real file browser: single-click (or Space) selects; double-click
            // OR Return/Enter on the focused row activates it (via
            // `.onRowActivate`) — opening a folder in place; the ".." row (↰)
            // navigates up. Reads the live filesystem starting at $HOME.
            Text("page.table.fileBrowserCaption")
                .foregroundStyle(.palette.foregroundSecondary)
            Text(browserURL.path).dim()
            Table(
                FileBrowser.entries(at: browserURL),
                selection: $singleSelection
            ) {
                TableColumn("", value: \BrowserEntry.icon)
                    .width(.fixed(2))
                // `.fit` sizes the Name column to its widest entry.
                TableColumn("page.table.column.name", value: \BrowserEntry.name)
                    .width(.fit)
                TableColumn("page.table.column.size", value: \BrowserEntry.size)
                    .width(.fixed(10))
                    .alignment(.trailing)
                TableColumn("page.table.column.modified", value: \BrowserEntry.modified)
                    .width(.fixed(12))
                TableColumn("page.table.column.type", value: \BrowserEntry.typeLabel)
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
            .scrollIndicators(.visible)

            // Two multi-line tables side by side: the small original (12 rows,
            // 2-line Details) on the left demonstrates wrapping cells, and a
            // fixed-height table of hundreds of rows with pseudo-random line
            // counts on the right demonstrates scrolling — only the right one
            // is height-constrained, so only it gets the line/row toggle.
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("page.table.multiSelectionCaption")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("component.multiSelectHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Table(
                        FileEntry.sampleFiles,
                        selection: $multiSelection
                    ) {
                        TableColumn("page.table.column.name", value: \FileEntry.name)
                            .width(.fit)
                        // A narrow column with .lineLimit(2): the Details value wraps
                        // onto a second line, growing the row, and clips the rest.
                        TableColumn("page.table.column.details", value: \FileEntry.details)
                            .width(.fixed(22))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    Text("page.table.wrappingCaption")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle("demo.scrollGranularity.line", isOn: $fixedHeightByLine)
                    Toggle("page.table.useScrollbar", isOn: $fixedHeightScrollbar)
                    // How early the table scrolls to follow the moving
                    // cursor: at the edge (default), 2 lines early, or centred.
                    FollowMarginPicker(selection: $fixedHeightFollowMargin)
                    // 300 rows in a fixed 20-row viewport → it scrolls. The Note
                    // column is `.flexible` with `.lineLimit(3)`, so each row's
                    // height varies: short notes stay one line, longer ones wrap
                    // to two or three, and the tallest fold their tail with an
                    // ellipsis (plus mid-word truncation and explicit breaks).
                    Table(NoteEntry.bigNotes, selection: $notesSelection) {
                        TableColumn("#", value: \NoteEntry.index)
                            .width(.fixed(5))
                            .alignment(.trailing)
                        TableColumn("page.table.column.details", value: \NoteEntry.note)
                            .width(.flexible)
                            .lineLimit(3)
                    }
                    .frame(height: 20)
                    .scrollIndicatorStyle(fixedHeightScrollbar ? .scrollbar : .text)
                    .scrollGranularity(fixedHeightByLine ? .line : .row)
                    .scrollFollowMargin(
                        FollowMarginChoice(rawValue: fixedHeightFollowMargin)?.margin ?? .none)
                }
                .frame(maxWidth: .infinity)
            }

            // Directly under the two tables it reports on — the file browser
            // above and the multi-selection table beside it. It used to sit at
            // the foot of the page, half a dozen demos away from either, where
            // there was no way to tell what it was reporting.
            DemoSection("page.table.currentSelections") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("page.table.single", singleSelection ?? L("page.table.none"))
                    ValueDisplayRow("page.table.multi", multiSelection.isEmpty ? L("page.table.none") : multiSelection.sorted().joined(separator: ", "))
                }
            }

            Text("page.table.ratioCaption")
                .foregroundStyle(.palette.foregroundSecondary)
            Table(FileEntry.sampleFiles, selection: $ratioSelection) {
                // `.ratio` sizes each column to a fraction of the table's
                // width: Name takes half, Size and Type split the rest.
                TableColumn("page.table.column.name", value: \FileEntry.name)
                    .width(.ratio(0.5))
                TableColumn("page.table.column.size", value: \FileEntry.size)
                    .width(.ratio(0.25))
                    .alignment(.trailing)
                TableColumn("page.table.column.type", value: \FileEntry.type)
                    .width(.ratio(0.25))
            }
            .frame(height: 6)

            // Animated cells: every string below derives from `liveTick`, which
            // a `.task` loop advances four times a second — spinner frames,
            // climbing percentages and a running clock, all in plain cells.
            Text("page.table.liveCaption")
                .foregroundStyle(.palette.foregroundSecondary)
            Table(TransferEntry.liveTransfers(tick: liveTick), selection: $liveSelection) {
                TableColumn("page.table.column.name", value: \TransferEntry.name)
                    .width(.fit)
                TableColumn("page.table.column.status", value: \TransferEntry.status)
                    .width(.flexible)
                TableColumn("page.table.column.elapsed", value: \TransferEntry.elapsed)
                    .width(.fixed(8))
                    .alignment(.trailing)
            }
            .frame(height: 6)

            // Drag-to-reorder, the Table half of the Lists page's `.onMove`
            // section: same state machine, same feedback modes, and here the
            // modifier goes on the Table (its rows are values, not views, so
            // there is no ForEach to hang it on).
            DemoSection("page.table.sortSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.table.sortInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Table(sortedTracks, selection: $sortSelection, sortOrder: $trackSort) {
                        TableColumn("page.table.column.track", value: \Track.title)
                            .width(.fit)
                        TableColumn("page.table.column.artist", value: \Track.artist)
                            .width(.flexible)
                        // Shows the "m:ss" string, orders by the Int behind it.
                        TableColumn("page.table.column.length", value: \Track.seconds) {
                            $0.length
                        }
                        .width(.fixed(9))
                        .alignment(.trailing)
                    }
                    .frame(height: 8)
                    .onChange(of: trackSort, initial: true) {
                        sortedTracks.sort(using: trackSort)
                    }
                }
            }

            DemoSection("page.table.reorderSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.table.reorderInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.rows.keyboardMoveHint")
                        .foregroundStyle(.palette.foregroundTertiary)
                        .dim()
                    Picker("page.list.reorderFeedback", selection: $reorderFeedback) {
                        ForEach(ReorderFeedbackChoice.allCases, id: \.rawValue) { choice in
                            Text(choice.label).tag(choice.rawValue)
                        }
                    }
                    Table(playlist, selection: $playlistSelection) {
                        TableColumn("page.table.column.track", value: \Track.title)
                            .width(.fit)
                        TableColumn("page.table.column.artist", value: \Track.artist)
                            .width(.flexible)
                        TableColumn("page.table.column.length", value: \Track.length)
                            .width(.fixed(6))
                            .alignment(.trailing)
                    }
                    .onMove { playlist.move(fromOffsets: $0, toOffset: $1) }
                    .frame(height: 8)
                    .rowReorderFeedback(
                        ReorderFeedbackChoice(rawValue: reorderFeedback)?.feedback ?? .live)
                }
            }

            KeyboardHelpSection(
                "page.table.navigation",
                shortcuts: [
                    "page.table.help.navigate",
                    "page.table.help.jump",
                    "page.table.help.fastScroll",
                    "page.table.help.select",
                    "page.table.help.switch",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .task {
            await runLiveTicker()
        }
        .appHeader {
            DemoAppHeader("menu.item.tables")
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
