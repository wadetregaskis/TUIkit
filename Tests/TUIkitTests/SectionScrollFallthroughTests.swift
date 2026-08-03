//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SectionScrollFallthroughTests.swift
//
//  Page/Home/End keys the focused element didn't consume scroll the
//  section's one scroller — as USER scrolls. These pin the entry-point
//  contract: the fallback used raw `scroll(by:)`/`scrollOffset` writes,
//  which bypassed the shadow anchor (a bound anchor stayed engaged and
//  snapped the viewport straight back — PageDown appeared dead), left a
//  wheel's sub-row clip in place on Home, and never engaged the edges or
//  a ScrollView's tail seek on End.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Section scroll fall-through (Page/Home/End)")
struct SectionScrollFallthroughTests {

    /// A `@State`-like box the anchor binding writes through.
    private final class AnchorBox {
        var value: ScrollAnchor<AnyHashable>?
        init(_ value: ScrollAnchor<AnyHashable>?) { self.value = value }
    }

    /// A focus manager holding a focused non-scrolling control and one
    /// overflowing ScrollView — the "Button inside a scrollable page" shape
    /// the fallback exists for.
    private func makeSection() -> (FocusManager, ScrollViewHandler, AnchorBox) {
        let manager = FocusManager()
        let button = MockFocusable(id: "btn")
        manager.register(button)

        let scroller = ScrollViewHandler(focusID: "sv")
        scroller.contentHeight = 50
        scroller.viewportHeight = 10
        let box = AnchorBox(nil)
        scroller.anchorPositionBinding = Binding(
            get: { box.value }, set: { box.value = $0 })
        manager.register(scroller)
        manager.focus(button)
        return (manager, scroller, box)
    }

    @Test("PageDown releases a bound anchor (else it snaps the scroll back)")
    func pageDownReleasesAnchor() {
        let (manager, scroller, box) = makeSection()
        // As if the app bound an anchor and the view is holding it.
        box.value = .bottom

        #expect(manager.dispatchKeyEvent(KeyEvent(key: .pageDown)))
        #expect(scroller.scrollOffset == 10, "one viewport page")
        #expect(
            box.value == ScrollAnchor<AnyHashable>.window,
            "a user scroll must release the held anchor, or the hold snaps the viewport straight back")
    }

    @Test("End engages the bottom edge and seeks the tail")
    func endEngagesBottomEdge() {
        let (manager, scroller, box) = makeSection()

        #expect(manager.dispatchKeyEvent(KeyEvent(key: .end)))
        #expect(scroller.scrollOffset == scroller.maxOffset)
        #expect(box.value == ScrollAnchor<AnyHashable>.bottom, "§1.3: End restores anchor-to-bottom")
        #expect(scroller.seekingTail, "an End while content streams in pins the TAIL, not this offset")
    }

    @Test("Home engages the top edge")
    func homeEngagesTopEdge() {
        let (manager, scroller, box) = makeSection()
        scroller.scrollOffset = 20

        #expect(manager.dispatchKeyEvent(KeyEvent(key: .home)))
        #expect(scroller.scrollOffset == 0)
        #expect(box.value == ScrollAnchor<AnyHashable>.top, "§1.3: Home restores anchor-to-top")
    }

    @Test("The fallback respects .scrollDisabled")
    func scrollDisabledIsRespected() {
        let (manager, scroller, _) = makeSection()
        scroller.isScrollEnabled = false

        #expect(!manager.dispatchKeyEvent(KeyEvent(key: .pageDown)))
        #expect(scroller.scrollOffset == 0, "a gesture must not move a scroll-disabled viewport")
    }
}
