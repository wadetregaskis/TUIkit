//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TightViewportTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// What a view draws when the terminal is smaller than its own decoration.
///
/// Chrome that sits BEFORE the content — a leading pad column, a top pad row,
/// a border's first line — is an offset, and an offset is measured from an
/// edge the viewport may not extend past. Given one row, a `.padding()` used to
/// emit its blank top row first and the content on row 1, so the single row the
/// terminal could show was the blank one: the whole screen went empty. It was
/// found by sweeping the stress harness from 1×1 upward, where two scenarios
/// rendered nothing at all below 2×2 while the other nineteen drew something.
///
/// The rule these pin down is one line long: **decoration that precedes the
/// content may never take the last cell.** Trailing and bottom insets need no
/// such clamp — they follow the content, so they can overflow harmlessly.
@Suite("Chrome never hides content in a tight viewport")
struct TightViewportTests {

    /// Every line of `buffer`, trimmed to the viewport, with SGR removed.
    @MainActor
    private func visible(_ buffer: FrameBuffer, width: Int, height: Int) -> String {
        buffer.lines.prefix(height)
            .map { String($0.stripped.prefix(width)) }
            .joined()
    }

    @Test(
        "A padded view keeps its content on screen at every viewport size",
        arguments: [1, 2, 3, 4, 8], [1, 2, 3, 4, 8])
    @MainActor
    func paddedContentStaysVisible(width: Int, height: Int) {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(Text("X").padding(), context: context)
        #expect(
            visible(buffer, width: width, height: height).contains("X"),
            "\(width)×\(height): the padding hid the content it was decorating")
    }

    /// A border costs a cell on each side of each axis, so it cannot show both
    /// its chrome and its content in fewer than three, and something has to
    /// give. What must NOT give is the whole view: before this, two rows drew
    /// literally nothing, because the body was offered `max(0, 2 - 2)` rows,
    /// rendered empty, and an empty body collapses its container.
    ///
    /// So the boundary is asserted rather than described. From 2×2 the content
    /// is on screen with the border clipped around it; at one row or one
    /// column there is no room for both and the box wins, which at least says
    /// a box is there. The earlier spelling of this test only checked the
    /// visible region was not blank — which the border's own glyphs satisfy,
    /// so it would have passed with the content off-screen at every size, and
    /// said nothing about the half that matters.
    @Test(
        "A bordered view shows its content from 2×2, and its box below that",
        arguments: [1, 2, 3, 4, 8], [1, 2, 3, 4, 8])
    @MainActor
    func borderedContentStaysVisible(width: Int, height: Int) {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(Text("X").border(), context: context)
        let shown = visible(buffer, width: width, height: height)
        #expect(
            !shown.trimmingCharacters(in: .whitespaces).isEmpty,
            "\(width)×\(height): the border drew nothing at all")
        if width >= 2 && height >= 2 {
            #expect(
                shown.contains("X"),
                "\(width)×\(height): the border hid the content it was drawn around")
        }
    }

    /// The shape the sweep actually failed on: a stack of content under a
    /// single root `.padding()`, which is how both stress scenarios and most
    /// real apps are built.
    @Test(
        "A padded stack keeps its first row on screen at every viewport size",
        arguments: [1, 2, 3, 6, 12], [1, 2, 3, 6, 12])
    @MainActor
    func paddedStackStaysVisible(width: Int, height: Int) {
        let view = VStack {
            Text("AAA")
            Text("BBB")
        }
        .padding()
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let shown = visible(buffer, width: width, height: height)
        #expect(
            !shown.trimmingCharacters(in: .whitespaces).isEmpty,
            "\(width)×\(height): a padded stack rendered a blank screen")
    }

    /// The clamp must not cost anything once there is room, or every padded
    /// view in a normal terminal would shift by a cell.
    @Test("Padding is untouched as soon as the viewport can afford it")
    @MainActor
    func paddingIsIntactWhenItFits() {
        let context = RenderContext(
            availableWidth: 20, availableHeight: 5, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let buffer = renderToBuffer(Text("X").padding(), context: context)
        #expect(buffer.lines.count == 3, "one row of content between two pad rows")
        #expect(
            buffer.lines[0].stripped.trimmingCharacters(in: .whitespaces).isEmpty,
            "the top pad row is still blank")
        #expect(
            buffer.lines[1].stripped.hasPrefix(" X"),
            "the content still starts one cell in, not at the edge")
    }
}
