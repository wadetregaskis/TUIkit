//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OutlineClickDisclosureTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A `List` with no selection binding has nothing for a row click to do — and an
/// outline row is the one case where there IS something to do: open or close it.
///
/// The triangle has always been the only mouse target, deliberately: "an outline
/// row's text has to stay free for whatever contains the outline to claim — a
/// list's selection" (`OutlineGroupTests.onlyTheTriangleToggles`). Where nothing
/// will claim it, that reasoning says the row is free, and this is what fills the
/// gap it leaves.
@MainActor
@Suite("Clicking an outline row discloses it when the list has no selection")
struct OutlineClickDisclosureTests {

    private struct Node: Identifiable {
        let id: String
        var kids: [Self]?
    }

    private static let tree = [
        Node(id: "Sources", kids: [Node(id: "TUIkit", kids: nil)]),
        Node(id: "Tests", kids: [Node(id: "TUIkitTests", kids: nil)]),
    ]

    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 12, environment: environment,
                tuiContext: tui)
        )
    }

    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    /// Clicks the LABEL of the first branch row (never its triangle) and answers
    /// whether the branch opened.
    private func labelClickOpens(selectable: Bool) -> Bool {
        let (tui, context) = harness()
        let outline = {
            OutlineGroup(Self.tree, children: \Node.kids) { Text(verbatim: $0.id) }
        }
        let view: AnyView =
            selectable
            ? AnyView(List(selection: .constant(String?.none)) { outline() }.frame(height: 8))
            : AnyView(List { outline() }.frame(height: 8))
        let first = frame(view, tui: tui, context: context)
        // The row's own line, and a column well past the triangle — inside the
        // word "Sources".
        let row = first.lines.firstIndex { $0.stripped.contains("Sources") } ?? 0
        let column = (first.lines[row].stripped.range(of: "Sources").map {
            first.lines[row].stripped.distance(
                from: first.lines[row].stripped.startIndex, to: $0.lowerBound)
        } ?? 8) + 2
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: column, y: row))
        return frame(view, tui: tui, context: context)
            .lines.contains { $0.stripped.contains("TUIkit") }
    }

    @Test("No selection: a click on the label opens the branch")
    func labelClickDisclosesWithoutSelection() {
        #expect(labelClickOpens(selectable: false))
    }

    /// The control, and the behaviour that must not change: where the list DOES
    /// select, the label belongs to the selection and the triangle stays the only
    /// disclosure target.
    @Test("With a selection binding: a click on the label selects, it does not open")
    func labelClickSelectsWhenSelectable() {
        #expect(labelClickOpens(selectable: true) == false)
    }
}
