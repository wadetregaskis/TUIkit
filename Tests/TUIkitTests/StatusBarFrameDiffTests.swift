//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarFrameDiffTests.swift
//
//  The status bar through a whole frame — `RenderLoop.render` into a
//  `MockTerminal`, read back row by row — rather than through
//  `StatusBar.renderToBuffer`, which is where every earlier bar test stopped.
//  What broke here lived between the view and the terminal: in what the frame
//  diff believed was already on screen, and in whether the loop built the bar
//  at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A page of one line of text, so the rows the tests read are the status bar's.
private struct StatusBarProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

@MainActor
@Suite("The status bar reaches the terminal")
struct StatusBarFrameDiffTests {

    /// Everything written to each terminal row since the terminal was last reset,
    /// escapes stripped, keyed by the row of the cursor move before it.
    ///
    /// Accumulated rather than last-write-wins — the weaker oracle, on purpose, and
    /// still enough: a row the frame never visited is ABSENT and a row it only
    /// erased is blank, and those are the two ways the bar went missing.
    private func paints(_ terminal: MockTerminal) -> [Int: String] {
        var rows: [Int: String] = [:]
        var current: Int?
        for chunk in terminal.writtenOutput {
            if let moved = cursorRow(chunk) {
                current = moved
                if rows[moved] == nil { rows[moved] = "" }
            } else if let current {
                rows[current, default: ""] += chunk.stripped
            }
        }
        return rows
    }

    /// The row `chunk` moves the cursor to, if it is a cursor move — which
    /// `MockTerminal.moveCursor(toRow:column:)` writes as a chunk of its own.
    private func cursorRow(_ chunk: String) -> Int? {
        let introducer = "\u{1B}["
        guard chunk.hasPrefix(introducer), chunk.hasSuffix("H") else { return nil }
        let fields = chunk.dropFirst(introducer.count).dropLast().split(separator: ";")
        guard fields.count == 2, Int(fields[1]) != nil else { return nil }
        return Int(fields[0])
    }

    /// Whether a row's paint draws anything but spaces.
    private func isInked(_ paint: String?) -> Bool {
        paint?.contains(where: { $0 != " " }) ?? false
    }

    /// A tooltip in the bar moves the bar's top edge, and every row of the bar has
    /// to be written at its new place — on the way up and on the way down.
    ///
    /// The frame diff compares the bar's rows by index from wherever the bar is
    /// written, and only the bar appearing or disappearing invalidated it. A
    /// tooltip grows the bar upwards by a row, and the top border — the same bytes
    /// either side of the move — compared equal and was skipped. Showing the
    /// tooltip left blank the row the content pass had just erased; hiding it never
    /// revisited the row the border returned to, so the tooltip's text stayed there.
    @Test("A tooltip that moves the bar's top edge repaints every row of the bar, both ways")
    func tooltipMovingTheBarRepaintsIt() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(StatusBarProbeApp())
        let tooltips = harness.tuiContext.tooltipState
        _ = loop.render()
        #expect(harness.statusBar.height == 3, "pre-condition: the default bordered bar, `q quit` only")

        // 80x24, `MockTerminal`'s size: the grown bar is rows 21...24.
        tooltips.hovering("Rebuild the index", handlerID: nil, nowNanos: 0)
        harness.terminal.reset()
        _ = loop.render()
        #expect(harness.statusBar.height == 4, "pre-condition: the tooltip must add a row, or nothing moved")
        let shown = paints(harness.terminal)
        for row in 21...24 {
            #expect(isInked(shown[row]), "row \(row) of the grown bar: \(shown[row].debugDescription)")
        }

        tooltips.leaving("Rebuild the index")
        harness.terminal.reset()
        _ = loop.render()
        #expect(harness.statusBar.height == 3, "pre-condition: the tooltip must be gone")
        let hidden = paints(harness.terminal)
        for row in 22...24 {
            #expect(isInked(hidden[row]), "row \(row) of the shrunk bar: \(hidden[row].debugDescription)")
        }
    }

    /// A bar with no items still draws a tooltip in the rows it made room for.
    ///
    /// `StatusBarState.height` counts a tooltip row on a bar with no items, so the
    /// page was shortened for it — but the loop built the bar only when it had
    /// items, so the content pass erased those rows and nothing was drawn in them.
    /// No items and no system items is the documented way to hide the bar.
    @Test("A tooltip on a bar with no items is drawn in the rows it reserves")
    func tooltipOnAnItemlessBarIsDrawn() {
        let harness = RenderLoopHarness()
        harness.statusBar.showSystemItems = false
        let loop = harness.loop(StatusBarProbeApp())
        _ = loop.render()
        #expect(harness.statusBar.height == 0, "pre-condition: no items, no bar")

        // A bordered bar round one tooltip row: rows 22...24 of 24.
        harness.tuiContext.tooltipState.hovering("Copy to clipboard", handlerID: nil, nowNanos: 0)
        harness.terminal.reset()
        _ = loop.render()
        #expect(harness.statusBar.height == 3, "pre-condition: the tooltip must take its rows")
        let drawn = paints(harness.terminal)
        for row in 22...24 {
            #expect(isInked(drawn[row]), "row \(row) of the tooltip's bar: \(drawn[row].debugDescription)")
        }
        let tooltipRow = drawn[23] ?? ""
        #expect(tooltipRow.contains("Copy to clipboard"), "\(drawn)")
    }
}
