//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HStackRampOffsetTests.swift
//
//  Where a row's child sits vertically inside a `.gradientExtent(.subtree)`
//  ramp. `_HStackCore` derives that offset from the heights its layout
//  already measured rather than measuring every child a second time; these
//  pin that the offset is still right for every alignment, that a child
//  which fills its height is still asked, and that the second measure is
//  gone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("HStack ramp offset")
struct HStackRampOffsetTests {

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    private func vertical() -> LinearGradient {
        LinearGradient(
            colors: [Color.rgb(255, 0, 0), Color.rgb(0, 0, 255)], startPoint: .top, endPoint: .bottom)
    }

    private func horizontal() -> LinearGradient {
        LinearGradient(
            colors: [Color.rgb(255, 0, 0), Color.rgb(0, 0, 255)], startPoint: .leading,
            endPoint: .trailing)
    }

    /// A three-row column beside a one-row leaf: the leaf's ink must be the ink
    /// of the column row it stands on, which is what "one ramp across the row"
    /// means once alignment moves the leaf down.
    private func leafRow(_ alignment: VerticalAlignment, expectedRow: Int) {
        let lines = renderToBuffer(
            HStack(alignment: alignment, spacing: 0) {
                VStack(spacing: 0) {
                    Text(verbatim: "AAA")
                    Text(verbatim: "BBB")
                    Text(verbatim: "CCC")
                }
                Text(verbatim: "X")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        #expect(lines.count == 3, "\(lines)")
        let leaf = (0..<3).map { truecolorInk(lines[$0], atColumn: 3) }
        let column = (0..<3).map { truecolorInk(lines[$0], atColumn: 0) }
        #expect(Set(column.compactMap { $0 }).count == 3, "the column's rows are three steps: \(column)")
        #expect(leaf.compactMap { $0 }.count == 1, "the leaf occupies one row: \(leaf)")
        #expect(leaf[expectedRow] != nil, "the leaf stands on row \(expectedRow): \(leaf)")
        #expect(leaf[expectedRow] == column[expectedRow], "the leaf takes its row's ink: \(leaf) vs \(column)")
    }

    @Test("A bottom-aligned leaf takes the bottom row's ink")
    func bottomAlignedLeaf() { leafRow(.bottom, expectedRow: 2) }

    @Test("A centre-aligned leaf takes the middle row's ink")
    func centreAlignedLeaf() { leafRow(.center, expectedRow: 1) }

    @Test("A top-aligned leaf takes the top row's ink")
    func topAlignedLeaf() { leafRow(.top, expectedRow: 0) }

    /// A sibling that fills its height (a row `Divider`) takes the fallback
    /// path — it is measured at the row height — and must neither move the
    /// rigid leaf nor fail to span the row itself.
    @Test("A height-filling sibling is still placed by measurement")
    func fillingSiblingIsMeasured() {
        let lines = renderToBuffer(
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Text(verbatim: "AAA")
                    Text(verbatim: "BBB")
                    Text(verbatim: "CCC")
                }
                Divider()
                Text(verbatim: "X")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        #expect(lines.count == 3, "\(lines)")
        let divider = (0..<3).map { truecolorInk(lines[$0], atColumn: 3) }
        #expect(divider.allSatisfy { $0 != nil }, "the divider spans the row: \(divider)")
        #expect(
            truecolorInk(lines[2], atColumn: 4) == truecolorInk(lines[2], atColumn: 0),
            "the leaf still stands on the bottom row with the bottom row's ink")
    }

    /// The optimisation itself: under a ramp a rigid child is measured ONCE per
    /// render (by the layout), not twice (again for its ramp offset).
    @Test("A rigid child under a ramp is measured once per render")
    func rigidChildMeasuredOnce() {
        final class Box { var measures = 0 }
        let box = Box()
        let view = HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Text(verbatim: "AAA")
                Text(verbatim: "BBB")
            }
            Text(verbatim: "X").onRenderPass { if $0 == .measure { box.measures += 1 } }
        }
        .foregroundStyle(vertical())
        .gradientExtent(.subtree)
        _ = renderToBuffer(view, context: context())
        #expect(box.measures == 1, "measured \(box.measures) times; the layout's measure is the only one")
    }

    /// A spacer is neither measured nor placed, but the child after it must
    /// still land where the spacer's width puts it — at the far end of the ramp.
    @Test("A spacer advances the ramp without being measured")
    func spacerAdvancesTheRamp() {
        let lines = renderToBuffer(
            HStack(spacing: 0) {
                Text(verbatim: "AA")
                Spacer()
                Text(verbatim: "BB")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context(width: 10)
        ).lines
        let cells = truecolorInks(lines[0])
        #expect(cells.count == 10, "\(cells)")
        #expect(cells[0] == "255;0;0", "the row starts at the ramp's start: \(cells)")
        #expect(cells[9] == "0;0;255", "the trailing leaf ends at the ramp's end: \(cells)")
        #expect(cells[2...7].allSatisfy { $0 == nil }, "the spacer draws nothing: \(cells)")
    }
}
