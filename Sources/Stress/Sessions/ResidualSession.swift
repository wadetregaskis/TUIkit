//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ResidualSession.swift
//
//  Rows that draw what is NOT their element. A `ForEach` row is memoized by
//  its element, so a row is right to be served only while everything it draws
//  comes from that element — and three ordinary shapes draw something else:
//
//  - an INDEX-keyed row reading `document.lines[index]`, whose key does not
//    move when the line under it is retyped, or when a line inserted above it
//    shifts every line below it along;
//  - a row computing `isSelected: item.id == selection` in the `ForEach`
//    closure, from a selection that is not part of any row;
//  - rows under a parent's `.disabled(busy)` and `.bold(busy)`, which write
//    the environment directly rather than through a noted modifier.
//
//  Today each is right because the write that changes it — an `@Observable`
//  read by the page's body, or the page's own `@State` — clears everything
//  below the page. That clear is what a value-trusting memo (Option C, or the
//  priced "trust the row keys" Option B) takes away, and when it goes these
//  are the rows that go wrong: the step-0 experiments drew the editor wrong on
//  1,494 of 1,500 frames, and a throwaway session of the third shape wrong on
//  337 of 400. This session puts all three on one page, so a change to what
//  survives an ancestor's write has its oracle before it is written: the
//  cache-cleared twin of `--verify`, and the page's own check of what the
//  model says it must show.
//
//  Above them sits a band of the shapes the reviews of Option C named since
//  (see `ResidualRows.swift`): rows holding a `Binding`, an existential, a
//  token memo; rows reading an injected object that the page swaps; buttons
//  that are whole rows; a list whose selection is bound to a model and whose
//  rows carry the page's badge; a stack whose rows off the window each read a
//  counter of their own; and, on the tasks, the page's help text and a custom
//  button style that reads a model. Every write that moves one of them is one
//  the page's body reads too, so each is right today by the same clear.
//
//  The rows say they are `Equatable`, because that is what Option C asks of a
//  row before it re-checks one: it serves an `Equatable` row whose rebuilt
//  value equals the one it drew, under an environment that has not moved, and
//  refuses every other row, drawing it again as today. Rows that were not
//  `Equatable` would all be refused, and the page would pass whatever C's
//  serve did. `residual-opaque` is the same page with the conformance taken
//  away — the rows C must leave exactly as they are.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The model

/// What the page shows: lines keyed by index, items to pick from, tasks that
/// the page can make busy, and what the band of extra rows reads.
@Observable
@MainActor
final class ResidualModel {
    /// A pickable item or a task. `Equatable`, so its row is memoized by it.
    struct Item: Identifiable, Equatable {
        let id: Int
        var title: String
    }

    var lines: [String]
    var items: [Item]
    var tasks: [Item]
    /// What the existential rows hold.
    var payloads: [any ResidualPayload]
    /// What the token-memoized rows draw, keyed by index.
    var tokens: [String]
    /// Buttons drawn as the whole of a row.
    var actions: [Item]
    /// What the pick list offers, and which of them is picked.
    var picks: [Item]
    var pick: Int?
    /// One per row of the off-window stack, each read by its row alone.
    /// ``ResidualColumns/widestCounter``'s is always the longest.
    let counters: [ResidualCounter]
    /// One per fitting row, each read only by the wide candidate its row's
    /// `ViewThatFits` measures.
    let fits: [ResidualCounter]

    init(
        lines: [String], items: [Item], tasks: [Item], payloads: [any ResidualPayload], tokens: [String],
        actions: [Item], picks: [Item], counters: [ResidualCounter], fits: [ResidualCounter]
    ) {
        self.lines = lines
        self.items = items
        self.tasks = tasks
        self.payloads = payloads
        self.tokens = tokens
        self.actions = actions
        self.picks = picks
        self.counters = counters
        self.fits = fits
    }
}

// MARK: - What the rows say they are

/// Whether the page's rows say they are `Equatable` — the one thing Option C
/// asks of a row before it re-checks it after a write above it.
///
/// A marker rather than two copies of each row: the rows are the same structs,
/// and conform only under ``EquatableRows``.
protocol ResidualRowKind {
    /// The session's id.
    static var sessionID: String { get }
    /// What the rows are, for `--sessions`.
    static var rowsSummary: String { get }
}

/// Rows that are `Equatable`: re-checked by Option C after a write above them.
enum EquatableRows: ResidualRowKind {
    static let sessionID = "residual"
    static let rowsSummary = "rows that say they are Equatable"
}

/// Rows that are not: refused by Option C, and drawn again as today.
enum OpaqueRows: ResidualRowKind {
    static let sessionID = "residual-opaque"
    static let rowsSummary = "the same rows, not Equatable"
}

// MARK: - The page

/// Where the columns sit, and how tall the band of extra rows is.
enum ResidualColumns {
    /// How wide the lines column is; the items column starts one cell after it.
    static let linesWidth = 36
    /// How wide the items column is.
    static let itemsWidth = 24
    /// How wide the band's third column is: the pick list over the stack.
    static let listsWidth = 30
    /// How many flags, payloads, tokens, swatches and action buttons there are.
    static let flags = 4
    static let payloads = 3
    static let tokens = 3
    static let swatches = 2
    static let actions = 3
    /// The band's height: its first column, the tallest.
    static let bandHeight = flags + payloads + tokens
    /// How many counters the stack holds, and which one's row is the widest,
    /// well below the window: a counter elsewhere stays below
    /// ``narrowCounters``' bound, and this one above it.
    static let counters = 40
    static let widestCounter = 30
    static let narrowCounters = 0...20
    static let wideCounter = 25...60
    /// How many fitting rows there are, and the range their counters move in:
    /// the wide candidate fits the items column up to ``fitsUpTo``.
    static let fitRows = 2
    static let fitCounter = 10...30
    static let fitsUpTo = itemsWidth - 3
    /// The help texts the page cycles the tasks through.
    static let hints = ["start it", "stop it", "skip it"]
}

/// The status lines the page draws and its check looks for.
enum ResidualStatus {
    static func main(selection: Int, busy: Bool, lines: Int) -> String {
        "#\(selection) selected · \(busy ? "busy" : "idle") · \(lines) lines"
    }

    static func extras(
        theme: String, hint: Int, badge: Int, flagsOn: Int, pick: Int?, sum: Int, angled: Bool
    ) -> String {
        "\(theme) · hint \(hint) · badge \(badge) · \(flagsOn) on · pick \(pick.map(String.init) ?? "-") · "
            + "Σ\(sum) · \(angled ? "<>" : "[]")"
    }
}

/// Two status lines over a band of extra rows and three columns: numbered
/// lines keyed by index, items with the selection marked, and tasks the page
/// disables and bolds while it is busy. `selection`, `busy`, the help text,
/// the badge, the flags and which theme is injected are the page's own
/// `@State`, moved by `j`/`k`, `b`, `h`, `g`, `f` and `t`.
struct ResidualPage<Kind: ResidualRowKind>: View {
    let model: ResidualModel
    let palette: ResidualPalette
    let themes: [ResidualTheme]
    @State private var selection = 0
    @State private var busy = false
    @State private var hint = 0
    @State private var badge = 1
    @State private var flags = [false, true, false, true]
    @State private var flagCursor = 0
    @State private var theme = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: ResidualStatus.main(selection: selection, busy: busy, lines: model.lines.count))
            Text(
                verbatim: ResidualStatus.extras(
                    theme: themes[theme].name, hint: hint, badge: badge, flagsOn: flags.count { $0 },
                    pick: model.pick, sum: (model.counters + model.fits).reduce(0) { $0 + $1.value },
                    angled: palette.angled))
            band.frame(height: ResidualColumns.bandHeight, alignment: .top)
            columns
        }
        .onKeyPress(keys: Set(["j", "k", "b", "h", "g", "f", "t"].map { Key.character($0) })) { event in
            let count = max(1, model.items.count)
            switch event.key {
            case .character("j"): selection = (selection + 1) % count
            case .character("k"): selection = (selection + count - 1) % count
            case .character("h"): hint = (hint + 1) % ResidualColumns.hints.count
            case .character("g"): badge = (badge + 1) % 4
            case .character("f"):
                flags[flagCursor].toggle()
                flagCursor = (flagCursor + 1) % flags.count
            case .character("t"): theme = (theme + 1) % themes.count
            default: busy.toggle()
            }
            return true
        }
    }

    /// The band of extra rows: what holds a `Binding`, an existential or a
    /// token memo; what reads the injected object; buttons that are rows; and
    /// the bound pick list over the stack whose rows read counters.
    private var band: some View {
        HStack(alignment: .top, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<flags.count, id: \.self) { index in
                    ResidualFlagRow<Kind>(number: index, isOn: $flags[index])
                }
                ForEach(0..<model.payloads.count, id: \.self) { index in
                    ResidualPayloadRow<Kind>(payload: model.payloads[index])
                }
                ForEach(0..<model.tokens.count, id: \.self) { index in
                    HStack(spacing: 0) {
                        Text(verbatim: ResidualText.token(index, model.tokens[index])).memoized(id: index)
                    }
                }
            }
            .frame(width: ResidualColumns.linesWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<ResidualColumns.swatches, id: \.self) { index in ResidualSwatchRow<Kind>(number: index) }
                    .environment(themes[theme])
                ForEach(model.actions) { action in Button(action.title) {} }
                ForEach(0..<model.fits.count, id: \.self) { index in
                    ResidualFitRow<Kind>(number: index, counter: model.fits[index])
                }
            }
            .frame(width: ResidualColumns.itemsWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                List(selection: Bindable(model).pick) {
                    ForEach(model.picks) { pick in ResidualPickRow<Kind>(title: pick.title).badge(badge) }
                }
                .frame(height: 5)
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<model.counters.count, id: \.self) { index in
                            ResidualCounterRow<Kind>(number: index, counter: model.counters[index])
                        }
                    }
                }
                .frame(height: ResidualColumns.bandHeight - 5)
            }
            .frame(width: ResidualColumns.listsWidth, alignment: .leading)
        }
    }

    /// The first three shapes: lines by index, the selection mark, and tasks
    /// under the page's busy, help text and custom button style.
    private var columns: some View {
        HStack(alignment: .top, spacing: 1) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<model.lines.count, id: \.self) { index in
                    LineRow<Kind>(number: index + 1, text: model.lines[index])
                }
            }
            .frame(width: ResidualColumns.linesWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.items) { item in
                    PickRow<Kind>(title: item.title, isSelected: item.id == selection)
                }
            }
            .frame(width: ResidualColumns.itemsWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.tasks) { task in TaskRow<Kind>(task: task) }
            }
            .disabled(busy)
            .bold(busy)
            .help(ResidualColumns.hints[hint])
            .buttonStyle(ResidualButtonStyle(palette: palette))
        }
    }
}

/// Labels the page and its check both spell.
enum ResidualLabels {
    /// The label a line is drawn with: its number, right-aligned in three cells.
    static func line(_ number: Int) -> String {
        let digits = String(number)
        return String(repeating: " ", count: max(0, 3 - digits.count)) + digits + " "
    }
}

/// A numbered line: whatever text is at its index now.
private struct LineRow<Kind: ResidualRowKind>: View {
    let number: Int
    let text: String

    var body: some View {
        Text(verbatim: ResidualLabels.line(number) + text)
    }
}

/// An item, marked when it is the selection.
private struct PickRow<Kind: ResidualRowKind>: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(verbatim: (isSelected ? "> " : "  ") + title)
    }
}

/// A task: its number and a button, both dimmed and bolded by the page.
private struct TaskRow<Kind: ResidualRowKind>: View {
    let task: ResidualModel.Item

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "#\(task.id)")
            Button(task.title) {}
        }
    }
}

// Every field of every row compared, as the synthesized `==` does: a row that
// equals the one drawn draws the same. Isolated, as the views are.
extension LineRow: @MainActor Equatable where Kind == EquatableRows {}
extension PickRow: @MainActor Equatable where Kind == EquatableRows {}
extension TaskRow: @MainActor Equatable where Kind == EquatableRows {}
