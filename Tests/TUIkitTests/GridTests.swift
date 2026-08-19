//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    @Test("A GridRow outside a Grid still lays its cells out in a row")
    func rowWithoutGrid() {
        let rendered = lines(GridRow { Text("a"); Text("b") })
        #expect(rendered[0].hasPrefix("a b"))
    }
}
