//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollStickyEdgeTests.swift
//
//  §1.3's sticky edges: "deliberately pushing PAST the top or bottom re-engages
//  the corresponding edge anchor. Merely GRAZING the edge (a scroll that happens
//  to land exactly there, no further) does not stick."
//
//  The distinction needs no timing or gesture heuristics, because
//  `userScrollFine(by:)` tries ordinary movement before the edge case: the step
//  that reaches an edge is spent getting there, so only a step the content
//  cannot absorb reaches the sticky branch. These tests pin that ordering, since
//  it is the whole mechanism.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Pushing past an edge sticks to it")
struct ScrollStickyEdgeTests {

    private final class Box {
        var anchor: ScrollAnchor<AnyHashable>?
    }

    /// A scrollable with real edges (100 lines in a 10-line viewport) and a
    /// bound anchor to observe.
    private func handler(
        declaring declared: ScrollAnchorMode = .window, extent: Int = 100
    ) -> (ScrollViewHandler, Box) {
        let box = Box()
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = extent
        handler.viewportHeight = 10
        handler.wheelEdgeHold.delayNanos = 0
        handler.declaredAnchorMode = declared
        handler.anchorPositionBinding = Binding(
            get: { box.anchor }, set: { box.anchor = $0 })
        return (handler, box)
    }

    // MARK: - Graze versus push

    @Test("Landing exactly on the bottom does not stick; the next push does")
    func grazeThenPush() {
        let (sv, box) = handler()
        sv.scrollOffset = sv.maxOffset - 2

        // Reaches the edge and stops there — this step was spent arriving.
        #expect(sv.userScrollFine(by: 2))
        #expect(sv.scrollOffset == sv.maxOffset)
        #expect(
            box.anchor == .window,
            """
            §1.3: a scroll that merely lands on the edge does not STICK. It did \
            move, so it is an ordinary §1.2 release — the distinction under test \
            is release-vs-stick, not whether anything happened.
            """)

        // Nothing left to absorb it: unambiguously deliberate.
        _ = sv.userScrollFine(by: 2)
        #expect(box.anchor == .bottom, "…and the next one sticks")
    }

    @Test("The same holds at the top")
    func grazeThenPushAtTop() {
        let (sv, box) = handler()
        sv.scrollOffset = 2
        #expect(sv.userScrollFine(by: -2))
        #expect(sv.scrollOffset == 0)
        #expect(box.anchor == .window, "arrived (so released), but did not stick")
        _ = sv.userScrollFine(by: -2)
        #expect(box.anchor == .top)
    }

    @Test("Sticking works from the keyboard too, not just the wheel")
    func arrowKeysStickToo() {
        let (sv, box) = handler()
        sv.scrollOffset = sv.maxOffset
        _ = sv.handleKeyEvent(KeyEvent(key: .down))
        #expect(
            box.anchor == .bottom,
            "§1.3 lists arrow keys alongside the wheel and the scrollbar")
    }

    @Test("A wheel tick pushing past the edge sticks")
    func wheelSticks() {
        let (sv, box) = handler()
        sv.scrollOffset = sv.maxOffset
        _ = sv.handleWheelEvent(MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
        #expect(box.anchor == .bottom)
    }

    // MARK: - Sticking versus releasing

    @Test("Scrolling away from an edge releases, as before")
    func scrollingAwayStillReleases() {
        let (sv, box) = handler()
        sv.scrollOffset = sv.maxOffset
        _ = sv.userScrollFine(by: 2)  // stick
        #expect(box.anchor == .bottom)

        _ = sv.userScrollFine(by: -3)  // scroll back into the content
        #expect(
            box.anchor == .window,
            "an ordinary scroll is still the §1.2 release — sticking did not replace it")
    }

    @Test("Sticking to the edge the view DECLARED restores nil, not that edge")
    func stickingToTheDeclaredEdgeRestoresNil() {
        let (sv, box) = handler(declaring: .bottom)
        box.anchor = .window  // the user had scrolled away
        sv.scrollOffset = sv.maxOffset
        _ = sv.userScrollFine(by: 2)
        #expect(
            box.anchor == nil,
            """
            `nil` means "no departure from the declaration", so an app's \
            "am I still following the log?" test (anchor == nil) answers yes \
            again — writing `.bottom` would leave it answering no while the \
            view demonstrably follows.
            """)
    }

    // MARK: - Where there is no edge

    @Test("A view whose content fits has no edge to stick to")
    func fittingContentDoesNotStick() {
        let (sv, box) = handler(extent: 5)  // 5 lines in a 10-line viewport
        #expect(sv.maxOffset == 0)
        _ = sv.userScrollFine(by: 3)
        _ = sv.handleWheelEvent(MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
        #expect(
            box.anchor == nil,
            """
            such a view sits at its top and its bottom at once, so "pushing past \
            the bottom" names nothing — engaging an edge would drop an anchor the \
            user never departed from
            """)
    }

    @Test("A fitting view may still overscroll, even though it cannot stick")
    func fittingContentStillOverscrolls() {
        let (sv, box) = handler(extent: 5)
        sv.overscrollState.resolve(top: .none, bottom: .rows(3), viewportHeight: 10)
        _ = sv.userScrollFine(by: 2)
        #expect(sv.overscrollState.excursion == 2, "the push shows")
        #expect(box.anchor == nil, "but there is still no edge to anchor to")
    }

    @Test("Unbound scrollables are unaffected")
    func nothingBoundIsANoOp() {
        let sv = ScrollViewHandler(focusID: "sv")
        sv.contentHeight = 100
        sv.viewportHeight = 10
        sv.scrollOffset = sv.maxOffset
        // No `anchorPositionBinding`: the sticky path must be a silent no-op
        // rather than, say, trapping on a nil binding.
        #expect(!sv.userScrollFine(by: 2), "still blocked, and still not consumed")
        #expect(sv.scrollOffset == sv.maxOffset)
    }
}
