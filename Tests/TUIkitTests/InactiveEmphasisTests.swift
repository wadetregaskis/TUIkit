//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InactiveEmphasisTests.swift
//
//  A view that does not appear active hides its focus indication through
//  `indicatesFocus` (see FocusEffectDisabledTests). What is still on screen
//  and still asks the emphasis clock for a focused element — an open menu's
//  highlight, a hovered split divider, a view of an app's own — holds still:
//  one frame at its bright end, no run, and no read of the clock, so the loop
//  can stop waking for it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("Focus emphasis holds still while a view does not appear active")
struct InactiveEmphasisTests {

    // MARK: - The clock

    /// An environment with a live cursor clock and a volatile-read tracker, as a
    /// running frame has, under `appearsActive` and `style`.
    private func environment(
        appearsActive: Bool, style: TextCursorStyle.Animation = .pulse
    ) -> (EnvironmentValues, CursorTimer, VolatileReadTracker) {
        let timer = CursorTimer(renderNotifier: AppState())
        let tracker = VolatileReadTracker()
        var environment = EnvironmentValues()
        environment.cursorTimer = timer
        environment.volatileReadTracker = tracker
        environment.selectionIndicatorStyle = style
        environment.appearsActive = appearsActive
        timer.beginFrameReadTracking()
        return (environment, timer, tracker)
    }

    @Test(
        "A focused element's cycle is one still frame, focused, at its bright end",
        arguments: [TextCursorStyle.Animation.pulse, .blink])
    func cycleHoldsStill(style: TextCursorStyle.Animation) {
        let (active, _, _) = environment(appearsActive: true, style: style)
        #expect(active.selectionEmphasis.cycle(true).isAnimating, "the premise: it animates while active")

        let (inactive, _, _) = environment(appearsActive: false, style: style)
        let cycle = inactive.selectionEmphasis.cycle(true)
        #expect(cycle.frames.count == 1)
        #expect(!cycle.isAnimating)
        #expect(cycle.isFocused, "held still, not unfocused: a fill still draws as focused")
        #expect(cycle.colorNow(dim: .red, bright: .blue) == .blue)
        #expect(cycle.colors(dim: .red, bright: .blue) == [.blue])
        #expect(cycle.run("●", dim: .red, bright: .blue, offsetX: 0, offsetY: 0) == nil)
    }

    @Test(
        "Resolving a focused element reads no clock",
        arguments: [TextCursorStyle.Animation.pulse, .blink])
    func resolveReadsNoClock(style: TextCursorStyle.Animation) {
        let (active, activeTimer, _) = environment(appearsActive: true, style: style)
        _ = active.selectionEmphasis(true)
        #expect(activeTimer.didReadThisFrame, "the premise: an active focused element reads the clock")

        let (inactive, timer, tracker) = environment(appearsActive: false, style: style)
        let emphasis = inactive.selectionEmphasis(true)
        #expect(!timer.didReadThisFrame)
        #expect(tracker.reads == 0)
        #expect(emphasis == .steady(isFocused: true))
        #expect(emphasis.color(dim: .red, bright: .blue) == .blue)
    }

    @Test("Without a cursor clock, resolving reads no pulse phase either")
    func resolveReadsNoPhaseSeam() {
        var environment = EnvironmentValues()
        let tracker = VolatileReadTracker()
        environment.volatileReadTracker = tracker
        _ = environment.selectionEmphasis(true)
        #expect(tracker.reads > 0, "the premise: the seam is read while active")

        let quiet = VolatileReadTracker()
        environment.volatileReadTracker = quiet
        environment.appearsActive = false
        _ = environment.selectionEmphasis(true)
        #expect(quiet.reads == 0)
    }

    // MARK: - An open menu

    /// The popup a right-click opens, in a scene in `phase`, under `style`: its
    /// highlighted row and its frame.
    private func contextMenuPopup(
        phase: ScenePhase, style: TextCursorStyle.Animation = .pulse
    ) throws -> FrameBuffer {
        let tui = TUIContext()
        tui.scenePhase = phase
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        let view = Text("Right-click me")
            .contextMenu {
                Button("Cut") {}
                Button("Copy") {}
            }
            .selectionIndicatorStyle(style)
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyEventDispatcher.clearHandlers()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }
        _ = render()
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .pressed, x: 3, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .right, phase: .released, x: 3, y: 0))
        return try #require(render().overlays.first, "the popup opened").content
    }

    @Test("An open menu keeps its highlight, still, as it draws with the animation off")
    func openMenuHoldsStill() throws {
        let breathing = try contextMenuPopup(phase: .active)
        #expect(!breathing.animatedCells.isEmpty, "the premise: an open menu breathes while active")

        let inactive = try contextMenuPopup(phase: .inactive)
        #expect(inactive.animatedCells.isEmpty, "\(inactive.animatedCells.count) runs left")
        let still = try contextMenuPopup(phase: .active, style: .none)
        #expect(inactive.lines == still.lines, "the highlight and the frame, at their bright ends")
    }

    // MARK: - A hovered divider

    private func splitContext(appearsActive: Bool) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.appearsActive = appearsActive
        return RenderContext(
            availableWidth: 60, availableHeight: 12, environment: environment, tuiContext: TUIContext())
    }

    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let states = context.environment.stateStorage!
        let focus = context.environment.focusManager!
        states.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        states.endRenderPass()
        return buffer
    }

    /// A split's resting and hovered frames, and the grip's row.
    private func hoveredSplit(appearsActive: Bool) throws -> (resting: FrameBuffer, hovered: FrameBuffer, row: Int) {
        let context = splitContext(appearsActive: appearsActive)
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
        let dispatcher = try #require(context.environment.mouseEventDispatcher)
        // Motion must be on for the dispatcher to synthesise an enter.
        dispatcher.setActiveSupport(MouseSupport(clicks: true, scrolling: true, drag: true, motion: true))
        let resting = frame(view, context)
        dispatcher.setRegions(resting.hitTestRegions)
        let row = resting.height / 2
        let column = try #require(resting.lines[row].stripped.firstIndex(of: "◀"), "the grip's ◀")
        let x = resting.lines[row].stripped.distance(
            from: resting.lines[row].stripped.startIndex, to: column)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .moved, x: x, y: row))
        return (resting, frame(view, context), row)
    }

    @Test("A hovered split divider still shows the hover, and holds it still")
    func hoveredDividerHoldsStill() throws {
        let active = try hoveredSplit(appearsActive: true)
        #expect(!active.hovered.animatedCells.isEmpty, "the premise: a hovered divider breathes while active")

        let inactive = try hoveredSplit(appearsActive: false)
        #expect(inactive.hovered.animatedCells.isEmpty, "\(inactive.hovered.animatedCells.count) runs left")
        #expect(
            inactive.hovered.lines[inactive.row] != inactive.resting.lines[inactive.row],
            "the hover is still drawn")
    }
}
