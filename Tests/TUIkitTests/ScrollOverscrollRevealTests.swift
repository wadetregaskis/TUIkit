//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollOverscrollRevealTests.swift
//
//  Reveal-on-focus while a ScrollView is held pushed past its top. The slide
//  (`_ScrollViewCore.applyOverscroll`) is drawn after the reveal has chosen its
//  offset, so a reveal that ignores the excursion places its control and the
//  slide then carries it off the bottom of the viewport — and with the unslid
//  geometry reading "visible", nothing ever re-snaps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A reveal under an overscroll push still shows its control")
struct ScrollOverscrollRevealTests {
    /// Eight lines of viewport, pushed three past the top: the slide carries
    /// window rows 5…7 off the bottom.
    private static let viewport = 8

    /// One frame through the render-pass hooks the loop drives. The reveal fires
    /// on the focus changing BETWEEN frames, which a lone `renderToBuffer` with
    /// no pass bookkeeping does not model honestly.
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollOverscrollTop = .rows(3)
        let context = RenderContext(
            availableWidth: 24, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer
    }

    private func screen(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// Thirty one-line Buttons, each with an id a test can focus by name.
    private func rows() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { index in
                    Button("row \(index)") {}
                        .focusID("row-\(index)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Opens the view against its top edge, then pushes it past that edge with
    /// one wheel tick — already at the top, there is no graze to spend first.
    private func pushedPastTop(tuiContext: TUIContext, focusManager: FocusManager) -> [String] {
        let opening = renderFrame(rows(), tuiContext: tuiContext, focusManager: focusManager)
        tuiContext.mouseEventDispatcher.setRegions(opening.hitTestRegions)
        _ = tuiContext.mouseEventDispatcher.dispatch(
            MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))
        return screen(renderFrame(rows(), tuiContext: tuiContext, focusManager: focusManager))
    }

    private func leadingBlankLines(_ screen: [String]) -> Int {
        screen.prefix { $0.isEmpty }.count
    }

    private func line(of label: String, in screen: [String]) -> Int? {
        screen.firstIndex { $0.contains(label) }
    }

    @Test("Focusing a control the push slid off the viewport draws it on screen")
    func focusingAHiddenControlShowsIt() throws {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let pushed = pushedPastTop(tuiContext: tuiContext, focusManager: focusManager)
        let hiddenLine = line(of: "row 6", in: pushed)
        try #require(
            leadingBlankLines(pushed) == 3 && hiddenLine == nil,
            "sanity: the push opened three lines and slid row 6 off:\n\(pushed.joined(separator: "\n"))")

        // Row 6 is inside the unslid window (rows 0…7), so the reveal has
        // nothing to scroll: only the slide is hiding it.
        focusManager.focus(id: "row-6")
        let revealed = screen(renderFrame(rows(), tuiContext: tuiContext, focusManager: focusManager))
        let drawnLine = line(of: "row 6", in: revealed)
        #expect(focusManager.currentFocusedID == "row-6", "sanity: the focus landed")
        #expect(
            drawnLine == 6,
            """
            the focused control is drawn on its window line, got \(String(describing: drawnLine)):
            \(revealed.joined(separator: "\n"))
            """)
    }

    @Test("A reveal that scrolls down lands its control on the last line, not past it")
    func scrollingRevealLandsOnScreen() throws {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let pushed = pushedPastTop(tuiContext: tuiContext, focusManager: focusManager)
        try #require(
            leadingBlankLines(pushed) == 3,
            "sanity: the push opened three lines:\n\(pushed.joined(separator: "\n"))")

        // Below the fold: the reveal scrolls until row 20 is the window's last
        // line — exactly the line a push past the top slides off.
        focusManager.focus(id: "row-20")
        let revealed = screen(renderFrame(rows(), tuiContext: tuiContext, focusManager: focusManager))
        let drawnLine = line(of: "row 20", in: revealed)
        #expect(
            drawnLine == Self.viewport - 1,
            """
            the revealed control is on the viewport's last line, got \(String(describing: drawnLine)):
            \(revealed.joined(separator: "\n"))
            """)
    }

    @Test("A reveal with nothing to move keeps a push that leaves its control in view")
    func visibleTargetKeepsThePush() throws {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let pushed = pushedPastTop(tuiContext: tuiContext, focusManager: focusManager)
        try #require(
            leadingBlankLines(pushed) == 3,
            "sanity: the push opened three lines:\n\(pushed.joined(separator: "\n"))")

        // Row 2 is drawn on line 5 under the push, clear of the rows it slides
        // off. A reveal that dropped the excursion on every snap would pass the
        // two tests above and cancel, here, a push the user still holds.
        focusManager.focus(id: "row-2")
        let revealed = screen(renderFrame(rows(), tuiContext: tuiContext, focusManager: focusManager))
        let drawnLine = line(of: "row 2", in: revealed)
        let blanks = leadingBlankLines(revealed)
        #expect(drawnLine == 5, "the control stayed where the push drew it, got \(String(describing: drawnLine))")
        #expect(blanks == 3, "and the push is still held:\n\(revealed.joined(separator: "\n"))")
    }
}
