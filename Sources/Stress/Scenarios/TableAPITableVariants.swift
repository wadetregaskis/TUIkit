//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableAPITableVariants.swift
//
//  The TABLE-level axes of the API matrix: how rows are laid out, what the
//  table is bound to, how its data moves, and what surrounds it.
//  See `TableAPIMatrix.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

// MARK: - Row layout

extension TableAPIMatrix {

    /// Line limits, alignments and column spacing: the settings that change
    /// what a drawn row IS rather than what is in it.
    ///
    /// The line limit is the one that changes the algorithm and not just the
    /// arithmetic — a table whose rows can span more than one line meters its
    /// scrollbar in LINES, which means asking rows outside the viewport how tall
    /// they are, which means wrapping their text. Everything about a multi-line
    /// table's frame cost follows from that.
    static var layoutVariants: [ScenarioVariant] {
        [
            variant("lines-wrapped", axis: "layout", "a three-line column, so the scrollbar is metered in lines") { config in
                table("lines-wrapped", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(20))
                        TableColumn("Summary", value: \APIRow.summary).lineLimit(3)
                    }
                }
            },

            // Columns of different heights in the same row: the row is as tall
            // as its tallest column, so every column is padded to a height it
            // did not ask for and the composer cannot take a single-line path.
            variant("lines-mixed", axis: "layout", "columns with line limits 1, 2 and 4 in one row") { config in
                table("lines-mixed", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(18)).lineLimit(2)
                        TableColumn("Summary", value: \APIRow.summary).lineLimit(4)
                        TableColumn("Status", value: \APIRow.status).width(.fixed(10))
                    }
                }
            },

            variant("align-trailing", axis: "layout", "every column trailing-aligned — the pad goes in front") { config in
                table("align-trailing", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(9)).alignment(.trailing)
                        TableColumn("Size", value: \APIRow.size).width(.fixed(12)).alignment(.trailing)
                        TableColumn("Score", value: \APIRow.index).width(.fixed(9)).alignment(.trailing)
                        TableColumn("Name", value: \APIRow.name).alignment(.trailing)
                    }
                }
            },

            variant("align-mixed", axis: "layout", "leading, centre and trailing columns together") { config in
                table("align-mixed", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7)).alignment(.trailing)
                        TableColumn("Status", value: \APIRow.status).width(.fixed(12)).alignment(.center)
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Load", value: \APIRow.bar).width(.fixed(10)).alignment(.center)
                        TableColumn("Size", value: \APIRow.size).width(.fixed(12)).alignment(.trailing)
                    }
                }
            },

            // `columnSpacing: 0` — the columns abut. Worth a point of its own
            // because the spacing is what separates one cell's trailing pad from
            // the next cell's first byte, and a clip that leaves SGR open shows
            // up here and nowhere else.
            variant("spacing-none", axis: "layout", "columnSpacing 0 — cells abut, styled runs meet") { config in
                table("spacing-none", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil), columnSpacing: 0) {
                        TableColumn("Status", value: \APIRow.status).width(.fixed(12))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(20))
                        TableColumn("Status2", value: \APIRow.status).width(.fixed(12))
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            variant("spacing-wide", axis: "layout", "columnSpacing 6 — a third of the line is separator") { config in
                table("spacing-wide", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil), columnSpacing: 6) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Slug", value: \APIRow.slug)
                        TableColumn("Status", value: \APIRow.status)
                    }
                }
            },
        ]
    }
}

// MARK: - What the table is bound to

extension TableAPIMatrix {

    /// Selection, sorting and the disabled state — the bindings, and what each
    /// costs per drawn row.
    ///
    /// Each is a distinct per-row question: single selection compares one id,
    /// multi-selection probes a `Set`, and a sorted table re-orders its whole
    /// collection before anything is drawn at all. The no-binding table is here
    /// as the control, since it is the only one that draws no selection gutter.
    static var interactionVariants: [ScenarioVariant] {
        [
            variant("select-none", axis: "interaction", "no selection binding at all — no gutter is reserved") { config in
                table("select-none", config) { rows in
                    Table(rows) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            variant("select-single", axis: "interaction", "a live single-selection binding with a row selected") { config in
                AnyView(SingleSelectionTable(count: count(config)))
            },

            // A `Set` probed once per drawn row, and — the part that matters —
            // a selection large enough that most drawn rows ARE selected, so the
            // selected-row styling path runs for most of the viewport rather
            // than once.
            variant("select-multi", axis: "interaction", "multi-selection with a third of the rows selected") { config in
                AnyView(MultiSelectionTable(count: count(config)))
            },

            // The app sorts; the table publishes the order it was asked for.
            // That is SwiftUI's division of labour and TUIkit's, and it means a
            // live sorted table re-sorts its whole collection on every snapshot
            // — O(n log n) key-path comparisons before a single row is drawn.
            variant("sorted", axis: "interaction", "a sort binding, with the app re-sorting every frame") { config in
                AnyView(SortedTable(count: min(count(config), 5_000)))
            },

            variant("disabled", axis: "interaction", "a disabled table — out of the focus ring entirely") { config in
                table("disabled", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                    .disabled(true)
                }
            },
        ]
    }
}

// MARK: - How the data moves

extension TableAPIMatrix {

    /// The update patterns, with the columns and everything else held at the
    /// default. `churn-fraction` is what every other variant here runs at, so
    /// these three are its neighbours: nothing changing, everything changing,
    /// and everything moving without changing.
    static var churnVariants: [ScenarioVariant] {
        [
            variant("churn-none", axis: "churn", "data built once and never changed") { config in
                stillTable("churn-none", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Status", value: \APIRow.status)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            variant("churn-all", axis: "churn", "every row differs every frame — the memo ceiling") { config in
                table("churn-all", config, churn: .all) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Status", value: \APIRow.status)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            // The log-tailing shape: nothing changes content, everything changes
            // position. A memo keyed by a row's POSITION serves none of this
            // while looking correct; one keyed by its identity serves all of it.
            variant("churn-tail", axis: "churn", "a window over a growing sequence — rows move, content does not") { config in
                table("churn-tail", config, churn: .tail) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("Seq", value: \APIRow.index).width(.fixed(9))
                        TableColumn("Source", value: \APIRow.slug)
                        TableColumn("Level", value: \APIRow.status)
                        TableColumn("Message", value: \APIRow.summary)
                    }
                }
            },
        ]
    }
}

// MARK: - Size, chrome and surroundings

extension TableAPIMatrix {

    /// How big the table is, what indicator it wears, and what it is nested in.
    ///
    /// The sizes are not a smooth axis: 250 wrapped rows is the most expensive
    /// per-frame shape a `Table` has, because at or below the extent
    /// estimator's row limit EVERY row is measured — the 300-row table beside it
    /// samples 64 and is an order of magnitude cheaper. A size sweep that
    /// stepped 100, 1,000, 10,000 would step straight over it.
    static var shapeVariants: [ScenarioVariant] {
        [
            variant("size-tiny", axis: "shape", "twelve rows — everything on screen, nothing to scroll") { config in
                stillTable("size-tiny", config, count: 12) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            variant("size-wrapped-250", axis: "shape", "250 wrapped rows — below the estimator's limit, so every row is measured") { config in
                // NOT `config.sized(…)`: the whole point is the side of the
                // 256-row limit this sits on, and a scale multiplier would move
                // it to the other one.
                table("size-wrapped-250", config, count: 250) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(20))
                        TableColumn("Summary", value: \APIRow.summary).lineLimit(3)
                    }
                }
            },

            variant("size-wrapped-1000", axis: "shape", "1,000 wrapped rows — above the limit, so 64 are sampled") { config in
                table("size-wrapped-1000", config, count: 1_000) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(20))
                        TableColumn("Summary", value: \APIRow.summary).lineLimit(3)
                    }
                }
            },

            variant("size-huge", axis: "shape", "100,000 static rows, a 35-row window") { config in
                stillTable("size-huge", config, count: config.sized(100_000)) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(9))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Status", value: \APIRow.status)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            variant("empty", axis: "shape", "no rows — the placeholder path") { config in
                stillTable("empty", config, count: 0) { rows in
                    // The placeholder is an INIT parameter here rather than the
                    // modifier the architecture rules ask for — noted for the
                    // owner, and written the way the API currently reads.
                    Table(rows, selection: Binding<Int?>.constant(nil), emptyPlaceholder: "nothing here") {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                    }
                }
            },

            // `.exact` re-measures every row every frame, by its own
            // documentation, and is the one precision that is never cached. On a
            // wrapped table of 1,000 rows that is a thousand wraps a frame to
            // place a thumb — which is the bargain the mode exists to offer, and
            // wants measuring so the price stays known.
            variant("precision-exact", axis: "shape", "wrapped rows with .scrollExtentPrecision(.exact)") { config in
                table("precision-exact", config, count: 1_000) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(20))
                        TableColumn("Summary", value: \APIRow.summary).lineLimit(3)
                    }
                    .scrollExtentPrecision(.exact)
                }
            },

            variant("chrome-text", axis: "shape", "\"N more below\" text indicators instead of a scrollbar") { config in
                table("chrome-text", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                    .scrollIndicatorStyle(.text)
                }
            },

            variant("chrome-hidden", axis: "shape", "no scroll indicator at all") { config in
                table("chrome-hidden", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                    .scrollIndicators(.hidden)
                }
            },

            // Padded and bordered, which is how a table appears in a real
            // layout: the border measures the table at one width and renders it
            // at another, so anything keyed on the width is asked two questions
            // per frame rather than one.
            variant("padded-bordered", axis: "shape", "inside padding and a border") { config in
                table("padded-bordered", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                    .padding()
                    .border()
                }
            },

            // A table inside a ScrollView: the table is given unbounded height,
            // so it draws EVERY row and the outer view does the windowing. The
            // shape that turns a 35-row frame into a 500-row one, and the one an
            // app writes by accident.
            variant("in-scrollview", axis: "shape", "a 500-row table inside a ScrollView — no windowing") { config in
                table("in-scrollview", config, count: 500) { rows in
                    ScrollView {
                        Table(rows, selection: Binding<Int?>.constant(nil)) {
                            TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                            TableColumn("Name", value: \APIRow.name)
                            TableColumn("Summary", value: \APIRow.summary)
                        }
                    }
                }
            },
        ]
    }
}

// MARK: - The bound tables

/// A live single-selection binding, with a row selected.
private struct SingleSelectionTable: View {
    let count: Int
    @State private var selection: Int? = 3
    @Environment(StressClock.self) private var clock

    var body: some View {
        let rows = APIChurn.fraction(apiChurnPeriod).rows(count: count, tick: clock.tick)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-api.heading", "select-single", count)).bold()
            Divider()
            Table(rows, selection: $selection) {
                TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                TableColumn("Name", value: \APIRow.name)
                TableColumn("Status", value: \APIRow.status)
                TableColumn("Summary", value: \APIRow.summary)
            }
        }
    }
}

/// Multi-selection with a third of the table selected, so most drawn rows wear
/// the selected styling rather than one of them.
private struct MultiSelectionTable: View {
    let count: Int
    @State private var selection: Set<Int>
    @Environment(StressClock.self) private var clock

    init(count: Int) {
        self.count = count
        self.selection = Set(stride(from: 0, to: count, by: 3))
    }

    var body: some View {
        let rows = APIChurn.fraction(apiChurnPeriod).rows(count: count, tick: clock.tick)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-api.heading", "select-multi", count)).bold()
            Divider()
            Table(rows, selection: $selection) {
                TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                TableColumn("Name", value: \APIRow.name)
                TableColumn("Status", value: \APIRow.status)
                TableColumn("Summary", value: \APIRow.summary)
            }
        }
    }
}

/// A sort binding, with the app doing the sorting — every frame, because a live
/// table's snapshot arrives unsorted.
private struct SortedTable: View {
    let count: Int
    @State private var selection: Int?
    @State private var order: [KeyPathComparator<APIRow>] = [KeyPathComparator(\APIRow.score)]
    @Environment(StressClock.self) private var clock

    var body: some View {
        var rows = APIChurn.fraction(apiChurnPeriod).rows(count: count, tick: clock.tick)
        rows.sort(using: order)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.table-api.heading", "sorted", count)).bold()
            Divider()
            Table(rows, selection: $selection, sortOrder: $order) {
                TableColumn("ID", value: \APIRow.id) { "\($0.id)" }.width(.fixed(7))
                TableColumn("Name", value: \APIRow.name)
                TableColumn("Score", value: \APIRow.score) { "\($0.score)" }
                    .width(.fixed(8)).alignment(.trailing)
                TableColumn("Summary", value: \APIRow.summary)
            }
        }
    }
}
