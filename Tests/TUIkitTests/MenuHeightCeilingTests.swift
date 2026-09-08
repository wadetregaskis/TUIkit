//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuHeightCeilingTests.swift
//
//  A menu is laid out against a canvas taller than the screen, because the
//  renderer windows rows that have to exist first. That canvas used to be
//  `max(availableHeight * 64, 4096)` — a ceiling wearing a generous canvas's
//  clothes. These pin that a menu longer than any such constant still reaches
//  its last row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("A menu has no height ceiling")
struct MenuHeightCeilingTests {
    private func context(width: Int = 60, height: Int = 40) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// 50 is the ordinary case; the other two straddle the 4,096 the old canvas
    /// stopped at. At 5,000 and 9,000 rows the highlight could be moved to the
    /// last ordinal — the rows all rendered and published — but the column had
    /// only 4,096 LINES to be sliced into, so the drop-down had nothing to show
    /// for it and no way to scroll there.
    @Test("a pop-up menu can show its last row", arguments: [50, 5_000, 9_000])
    func popUpReachesItsLastRow(count: Int) {
        let controller = MenuPopupController()
        let items = ForEach(0..<count, id: \.self) { index in Button("Item \(index)") {} }
        // Twice: the first render is what publishes the selectable ordinals the
        // highlight then moves within.
        _ = renderMenuPopup(items, context: context(), controller: controller, dismiss: {})
        controller.highlight.move(to: count - 1)
        let buffer = renderMenuPopup(
            items, context: context(), controller: controller, dismiss: {})
        let text = buffer.lines.joined(separator: "\n").stripped
        #expect(text.contains("Item \(count - 1)"), "\(count) rows: last row not drawn")
    }

    /// The inline menu's overflow question is "taller than the cap?", and the
    /// answer must not depend on how much taller. It asks at `capHeight + 1`
    /// now; a menu of any length is the same one bit.
    @Test("an inline menu scrolls at any length", arguments: [50, 5_000, 9_000])
    func inlineScrollsAtAnyLength(count: Int) {
        let items = ForEach(0..<count, id: \.self) { index in Button("Item \(index)") {} }
        let size = measureMenuColumn(items, context: context(), capHeight: 40)
        let drawn = renderMenuColumn(items, context: context(), capHeight: 40)
        #expect(size.height == 40, "\(count) rows: measured \(size.height)")
        #expect(drawn.height == 40, "\(count) rows: drew \(drawn.height)")
        #expect(size.width == drawn.width, "\(count) rows")
    }

    /// The overflow question has to be asked of the height the menu DRAWS, not
    /// the height its rows asked for while hugging.
    ///
    /// A row is measured against the menu's whole interior while it hugs, and
    /// drawn into that interior less the hint column beside it — so a label
    /// with a space in it can wrap into the difference, and the drawn column is
    /// taller than the hug said. Where the hug fitted the cap and the reflow
    /// did not, the probe was skipped, the non-scrolling arm taken, and the
    /// trailing rows clipped away with no scrollbar and no way to reach them.
    ///
    /// The width is chosen to CLAMP — narrow enough that the hug wants every
    /// cell — because that is the only arm on which rows reflow at all.
    @Test("A menu whose rows reflow past the cap scrolls rather than losing them")
    func reflowPastTheCapStillScrolls() {
        // Labels with a space and a key equivalent: the hint takes a column
        // beside the label, so the label is drawn narrower than it hugged and
        // wraps at the space.
        // SIX rows, so the hug height (six rows plus the border) sits UNDER the
        // twelve-row cap — which is the whole point. A menu with more rows than
        // the cap overflows while hugging and asks the question anyway; this one
        // only overflows once its labels wrap, which is the case the old gate
        // could not see.
        let items = ForEach(0..<6, id: \.self) { index in
            Button("Delete Everything \(index)") {}
                .keyboardShortcut(KeyEquivalent("\u{7F}"))
        }
        // Width 26 is the band that matters. Narrower and the labels wrap
        // during the HUG too, so the hug height clears the cap on its own and
        // the old gate asked the question anyway; wider and nothing wraps at
        // all. Here the hug is eight rows and the draw is fourteen.
        let narrow = context(width: 26, height: 12)
        let size = measureMenuColumn(items, context: narrow, capHeight: 12)
        let drawn = renderMenuColumn(items, context: narrow, capHeight: 12)
        let text = drawn.lines.map(\.stripped).joined(separator: "\n")
        // The assertion is REACHABILITY, not height. Both arms come back twelve
        // rows tall — the render clips whatever it produced to the cap — so a
        // height comparison sees nothing. What the non-scrolling arm loses is
        // the rows past the cap, with no way to get to them; the scrolling arm
        // puts a bar in its own column, which is the visible difference.
        #expect(
            text.contains("▲") || text.contains("▼"),
            "the column overflowed its cap with no way to scroll:\n\(text)")
        #expect(size.height == drawn.height, "measured \(size.height), drew \(drawn.height)")
    }
}
