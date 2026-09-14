//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewFixedToggleTests.swift
//
//  A split view that cannot resize (`navigationSplitViewResizable(false)`) still
//  lets the user hide its sidebar: its leftmost divider draws only the ◀ and is
//  a Tab stop for toggling, while every other divider stays an inert space.
//  Before, a fixed split had no divider handle at all, so only the ▶ edge column
//  could change its columns, and nothing could hide one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A split view that cannot resize keeps its ◀ toggle")
struct NavigationSplitViewFixedToggleTests {

    private func splitContext(width: Int = 80, height: Int = 9) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: TUIContext())
    }

    /// One frame through the per-frame passes, as the run loop drives them.
    private func frame(_ view: some View, _ context: RenderContext) -> FrameBuffer {
        let stateStorage = context.environment.stateStorage!
        let focusManager = context.environment.focusManager!
        context.environment.mouseEventDispatcher?.beginRenderPass()
        stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        stateStorage.endRenderPass()
        context.environment.mouseEventDispatcher?.setRegions(buffer.hitTestRegions)
        return buffer
    }

    private final class Box {
        var visibility: NavigationSplitViewVisibility
        init(_ visibility: NavigationSplitViewVisibility) { self.visibility = visibility }
        var binding: Binding<NavigationSplitViewVisibility> {
            Binding(get: { self.visibility }, set: { self.visibility = $0 })
        }
    }

    private func threeColumns(_ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Toggle("side", isOn: .constant(false)).focusID("side")
        } content: {
            Toggle("list", isOn: .constant(false)).focusID("list")
        } detail: {
            Toggle("detail", isOn: .constant(false)).focusID("detail")
        }
        .navigationSplitViewResizable(false)
    }

    private func count(_ glyph: Character, in buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { $0 + $1.stripped.filter { $0 == glyph }.count }
    }

    private func centre(_ glyph: Character, in buffer: FrameBuffer) -> Int? {
        Array(buffer.lines[buffer.height / 2].stripped).firstIndex(of: glyph)
    }

    @Test("The leftmost divider draws only ◀; no grip dots anywhere")
    func drawsOnlyTheArrow() {
        let buffer = frame(threeColumns(Box(.all)), splitContext())
        #expect(count("◀", in: buffer) == 1)
        #expect(count("◦", in: buffer) == 0)
        #expect(centre("◀", in: buffer) != nil, "on the centre row")
    }

    @Test("Only the leftmost divider is a Tab stop")
    func onlyTheToggleIsAStop() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        _ = frame(threeColumns(Box(.all)), context)
        let dividers = focusManager.sectionIDs.filter { $0.hasPrefix("nav-split-divider-") }
        #expect(dividers.count == 1, "\(dividers)")
        #expect(dividers.first?.hasPrefix("nav-split-divider-sidebar") == true)
    }

    @Test("Return hides the sidebar and Return on ▶ brings it back to the divider")
    func returnRoundTrips() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = threeColumns(box)
        _ = frame(view, context)
        guard let divider = dividerSectionID(in: focusManager) else {
            Issue.record("no divider section"); return
        }
        focusManager.activateSection(id: divider)
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .enter)))
        _ = frame(view, context)
        #expect(box.visibility == .doubleColumn)
        #expect(focusManager.activeSectionIdentifier?.hasPrefix("nav-split-edge") == true)

        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        _ = frame(view, context)
        #expect(box.visibility == .all)
        #expect(focusManager.activeSectionIdentifier == divider)
    }

    @Test("Left and Right on the toggle move to the columns either side, and resize nothing")
    func arrowsMoveBetweenColumns() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = threeColumns(Box(.all))
        let before = frame(view, context)
        guard let divider = dividerSectionID(in: focusManager) else {
            Issue.record("no divider section"); return
        }

        focusManager.activateSection(id: divider)
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        _ = frame(view, context)
        #expect(focusManager.currentFocusedID == "list")

        focusManager.activateSection(id: divider)
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .left)))
        _ = frame(view, context)
        #expect(focusManager.currentFocusedID == "side")

        focusManager.activateSection(id: divider)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .end))
        let after = frame(view, context)
        #expect(centre("◀", in: after) == centre("◀", in: before), "End resized a fixed split")
    }

    @Test("In the columns, Left and Right still skip the toggle")
    func columnsSkipTheToggle() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = threeColumns(Box(.all))
        _ = frame(view, context)
        focusManager.focus(id: "side")
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        _ = frame(view, context)
        #expect(focusManager.currentFocusedID == "list")
    }

    @Test("A still click on ◀ hides the sidebar; a drag from it resizes nothing")
    func mouse() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.all)
        let view = threeColumns(box)
        let buffer = frame(view, context)
        guard let x = centre("◀", in: buffer) else { Issue.record("no arrow"); return }
        let y = buffer.height / 2

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: x + 4, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x + 4, y: y))
        #expect(box.visibility == .all)
        #expect(centre("◀", in: frame(view, context)) == x, "a fixed split does not drag")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(box.visibility == .doubleColumn)
    }
}
