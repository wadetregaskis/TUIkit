//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OptionListNavigationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// The shared jump-navigation maths behind Home/End/Page/Shift-accelerated
/// movement in the flat option lists (radio group, Picker drop-down, Menu).
/// These lock the *clamping, no-wrap* contract those controls all rely on.
@Suite("OptionListNavigation")
struct OptionListNavigationTests {
    /// A vertical-list call (on-axis = up/down), matching a Picker drop-down or a
    /// vertical radio group.
    private func dest(
        _ key: Key, from index: Int, count: Int = 10,
        shift: Bool = false, multiplier: Int = 5, pageSize: Int = 3
    ) -> Int? {
        OptionListNavigation.clampedDestination(
            for: KeyEvent(key: key, shift: shift),
            from: index, count: count,
            onAxisForward: .down, onAxisBackward: .up,
            multiplier: multiplier, pageSize: pageSize)
    }

    @Test("Home jumps to the first option, End to the last")
    func homeEnd() {
        #expect(dest(.home, from: 5) == 0)
        #expect(dest(.end, from: 5) == 9)
    }

    @Test("Page moves by pageSize and clamps at both ends (never wraps)")
    func pageClamps() {
        #expect(dest(.pageDown, from: 0, pageSize: 3) == 3)
        #expect(dest(.pageUp, from: 5, pageSize: 3) == 2)
        // Overshooting a boundary lands ON it, not past / wrapped.
        #expect(dest(.pageUp, from: 1, pageSize: 3) == 0)
        #expect(dest(.pageDown, from: 8, pageSize: 3) == 9)
    }

    @Test("Shift + on-axis arrow accelerates by the multiplier, clamped")
    func shiftAccelerates() {
        #expect(dest(.down, from: 0, shift: true, multiplier: 5) == 5)
        #expect(dest(.up, from: 7, shift: true, multiplier: 5) == 2)
        #expect(dest(.down, from: 8, shift: true, multiplier: 5) == 9)  // clamps
        #expect(dest(.up, from: 1, shift: true, multiplier: 5) == 0)  // clamps
    }

    @Test("A plain (Shift-less) arrow is not handled — caller owns plain movement")
    func plainArrowUnhandled() {
        #expect(dest(.down, from: 0, shift: false) == nil)
        #expect(dest(.up, from: 5, shift: false) == nil)
    }

    @Test("Off-axis and unrelated keys return nil")
    func offAxisUnhandled() {
        // Left/Right aren't on-axis for a vertical list, even with Shift.
        #expect(dest(.left, from: 5, shift: true) == nil)
        #expect(dest(.right, from: 5, shift: true) == nil)
        #expect(dest(.enter, from: 5) == nil)
        #expect(dest(.character("x"), from: 5) == nil)
    }

    @Test("An empty list handles nothing")
    func emptyList() {
        #expect(dest(.home, from: 0, count: 0) == nil)
        #expect(dest(.end, from: 0, count: 0) == nil)
    }

    @Test("A horizontal axis accelerates on Left/Right, not Up/Down")
    func horizontalAxis() {
        func hdest(_ key: Key, shift: Bool) -> Int? {
            OptionListNavigation.clampedDestination(
                for: KeyEvent(key: key, shift: shift), from: 4, count: 10,
                onAxisForward: .right, onAxisBackward: .left, multiplier: 3, pageSize: 10)
        }
        #expect(hdest(.right, shift: true) == 7)
        #expect(hdest(.left, shift: true) == 1)
        #expect(hdest(.down, shift: true) == nil)  // off-axis here
        #expect(hdest(.up, shift: true) == nil)
    }

    @Test("pageSize == count collapses Page onto Home/End (a viewport-less list)")
    func pageSizeEqualsCountIsHomeEnd() {
        // How a radio group calls it: no viewport, so Page jumps to the ends.
        #expect(dest(.pageUp, from: 5, pageSize: 10) == 0)
        #expect(dest(.pageDown, from: 5, pageSize: 10) == 9)
    }
}
