//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollOverscrollProgrammaticTests.swift
//
//  §1.5's promise about programmatic movement: a `scrollTo` or a bound
//  `ScrollPosition` lands exactly where it aimed even while the user holds the
//  view pushed past an edge. The slide (`_ScrollViewCore.applyOverscroll`) is
//  drawn after the offset is chosen, so a request that leaves the excursion
//  standing lands short by exactly the push.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A programmatic request a bound `ScrollPosition` can make over forty one-line
/// rows in a six-line viewport, and where the row it aims at must be drawn.
enum OverscrollProgrammaticRequest: CaseIterable, Sendable {
    case topEdge, bottomEdge, offset, row

    /// The viewport line the aimed-at row must land on, and that row. The
    /// bottom edge puts the last row, 39, on the last line, 5.
    var landing: (line: Int, row: Int) {
        switch self {
        case .topEdge: (0, 0)
        case .bottomEdge: (5, 39)
        case .offset: (0, 10)
        case .row: (0, 30)
        }
    }

    /// Makes the request.
    func apply(to position: inout ScrollPosition) {
        switch self {
        case .topEdge: position.scrollTo(edge: .top)
        case .bottomEdge: position.scrollTo(edge: .bottom)
        case .offset: position.scrollTo(y: 10)
        case .row: position.scrollTo(id: 30, anchor: .top)
        }
    }
}

@MainActor
@Suite("A programmatic scroll lands exactly while the view is pushed past an edge")
struct ScrollOverscrollProgrammaticTests {
    private static let viewport = 6

    /// One frame through the render-pass hooks the loop drives: the position
    /// request and its read-back are render-time side effects.
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollOverscrollTop = .rows(2)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
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

    private func rows(position: Binding<ScrollPosition>) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition(position)
    }

    @Test(
        "A request made while pushed past the top lands on its line",
        arguments: OverscrollProgrammaticRequest.allCases)
    func requestDropsTheExcursion(_ request: OverscrollProgrammaticRequest) throws {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })

        let opening = renderFrame(rows(position: binding), tuiContext: tuiContext, focusManager: focusManager)
        tuiContext.mouseEventDispatcher.setRegions(opening.hitTestRegions)
        // Already at the top, so the tick has nowhere to go but the allowance.
        _ = tuiContext.mouseEventDispatcher.dispatch(
            MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))
        let pushed = screen(renderFrame(rows(position: binding), tuiContext: tuiContext, focusManager: focusManager))
        let pushedTop = Array(pushed.prefix(3))
        try #require(
            pushedTop == ["", "", "row 0"],
            "sanity: the tick pushed the content two lines down:\n\(pushed.joined(separator: "\n"))")

        request.apply(to: &position)
        let landed = screen(renderFrame(rows(position: binding), tuiContext: tuiContext, focusManager: focusManager))
        let (line, row) = request.landing
        let drawn = landed.indices.contains(line) ? landed[line] : nil
        #expect(
            drawn == "row \(row)",
            """
            \(request) aimed row \(row) at line \(line), and the push moved it:
            \(landed.joined(separator: "\n"))
            """)
    }
}
