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
}
