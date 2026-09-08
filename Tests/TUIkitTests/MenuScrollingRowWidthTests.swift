//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuScrollingRowWidthTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// A menu that scrolls draws its rows into one cell less than a menu that hugs:
/// the `ScrollView` the scrolled arm inserts reserves a trailing column for its
/// bar. The row width handed down has to say so, and it did not — every row was
/// told a cell it did not have, so the border clipped the last of them.
///
/// The visible casualty is the key equivalent, which is the only thing that lives
/// at a menu row's trailing edge. It vanished the moment a menu grew past its cap
/// — from TWO causes at once, which is why this suite pins the geometry and not
/// just its presence: the row was a cell too wide, AND the shortcut's claim was
/// refused to the render because the scrolled arm lays the rows out at different
/// identities than the arm the plan measured (see `KeyboardShortcutAssignment`).
///
/// Pinned against the same menu at two heights, because neither picture says
/// anything alone: the hugging arm is right and the scrolled one was a cell out,
/// and only the pair says which.
@MainActor
@Suite("A scrolling menu's rows give up the scrollbar's column, and nothing else")
struct MenuScrollingRowWidthTests {

    /// Every row carries a one-character key equivalent — the smallest thing that
    /// sits at a row's trailing edge, so the first casualty of a row drawn one
    /// cell too wide. Six rows against an eight-row slot is the overflow.
    @ViewBuilder
    private var items: some View {
        Button("Rename") {}.keyboardShortcut("r", modifiers: [])
        Button("Duplicate") {}.keyboardShortcut("d", modifiers: [])
        Button("Move to…") {}.keyboardShortcut("m", modifiers: [])
        Button("Export as PDF") {}.keyboardShortcut("e", modifiers: [])
        Button("Compress") {}.keyboardShortcut("c", modifiers: [])
        Button("Delete", role: .destructive) {}.keyboardShortcut("x", modifiers: [])
    }

    /// The menu is 21 cells wide at this width, whichever arm it takes, so the
    /// column indices below are directly comparable between the two.
    private func lines(height: Int, configure: (inout EnvironmentValues) -> Void = { _ in })
        -> [String]
    {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        configure(&environment)
        let context = RenderContext(
            availableWidth: 30, availableHeight: height, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(
            Menu("Actions") { items }.menuStyle(.inline), context: context)
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    /// Which column `hint` was drawn in on the row carrying `label`, or nil if
    /// that row does not carry it at all.
    ///
    /// Searched from the END, because the hint lives at the row's trailing edge
    /// and the same letter may well appear in the label.
    private func hintColumn(_ hint: Character, on label: String, in lines: [String]) -> Int? {
        guard let row = lines.first(where: { $0.contains(label) }) else { return nil }
        return Array(row).lastIndex(of: hint)
    }

    /// The hugging control: all six rows fit, and each hint is drawn in the
    /// column the interior's trailing padding leaves it.
    @Test("Hugging: every row's key equivalent is drawn in the trailing column")
    func hintsDrawnWhenHugging() {
        let drawn = lines(height: 20)
        for (hint, label) in [
            (Character("r"), "Rename"), ("d", "Duplicate"), ("m", "Move to…"),
            ("e", "Export as PDF"), ("c", "Compress"), ("x", "Delete"),
        ] {
            // Border, inset, padding, ROW(15), padding, inset, border: the hint
            // is the row's last cell, at column 17 of 21.
            #expect(
                hintColumn(hint, on: label, in: drawn) == 17,
                "'\(hint)' in the trailing column of the '\(label)' row: \(drawn)")
        }
    }

    /// The regression, stated as geometry. The scrolled arm draws fewer rows —
    /// that is what scrolling is — so this asks about the ones it does draw, and
    /// it used to find no hint on any of them.
    @Test("Scrolling: the hint moves in by exactly the scrollbar's column")
    func hintGivesUpExactlyTheBarColumn() throws {
        let hugging = lines(height: 20)
        let scrolling = lines(height: 8)

        let huggingColumn = try #require(
            hintColumn("r", on: "Rename", in: hugging), "hugging: \(hugging)")
        let scrollingColumn = try #require(
            hintColumn("r", on: "Rename", in: scrolling),
            "the 'r' hint is drawn at all once the menu scrolls: \(scrolling)")
        #expect(
            scrollingColumn == huggingColumn - 1,
            "one column in, not two and not none: \(scrollingColumn) vs \(huggingColumn)")

        // And the column it gave up is the bar's: the scrollbar draws in the
        // one after the trailing padding that follows the hint.
        let barColumn = huggingColumn + 1
        #expect(
            scrolling.contains { Array($0)[barColumn] == "▲" || Array($0)[barColumn] == "▼" },
            "the bar occupies column \(barColumn): \(scrolling)")
        #expect(
            !hugging.contains { Array($0)[barColumn] == "▲" || Array($0)[barColumn] == "▼" },
            "…and nothing does when the menu hugs: \(hugging)")
    }

    /// Every row of the scrolled menu keeps its hint, not just the first — the
    /// clip was per row, so a check of one row would have passed on a menu whose
    /// first row happened to have no shortcut.
    @Test("Scrolling: every row on screen keeps its own key equivalent")
    func everyVisibleRowKeepsItsHint() {
        let drawn = lines(height: 8)
        for (hint, label) in [
            (Character("r"), "Rename"), ("d", "Duplicate"), ("m", "Move to…"),
        ] {
            #expect(
                hintColumn(hint, on: label, in: drawn) != nil,
                "the '\(label)' row kept its '\(hint)': \(drawn)")
        }
    }

    /// `.scrollIndicatorStyle(.text)` reserves no column — its indicators replace
    /// a LINE — so a scrolling menu under it keeps the hugging arm's row width.
    /// The bar question is asked of the same helper the `ScrollView` resolves its
    /// own bar from, so the two cannot drift; this is what says so.
    @Test("Scrolling with text indicators: no column taken, so no cell given up")
    func textIndicatorsTakeNoColumn() throws {
        let hugging = lines(height: 20)
        let texted = lines(height: 8) { $0.scrollIndicatorStyle = .text }
        #expect(
            texted.contains { $0.contains("lines below") },
            "the text indicator is what this menu scrolls with: \(texted)")
        #expect(
            hintColumn("r", on: "Rename", in: texted)
                == hintColumn("r", on: "Rename", in: hugging),
            "the hint stays where the hugging arm puts it: \(texted)")
    }
}
