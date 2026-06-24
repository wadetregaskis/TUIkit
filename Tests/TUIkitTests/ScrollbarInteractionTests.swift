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
        #expect(hit(0) == .arrowStart)
        #expect(hit(9) == .arrowEnd)
        #expect(hit(-1) == .outside)
        #expect(hit(10) == .outside)
        if case .thumb = hit(1) {} else {
            Issue.record("the top of the track is the thumb at offset 0: \(hit(1))")
        }
        #expect(hit(8) == .trackAfter, "the bottom of the track is after a top thumb: \(hit(8))")
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
}
