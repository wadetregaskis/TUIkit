//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectableRowAlphaTests.swift
//
//  Row 2 of §16.1 for `Table`, and its `_ListCore` twin. A selectable row paints
//  three things of its own — its cells' ink, its selection mark, and its still
//  background — and any of the three can be translucent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A selectable row's own colours")
struct SelectableRowAlphaTests {

    private struct Row: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    private let rows = (0..<4).map { Row(id: $0, name: "row\($0)") }

    private func buffer<V: View>(_ view: V, width: Int = 30, height: Int = 8) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    private var half: Double { 128.0 / 255 }

    @ViewBuilder
    private func table(_ selection: Binding<Set<Int>>? = nil) -> some View {
        if let selection {
            Table(rows, selection: selection) { TableColumn("Name") { $0.name } }
        } else {
            Table(rows) { TableColumn("Name") { $0.name } }
        }
    }

    // MARK: - The shared derivation

    /// Three rectangles, never merged. The mark and the text are different colours, so
    /// a merged ink rectangle would resolve the ● at the text's alpha; the fill is a
    /// different CHANNEL, so its rectangle overlaps both and the resolver multiplies.
    @Test("A row's three paints claim three rectangles, and the gap cell only a field")
    func threeRectangles() {
        let faded = Color.rgb(200, 40, 40).opacity(0.5)
        let claims = SelectableRowClaims.claims(
            line: 0, width: 10, cells: 2..<8, ink: faded, mark: faded, fill: faded)
        #expect(claims.count == 3, "\(claims)")
        let ink = claims.filter { $0.inkOpacity < 1 }
        #expect(ink.count == 2, "the mark and the cells, separately: \(claims)")
        #expect(ink.contains { $0.offsetX == 0 && $0.width == 1 }, "the mark: \(claims)")
        #expect(ink.contains { $0.offsetX == 2 && $0.width == 6 }, "the cells: \(claims)")
        // Column 1 is the gap between the mark and the text: a bare space, so it may
        // carry a FIELD claim and must not carry an ink one.
        #expect(!ink.contains { $0.offsetX <= 1 && $0.offsetX + $0.width > 1 }, "\(claims)")
        let field = claims.filter { $0.fieldOpacity < 1 }
        #expect(field.count == 1 && field[0].width == 10, "\(claims)")
    }

    @Test("An opaque row claims nothing and allocates nothing")
    func opaqueRowClaimsNothing() {
        #expect(
            SelectableRowClaims.claims(
                line: 0, width: 10, cells: 2..<8, ink: .red, mark: .blue, fill: .green
            ).isEmpty)
    }

    // MARK: - Table

    @Test("A Table's cell ink claims under a faded foregroundStyle")
    func tableCellInkClaims() {
        let drawn = buffer(table().foregroundStyle(Color.red.opacity(0.5)))
        let claims = drawn.opacityRegions.filter { $0.inkOpacity == half }
        #expect(!claims.isEmpty, "\(drawn.opacityRegions)")
        // One per drawn row, and none of them on the header.
        #expect(claims.allSatisfy { $0.offsetY > 0 }, "a claim landed on the header: \(claims)")
    }

    @Test("A Table with an opaque style claims nothing")
    func opaqueTableClaimsNothing() {
        #expect(buffer(table()).opacityRegions.isEmpty)
    }

    /// The cursor row's background pulses, and that pulse spends its alpha (§29) — so
    /// the row's INK claim still applies to every frame and the fill claims nothing.
    /// `resolvingOpacity` re-blends a covered run's frames through the ink claim, so
    /// the migration is honest on the selected row too, which is what §19.1 doubted.
    @Test("The cursor row claims its ink and not its breathing fill")
    func cursorRowClaimsInkOnly() {
        let drawn = buffer(
            table(.constant([1])).foregroundStyle(Color.red.opacity(0.5)))
        #expect(drawn.opacityRegions.allSatisfy { $0.fieldOpacity == 1 }, "\(drawn.opacityRegions)")
        #expect(drawn.opacityRegions.contains { $0.inkOpacity == half })
    }

    /// A row under a ramp that varies ALONG it paints cell by cell through
    /// `PaintRenderer.band`, which is §15's `perCell` decline. That arm stays loud —
    /// its bytes keep the raw colour so the emitter's assertion still fires — and the
    /// decision is per FRAME, from one sampler, so a table either claims all its rows
    /// or none of them. Never right on nineteen rows and wrong on the twentieth.
    @Test("A banded table claims nothing at all, rather than some of its rows")
    func bandedTableIsAllOrNothing() {
        let drawn = buffer(
            table().foregroundStyle(
                LinearGradient(
                    colors: [.rgb(200, 40, 40), .rgb(40, 40, 200)],
                    startPoint: .leading, endPoint: .trailing)))
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    // MARK: - The `_ListCore` twin

    /// The twin, migrated in the same commit and through the same derivation. A `List`
    /// draws its mark and its still fill exactly as a `Table` does — the two have
    /// drifted before, which is why `RowSelectionIndicator` and `RowBackground` live
    /// beside each other, and `SelectableRowClaims` now with them.
    /// **The `_ListCore` twin, tested at the seam rather than end to end — and here is
    /// why, because the gap matters more than the test.**
    ///
    /// A `List` draws its mark and its still fill exactly as a `Table` does, through
    /// the same `SelectableRowClaims.claims`. But every translucent thing it can paint
    /// requires the list to hold the FOCUS: `RowSelectionIndicator.forRow` takes the
    /// accent raw only for a row that is both selected and the cursor row of a focused
    /// control, and the unfocused mark spends its alpha through `opacity(_:over:)`.
    /// `rowBackground` is the same — `.focusBackground` and the cursor pulse are the
    /// only paths to a colour a theme could have faded.
    ///
    /// Focusing a `List` from a headless `renderToBuffer` did not work: two full
    /// render passes with `beginRenderPass`/`endRenderPass` around each, then
    /// `focusNext()` and then `focus(id:)` against an explicit `.focusID`, all left
    /// the rows unfocused. So this asserts the CONTRACT `_ListCore` depends on — the
    /// shape the derivation produces for a list row, which paints no cells of its own
    /// — and the focused end-to-end path is left to a live/PTY assertion it does not
    /// have. Said plainly rather than papered over with an unfocused render that would
    /// have passed for the wrong reason.
    @Test("A list row's claims: a mark on the first line only, and a fill across all of them")
    func listRowClaimShape() {
        let faded = Color.rgb(200, 40, 40).opacity(0.5)
        // How `_ListCore.renderRow` calls it: no cells, because a list row's content is
        // a child buffer with its own regions that `attachRowOpacity` carries up.
        let claims = (0..<3).flatMap { line in
            SelectableRowClaims.claims(
                line: line, width: 12, cells: 0..<0, ink: nil,
                mark: line == 0 ? faded : nil, fill: faded)
        }
        let marks = claims.filter { $0.inkOpacity < 1 }
        #expect(marks.count == 1, "one mark, not three: \(claims)")
        #expect(marks.first?.offsetY == 0)
        let fills = claims.filter { $0.fieldOpacity < 1 }
        #expect(fills.count == 3, "one per line: \(claims)")
        #expect(Set(fills.map(\.offsetY)) == [0, 1, 2])
        #expect(fills.allSatisfy { $0.offsetX == 0 && $0.width == 12 })
    }
}
