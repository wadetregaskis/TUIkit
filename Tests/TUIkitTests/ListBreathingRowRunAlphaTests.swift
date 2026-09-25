//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListBreathingRowRunAlphaTests.swift
//
//  A breathing List row — the cursor row of a focused list — repaints its whole
//  line every tick and drops its children's runs for the duration. A run that
//  states its alpha per frame took the only statement about its cells with it, so
//  the cursor row's several-alpha border drew at full strength while every other
//  row's faded (§69.4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A breathing List row's dropped child runs")
struct ListBreathingRowRunAlphaTests {

    private struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private let rows = (0..<3).map { Row(id: $0, name: "row\($0)") }

    /// One colour at two alphas: the §69.3 border, which states no region and carries
    /// its alpha on its runs instead. Drawn at step 1, the FADED frame, because that is
    /// the frame a dropped run has to leave behind — at step 0 the drawn line is
    /// honestly opaque, there is nothing to leave, and this test could not fail.
    private var border: AnimatedColor {
        AnimatedColor(frames: [Color.rgb(200, 40, 40), Color.rgb(200, 40, 40).opacity(0.5)], step: 1)
    }

    /// `ListRowFocusedAlphaTests`' harness, for its reasons: the focus manager has to be
    /// IN the environment, and it takes two passes, because a row cannot be focused
    /// before it has registered.
    private func focusedListBuffer<V: View>(_ view: V, focusID: String) -> FrameBuffer {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        func pass() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 14,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }

        _ = pass()
        focusManager.focus(id: focusID)
        return pass()
    }

    /// Row 0 is both the cursor row and the selected one, so it is the row that
    /// breathes. A `List` draws inside its own border, so its three lines are 1 to 3;
    /// rows 1 and 2 do not breathe and keep their runs.
    @Test("The cursor row's several-alpha border keeps its drawn alpha while the row breathes")
    func cursorRowLeavesItsAlpha() throws {
        let drawn = focusedListBuffer(
            List(selection: .constant(Set([0]))) {
                ForEach(rows) { row in Text(row.name).border(border) }
            }
            .focusID("breathing-list")
            .tint(.red),
            focusID: "breathing-list")
        let runs = drawn.animatedCells.map { "y=\($0.offsetY) w=\($0.width) alpha=\($0.alpha != nil)" }
        let cursorRowLines: Set<Int> = [1, 2, 3]

        // The premise, without which the rest would pass for the wrong reason: row 0
        // really breathes. Its whole-line pulse is wider than the bordered box inside it
        // and carries no payload.
        let breathes = drawn.animatedCells.contains { $0.alpha == nil && $0.offsetY == 1 && $0.width > 6 }
        try #require(breathes, "the cursor row is not breathing: \(runs)")
        // And the drop itself, which is right and stays: the other rows carry their
        // payload on their runs, and the cursor row carries none.
        let carried = drawn.animatedCells.filter { $0.alpha != nil }
        let carriedOnTheCursorRow = carried.contains { cursorRowLines.contains($0.offsetY) }
        #expect(!carried.isEmpty, "the other rows' borders carry their alpha on their runs: \(runs)")
        #expect(!carriedOnTheCursorRow, "a breathing row drops its children's runs: \(runs)")

        // What was missing: the dropped runs' drawn frame, left behind as regions on the
        // cursor row's lines — and nowhere else, where a surviving run would fold it twice.
        let owed = drawn.opacityRegions.filter { $0.inkOpacity < 1 }
        let owedRows = Set(owed.map(\.offsetY))
        let atTheDrawnFrame = owed.allSatisfy { $0.inkOpacity == 128.0 / 255 }
        #expect(owedRows == cursorRowLines, "the cursor row's border claims nothing: \(owed)")
        #expect(atTheDrawnFrame, "at the faded frame its lines were drawn at: \(owed)")
    }

    /// Both alphas, in their order. The resolver takes a cell's LAYER from the first
    /// region covering it, and a dropped run's drawn frame left behind among the
    /// list's own claims came ahead of an `.opacity(_:)` inside the row: its border
    /// cells lost the fade, the ink right, the layer gone.
    ///
    /// Since 2026-09-24 the row spends such content against the fill it paints
    /// (`Opacity as composition.md` §96.1) — the row's own fade and its runs' drawn
    /// frame together, in one resolution, which appends a run's payload after the
    /// regions by construction — so nothing is left to order at the attach, and the
    /// question is asked of the picture: the cursor row's top rule is the border's
    /// red at its drawn alpha over the row's fill, and THEN at the row's 0.3 over
    /// that fill.
    @Test("An opacity inside the cursor row fades its dropped border cells at both alphas")
    func contentOpacityAndBorderAlpha() throws {
        let drawn = ColorDepth.withCurrent(.truecolor) {
            focusedListBuffer(
                List(selection: .constant(Set([0]))) {
                    ForEach(rows) { row in Text(row.name).border(border).opacity(0.3) }
                }
                .focusID("breathing-list")
                .tint(.red),
                focusID: "breathing-list")
        }
        // Spent at the row: the cursor row's content owes the root nothing.
        #expect(
            !drawn.opacityRegions.contains { $0.opacity < 1 && (1...3).contains($0.offsetY) },
            "the cursor row carried its fade up: \(drawn.opacityRegions)")
        let cells = paintedCells(drawn.lines[1])
        let corner = try #require(
            cells.indices.first { $0 > 1 && ["╭", "┌"].contains(cells[$0].glyph) },
            "no top rule on the cursor row: \(drawn.lines[1].stripped)")
        let fill = try #require(Self.rgb(cells[corner].state.backgroundColour), "the rule is on no fill")
        let expected = try #require(
            Color.rgb(200, 40, 40).opacity(128.0 / 255, over: fill).opacity(0.3, over: fill).rgbComponents)
        #expect(
            Self.rgb(cells[corner].ink)?.rgbComponents.map { [$0.red, $0.green, $0.blue] }
                == [expected.red, expected.green, expected.blue],
            "the rule is drawn in \(String(describing: cells[corner].ink)) on \(fill)")
    }

    /// `colour` as a `Color`, where it is 24-bit.
    private static func rgb(_ colour: SGRState.Colour?) -> Color? {
        guard case .rgb(let red, let green, let blue) = colour else { return nil }
        return .rgb(UInt8(red), UInt8(green), UInt8(blue))
    }
}
