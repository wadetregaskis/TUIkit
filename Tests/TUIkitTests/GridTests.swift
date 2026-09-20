//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// `Grid` is the container a terminal wants most and had none of: cells that
/// line up in columns without anyone being told a width.
///
/// The property every case here turns on is that a **column** is as wide as its
/// widest cell across ALL rows — which is what distinguishes a grid from a
/// column of `HStack`s, where each row sizes independently.
@MainActor
@Suite("Grid")
struct GridTests {

    private func lines(_ view: some View, width: Int = 60, height: Int = 12) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    @Test("Columns are as wide as their widest cell, across rows")
    func columnsAlignAcrossRows() {
        // A column of HStacks would put "b" at column 2 in row 1 and column 8
        // in row 2. A grid lines them up.
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a")
                    Text("b")
                }
                GridRow {
                    Text("aaaaaaa")
                    Text("b")
                }
            })

        func columnOfB(_ line: String) -> Int? { line.firstIndex(of: "b").map { line.distance(from: line.startIndex, to: $0) } }
        #expect(columnOfB(rendered[0]) == columnOfB(rendered[1]))
        // 7 for the widest first-column cell, plus the default 1-cell gap.
        #expect(columnOfB(rendered[0]) == 8)
    }

    @Test("The reported size is the size rendered")
    func measureMatchesRender() {
        let view = Grid {
            GridRow {
                Text("one")
                Text("two")
            }
            GridRow {
                Text("three")
                Text("four")
            }
        }
        let context = makeRenderContext(width: 60, height: 12)
        let measured = measureChild(view, proposal: .unspecified, context: context)
        let rendered = renderToBuffer(view, context: context)
        #expect(measured.width == rendered.width)
        #expect(measured.height == rendered.lines.count)
    }

    /// The case the test above cannot see, because every row in it has content.
    ///
    /// `renderToBuffer` gives each row a canvas of `max(1, rowHeight)` — a row
    /// is at least a line, whatever it holds — while `sizeThatFits` summed the
    /// raw heights. So every row that measures zero tall made the reported
    /// height one line short of the drawn one, and the parent clipped the
    /// difference off the bottom: with one empty row, the grid's LAST row does
    /// not appear.
    @Test("A row with nothing in it is measured the height it is drawn")
    func emptyRowMeasuresAsDrawn() {
        let view = Grid {
            GridRow { Text("one") }
            GridRow { EmptyView() }
            GridRow { Text("three") }
        }
        let context = makeRenderContext(width: 60, height: 12)
        let measured = measureChild(view, proposal: .unspecified, context: context)
        let rendered = renderToBuffer(view, context: context)
        #expect(
            measured.height == rendered.lines.count,
            "measured \(measured.height) but drew \(rendered.lines.count)")
    }

    /// A child that is not a `GridRow` spans the whole grid — the render places
    /// it at `x: 0` across the full width, and `Grid`'s own doc comment calls
    /// out the `Divider` case. But `lattice`'s first pass voted it into a
    /// COLUMN: it arrives as a one-cell row with `span == 1`, and the vote is
    /// guarded on the span alone, so its full measured width became column 0's
    /// width and pushed every other column right by the difference. The second
    /// pass already knows better and skips full-width rows; the first did not.
    @Test("A child that spans the grid does not widen the first column")
    func spanningChildDoesNotWidenFirstColumn() {
        func columnOfB(_ line: String) -> Int? {
            line.firstIndex(of: "b").map { line.distance(from: line.startIndex, to: $0) }
        }
        let withoutSpanner = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a")
                    Text("b")
                }
            })
        let withSpanner = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a")
                    Text("b")
                }
                Text("a spanning child much wider than either column")
            })
        #expect(
            columnOfB(withSpanner[0]) == columnOfB(withoutSpanner[0]),
            "the spanning child moved the second column")
    }

    @Test("Spacing is in whole cells and defaults to 1 column, 0 rows")
    func spacingDefaults() {
        let tight = lines(
            Grid(alignment: .leading, horizontalSpacing: 0) {
                GridRow {
                    Text("ab")
                    Text("cd")
                }
            })
        #expect(tight[0].hasPrefix("abcd"))

        let spaced = lines(
            Grid(alignment: .leading, horizontalSpacing: 3) {
                GridRow {
                    Text("ab")
                    Text("cd")
                }
            })
        #expect(spaced[0].hasPrefix("ab   cd"))
    }

    @Test("A vertical gap inserts blank lines between rows")
    func verticalSpacing() {
        let rendered = lines(
            Grid(alignment: .leading, verticalSpacing: 1) {
                GridRow { Text("top") }
                GridRow { Text("bottom") }
            })
        #expect(rendered[0].hasPrefix("top"))
        #expect(rendered[1].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(rendered[2].hasPrefix("bottom"))
    }

    @Test("A non-GridRow child spans every column")
    func nonRowChildSpansTheWidth() {
        // The case SwiftUI needs `gridCellUnsizedAxes` for: a Divider between
        // rows must not size a column.
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("bbb")
                }
                Divider()
                GridRow {
                    Text("ccc")
                    Text("ddd")
                }
            })
        // The divider fills the grid's whole width (3 + 1 + 3), not one column.
        #expect(rendered[1].count >= 7)
        #expect(rendered[0].hasPrefix("aaa bbb"))
        #expect(rendered[2].hasPrefix("ccc ddd"))
    }

    @Test("A span PRECEDED by an ordinary cell grows the right column")
    func spanAfterAnOrdinaryCell() {
        // The bug: Pass B filtered the loop with `where span > 1`, which skips
        // the whole body — the index bookkeeping included — so a spanning cell
        // that follows a single-column one measured itself against the wrong
        // columns and grew the wrong one. Here the span is in columns 1…2, and
        // the widening must land on column 2, leaving column 0 alone.
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a")
                    Text("b")
                    Text("c")
                }
                GridRow {
                    Text("x")
                    Text("wiiiide").gridCellColumns(2)
                }
            })
        // Row 0's first column stays one cell wide, so "a b" is still "a b".
        #expect(rendered[0].trimmingCharacters(in: .whitespaces) == "a b c", "\(rendered)")
        #expect(rendered[1].hasPrefix("x wiiiide"), "the span moved: \(rendered)")
    }

    @Test("gridCellColumns spans, and grows its last column only if it must")
    func cellSpanning() {
        // "wide" (4) fits inside a+space+b (1+1+1 = 3)? No — so the LAST of the
        // spanned columns grows by the shortfall, leaving the first column at
        // the width its single-column cells asked for.
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a")
                    Text("b")
                }
                GridRow {
                    Text("wide").gridCellColumns(2)
                }
            })
        #expect(rendered[0].hasPrefix("a b"))
        #expect(rendered[1].hasPrefix("wide"))
        // Column 0 stayed 1 wide: the span did not steal it.
        let secondRowGrid = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a")
                    Text("b")
                }
                GridRow {
                    Text("wide").gridCellColumns(2)
                }
                GridRow {
                    Text("x")
                    Text("y")
                }
            })
        #expect(secondRowGrid[2].hasPrefix("x y"))
    }

    @Test("Cells sit at the grid's alignment within their column")
    func gridAlignmentPlacesCells() {
        let trailing = lines(
            Grid(alignment: .trailing) {
                GridRow {
                    Text("a")
                    Text("z")
                }
                GridRow {
                    Text("aaaaa")
                    Text("z")
                }
            })
        // "a" is pushed to the right edge of its 5-wide column.
        #expect(trailing[0].hasPrefix("    a z"))
        #expect(trailing[1].hasPrefix("aaaaa z"))
    }

    @Test("gridColumnAlignment overrides the grid for one column")
    func columnAlignmentWins() {
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a").gridColumnAlignment(.trailing)
                    Text("z")
                }
                GridRow {
                    Text("aaaaa")
                    Text("z")
                }
            })
        #expect(rendered[0].hasPrefix("    a z"))
    }

    @Test("gridCellAnchor beats every other alignment for that cell")
    func cellAnchorWins() {
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("a").gridCellAnchor(.trailing)
                    Text("z")
                }
                GridRow {
                    Text("aaaaa")
                    Text("z")
                }
            })
        #expect(rendered[0].hasPrefix("    a z"))
    }

    @Test("A row's alignment overrides the grid's vertical alignment")
    func rowAlignmentOverrides() {
        // The first cell is one line; the second is three. With the row pinned
        // to .top the short cell sits on the row's first line.
        let rendered = lines(
            Grid(alignment: .leading) {
                GridRow(alignment: .top) {
                    Text("x")
                    Text("1\n2\n3")
                }
            })
        #expect(rendered[0].hasPrefix("x 1"))

        let bottom = lines(
            Grid(alignment: .leading) {
                GridRow(alignment: .bottom) {
                    Text("x")
                    Text("1\n2\n3")
                }
            })
        #expect(bottom[2].hasPrefix("x 3"))
    }

    @Test("An empty grid renders nothing and does not crash")
    func emptyGrid() {
        #expect(renderToBuffer(Grid {}, context: makeRenderContext(width: 20, height: 4)).width == 0)
    }

    @Test("A zero-sized terminal does not produce negative geometry")
    func degenerateTerminal() {
        // The negative-size class: chrome subtractions reach zero on a tiny
        // terminal and every container has to survive it.
        let buffer = renderToBuffer(
            Grid {
                GridRow {
                    Text("a")
                    Text("b")
                }
            },
            context: makeRenderContext(width: 0, height: 0))
        #expect(buffer.width >= 0)
    }

    @Test("A modifier on one row leaves the grid's columns alone")
    func modifiedRowKeepsTheLattice() {
        // SwiftUI's GridRow documentation: "If you apply a view modifier to a
        // row, the row applies the modifier to all of the cells, similar to how
        // a Group behaves." The row is therefore still a row, and its cells
        // still belong to the grid's columns.
        //
        // `.foregroundStyle` is the spelling the audit reported, and it builds
        // `_StyleEnvironmentView`; the `.padding` twin below is the one that
        // goes through `ModifiedView`. Both reach `GridRowProviding` now, by
        // two different routes, so both spellings are checked.
        let plain = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("b")
                }
                GridRow {
                    Text("cc")
                    Text("dd")
                }
            })
        let modified = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("b")
                }
                GridRow {
                    Text("cc")
                    Text("dd")
                }
                .foregroundStyle(.red)
            })
        #expect(
            modified.map { $0.trimmingCharacters(in: .whitespaces) }
                == plain.map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(
            modified.last?.hasPrefix("cc  dd") == true,
            "the modified row's cells belong to the grid's columns, so dd starts at x=4")
    }

    @Test("A padded row is still a row, and the padding lands on its cells")
    func paddedRowIsStillARow() {
        // The same rule through `ModifiedView`, checked against the oracle
        // SwiftUI's sentence gives: the modifier written on each cell instead.
        let rowModified = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("b")
                }
                GridRow {
                    Text("cc")
                    Text("dd")
                }
                .padding(.horizontal, 1)
            })
        let cellModified = lines(
            Grid(alignment: .leading) {
                GridRow {
                    Text("aaa")
                    Text("b")
                }
                GridRow {
                    Text("cc").padding(.horizontal, 1)
                    Text("dd").padding(.horizontal, 1)
                }
            })
        #expect(rowModified == cellModified)
    }

    @Test("A row carrying an environment value is still a row")
    func environmentWrappedRowIsStillARow() {
        // `.tint(_:)` builds `TintModifier`, and `.environment(_:_:)` builds
        // `EnvironmentModifier` — which lives in TUIkitView, below the module
        // `GridRowProviding` is declared in, so its conformance is written in
        // Grid.swift. Both spellings are checked because that split is the kind
        // of thing that leaves one of a pair behind.
        let plain = lines(
            Grid(alignment: .leading) {
                GridRow { Text("aaa"); Text("b") }
                GridRow { Text("cc"); Text("dd") }
            })
        let tinted = lines(
            Grid(alignment: .leading) {
                GridRow { Text("aaa"); Text("b") }
                GridRow { Text("cc"); Text("dd") }.tint(.blue)
            })
        let scoped = lines(
            Grid(alignment: .leading) {
                GridRow { Text("aaa"); Text("b") }
                GridRow { Text("cc"); Text("dd") }.environment(\.lineLimit, .lines(3))
            })
        #expect(
            tinted.map { $0.trimmingCharacters(in: .whitespaces) }
                == plain.map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(
            scoped.map { $0.trimmingCharacters(in: .whitespaces) }
                == plain.map { $0.trimmingCharacters(in: .whitespaces) })
        #expect(
            scoped.last?.hasPrefix("cc  dd") == true,
            "the wrapped row's cells belong to the grid's columns, so dd starts at x=4")
    }

    @Test("A GridRow outside a Grid still lays its cells out in a row")
    func rowWithoutGrid() {
        let rendered = lines(GridRow { Text("a"); Text("b") })
        #expect(rendered[0].hasPrefix("a b"))
    }

    /// The case `measureMatchesRender` cannot see, because it measures and
    /// renders in ONE context, so the proposal and `availableWidth` never
    /// disagree.
    ///
    /// A squeezing `HStack` makes them disagree: it re-measures a column it
    /// narrowed at `ProposedSize(width: allocated)` with the ROW's context,
    /// then renders the column at the allocation. `lattice` measured its cells
    /// against the context alone, so the grid reported the height of a wrap it
    /// never draws and the row clipped the line it had not budgeted for.
    ///
    /// Spaced words on purpose, unlike the space-less strings the ViewThatFits
    /// twin of this test uses: the defect IS a re-wrap. The sentence wraps to
    /// 2 lines at 20 cells and to 3 ("alpha beta" / "gamma delta" / "epsilon",
    /// 11 wide) at 15.
    @Test("A grid squeezed by its parent reports the size it draws at the proposed width")
    func squeezedGridMeasuresAtTheProposal() {
        let grid = Grid {
            GridRow { Text("alpha beta gamma delta epsilon") }
        }

        let squeezed = measureChild(
            grid, proposal: ProposedSize(width: 15, height: nil), context: makeRenderContext(width: 20, height: 12))
        let drawn = renderToBuffer(grid, context: makeRenderContext(width: 15, height: 12))
        #expect(drawn.lines.count == 3)
        #expect(squeezed.height == drawn.lines.count)
        #expect(squeezed.width == drawn.width)

        // …and the row that does the squeezing keeps the line. 20 - 4 ("TAIL")
        // - 1 (spacing) = 15 cells for the grid.
        let row = renderToBuffer(
            HStack(alignment: .top, spacing: 1) {
                Text("TAIL")
                grid
            },
            context: makeRenderContext(width: 20, height: 12))
        let stripped = row.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        #expect(row.lines.count == 3)
        #expect(stripped == ["TAIL alpha beta", "gamma delta", "epsilon"])
    }
}
