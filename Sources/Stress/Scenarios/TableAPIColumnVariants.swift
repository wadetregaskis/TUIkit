//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableAPIColumnVariants.swift
//
//  The COLUMN axes of the Table API matrix: how a column gets its value, how
//  wide it is, and what it holds. See `TableAPIMatrix.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - How a column gets its value

extension TableAPIMatrix {

    /// The value-supply axis: the five initializers `TableColumn` has, and the
    /// three row types a table can be built over.
    ///
    /// The first entry is the matrix's default, and deliberately the shape a
    /// memo can do the most with: every column names a property, so a row that
    /// compares equal to last frame's provably draws the same text. Each later
    /// entry removes one thing from that — a closure column, a row that cannot
    /// be compared, a row whose equality is its address — and the difference
    /// between their frame times IS the memo's reach.
    static var dataVariants: [ScenarioVariant] {
        [
            variant("keypath", axis: "data", "every column names a property (KeyPath<Value, String>)") { config in
                table("keypath", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Slug", value: \APIRow.slug)
                        TableColumn("Status", value: \APIRow.status)
                        TableColumn("Summary", value: \APIRow.summary)
                        TableColumn("Load", value: \APIRow.bar).width(.fixed(10))
                    }
                }
            },

            variant("closure", axis: "data", "every column computes its value in a closure") { config in
                table("closure", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID") { (row: APIRow) in row.index }.width(.fixed(7))
                        TableColumn("Name") { (row: APIRow) in row.name }
                        TableColumn("Slug") { (row: APIRow) in row.slug }
                        TableColumn("Status") { (row: APIRow) in row.status }
                        TableColumn("Summary") { (row: APIRow) in row.summary }
                        TableColumn("Load") { (row: APIRow) in row.bar }.width(.fixed(10))
                    }
                }
            },

            // One closure among five key paths, because a table is only as
            // memoisable as its least specific column: the closure could read
            // anything, so nothing about the ROW can settle whether the ROW's
            // text is unchanged. What is left is comparing what the columns
            // produced, which this variant is the measurement of.
            variant("mixed-columns", axis: "data", "five key-path columns and one closure") { config in
                table("mixed-columns", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Slug", value: \APIRow.slug)
                        TableColumn("Status", value: \APIRow.status)
                        TableColumn("Summary") { (row: APIRow) in row.summary }
                        TableColumn("Load", value: \APIRow.bar).width(.fixed(10))
                    }
                }
            },

            // `TableColumn(_:value:content:)`: sorts by one property, displays
            // another. The overload an app reaches for whenever a column's
            // display form is not its sort form — a size shown as "4.2 KB" that
            // orders by its byte count — and the one whose `sortComparator` is
            // NOT evidence that the column names its value.
            variant("sortable-content", axis: "data", "columns that sort by a property and display a formatted string") { config in
                table("sortable-content", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.id) { "\($0.id)" }.width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name)
                        TableColumn("Score", value: \APIRow.score) { "\($0.score)" }
                            .width(.fixed(7)).alignment(.trailing)
                        TableColumn("Size", value: \APIRow.bytes) { $0.size }
                            .width(.fixed(10)).alignment(.trailing)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            // `Table` requires `Identifiable`, not `Equatable`. A row that
            // cannot be compared is the honest common case (a model struct with
            // a closure or an existential in it), and anything keyed on rows has
            // to fall back to what they PRODUCED.
            variant("opaque-rows", axis: "data", "rows with no Equatable conformance") { config in
                let count = self.count(config)
                return AnyView(
                    APIFrame(
                        variant: "opaque-rows", count: count, observesClock: true,
                        rows: { tick in
                            (0..<count).map {
                                APIOpaqueRow(
                                    id: $0,
                                    generation: (tick &+ apiChurnPeriod &- 1 &- $0 % apiChurnPeriod)
                                        / apiChurnPeriod)
                            }
                        },
                        content: { rows in
                            Table(rows, selection: Binding<Int?>.constant(nil)) {
                                TableColumn("ID", value: \APIOpaqueRow.index).width(.fixed(7))
                                TableColumn("Name", value: \APIOpaqueRow.name)
                                TableColumn("Summary", value: \APIOpaqueRow.summary)
                            }
                        }))
            },

            // Reference-type rows: identity is still the `id`, but a fresh
            // object per frame is never `===` last frame's, so anything that
            // reached for reference equality serves nothing while looking right.
            variant("class-rows", axis: "data", "rows that are class instances, rebuilt each frame") { config in
                let count = self.count(config)
                return AnyView(
                    APIFrame(
                        variant: "class-rows", count: count, observesClock: true,
                        rows: { tick in
                            (0..<count).map {
                                APIClassRow(
                                    id: $0,
                                    generation: (tick &+ apiChurnPeriod &- 1 &- $0 % apiChurnPeriod)
                                        / apiChurnPeriod)
                            }
                        },
                        content: { rows in
                            Table(rows, selection: Binding<Int?>.constant(nil)) {
                                TableColumn("ID", value: \APIClassRow.index).width(.fixed(7))
                                TableColumn("Name", value: \APIClassRow.name)
                                TableColumn("Summary", value: \APIClassRow.summary)
                            }
                        }))
            },
        ]
    }
}

// MARK: - How wide a column is

extension TableAPIMatrix {

    /// The four ``ColumnWidth`` modes plus the mixture an app actually writes.
    ///
    /// `.flexible` is the baseline (`keypath` above); the rest are here because
    /// they are not merely different arithmetic. `.fit` is O(rows) — it scans
    /// every cell in the column, on every frame, to find the widest — which is
    /// the single most expensive thing a column declaration can do, and the
    /// only width mode whose cost grows with data the viewport never shows.
    static var widthVariants: [ScenarioVariant] {
        [
            variant("width-fixed", axis: "width", "every column a fixed width") { config in
                table("width-fixed", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Name", value: \APIRow.name).width(.fixed(20))
                        TableColumn("Slug", value: \APIRow.slug).width(.fixed(18))
                        TableColumn("Status", value: \APIRow.status).width(.fixed(10))
                        TableColumn("Summary", value: \APIRow.summary).width(.fixed(40))
                    }
                }
            },

            variant("width-ratio", axis: "width", "every column a ratio of the available width") { config in
                table("width-ratio", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.ratio(0.08))
                        TableColumn("Name", value: \APIRow.name).width(.ratio(0.2))
                        TableColumn("Slug", value: \APIRow.slug).width(.ratio(0.17))
                        TableColumn("Status", value: \APIRow.status).width(.ratio(0.15))
                        TableColumn("Summary", value: \APIRow.summary).width(.ratio(0.4))
                    }
                }
            },

            // The O(rows) one. Every `.fit` column asks every row for its value
            // and measures it, so this variant's frame cost is dominated by rows
            // that are never drawn — and it is the shape where a memo over the
            // fitted widths is worth more than one over the drawn rows.
            variant("width-fit", axis: "width", "every column sized to fit its content (O(rows) per column)") { config in
                table("width-fit", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fit)
                        TableColumn("Name", value: \APIRow.name).width(.fit)
                        TableColumn("Status", value: \APIRow.status).width(.fit)
                        TableColumn("Load", value: \APIRow.bar).width(.fit)
                        TableColumn("Summary", value: \APIRow.summary)
                    }
                }
            },

            variant("width-mixed", axis: "width", "fixed, fit, ratio and flexible columns in one table") { config in
                table("width-mixed", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Status", value: \APIRow.status).width(.fit)
                        TableColumn("Name", value: \APIRow.name).width(.ratio(0.25))
                        TableColumn("Summary", value: \APIRow.summary)
                        TableColumn("Load", value: \APIRow.bar).width(.fixed(10))
                    }
                }
            },

            // Ten columns of five cells each: the table is mostly chrome, and
            // every drawn line crosses nine column boundaries. Wide tables are
            // where per-column work (the spacing joins, the pad, the SGR carried
            // across a boundary) stops being a rounding error.
            variant("width-many", axis: "width", "ten narrow columns — mostly boundaries") { config in
                table("width-many", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("#", value: \APIRow.index).width(.fixed(5))
                        TableColumn("A", value: \APIRow.status).width(.fixed(5))
                        TableColumn("B", value: \APIRow.slug).width(.fixed(5))
                        TableColumn("C", value: \APIRow.name).width(.fixed(5))
                        TableColumn("D", value: \APIRow.summary).width(.fixed(5))
                        TableColumn("E", value: \APIRow.bar).width(.fixed(5))
                        TableColumn("F", value: \APIRow.index).width(.fixed(5))
                        TableColumn("G", value: \APIRow.status).width(.fixed(5))
                        TableColumn("H", value: \APIRow.slug).width(.fixed(5))
                        TableColumn("I", value: \APIRow.name).width(.fixed(5))
                    }
                }
            },
        ]
    }
}

// MARK: - What a cell holds

extension TableAPIMatrix {

    /// The cell-content axis: what the string a column hands back costs to
    /// produce, and what it costs to MEASURE and clip once produced.
    ///
    /// These are two different costs and they move independently. A formatted
    /// byte count is expensive to build and trivially ASCII to measure; a line
    /// of emoji is cheap to build and takes the per-cluster width path; a styled
    /// cell is cheap and short but declines every byte-wise fast path in the
    /// clip. A corpus whose cells are all `"\(index)"` measures none of it.
    static var textVariants: [ScenarioVariant] {
        [
            variant("text-cheap", axis: "text", "cells are interpolated integers — the cheapest possible") { config in
                table("text-cheap", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(9))
                        TableColumn("Score", value: \APIRow.index).width(.fixed(9))
                        TableColumn("Also", value: \APIRow.index).width(.fixed(9))
                        TableColumn("Again", value: \APIRow.index)
                    }
                }
            },

            // `Double.formatted(.byteCount)` and `Date.formatted` — what an app
            // shows, not a stand-in for it. Foundation's formatters are orders
            // of magnitude more expensive than anything else in a cell, which
            // makes this the variant where NOT rebuilding a row is worth most.
            variant("text-formatted", axis: "text", "cells built by Foundation formatters (byte count, date)") { config in
                table("text-formatted", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Size", value: \APIRow.size).width(.fixed(12)).alignment(.trailing)
                        TableColumn("Modified", value: \APIRow.stamp).width(.fixed(22))
                        TableColumn("Name", value: \APIRow.name)
                    }
                }
            },

            variant("text-styled", axis: "text", "every cell carries SGR, so no byte-wise clip applies") { config in
                table("text-styled", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("A", value: \APIRow.status)
                        TableColumn("B", value: \APIRow.status)
                        TableColumn("C", value: \APIRow.status)
                        TableColumn("D", value: \APIRow.status)
                    }
                }
            },

            variant("text-wide", axis: "text", "CJK and emoji cells — every width question goes per-cluster") { config in
                table("text-wide", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("ID", value: \APIRow.index).width(.fixed(7))
                        TableColumn("Glyphs", value: \APIRow.glyphs).width(.fixed(14))
                        TableColumn("More", value: \APIRow.glyphs).width(.fixed(9))
                        TableColumn("Name", value: \APIRow.name)
                    }
                }
            },

            // Roughly a fifth of what is measured survives the clip, which is
            // where a walk that scans the whole string to produce a short prefix
            // costs the most — the shape the user profile that started all this
            // was of.
            variant("text-overlong", axis: "text", "~90-cell sentences in ~18-cell columns") { config in
                table("text-overlong", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("One", value: \APIRow.summary)
                        TableColumn("Two", value: \APIRow.summary)
                        TableColumn("Three", value: \APIRow.summary)
                        TableColumn("Four", value: \APIRow.summary)
                        TableColumn("Five", value: \APIRow.summary)
                        TableColumn("Six", value: \APIRow.summary)
                    }
                }
            },

            variant("trunc-head", axis: "text", "every column truncates from the head") { config in
                table("trunc-head", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("One", value: \APIRow.summary).truncationMode(.head)
                        TableColumn("Two", value: \APIRow.summary).truncationMode(.head)
                        TableColumn("Three", value: \APIRow.summary).truncationMode(.head)
                        TableColumn("Four", value: \APIRow.summary).truncationMode(.head)
                    }
                }
            },

            // `.middle` clips from both ends, so it is the mode that walks the
            // string twice and the one a fast path is likeliest to miss.
            variant("trunc-middle", axis: "text", "every column truncates in the middle (two walks)") { config in
                table("trunc-middle", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("One", value: \APIRow.summary).truncationMode(.middle)
                        TableColumn("Two", value: \APIRow.summary).truncationMode(.middle)
                        TableColumn("Three", value: \APIRow.summary).truncationMode(.middle)
                        TableColumn("Four", value: \APIRow.summary).truncationMode(.middle)
                    }
                }
            },

            variant("trunc-mixed", axis: "text", "tail, head and middle truncation, plus a styled column") { config in
                table("trunc-mixed", config) { rows in
                    Table(rows, selection: Binding<Int?>.constant(nil)) {
                        TableColumn("Tail", value: \APIRow.summary)
                        TableColumn("Head", value: \APIRow.summary).truncationMode(.head)
                        TableColumn("Middle", value: \APIRow.summary).truncationMode(.middle)
                        TableColumn("Styled", value: \APIRow.status)
                        TableColumn("Wide", value: \APIRow.glyphs).truncationMode(.middle)
                    }
                }
            },
        ]
    }
}
