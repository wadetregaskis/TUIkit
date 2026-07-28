//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Self.swift
//
//  The walk that a pop-up `Menu`, a `.contextMenu`, a `Picker`'s drop-down and
//  a combo box's suggestions menu all share.
//
//  These four used to implement it three times over, and the copies disagreed
//  in ways nobody had decided: the jump keys reached one of them long before
//  the others, and each edge rule was settled where it happened to be written.
//  Now there is one implementation and two knobs, so the interesting thing to
//  test is the KNOBS — that the surfaces still differ exactly where they are
//  meant to, and nowhere else. Every case below is therefore parameterised over
//  the real configurations rather than over a made-up one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@Suite("Menu highlight")
struct MenuHighlightTests {

    /// The configurations that actually ship, named by the control that uses
    /// them — the SAME factories the controls call, so a control given the
    /// wrong one is a change these tests can see.
    typealias Config = (name: String, build: @Sendable () -> MenuHighlight)

    private static let popUp: Config = ("Menu / .contextMenu", MenuHighlight.popUpMenu)
    private static let dropDown: Config = ("Picker drop-down", MenuHighlight.pickerDropDown)
    private static let suggestions: Config = ("combo box", MenuHighlight.suggestions)

    private static let all = [popUp, dropDown, suggestions]

    private func make(_ config: Config, count: Int = 4, at ordinal: Int? = nil) -> MenuHighlight {
        let highlight = config.build()
        highlight.adopt(count: count)
        highlight.move(to: ordinal)
        return highlight
    }

    /// A key press, with the page size a four-row menu would report.
    @discardableResult
    private func press(_ highlight: MenuHighlight, _ event: KeyEvent) -> Bool {
        highlight.handle(event, multiplier: 5, pageSize: 4)
    }

    // MARK: - What every surface agrees on

    @Test("A plain arrow steps one row", arguments: Self.all)
    func plainArrowSteps(config: Config) {
        let highlight = make(config, at: 1)
        #expect(press(highlight, KeyEvent(key: .down)))
        #expect(highlight.ordinal == 2, "\(config.name)")
        #expect(press(highlight, KeyEvent(key: .up)))
        #expect(highlight.ordinal == 1, "\(config.name)")
    }

    /// The gestures a `List`, a `Table` and a `RadioButtonGroup` all answer.
    /// A menu answering them differently would be the drift this file exists
    /// to prevent.
    @Test(
        "The jump keys land in the same place everywhere",
        arguments: Self.all,
        [
            (KeyEvent(key: .home), 0), (KeyEvent(key: .end), 3),
            (KeyEvent(key: .pageUp), 0), (KeyEvent(key: .pageDown), 3),
            (KeyEvent(key: .up, shift: true), 0), (KeyEvent(key: .down, shift: true), 3),
        ])
    func jumpKeys(
        config: Config, key: (KeyEvent, Int)
    ) {
        let highlight = make(config, at: 1)
        #expect(press(highlight, key.0), "\(config.name)")
        #expect(highlight.ordinal == key.1, "\(config.name)")
    }

    /// Even where a plain arrow wraps. A jump key names an END; one that
    /// overshot into the far end would be indistinguishable from a mis-press.
    @Test("A jump key clamps even in a wrapping list")
    func jumpKeysClampEvenWhenArrowsWrap() {
        let highlight = make(Self.dropDown, at: 3)
        #expect(press(highlight, KeyEvent(key: .end)))
        #expect(highlight.ordinal == 3, "already at the end, and it stays there")
        #expect(press(highlight, KeyEvent(key: .down, shift: true)))
        #expect(highlight.ordinal == 3, "a 5× step from the last row does not come round")
    }

    /// Dividers and disabled rows are not things you can pick, so a highlight
    /// is an ordinal over the SELECTABLE rows, not over the drawn ones.
    @Test("The walk skips whatever is not selectable", arguments: Self.all)
    func walkSkipsGaps(config: Config) {
        let highlight = config.build()
        highlight.adopt(selectable: [0, 2, 5])  // 1, 3 and 4 are a divider and two disabled rows
        highlight.move(to: 0)
        #expect(press(highlight, KeyEvent(key: .down)))
        #expect(highlight.ordinal == 2, "\(config.name)")
        #expect(press(highlight, KeyEvent(key: .down)))
        #expect(highlight.ordinal == 5, "\(config.name)")
        #expect(press(highlight, KeyEvent(key: .end)))
        #expect(highlight.ordinal == 5, "\(config.name)")
    }

    /// A menu is rebuilt every frame — a combo box filters its suggestions
    /// against the field's text, and any menu's content can change under it.
    @Test("A highlight whose row vanished moves to the nearest survivor")
    func vanishedRowMovesDown() {
        let highlight = make(Self.popUp, count: 6, at: 3)
        highlight.adopt(selectable: [0, 1, 5])
        #expect(highlight.ordinal == 5, "the next one still standing, below where it was")

        let atTheEnd = make(Self.popUp, count: 6, at: 5)
        atTheEnd.adopt(selectable: [0, 1, 2])
        #expect(atTheEnd.ordinal == 2, "…and the last one, when nothing below survived")
    }

    @Test("An empty menu answers nothing", arguments: Self.all)
    func emptyMenuIsInert(config: Config) {
        let highlight = make(config, count: 0)
        #expect(!press(highlight, KeyEvent(key: .down)), "\(config.name)")
        #expect(highlight.ordinal == nil, "\(config.name)")
    }

    // MARK: - Where they differ, on purpose

    /// The one deliberate difference in the edge rule. A drop-down's list is
    /// the whole interaction while it is up, so there is nothing to be jumped
    /// away from; a `Menu` and a combo box both have somewhere else the
    /// keyboard can be, so a wrap would read as a jump.
    @Test(
        "Only the Picker drop-down wraps at the ends",
        arguments: [
            (Self.popUp, 3, 0), (Self.suggestions, 3, 0),
            (Self.dropDown, 0, 3),
        ])
    func edgeRule(
        config: Config, downFromLast: Int, upFromFirst: Int
    ) {
        let atTheEnd = make(config, at: 3)
        #expect(press(atTheEnd, KeyEvent(key: .down)))
        #expect(atTheEnd.ordinal == downFromLast, "\(config.name)")

        let atTheStart = make(config, at: 0)
        #expect(press(atTheStart, KeyEvent(key: .up)))
        #expect(atTheStart.ordinal == upFromFirst, "\(config.name)")
    }

    /// From nothing, the list is entered at whichever end you came at it from —
    /// the same rule at both ends, and what NSComboBox and every pop-up menu do.
    @Test("Down enters at the top and Up at the bottom", arguments: Self.all)
    func enteringFromNothing(config: Config) {
        let viaDown = make(config, at: nil)
        #expect(press(viaDown, KeyEvent(key: .down)))
        #expect(viaDown.ordinal == 0, "\(config.name)")

        let viaUp = make(config, at: nil)
        #expect(press(viaUp, KeyEvent(key: .up)))
        #expect(viaUp.ordinal == 3, "\(config.name)")
    }

    /// The other deliberate difference, and a narrow one. A combo box's caret is
    /// still in the FIELD while nothing is highlighted, and Shift+arrow there
    /// means "extend the text selection" — so that one key stays with the field.
    ///
    /// Everything else reaches the menu the moment it is open. It used to
    /// depend on whether a row happened to be highlighted YET, which made the
    /// jump keys work or not work depending on how the menu had been opened:
    /// Down-opened put the highlight on row 0 and Home/End then drove the menu,
    /// while a pointer-opened menu with unmatched text left it nil and the same
    /// keys moved the caret instead. "Is the menu open" is the question; "is a
    /// row highlighted" never was.
    @Test(
        "Every unshifted key enters the combo box's menu",
        arguments: [
            (KeyEvent(key: .home), 0), (KeyEvent(key: .end), 3),
            (KeyEvent(key: .pageUp), 3), (KeyEvent(key: .pageDown), 0),
            (KeyEvent(key: .down), 0), (KeyEvent(key: .up), 3),
        ])
    func unshiftedKeysEnterTheMenu(key: KeyEvent, expected: Int) {
        let combo = make(Self.suggestions, at: nil)
        #expect(press(combo, key), "the open menu takes it")
        #expect(combo.ordinal == expected)
    }

    @Test(
        "A shifted arrow stays with the combo box's field",
        arguments: [KeyEvent(key: .down, shift: true), KeyEvent(key: .up, shift: true)])
    func shiftedArrowsStayWithTheField(key: KeyEvent) {
        let combo = make(Self.suggestions, at: nil)
        #expect(!press(combo, key), "the field keeps it, to extend the selection")
        #expect(combo.ordinal == nil, "and the menu was not entered")

        let menu = make(Self.popUp, at: nil)
        #expect(press(menu, key), "a pop-up menu has no field to keep it")
        #expect(menu.ordinal != nil)
    }

    // MARK: - Following the highlight

    /// A menu that scrolls follows its highlight only when the KEYBOARD moved
    /// it. Wheel and scrollbar movement move the window without moving the
    /// highlight, and must leave the window where the user put it — as a
    /// desktop drop-down does.
    @Test("Keyboard movement asks for a scroll; the pointer does not")
    func followPending() {
        let highlight = make(Self.dropDown, at: 0)
        #expect(highlight.consumeFollowPending(), "placing it asked for one")
        #expect(!highlight.consumeFollowPending(), "and the ask is consumed once")

        #expect(press(highlight, KeyEvent(key: .down)))
        #expect(highlight.consumeFollowPending(), "a key press asks")

        highlight.point(at: 3)
        #expect(!highlight.consumeFollowPending(), "a hover does not")
        #expect(highlight.ordinal == 3, "…but it does move the highlight")
    }

    @Test("Clearing the highlight asks for nothing")
    func clearingAsksForNoScroll() {
        let highlight = make(Self.popUp, at: 2)
        _ = highlight.consumeFollowPending()
        highlight.move(to: nil)
        #expect(!highlight.consumeFollowPending())
    }
}
