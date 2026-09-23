//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusMoveScopeTests.swift
//
//  A focus move drops the cached buffers at both ends of it. For most controls
//  that has to include everything below the control, because that is where the
//  control draws itself. A scroll view's focus shows only in its scrollbar, so
//  a move onto or off one drops its own buffers and those containing it, and
//  keeps its content's: tabbing onto a 200-message chat used to measure and
//  draw every message again (6.8 ms).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// How many times the rows were measured or drawn: work a memo would have saved.
@MainActor
private final class RowWork {
    var count = 0
}

/// A row that counts its own measures and renders.
private struct CountingRow: View, Renderable, Layoutable {
    let work: RowWork
    let index: Int

    var body: Never { fatalError("CountingRow renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        work.count += 1
        return ViewSize.fixed(8, 1)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        work.count += 1
        return FrameBuffer(lines: ["row \(index)"], width: 8)
    }
}

/// A row that draws whether its focus stop holds the focus.
private struct FocusMarkedRow: View, @preconcurrency Equatable {
    let index: Int
    @Environment(\.isFocused) private var isFocused

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.index == rhs.index }

    var body: some View {
        Text((isFocused ? "* row " : "- row ") + "\(index)")
    }
}

@MainActor
@Suite("What a focus move drops")
struct FocusMoveScopeTests {
    /// One live-loop-shaped frame; returns what it drew, ANSI stripped.
    @discardableResult
    private func render(_ view: some View, _ tui: TUIContext, _ manager: FocusManager) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 12, environment: environment, tuiContext: tui)
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

    @Test("Tabbing onto a scroll view, and off it, keeps what its content drew")
    func aScrollViewsFocusKeepsItsContent() throws {
        let tui = TUIContext()
        let manager = FocusManager()
        let work = RowWork()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("elsewhere").focusable()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { CountingRow(work: work, index: $0) }
                }
            }
            .frame(height: 5)
        }
        render(view, tui, manager)
        let stops = manager.registeredFocusIDsInActiveSection()
        try #require(stops.count == 2, "a field and a scroll view that overflows: \(stops)")
        manager.focus(id: stops[0])
        render(view, tui, manager)
        render(view, tui, manager)

        let before = work.count
        manager.focus(id: stops[1])
        let onto = render(view, tui, manager)
        #expect(work.count == before, "tabbing onto the scroll view rebuilt \(work.count - before) rows")
        #expect(onto.contains("row 0"), "the content is still drawn: \(onto)")

        let settled = work.count
        manager.focus(id: stops[0])
        render(view, tui, manager)
        #expect(work.count == settled, "tabbing off the scroll view rebuilt \(work.count - settled) rows")
    }

    /// The other side of it: a `.focusable()` container tells its content
    /// whether it holds the focus, so its content must still be redrawn.
    @Test("A focusable container's content still shows the focus arriving")
    func aFocusableContainersContentStillRedraws() throws {
        let tui = TUIContext()
        let manager = FocusManager()
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("elsewhere").focusable()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { FocusMarkedRow(index: $0) }
            }
            .focusable()
        }
        render(view, tui, manager)
        let stops = manager.registeredFocusIDsInActiveSection()
        try #require(stops.count == 2)
        manager.focus(id: stops[0])
        render(view, tui, manager)
        #expect(render(view, tui, manager).contains("- row 0"))
        manager.focus(id: stops[1])
        let onto = render(view, tui, manager)
        #expect(onto.contains("* row 0"), "the rows kept the frame from before the focus arrived: \(onto)")
    }
}
