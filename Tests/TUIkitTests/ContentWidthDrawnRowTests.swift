//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentWidthDrawnRowTests.swift
//
//  A write that widens a row the record does not name. The challenge
//  (`StackContentWidth.swift`) re-measures the one row the kept all-rows width
//  names as its widest, so a write that pushed some OTHER row past it went
//  unseen until something started a walk over — and the worst shape of that is
//  the ordinary one: typing at the end of a line in an index-keyed editor until
//  it is the longest, the typed text past the old extent unreachable. The rows
//  the last frame DREW are re-measured with it now.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What each row's text is, by ordinal — eight cells unless set — read at
/// build time, so a test can change what a row draws between frames without
/// changing the rows' data, as an index-keyed editor's document does.
@MainActor
private final class RowCells {
    var cells: [Int: Int]
    init(_ cells: [Int: Int]) { self.cells = cells }
    func of(_ index: Int) -> Int { cells[index] ?? 8 }
}

/// A row of `cells.of(index)` cells; every seventh a line taller when
/// `varied`, which is what sends a stack to its anchored or exact paths.
private struct EditedRow: View {
    let index: Int
    let cells: RowCells
    let varied: Bool

    var body: some View {
        let line = String(repeating: "\(index % 10)", count: cells.of(index))
        return Text(varied && index.isMultiple(of: 7) ? line + "\nx" : line)
    }
}

/// The paths a windowed stack draws a band by: uniform rows (100 and 400),
/// and rows of several heights over the anchored threshold (400) and under it
/// (100) — the last answered by a walk of every row each frame, and here to
/// keep it that way.
/// Scrolled to the end, and the edited row the last one, so it is on screen
/// and in no sample: the anchored arm samples the FIRST sixteen rows wherever
/// the viewport is, and would have caught a row among them by accident.
private let drawnRowShapes: [(rows: Int, varied: Bool)] = [(100, false), (400, false), (400, true), (100, true)]

@MainActor
@Suite("A written row the kept width does not name")
struct ContentWidthDrawnRowTests {
    /// The frame a two-axis view over `rows` draws on its second frame, with
    /// its rows' cells as `cells` — the control an edited view must match.
    private func settled(rows: Int, varied: Bool, cells: [Int: Int]) -> String {
        let control = twoAxisFrames(
            tuiContext: TUIContext(), rows: { rows }, atBottom: true,
            row: { index in EditedRow(index: index, cells: RowCells(cells), varied: varied) })
        _ = control()
        return control()
    }

    /// Row 50, off screen, is the widest at 60; the last row, on screen, is 50
    /// and grows to 90 in one write. The challenge re-measured row 50, found it
    /// unchanged, and the extent stayed 60: the last row's final thirty cells
    /// were out of reach, on the frame of the write and every frame after it
    /// until something walked again. The frame of the write must be the frame
    /// of content that had the last row at 90 from the start.
    @Test("A drawn row that outgrows the widest is seen on the frame of the write", arguments: drawnRowShapes)
    func aDrawnRowOutgrowingTheWidest(shape: (rows: Int, varied: Bool)) {
        let last = shape.rows - 1
        let cells = RowCells([50: 60, last: 50])
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext, rows: { shape.rows }, atBottom: true,
            row: { index in EditedRow(index: index, cells: cells, varied: shape.varied) })
        _ = frame()
        #expect(frame() == settled(rows: shape.rows, varied: shape.varied, cells: [50: 60, last: 50]))

        cells.cells[last] = 90
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(
            frame() == settled(rows: shape.rows, varied: shape.varied, cells: [50: 60, last: 90]),
            "the frame of the write kept the old extent")
    }

    /// And the bound the record keeps below its widest must survive the raise:
    /// once the last row is the widest at 90, row 50's 60 is what every other
    /// row is at most. The last row backspaced to 50 is then narrower than that
    /// bound, and a walk finds row 50 again — where a raise that forgot the old
    /// widest as the new runner-up would have lowered the extent to 50 and left
    /// row 50's last ten cells out of reach.
    @Test("The old widest bounds the rest after a drawn row overtakes it", arguments: drawnRowShapes)
    func theOldWidestBoundsTheRest(shape: (rows: Int, varied: Bool)) {
        let last = shape.rows - 1
        let cells = RowCells([50: 60, last: 50])
        let tuiContext = TUIContext()
        let frame = twoAxisFrames(
            tuiContext: tuiContext, rows: { shape.rows }, atBottom: true,
            row: { index in EditedRow(index: index, cells: cells, varied: shape.varied) })
        _ = frame()
        _ = frame()
        cells.cells[last] = 90
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        _ = frame()

        cells.cells[last] = 50
        tuiContext.renderCache.clearAffected(by: ViewIdentity(path: ""))
        #expect(
            frame() == settled(rows: shape.rows, varied: shape.varied, cells: [50: 60, last: 50]),
            "the extent fell below row 50")
    }
}
