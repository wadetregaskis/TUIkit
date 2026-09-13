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

    /// WHERE those regions go, not only that they exist. The resolver takes a cell's
    /// LAYER from the first region covering it. Left behind among the list's own claims,
    /// which the container lays down before any row's content regions, they came ahead
    /// of an `.opacity(_:)` inside the row, and its border cells lost the fade: the ink
    /// right, the layer gone.
    @Test("An opacity inside the cursor row still comes first over its dropped border cells")
    func contentOpacityStaysFirst() throws {
        let drawn = focusedListBuffer(
            List(selection: .constant(Set([0]))) {
                ForEach(rows) { row in Text(row.name).border(border).opacity(0.3) }
            }
            .focusID("breathing-list")
            .tint(.red),
            focusID: "breathing-list")
        let dropped = try #require(
            drawn.opacityRegions.first { $0.inkOpacity < 1 && $0.offsetY == 1 },
            "the cursor row's top rule left nothing: \(drawn.opacityRegions)")
        let covering = drawn.opacityRegions.filter { $0.contains(column: dropped.offsetX, row: 1) }
        #expect(covering.first?.opacity == 0.3, "the row's own fade is not first over its border: \(covering)")
    }
}
