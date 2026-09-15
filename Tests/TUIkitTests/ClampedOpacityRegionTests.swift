//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClampedOpacityRegionTests.swift
//
//  `clamped(toWidth:height:)` cut hit regions to the box and dropped runs
//  whose cells were clipped away — and carried opacity regions verbatim. A
//  region kept for rows that no longer exist names whatever a later sibling
//  puts there, and at the root the alpha of those cells is read off it: a
//  TabView's filler rows and its bottom rule faded because a tab's faded
//  content had been cut to the panel's budget.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Clamping trims the opacity region with its cells")
struct ClampedOpacityRegionTests {

    @Test("A clipped fade does not outlive its cells")
    func clampTrimsTheRegion() {
        var child = FrameBuffer(lines: ["abcdef", "abcdef", "abcdef"])
        child.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 6, height: 3, opacity: 0.5)]
        let clipped = child.clamped(toWidth: 3, height: 1)
        #expect(clipped.opacityRegions == [OpacityRegion(offsetX: 0, offsetY: 0, width: 3, height: 1, opacity: 0.5)])

        // The consequence: a sibling taking the clipped-away columns is left alone.
        var row = clipped
        row.appendHorizontally(FrameBuffer(text: "XYZ"))
        let palette = EnvironmentValues().palette
        let resolved = row.resolvingOpacity(surface: palette.background, palette: palette)
        #expect(resolved.lines[0].hasSuffix("XYZ"), "the sibling's cells were rewritten: \(resolved.lines[0].debugDescription)")
    }

    @Test("A region entirely outside the box is dropped; one straddling it is cut, not moved")
    func regionsOutsideAndStraddling() {
        var child = FrameBuffer(lines: ["abcdef", "abcdef", "abcdef"])
        child.opacityRegions = [
            OpacityRegion(offsetX: 4, offsetY: 2, width: 2, height: 1, opacity: 0.5),
            OpacityRegion(offsetX: 2, offsetY: 0, width: 4, height: 2, opacity: 0.25),
        ]
        let clipped = child.clamped(toWidth: 4, height: 1)
        #expect(clipped.opacityRegions == [OpacityRegion(offsetX: 2, offsetY: 0, width: 2, height: 1, opacity: 0.25)])
    }
}

/// The scroll window trimmed the region's ROWS and left its COLUMNS whole, so a
/// horizontally-scrolling view carried a fade wider than its own viewport out
/// into the page: over a sibling beside it, and over its own scrollbar column.
/// The commit that introduced the clip said "a region wider than a row must not
/// reach the scrollbar" and clipped one axis.
@MainActor
@Suite("The scroll window trims the opacity region on both axes")
struct ScrollWindowOpacityClipTests {

    private static func core() -> _ScrollViewCore<Text> {
        _ScrollViewCore(
            axes: .horizontal, content: Text("x"), explicitFocusID: nil, isDisabled: false)
    }

    /// One 60-cell line under a 40% fade — what `Text(60 cells).opacity(0.4)`
    /// leaves when a horizontal ScrollView renders it at its natural width.
    private static func wideFadedContent() -> FrameBuffer {
        var full = FrameBuffer(
            lines: [String(repeating: "x", count: 60)], width: 60, uniformWidth: true)
        full.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 60, height: 1, opacity: 0.4)
        ]
        return full
    }

    @Test("A region wider than the viewport is cut to it, not carried into the page")
    func widerThanTheViewport() {
        let window = Self.core().windowedBuffer(
            full: Self.wideFadedContent(), scrollOffset: 0, viewportHeight: 3, viewportWidth: 20,
            horizontalEnabled: true, horizontalOffset: 0)
        #expect(
            window.opacityRegions == [
                OpacityRegion(offsetX: 0, offsetY: 0, width: 20, height: 1, opacity: 0.4)
            ])

        // The consequence, and the shape the bug was found in: a sibling to the
        // right of the scroller is left alone. Uncut, the region reached column
        // 26 and all seven cells of "SIDEBAR" came back with a blended
        // foreground they never asked for.
        var row = window
        row.appendHorizontally(FrameBuffer(text: "SIDEBAR"))
        let palette = EnvironmentValues().palette
        let resolved = row.resolvingOpacity(surface: palette.background, palette: palette)
        #expect(
            resolved.lines[0].hasSuffix("SIDEBAR"),
            "the sibling's cells were faded: \(resolved.lines[0].debugDescription)")
    }

    @Test("Scrolled right, the region still stops at the viewport's edge")
    func scrolledRight() {
        // dx = -12 moves the rectangle to columns -12…47; the viewport is 0…19,
        // and the scrollbar the page draws next sits at column 20.
        let window = Self.core().windowedBuffer(
            full: Self.wideFadedContent(), scrollOffset: 0, viewportHeight: 3, viewportWidth: 20,
            horizontalEnabled: true, horizontalOffset: 12)
        #expect(
            window.opacityRegions == [
                OpacityRegion(offsetX: 0, offsetY: 0, width: 20, height: 1, opacity: 0.4)
            ])
    }

    /// The overwrite path replaces a scroll view's first or last line with an "N
    /// more" indicator, and filtered the content's RUNS off that row — but not its
    /// claims. A translucent content line under "▼ N more below" left its claim
    /// behind, and the indicator resolved at the content's alpha (§50).
    ///
    /// Lines exactly one viewport wide, so none wraps short of the indicator's
    /// column; an opaque palette, so the indicator's own paint is not the subject.
    @Test("An indicator overwriting a row takes the content's claims on it away")
    func overwrittenRowKeepsNoClaim() throws {
        let width = 24
        let faded = Color.red.opacity(0.5)
        let drawn = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<30, id: \.self) { _ in
                        Text(String(repeating: "x", count: width)).foregroundStyle(faded)
                    }
                }
            }
            .scrollIndicatorStyle(.text),
            context: makeRenderContext(width: width, height: 8))
        // At offset 0 only the bottom indicator shows, on the last row.
        let arrow = try #require(cells(of: "▼", in: drawn).first, "\(drawn.lines.map(\.stripped))")
        // The precondition: the content's claim really does reach that column on the
        // row above, or the assertion below would prove nothing.
        let above = owed(atColumn: arrow.column, row: arrow.row - 1, in: drawn)
        #expect(above.ink == owed(faded), "the row above owes \(above)")
        let owes = owed(atColumn: arrow.column, row: arrow.row, in: drawn)
        #expect(owes.ink == 1 && owes.field == 1, "the ▼ cell owes \(owes)")
    }
}
