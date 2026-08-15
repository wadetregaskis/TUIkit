//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyGridTests.swift
//
//  ``LazyVGrid`` / ``LazyHGrid`` — the grids that flow, as opposed to ``Grid``,
//  where the rows are written out by hand.
//
//  Two layers, because they fail differently: the track arithmetic is where
//  every interesting decision is made (how many columns `.adaptive` fits, who
//  gets the remainder), and the rendering is where a correct set of tracks can
//  still be placed wrongly.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Flowing grids")
struct LazyGridTests {

    private func lines(_ view: some View, width: Int = 30, height: Int = 12) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines
            .map {
                $0.stripped.replacingOccurrences(
                    of: " +$", with: "", options: .regularExpression)
            }
    }

    /// The rows that actually have something on them.
    private func painted(_ view: some View, width: Int = 30, height: Int = 12) -> [String] {
        lines(view, width: width, height: height).filter { !$0.isEmpty }
    }

    // MARK: - Track Resolution

    @Test("flexible tracks split what is left after the gaps")
    func flexibleSplitsEvenly() {
        // 32 cells, three tracks, two single-cell gaps → 30 to divide.
        let tracks = GridItem.resolve(
            Array(repeating: GridItem(.flexible()), count: 3), available: 32)
        #expect(tracks.map(\.extent) == [10, 10, 10])
    }

    @Test("a remainder that will not divide is handed out a cell at a time")
    func remainderGoesRound() {
        // 33 cells − 2 gaps = 31 over three tracks: 11/10/10, never 10/10/10
        // with a cell dropped on the floor.
        let tracks = GridItem.resolve(
            Array(repeating: GridItem(.flexible()), count: 3), available: 33)
        #expect(tracks.map(\.extent).reduce(0, +) == 31)
        #expect(tracks.map(\.extent).max()! - tracks.map(\.extent).min()! <= 1)
    }

    @Test("fixed tracks keep their size and leave the rest unclaimed")
    func fixedIsFixed() {
        let tracks = GridItem.resolve([GridItem(.fixed(4)), GridItem(.fixed(6))], available: 40)
        #expect(tracks.map(\.extent) == [4, 6])
    }

    @Test("flexible tracks stop at their maximum")
    func flexibleRespectsMaximum() {
        let tracks = GridItem.resolve(
            [GridItem(.flexible(minimum: 2, maximum: 5)), GridItem(.flexible())], available: 40)
        #expect(tracks[0].extent == 5, "capped")
        #expect(tracks[1].extent == 34, "and the other takes everything else")
    }

    /// The point of `.adaptive`: the track COUNT is an output.
    @Test("adaptive fits as many tracks as it can")
    func adaptiveCounts() {
        // Minimum 4 + a 1-cell gap = 5 per track; 23 cells fits four.
        let tracks = GridItem.resolve([GridItem(.adaptive(minimum: 4))], available: 23)
        #expect(tracks.count == 4)
        // …and then the leftover is shared out, so the row is fully used.
        let used = tracks.reduce(0) { $0 + $1.extent } + (tracks.count - 1)
        #expect(used == 23, "\(tracks.map(\.extent))")
    }

    /// The gap goes BETWEEN tracks, so *n* tracks need *n−1* of them — and the
    /// track that just fits is the one whose trailing gap would have run off the
    /// end. Counting a gap per track loses a whole column at every exact fit,
    /// which is invisible at most widths: these are the widths where it shows.
    ///
    /// With a 4-cell minimum and a 1-cell gap, five tracks need 5×4 + 4 = 24.
    @Test("the last track needs no gap after it")
    func gapsGoBetween() {
        let item = [GridItem(.adaptive(minimum: 4))]
        let counts = [23, 24, 28, 29].map { GridItem.resolve(item, available: $0).count }
        #expect(counts == [4, 5, 5, 6], "\(counts)")

        // …and the resolved tracks really do fit the width they claimed to.
        for available in [23, 24, 28, 29] {
            let tracks = GridItem.resolve(item, available: available)
            let used = tracks.reduce(0) { $0 + $1.extent } + (tracks.count - 1)
            #expect(used <= available, "\(tracks.count) tracks over-filled \(available)")
        }
    }

    @Test("adaptive reflows as the width changes")
    func adaptiveReflows() {
        let item = [GridItem(.adaptive(minimum: 5))]
        let counts = [12, 24, 60].map { GridItem.resolve(item, available: $0).count }
        #expect(counts == [2, 4, 10], "\(counts)")
    }

    /// A grid too narrow for even one track still renders one, clipped, rather
    /// than vanishing — a blank region is far harder to diagnose than a squeezed
    /// one.
    @Test("adaptive yields one track when nothing fits")
    func adaptiveNeverEmpty() {
        let tracks = GridItem.resolve([GridItem(.adaptive(minimum: 20))], available: 4)
        #expect(tracks.count == 1)
    }

    @Test("no width means no tracks")
    func nothingFits() {
        #expect(GridItem.resolve([GridItem(.flexible())], available: 0).isEmpty)
        #expect(GridItem.resolve([], available: 40).isEmpty)
    }

    @Test("a track's own spacing overrides the grid's")
    func perTrackSpacing() {
        let tracks = GridItem.resolve(
            [GridItem(.fixed(3), spacing: 4), GridItem(.fixed(3))], available: 40)
        #expect(tracks[0].spacing == 4)
        #expect(tracks[1].spacing == GridItem.defaultSpacing)
    }

    // MARK: - LazyVGrid

    @Test("content wraps onto a new row when the columns fill up")
    func verticalWraps() {
        let drawn = painted(
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(2)), count: 3), alignment: .leading)
            {
                ForEach(["a", "b", "c", "d", "e"], id: \.self) { Text(verbatim: $0) }
            })
        #expect(drawn.count == 2, "five items over three columns is two rows: \(drawn)")
        #expect(drawn[0].hasPrefix("a  b  c"), "\(drawn)")
        #expect(drawn[1].hasPrefix("d  e"), "the last row is short, not wrapped: \(drawn)")
    }

    @Test("row spacing leaves blank rows between the rows")
    func verticalSpacing() {
        let drawn = lines(
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(2)), count: 2),
                alignment: .leading, spacing: 1
            ) {
                ForEach(["a", "b", "c", "d"], id: \.self) { Text(verbatim: $0) }
            })
        #expect(drawn[0].hasPrefix("a  b"), "\(drawn)")
        #expect(drawn[1].isEmpty, "one blank row between: \(drawn)")
        #expect(drawn[2].hasPrefix("c  d"), "\(drawn)")
    }

    /// The default, and the reason a cell is a region rather than a position.
    @Test("cells centre their content by default")
    func verticalCentres() {
        let drawn = painted(
            LazyVGrid(columns: [GridItem(.fixed(5)), GridItem(.fixed(5))]) {
                Text(verbatim: "x")
                Text(verbatim: "y")
            })
        // Five cells wide, one-cell content: two spaces of lead in each.
        #expect(drawn[0].hasPrefix("  x"), "\(drawn)")
    }

    @Test("a column's own alignment beats the grid's")
    func perTrackAlignment() {
        let drawn = painted(
            LazyVGrid(
                columns: [GridItem(.fixed(5), alignment: .leading), GridItem(.fixed(5))],
                alignment: .center
            ) {
                Text(verbatim: "x")
                Text(verbatim: "y")
            })
        #expect(drawn[0].hasPrefix("x"), "the first column overrode centring: \(drawn)")
    }

    /// The whole reason to prefer `.adaptive` in a terminal.
    @Test("the same grid reflows when the terminal is narrower")
    func reflowsWithWidth() {
        let grid = LazyVGrid(columns: [GridItem(.adaptive(minimum: 3))], alignment: .leading) {
            ForEach(["a", "b", "c", "d", "e", "f"], id: \.self) { Text(verbatim: $0) }
        }
        let wide = painted(grid, width: 30)
        let narrow = painted(grid, width: 8)
        #expect(wide.count < narrow.count, "wide: \(wide) narrow: \(narrow)")
        #expect(narrow.allSatisfy { !$0.isEmpty })
    }

    // MARK: - LazyHGrid

    @Test("content wraps into a new column when the rows fill up")
    func horizontalWraps() {
        let drawn = painted(
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(1)), count: 2), alignment: .top) {
                ForEach(["a", "b", "c", "d", "e"], id: \.self) { Text(verbatim: $0) }
            })
        #expect(drawn.count == 2, "two rows of tracks: \(drawn)")
        // a c e down the first row of the grid, b d down the second.
        #expect(drawn[0].replacingOccurrences(of: " ", with: "") == "ace", "\(drawn)")
        #expect(drawn[1].replacingOccurrences(of: " ", with: "") == "bd", "\(drawn)")
    }

    @Test("an empty grid renders nothing rather than crashing")
    func empty() {
        let drawn = painted(
            LazyVGrid(columns: [GridItem(.flexible())]) {
                EmptyView()
            })
        #expect(drawn.isEmpty)
    }

    /// A grid is a container like any other: what wraps it still reaches
    /// inside. The architecture rule every public control is held to.
    @Test("modifiers reach the content inside a grid")
    func modifiersPropagate() {
        func render(_ view: some View) -> String {
            renderToBuffer(view, context: makeBareRenderContext(width: 20, height: 4))
                .lines.joined()
        }
        let plain = render(LazyVGrid(columns: [GridItem(.fixed(3))]) { Text(verbatim: "x") })
        let styled = render(
            LazyVGrid(columns: [GridItem(.fixed(3))]) { Text(verbatim: "x") }
                .foregroundStyle(.red))
        #expect(styled != plain, "the colour reached the cell")
        #expect(styled.contains("\u{1B}["), "…as an SGR run: \(styled.debugDescription)")
    }
}
