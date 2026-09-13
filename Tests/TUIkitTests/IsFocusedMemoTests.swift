//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IsFocusedMemoTests.swift
//
//  `.focusable()` and `.contextMenu` tell their content whether its focus stop
//  holds the focus through `\.isFocused`. A memo below them — an `.equatable()`
//  the app asked for, or the `_MemoizedRow` that `ForEach` puts round every
//  `Equatable` row without being asked — keys on identity, value and size and
//  never on the environment. Published by bare assignment, the value changed
//  with every key still equal, so the memo served the frame drawn before the
//  focus arrived: the view took the focus and never said so.
//
//  The unfocused frame is rendered twice before the focus moves, and the second
//  must store nothing: the memo has to be really serving in the arrangement, or
//  a pass here would prove nothing about it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// Draws whether it holds the focus as a MARK beside its title, the same width
/// either way — so a served buffer reads as the wrong mark, and nothing depends
/// on how `.focusable()` measures its content.
private struct FocusMarkedCard: View, @preconcurrency Equatable {
    let title: String
    @Environment(\.isFocused) private var isFocused

    /// By title alone: nothing in the VALUE changes when the focus moves, which
    /// is exactly what lets the memo hit.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Text((isFocused ? "* " : "- ") + title)
    }
}

@MainActor
@Suite("A memo below a focus stop redraws when the focus moves")
struct IsFocusedMemoTests {
    /// What one walk drew.
    private struct Walk {
        /// The second frame with the focus on the OTHER stop.
        let away: String
        /// The frame after the focus moved onto the target.
        let onto: String
        /// The frame after it moved off again.
        let back: String
        /// Whether that second unfocused frame stored nothing — i.e. it was
        /// served, so the memo is really in play.
        let steadyFrameWasServed: Bool
    }

    /// One live-loop-shaped frame; returns what it drew, ANSI stripped.
    private func render(_ view: some View, _ tui: TUIContext, _ manager: FocusManager) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        manager.beginRenderPass()
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return lines.joined(separator: "\n")
    }

    /// Settles `view` with the focus on the stop AHEAD of the target, renders
    /// that twice, then moves the focus onto the target and back off it.
    ///
    /// - Parameter view: A tree with exactly two focus stops, the target last.
    private func walk(_ view: some View) throws -> Walk {
        let tui = TUIContext()
        let manager = FocusManager()
        _ = render(view, tui, manager)
        let stops = manager.registeredFocusIDsInActiveSection()
        try #require(stops.count == 2, "the arrangement registers two focus stops: \(stops)")
        let elsewhere = stops[0]
        let target = stops[1]

        manager.focus(id: elsewhere)
        _ = render(view, tui, manager)
        let storesBefore = tui.renderCache.stats.stores
        let away = render(view, tui, manager)
        let steadyFrameWasServed = tui.renderCache.stats.stores == storesBefore

        manager.focus(id: target)
        let onto = render(view, tui, manager)
        manager.focus(id: elsewhere)
        let back = render(view, tui, manager)
        return Walk(away: away, onto: onto, back: back, steadyFrameWasServed: steadyFrameWasServed)
    }

    private func expectFocusShown(_ walk: Walk, sourceLocation: SourceLocation = #_sourceLocation) {
        let restingAway = walk.away.contains("- card")
        let markedOnto = walk.onto.contains("* card")
        let restingBack = walk.back.contains("- card")
        #expect(
            walk.steadyFrameWasServed,
            "the memo never served a frame, so this arrangement tests nothing",
            sourceLocation: sourceLocation)
        #expect(restingAway, "away from the target it draws at rest: \(walk.away)", sourceLocation: sourceLocation)
        #expect(
            markedOnto,
            "Tab reached the target and the memo served the frame from before it arrived: \(walk.onto)",
            sourceLocation: sourceLocation)
        #expect(
            restingBack,
            "the focus left and the target still says it holds it: \(walk.back)",
            sourceLocation: sourceLocation)
    }

    @Test("An .equatable() view under .focusable() shows the focus arriving and leaving")
    func equatableUnderFocusable() throws {
        let frames = try walk(
            VStack(alignment: .leading, spacing: 0) {
                Text("elsewhere").focusable()
                FocusMarkedCard(title: "card").equatable().focusable()
            })
        expectFocusShown(frames)
    }

    @Test("A ForEach row under .focusable() shows it too, with no memo asked for")
    func forEachRowUnderFocusable() throws {
        // `ForEach` wraps every `Equatable` element's row in `_MemoizedRow`, so
        // this is plain app code — the shape "`.equatable()` is opt-in" missed.
        let frames = try walk(
            VStack(alignment: .leading, spacing: 0) {
                Text("elsewhere").focusable()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["card"], id: \.self) { FocusMarkedCard(title: $0) }
                }
                .focusable()
            })
        expectFocusShown(frames)
    }

    @Test("An .equatable() view under .contextMenu, the other publisher, shows it too")
    func equatableUnderContextMenu() throws {
        let frames = try walk(
            VStack(alignment: .leading, spacing: 0) {
                Text("elsewhere").focusable()
                FocusMarkedCard(title: "card").equatable().contextMenu { Button("Cut") {} }
            })
        expectFocusShown(frames)
    }
}
