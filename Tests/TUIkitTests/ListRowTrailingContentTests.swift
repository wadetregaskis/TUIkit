//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowTrailingContentTests.swift
//
//  Regression tests for GitHub issue #5: a trailing view at the end of an
//  HStack-with-Spacer inside a List row (a right-flushed Spinner, Text, badge…)
//  must survive to the screen. Rows used to be extracted with the List's own
//  full-width context, so a width-greedy row filled the full List width; the
//  row gutters then pushed the line wider still and the border clamp chopped
//  the trailing cells — exactly where a right-flushed view sits.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("List row trailing content (issue #5)")
struct ListRowTrailingContentTests {
    /// All glyphs the default (.dots) spinner style can show, any frame.
    private let dotsGlyphs = Set("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

    private func strippedLines(_ view: some View, width: Int = 40, height: Int = 12) -> [String] {
        let context = makeRenderContext(width: width, height: height)
        return renderToBuffer(view, context: context).lines.map { $0.stripped }
    }

    @Test("The issue's exact shape: Spinner() trailing an HStack-with-Spacer row")
    func spinnerTrailingHStackInList() {
        let view = List("Items", selection: .constant(String?.none)) {
            ForEach(["Alpha", "Bravo", "Charlie", "Delta", "Echo"], id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Spinner()
                }
            }
        }
        let joined = strippedLines(view).joined()
        #expect(
            joined.contains { dotsGlyphs.contains($0) },
            "a label-less Spinner at the row's trailing edge renders")
    }

    @Test("Not Spinner-specific: right-aligned Text survives too")
    func trailingTextInList() {
        let view = List("Items", selection: .constant(String?.none)) {
            ForEach(["Alpha", "Bravo"], id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Text("42")
                }
            }
        }
        let lines = strippedLines(view)
        #expect(lines.joined().contains("42"), "right-flushed text renders: \(lines)")
    }

    @Test("Rows stay inside the border: no line wider than the List")
    func rowsFitTheInterior() {
        let view = List("Items", selection: .constant(String?.none)) {
            ForEach(["Alpha", "Bravo"], id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Text("42")
                }
            }
        }
        let lines = strippedLines(view)
        #expect(lines.allSatisfy { $0.count <= 40 }, "no overflow past the offered width")
        // The trailing view's last cell lands inside the border, with the
        // right gutter cell between it and the border column.
        if let row = lines.first(where: { $0.contains("42") }) {
            #expect(row.hasSuffix("42 │"), "trailing content sits flush to the right gutter: '\(row)'")
        }
    }

    @Test("With a scrollbar the trailing view AND the bar both render")
    func trailingContentWithScrollbar() {
        let view = List("Items", selection: .constant(String?.none)) {
            ForEach((0..<20).map { "Item \($0)" }, id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Text("★")
                }
            }
        }
        .scrollbarVisibility(.visible)

        let context = makeRenderContext(width: 40, height: 10)
        let lines = renderToBuffer(view, context: context).lines.map { $0.stripped }
        let joined = lines.joined()
        #expect(joined.contains("★"), "trailing view renders alongside the bar: \(lines)")
        // The bar's arrow cells sit in the last interior column; a greedy row
        // used to push the whole bar column past the border clamp.
        #expect(
            joined.contains("▲") && joined.contains("▼"),
            "the scrollbar column survives greedy rows: \(lines)")
    }

    @Test("The issue's NBSP-label workaround still renders (label preserved)")
    func nbspSpinnerLabelPreserved() {
        let view = List("Items", selection: .constant(String?.none)) {
            ForEach(["Alpha", "Bravo"], id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Spinner("\u{A0}\u{A0}\u{A0}")
                }
            }
        }
        let joined = strippedLines(view).joined()
        #expect(
            joined.contains { dotsGlyphs.contains($0) },
            "a whitespace-only label is honoured, not treated as no-label")
    }

    @Test("Control: the same row renders its trailing view outside a List")
    func bareHStackControl() {
        let view = HStack(spacing: 0) {
            Text("Alpha")
            Spacer()
            Spinner()
        }
        let joined = strippedLines(view).joined()
        #expect(joined.contains { dotsGlyphs.contains($0) })
    }

    @Test("Hugged list (.fixedSize) reserves the row gutters for its widest row")
    func huggedListKeepsWidestRowIntact() {
        let view = List("Items", selection: .constant(String?.none)) {
            ForEach(["Alpha", "Bravo the Wide"], id: \.self) { item in
                Text(item)
            }
        }
        .fixedSize(horizontal: true, vertical: false)

        let lines = strippedLines(view)
        #expect(
            lines.joined().contains("Bravo the Wide"),
            "the widest row is not clipped by its own gutters: \(lines)")
    }
}
