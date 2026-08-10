//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableColumnBuilderTests.swift
//
//  A column list is a result builder, so it has to accept the control flow one
//  looks like it accepts: an `if`, an `if`/`else`, a loop, a computed group.
//  It did not — `buildEither` and friends yielded arrays that the variadic
//  `buildBlock` could not take back, so a conditional column failed to compile
//  however plausible the methods looked. These pin each shape by USING it: the
//  test file would not build if the builder regressed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table column builder")
struct TableColumnBuilderTests {

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
        let size: String
        let kind: String
    }

    private static let rows = [
        Row(id: 1, name: "alpha", size: "1 KB", kind: "text"),
        Row(id: 2, name: "bravo", size: "2 KB", kind: "data"),
    ]

    /// The column titles a table ends up with, read off its rendered header.
    private func headerTitles(of table: Table<Row>) -> [String] {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 60, availableHeight: 8, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(table, context: context)
        guard buffer.lines.count > 1 else { return [] }
        // The header line arrives inside the container's border columns.
        return buffer.lines[1].stripped
            .split(separator: " ")
            .map(String.init)
            .filter { $0 != "│" }
    }

    @Test("An if with no else contributes its column only when the condition holds")
    func optionalColumn() {
        func table(showingKind: Bool) -> Table<Row> {
            Table(Self.rows, selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name)
                if showingKind {
                    TableColumn("Kind", value: \Row.kind)
                }
            }
        }
        #expect(headerTitles(of: table(showingKind: true)) == ["Name", "Kind"])
        #expect(headerTitles(of: table(showingKind: false)) == ["Name"])
    }

    @Test("An if/else picks one branch's columns")
    func eitherColumn() {
        func table(detailed: Bool) -> Table<Row> {
            Table(Self.rows, selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name)
                if detailed {
                    TableColumn("Size", value: \Row.size)
                    TableColumn("Kind", value: \Row.kind)
                } else {
                    TableColumn("Kind", value: \Row.kind)
                }
            }
        }
        #expect(headerTitles(of: table(detailed: true)) == ["Name", "Size", "Kind"])
        #expect(headerTitles(of: table(detailed: false)) == ["Name", "Kind"])
    }

    @Test("A loop contributes one column per iteration")
    func loopColumns() {
        let table = Table(Self.rows, selection: .constant(Int?.none)) {
            for title in ["Name", "Size", "Kind"] {
                TableColumn(title, value: { (row: Row) in
                    switch title {
                    case "Name": return row.name
                    case "Size": return row.size
                    default: return row.kind
                    }
                })
            }
        }
        #expect(headerTitles(of: table) == ["Name", "Size", "Kind"])
    }

    /// A group computed outside the builder — the shape a caller reaches for
    /// when several tables share a set of columns.
    @Test("A computed array of columns can be spliced in")
    func computedGroup() {
        let shared = [
            TableColumn("Size", value: \Row.size),
            TableColumn("Kind", value: \Row.kind),
        ]
        let table = Table(Self.rows, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Row.name)
            shared
        }
        #expect(headerTitles(of: table) == ["Name", "Size", "Kind"])
    }

    /// The plain case, which must keep working exactly as before. (Moved
    /// here from `TableTests`, which held the only builder test there was.)
    @Test("A straight list of columns is unaffected")
    func plainList() {
        let table = Table(Self.rows, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Size", value: \Row.size)
            TableColumn("Kind", value: \Row.kind)
        }
        #expect(headerTitles(of: table) == ["Name", "Size", "Kind"])
    }

    /// Conditionals nest, and an empty branch really contributes nothing.
    @Test("Nested conditionals compose, and an empty branch adds no column")
    func nestedConditionals() {
        func table(outer: Bool, inner: Bool) -> Table<Row> {
            Table(Self.rows, selection: .constant(Int?.none)) {
                TableColumn("Name", value: \Row.name)
                if outer {
                    if inner {
                        TableColumn("Size", value: \Row.size)
                    }
                    TableColumn("Kind", value: \Row.kind)
                }
            }
        }
        #expect(headerTitles(of: table(outer: true, inner: true)) == ["Name", "Size", "Kind"])
        #expect(headerTitles(of: table(outer: true, inner: false)) == ["Name", "Kind"])
        #expect(headerTitles(of: table(outer: false, inner: true)) == ["Name"])
    }
}
