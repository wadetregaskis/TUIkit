//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewDividerToggleTests.swift
//
//  The leftmost divider of a split view carries ◀ in place of its middle grip
//  dot. Return, Space or a still click on it hides the column to its left, and
//  the ▶ edge column that appears brings it back. Before it, nothing the user
//  could do on screen hid a column.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("The leftmost divider's ◀ hides the column to its left", .rendersEnglishUI)
struct NavigationSplitViewDividerToggleTests {

    private func splitContext(width: Int = 60, height: Int = 9) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.statusBar = StatusBarState()
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

    private func split(_ box: Box?, three: Bool) -> AnyView {
        switch (box, three) {
        case (let box?, true):
            AnyView(NavigationSplitView(columnVisibility: box.binding) {
                Text("SIDEBAR")
            } content: {
                Text("CONTENT")
            } detail: {
                Text("DETAIL")
            })
        case (let box?, false):
            AnyView(NavigationSplitView(columnVisibility: box.binding) {
                Text("SIDEBAR")
            } detail: {
                Text("DETAIL")
            })
        case (nil, true):
            AnyView(NavigationSplitView { Text("SIDEBAR") } content: { Text("CONTENT") } detail: { Text("DETAIL") })
        case (nil, false):
            AnyView(NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") })
        }
    }

    /// The glyphs of the divider column at `x`, top to bottom.
    private func column(_ x: Int, in buffer: FrameBuffer) -> String {
        String(buffer.lines.map { line -> Character in
            let row = Array(line.stripped)
            return row.indices.contains(x) ? row[x] : "?"
        })
    }

    /// Where `glyph` is on the centre row.
    private func centre(_ glyph: Character, in buffer: FrameBuffer) -> Int? {
        let row = Array(buffer.lines[buffer.height / 2].stripped)
        return row.firstIndex(of: glyph)
    }

    // MARK: Drawing

    @Test("The leftmost divider draws ◀ between two grip dots; the next divider keeps three dots")
    func drawsTheArrow() {
        let context = splitContext(width: 80)
        let buffer = frame(split(Box(.all), three: true), context)
        let dividers = (0..<buffer.width).filter { column($0, in: buffer).contains("◦") }
        #expect(dividers.count == 2, "\(buffer.lines.map(\.stripped))")
        guard dividers.count == 2 else { return }
        // A pin of the two divider columns, 9 rows tall: blank, then the grip
        // centred on row 4.
        #expect(column(dividers[0], in: buffer) == "   ◦◀◦   ")
        #expect(column(dividers[1], in: buffer) == "   ◦◦◦   ")
    }

    @Test("A disabled split draws no arrow, and its columns keep their widths")
    func disabledDrawsNothing() {
        let enabled = frame(split(Box(.all), three: false), splitContext())
        let disabledContext = splitContext()
        let focusManager = disabledContext.environment.focusManager!
        let box = Box(.all)
        let disabled = frame(split(box, three: false).disabled(true), disabledContext)
        guard let x = centre("◀", in: enabled) else {
            Issue.record("no arrow when enabled"); return
        }
        #expect(centre("◀", in: disabled) == nil)
        #expect(column(x, in: disabled).allSatisfy { $0 == " " })
        #expect(disabled.lines.map { Array($0.stripped).firstIndex(of: "D") } == enabled.lines.map {
            Array($0.stripped).firstIndex(of: "D")
        })
        #expect(dividerSectionID(in: focusManager) == nil)
        #expect(box.visibility == .all)
    }

    // MARK: Keyboard

    @Test(
        "Return and Space on the leftmost divider hide the column to its left",
        arguments: [
            (false, NavigationSplitViewVisibility.all, NavigationSplitViewVisibility.detailOnly),
            (false, .automatic, .detailOnly),
            (false, .doubleColumn, .detailOnly),
            (true, .all, .doubleColumn),
            (true, .automatic, .doubleColumn),
            (true, .doubleColumn, .detailOnly),
        ])
    func returnHides(three: Bool, from: NavigationSplitViewVisibility, to: NavigationSplitViewVisibility) {
        for key in [Key.enter, .space] {
            let context = splitContext()
            let focusManager = context.environment.focusManager!
            let box = Box(from)
            let view = split(box, three: three)
            _ = frame(view, context)
            focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
            #expect(focusManager.dispatchKeyEvent(KeyEvent(key: key)))
            #expect(box.visibility == to, "\(key) from \(from)")
        }
    }

    @Test("Return on the second divider does nothing")
    func secondDividerIgnoresReturn() {
        let context = splitContext(width: 80)
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = split(box, three: true)
        _ = frame(view, context)
        focusManager.activateSection(id: dividerSectionID(in: focusManager, index: 1) ?? "")
        #expect(!focusManager.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(box.visibility == .all)
    }

    @Test("Without a binding the split view keeps the visibility itself")
    func withoutABinding() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = split(nil, three: false)
        _ = frame(view, context)
        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        let hidden = frame(view, context)
        #expect(!hidden.lines.contains { $0.stripped.contains("SIDEBAR") }, "the sidebar hid")
        #expect(centre("▶", in: hidden) == 0, "the edge column shows")

        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        let shown = frame(view, context)
        #expect(shown.lines.contains { $0.stripped.contains("SIDEBAR") }, "and came back")
    }

    @Test(
        "Return, Return round-trips, the keyboard ending on the opposite handle each time",
        arguments: [
            (false, NavigationSplitViewVisibility.all, NavigationSplitViewVisibility.detailOnly),
            (true, .all, .doubleColumn),
            (true, .doubleColumn, .detailOnly),
        ])
    func roundTrip(three: Bool, from: NavigationSplitViewVisibility, hidden: NavigationSplitViewVisibility) {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(from)
        let view = split(box, three: three)
        _ = frame(view, context)
        guard let divider = dividerSectionID(in: focusManager) else {
            Issue.record("no divider"); return
        }
        focusManager.activateSection(id: divider)

        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        _ = frame(view, context)
        #expect(box.visibility == hidden)
        let edge = focusManager.activeSectionIdentifier ?? "nil"
        #expect(edge.hasPrefix("nav-split-edge"), "after ◀: \(edge)")
        #expect(focusManager.currentFocusedID == edge)

        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        _ = frame(view, context)
        #expect(box.visibility == (from == .automatic ? .all : from))
        #expect(focusManager.activeSectionIdentifier == divider, "after ▶")
        #expect(focusManager.currentFocusedID == divider)
    }

    @Test("A focused leftmost divider says Return hides a column; the second divider says nothing")
    func statusBarLabel() {
        let context = splitContext(width: 80)
        let focusManager = context.environment.focusManager!
        let statusBar = context.environment.statusBar!
        let view = split(Box(.all), three: true)
        _ = frame(view, context)
        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        statusBar.activationLabelOverride = nil
        _ = frame(view, context)
        #expect(statusBar.activationLabelOverride == "hide column")

        focusManager.activateSection(id: dividerSectionID(in: focusManager, index: 1) ?? "")
        statusBar.activationLabelOverride = nil
        _ = frame(view, context)
        #expect(statusBar.activationLabelOverride == nil)
    }

    // MARK: Mouse

    @Test("A still click on ◀ hides the sidebar")
    func clickOnTheArrowHides() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.all)
        let buffer = frame(split(box, three: false), context)
        guard let x = centre("◀", in: buffer) else { Issue.record("no arrow"); return }
        let y = buffer.height / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(box.visibility == .detailOnly)
    }

    @Test("A still click on a grip dot changes nothing")
    func clickOnADotDoesNothing() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.all)
        let view = split(box, three: false)
        let buffer = frame(view, context)
        guard let x = centre("◀", in: buffer) else { Issue.record("no arrow"); return }
        let y = buffer.height / 2 - 1
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(box.visibility == .all)
        #expect(centre("◀", in: frame(view, context)) == x, "nor resizes")
    }

    @Test("Pressing ◀ and dragging resizes without hiding")
    func dragFromTheArrowResizes() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.all)
        let view = split(box, three: false)
        let buffer = frame(view, context)
        guard let x = centre("◀", in: buffer) else { Issue.record("no arrow"); return }
        let y = buffer.height / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: x + 3, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x + 3, y: y))
        #expect(box.visibility == .all)
        #expect(centre("◀", in: frame(view, context)) == x + 3)
    }

    @Test("A drag that returns to ◀ before release still does not hide")
    func dragBackToTheArrowDoesNotHide() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.all)
        let view = split(box, three: false)
        let buffer = frame(view, context)
        guard let x = centre("◀", in: buffer) else { Issue.record("no arrow"); return }
        let y = buffer.height / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: x + 2, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(box.visibility == .all)
    }

    /// One cell per visible column leaves no room for the ▶ edge column (see
    /// NavigationSplitViewEdgeColumnTests' size sweep), so the keyboard has no
    /// ▶ to go to and lands on the column that is left.
    @Test("Hiding a column in a split too narrow for the edge hands the keyboard to the remaining column")
    func hideWithoutRoomForTheEdge() {
        let context = splitContext(width: 1)
        let focusManager = context.environment.focusManager!
        let box = Box(.all)
        let view = split(box, three: false)
        _ = frame(view, context)
        focusManager.activateSection(id: dividerSectionID(in: focusManager) ?? "")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        _ = frame(view, context)
        #expect(box.visibility == .detailOnly)
        #expect(focusManager.activeSectionIdentifier?.hasPrefix("nav-split-detail") == true)
    }
}
