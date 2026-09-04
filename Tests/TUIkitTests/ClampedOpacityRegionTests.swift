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
