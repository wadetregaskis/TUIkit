//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarInteractionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Scrollbar interaction")
struct ScrollbarInteractionTests {
    typealias Bar = ScrollbarRenderer

    private func event(_ x: Int, _ y: Int, _ phase: MousePhase = .pressed) -> MouseEvent {
        MouseEvent(button: .left, phase: phase, x: x, y: y)
    }

    @Test("Hit-test classifies arrows, track, and thumb")
    func hitTestRegions() {
        // length 10, single arrows: position 0 = up arrow, 9 = down arrow, track 1…8.
        // extent 30, viewport 10, offset 0 → the thumb sits at the top of the track.
        func hit(_ position: Int) -> ScrollbarHit {
            Bar.hitTest(
                position: position, length: 10, extent: 30, viewport: 10, offset: 0,
                arrows: .single, proportional: true)
        }
        #expect(hit(0) == .arrow(delta: -1), "the top arrow scrolls up")
        #expect(hit(9) == .arrow(delta: 1), "the bottom arrow scrolls down")
        #expect(hit(-1) == .outside)
        #expect(hit(10) == .outside)
        if case .thumb = hit(1) {} else {
            Issue.record("the top of the track is the thumb at offset 0: \(hit(1))")
        }
        #expect(hit(8) == .trackAfter, "the bottom of the track is after a top thumb: \(hit(8))")
    }

    @Test("Double arrows scroll by their own glyph direction at both ends")
    func doubleArrowDirections() {
        // length 12, double arrows: each end shows [▲, ▼]. Head: 0=▲, 1=▼.
        // Tail: 10=▲, 11=▼. Track is 2…9.
        func hit(_ position: Int) -> ScrollbarHit {
            Bar.hitTest(
                position: position, length: 12, extent: 40, viewport: 12, offset: 0,
                arrows: .double, proportional: true)
        }
        #expect(hit(0) == .arrow(delta: -1), "head up-arrow scrolls up")
        #expect(hit(1) == .arrow(delta: 1), "head down-arrow scrolls down")
        // The bug: the up-arrow at the *bottom* end used to scroll down.
        #expect(hit(10) == .arrow(delta: -1), "bottom up-arrow scrolls UP, not down")
        #expect(hit(11) == .arrow(delta: 1), "bottom down-arrow scrolls down")
    }

    @Test("Clicking the bottom up-arrow (double arrows) scrolls up")
    func doubleArrowBottomUpScrollsUp() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 40
        handler.viewportHeight = 12
        handler.scrollOffset = 20
        let handle = Bar.verticalMouseHandler(
            for: handler, length: 12, arrows: .double, proportional: true, behavior: .page)
        _ = handle(event(0, 10))  // the up-arrow at the bottom end
        #expect(handler.scrollOffset == 19, "the bottom up-arrow scrolls up one: \(handler.scrollOffset)")
    }

    @Test("Clicking the arrows steps by one line")
    func arrowClicksStepOne() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 30
        handler.viewportHeight = 10
        handler.scrollOffset = 5
        let handle = Bar.verticalMouseHandler(
            for: handler, length: 10, arrows: .single, proportional: true, behavior: .page)
        _ = handle(event(0, 0))
        #expect(handler.scrollOffset == 4, "the up arrow scrolls up one: \(handler.scrollOffset)")
        _ = handle(event(0, 9))
        _ = handle(event(0, 9))
        #expect(handler.scrollOffset == 6, "two down arrows scroll down two: \(handler.scrollOffset)")
    }

    @Test("Clicking the track pages by one viewport towards the click")
    func trackClickPages() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 0  // thumb at the top
        let handle = Bar.verticalMouseHandler(
            for: handler, length: 12, arrows: .single, proportional: true, behavior: .page)
        _ = handle(event(0, 10))  // well below the thumb → page down
        #expect(handler.scrollOffset == 10, "page down one viewport: \(handler.scrollOffset)")
    }

    @Test("Jump behaviour centres the thumb on the clicked spot, then follows the drag")
    func trackClickJumps() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 0
        let handle = Bar.verticalMouseHandler(
            for: handler, length: 12, arrows: .single, proportional: true, behavior: .jump)
        _ = handle(event(0, 10))  // near the bottom of the track → jump near the end
        let jumped = handler.scrollOffset
        #expect(jumped > 50, "jump lands near the click, not one page: \(jumped)")
        // Jump implicitly enters a drag (macOS): the thumb now follows the mouse.
        #expect(handler.scrollbarDragGrab != nil, "a jump-click implicitly grabs the thumb")
        _ = handle(event(0, 3, .dragged))  // drag back up
        #expect(handler.scrollOffset < jumped, "after a jump, dragging up follows the cursor: \(handler.scrollOffset)")
        _ = handle(event(0, 3, .released))
        #expect(handler.scrollbarDragGrab == nil, "release ends the drag")
    }

    /// Runs the auto-repeat driver once at a given monotonic time.
    private func tickRepeat(_ handler: ScrollViewHandler, atNanos: Int64) {
        var env = EnvironmentValues()
        env.frameNowNanos = atNanos
        let context = RenderContext(
            availableWidth: 10, availableHeight: 10, environment: env, tuiContext: TUIContext())
        Bar.driveAutoRepeat(state: handler, token: "t", context: context)
    }

    @Test("A held arrow auto-repeats after the initial delay, then at the interval")
    func autoRepeatTicks() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 50
        handler.scrollbarRepeat = ScrollbarRepeat(delta: -1)  // as if the up arrow is held

        let t0: Int64 = 1_000_000_000
        tickRepeat(handler, atNanos: t0)  // seeds the deadline; no scroll yet
        #expect(handler.scrollOffset == 50, "no repeat before the initial delay: \(handler.scrollOffset)")
        tickRepeat(handler, atNanos: t0 + Bar.autoRepeatInitialDelayNanos)
        #expect(handler.scrollOffset == 49, "first repeat fires after the delay: \(handler.scrollOffset)")
        tickRepeat(
            handler, atNanos: t0 + Bar.autoRepeatInitialDelayNanos + Bar.autoRepeatIntervalNanos)
        #expect(handler.scrollOffset == 48, "second repeat after one interval: \(handler.scrollOffset)")
    }

    @Test("With nothing held, the auto-repeat driver does nothing")
    func autoRepeatIdle() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 50
        handler.scrollbarRepeat = nil  // released / never pressed
        tickRepeat(handler, atNanos: 9_000_000_000)
        #expect(handler.scrollOffset == 50, "no repeat when nothing is held")
    }

    @Test("Pressing an arrow arms the auto-repeat; release disarms it")
    func arrowArmsRepeat() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 50
        let handle = Bar.verticalMouseHandler(
            for: handler, length: 12, arrows: .single, proportional: true, behavior: .page)
        _ = handle(event(0, 0))  // press the up arrow
        #expect(handler.scrollbarRepeat?.delta == -1, "arrow press arms a -1 repeat")
        _ = handle(event(0, 0, .released))
        #expect(handler.scrollbarRepeat == nil, "release disarms the repeat")
    }

    @Test("Dragging the thumb moves the offset; release ends the drag")
    func thumbDrag() {
        let handler = ScrollViewHandler(focusID: "t")
        handler.contentHeight = 100
        handler.viewportHeight = 10
        handler.scrollOffset = 0
        let handle = Bar.verticalMouseHandler(
            for: handler, length: 12, arrows: .single, proportional: true, behavior: .page)
        _ = handle(event(0, 1))  // press on the thumb (top of the track)
        #expect(handler.scrollbarDragGrab != nil, "pressing the thumb begins a drag")
        _ = handle(event(0, 10, .dragged))  // drag toward the bottom
        #expect(handler.scrollOffset > 50, "dragging down moves the offset toward the end: \(handler.scrollOffset)")
        _ = handle(event(0, 10, .released))
        #expect(handler.scrollbarDragGrab == nil, "releasing ends the drag")
    }

    // MARK: Horizontal handler (same logic, driven by event.x)

    @Test("A horizontal bar's arrows step by one column (event.x)")
    func horizontalArrowClicksStepOne() {
        let axis = ScrollAxis()
        axis.extent = 30  // content width
        axis.viewportHeight = 10  // viewport width
        axis.scrollOffset = 5
        let handle = Bar.horizontalMouseHandler(
            for: axis, length: 10, arrows: .single, proportional: true, behavior: .page)
        _ = handle(event(0, 0))  // left arrow at x = 0
        #expect(axis.scrollOffset == 4, "the left arrow scrolls left one: \(axis.scrollOffset)")
        _ = handle(event(9, 0))  // right arrow at x = 9
        _ = handle(event(9, 0))
        #expect(axis.scrollOffset == 6, "two right arrows scroll right two: \(axis.scrollOffset)")
    }

    @Test("Dragging a horizontal bar's thumb moves the offset (event.x)")
    func horizontalThumbDrag() {
        let axis = ScrollAxis()
        axis.extent = 100
        axis.viewportHeight = 10
        axis.scrollOffset = 0
        let handle = Bar.horizontalMouseHandler(
            for: axis, length: 12, arrows: .single, proportional: true, behavior: .page)
        _ = handle(event(1, 0))  // press on the thumb (left of the track)
        #expect(axis.scrollbarDragGrab != nil, "pressing the thumb begins a drag")
        _ = handle(event(10, 0, .dragged))  // drag toward the right
        #expect(axis.scrollOffset > 50, "dragging right moves the offset toward the end: \(axis.scrollOffset)")
        _ = handle(event(10, 0, .released))
        #expect(axis.scrollbarDragGrab == nil, "releasing ends the drag")
    }
}
