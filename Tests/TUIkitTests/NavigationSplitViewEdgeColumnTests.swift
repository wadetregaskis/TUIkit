//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewEdgeColumnTests.swift
//
//  A split view whose leading column is hidden draws a one-cell edge column at
//  its left with ▶, which brings the nearest hidden column back. Before it, a
//  sidebar hidden through `columnVisibility` left the user no way back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A hidden leading column leaves a ▶ edge column that brings it back", .rendersEnglishUI)
struct NavigationSplitViewEdgeColumnTests {

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

    private func twoColumns(_ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } detail: {
            Text("D")
        }
    }

    private func threeColumns(_ box: Box) -> some View {
        NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } content: {
            Text("C")
        } detail: {
            Text("D")
        }
    }

    private func character(_ buffer: FrameBuffer, x: Int, y: Int) -> Character? {
        guard buffer.lines.indices.contains(y) else { return nil }
        let row = Array(buffer.lines[y].stripped)
        return row.indices.contains(x) ? row[x] : nil
    }

    private func edgeSection(_ focusManager: FocusManager) -> String? {
        focusManager.section(withPrefix: "nav-split-edge")?.id
    }

    // MARK: Drawing

    @Test("A hidden sidebar draws ▶ at the left edge on the centre row, with the detail beside it")
    func detailOnlyDrawsTheEdge() {
        let context = splitContext()
        let buffer = frame(twoColumns(Box(.detailOnly)), context)
        #expect(character(buffer, x: 0, y: buffer.height / 2) == "▶")
        #expect(character(buffer, x: 1, y: 0) == "D", "the detail column starts one cell in")
        #expect(buffer.lines.allSatisfy { ["▶", " "].contains($0.stripped.first) })
    }

    @Test("Three columns at .doubleColumn draw the edge before the content column")
    func doubleColumnDrawsTheEdge() {
        let context = splitContext()
        let buffer = frame(threeColumns(Box(.doubleColumn)), context)
        #expect(character(buffer, x: 0, y: buffer.height / 2) == "▶")
        #expect(character(buffer, x: 1, y: 0) == "C")
    }

    @Test("With every column showing there is no edge column")
    func allHasNoEdge() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let buffer = frame(threeColumns(Box(.all)), context)
        #expect(!buffer.lines.contains { $0.stripped.contains("▶") })
        #expect(character(buffer, x: 0, y: 0) == "S")
        #expect(edgeSection(focusManager) == nil)
    }

    @Test("The detail column is exactly one cell narrower beside the edge")
    func detailIsOneCellNarrower() {
        let context = splitContext(width: 50)
        let box = Box(.detailOnly)
        let view = NavigationSplitView(columnVisibility: box.binding) {
            Text("S")
        } detail: {
            // A width-greedy row: its drawn width is the column's width.
            HStack(spacing: 0) { Text("<"); Spacer(); Text(">") }
        }
        let buffer = frame(view, context)
        let row = buffer.lines[0].stripped
        #expect(Array(row).first == "▶" || Array(row).first == " ")
        #expect(row.firstIndex(of: "<").map { row.distance(from: row.startIndex, to: $0) } == 1)
        #expect(row.firstIndex(of: ">").map { row.distance(from: row.startIndex, to: $0) } == 49)
    }

    @Test("A disabled split keeps the edge cell but draws it blank and makes it no Tab stop")
    func disabledKeepsTheCell() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let buffer = frame(twoColumns(Box(.detailOnly)).disabled(true), context)
        #expect(character(buffer, x: 0, y: buffer.height / 2) == " ")
        #expect(character(buffer, x: 1, y: 0) == "D", "the detail does not move")
        #expect(edgeSection(focusManager) == nil)
    }

    /// Leading chrome is an offset, and an offset as wide as the split pushes
    /// every column's content out of it. So the edge takes its cell only while
    /// the visible columns keep at least one each: from 2 columns wide with one
    /// column showing, from 3 with two (the divider takes the other). Below
    /// that the split draws as if nothing were hidden.
    @Test("Sizes from 1x1 up never trap, and the edge takes the first cell only while the columns keep one")
    func sizeSweep() {
        for width in 1...24 {
            for height in 1...5 {
                for three in [false, true] {
                    let context = splitContext(width: width, height: height)
                    let focusManager = context.environment.focusManager!
                    let box = Box(three ? .doubleColumn : .detailOnly)
                    let buffer = three
                        ? frame(threeColumns(box), context) : frame(twoColumns(box), context)
                    let label = "\(width)x\(height) \(three ? "three" : "two") columns"
                    let first: Character = three ? "C" : "D"
                    #expect(buffer.height == height, "\(label): height \(buffer.height)")
                    guard width > (three ? 2 : 1) else {
                        // Two visible columns and their divider in ONE cell give
                        // the columns no width at all, edge or no edge; that
                        // boundary is the columns' own, so only the edge is
                        // asserted there.
                        if !(three && width == 1) {
                            #expect(character(buffer, x: 0, y: 0) == first, "\(label): content off-screen")
                        }
                        #expect(!buffer.lines.contains { $0.stripped.contains("▶") }, "\(label)")
                        #expect(edgeSection(focusManager) == nil, "\(label)")
                        continue
                    }
                    #expect(character(buffer, x: 0, y: height / 2) == "▶", "\(label): no ▶")
                    #expect(
                        buffer.lines.allSatisfy { ["▶", " "].contains($0.stripped.first) },
                        "\(label): something other than the edge in the first cell")
                    #expect(
                        character(buffer, x: 1, y: 0) == first,
                        "\(label): the first visible column does not start at x=1")
                }
            }
        }
    }

    @Test("A measuring pass lays the edge out exactly as the render does")
    func measureMatchesRender() {
        for width in [1, 5, 30, 60] {
            let context = splitContext(width: width)
            let view = threeColumns(Box(.detailOnly))
            let rendered = frame(view, context)
            var measuring = context
            measuring.isMeasuring = true
            let measured = renderToBuffer(view, context: measuring)
            #expect(measured.width == rendered.width, "width \(width)")
            #expect(measured.height == rendered.height, "width \(width)")
            #expect(measured.lines.map { $0.stripped.first } == rendered.lines.map { $0.stripped.first })
        }
    }

    // MARK: Keyboard

    @Test("Tab reaches the edge column before the columns")
    func tabReachesTheEdgeFirst() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = VStack(spacing: 0) {
            Toggle("above", isOn: .constant(false)).focusID("above")
            NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
                Toggle("side", isOn: .constant(false))
            } detail: {
                Toggle("detail", isOn: .constant(false)).focusID("detail")
            }
        }
        _ = frame(view, context)
        focusManager.focus(id: "above")
        focusManager.focusNext()
        _ = frame(view, context)
        #expect(focusManager.activeSectionIdentifier?.hasPrefix("nav-split-edge") == true)
        focusManager.focusNext()
        _ = frame(view, context)
        #expect(focusManager.currentFocusedID == "detail")
    }

    @Test(
        "Return on the edge brings back the nearest hidden column",
        arguments: [
            (false, NavigationSplitViewVisibility.detailOnly, NavigationSplitViewVisibility.all),
            (true, .detailOnly, .doubleColumn),
            (true, .doubleColumn, .all),
        ])
    func returnReveals(three: Bool, from: NavigationSplitViewVisibility, to: NavigationSplitViewVisibility) {
        for key in [Key.enter, .space] {
            let context = splitContext()
            let focusManager = context.environment.focusManager!
            let box = Box(from)
            let view = three ? AnyView(threeColumns(box)) : AnyView(twoColumns(box))
            _ = frame(view, context)
            guard let edge = edgeSection(focusManager) else {
                Issue.record("no edge section"); return
            }
            focusManager.activateSection(id: edge)
            #expect(focusManager.dispatchKeyEvent(KeyEvent(key: key)))
            #expect(box.visibility == to, "\(key) from \(from)")
        }
    }

    @Test("After revealing, the keyboard is on the divider that hides the column again")
    func revealFocusesTheLeadingDivider() {
        for (three, from, column) in [
            (false, NavigationSplitViewVisibility.detailOnly, "sidebar"),
            (true, .detailOnly, "content"),
            (true, .doubleColumn, "sidebar"),
        ] {
            let context = splitContext()
            let focusManager = context.environment.focusManager!
            let box = Box(from)
            let view = three ? AnyView(threeColumns(box)) : AnyView(twoColumns(box))
            _ = frame(view, context)
            focusManager.activateSection(id: edgeSection(focusManager) ?? "")
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
            _ = frame(view, context)
            let active = focusManager.activeSectionIdentifier ?? "nil"
            #expect(active.hasPrefix("nav-split-divider-\(column)"), "from \(from): \(active)")
            #expect(focusManager.currentFocusedID == active)
        }
    }

    /// A split that cannot resize still has its leftmost divider, kept for the ◀
    /// toggle, so the keyboard goes there as it does on a resizable split.
    @Test("A split that cannot resize hands the keyboard to its ◀ toggle")
    func revealWithoutResizingFocusesTheToggle() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let box = Box(.detailOnly)
        let view = NavigationSplitView(columnVisibility: box.binding) {
            Toggle("side", isOn: .constant(false)).focusID("side")
        } detail: {
            Toggle("detail", isOn: .constant(false)).focusID("detail")
        }
        .navigationSplitViewResizable(false)
        _ = frame(view, context)
        focusManager.activateSection(id: edgeSection(focusManager) ?? "")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        _ = frame(view, context)
        #expect(box.visibility == .all)
        #expect(focusManager.activeSectionIdentifier?.hasPrefix("nav-split-divider-sidebar") == true)
    }

    @Test("A focused edge says Return shows a column")
    func statusBarLabel() {
        let context = splitContext()
        let focusManager = context.environment.focusManager!
        let view = twoColumns(Box(.detailOnly))
        _ = frame(view, context)
        focusManager.activateSection(id: edgeSection(focusManager) ?? "")
        context.environment.statusBar?.activationLabelOverride = nil
        _ = frame(view, context)
        #expect(context.environment.statusBar?.activationLabelOverride == "show column")
    }

    // MARK: Mouse

    @Test("A click on the edge column brings the sidebar back")
    func clickReveals() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.detailOnly)
        let view = twoColumns(box)
        _ = frame(view, context)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 0, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 0, y: 1))
        #expect(box.visibility == .all)
    }

    @Test("A press on the edge released somewhere else changes nothing")
    func releaseElsewhereCancels() {
        let context = splitContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        let box = Box(.detailOnly)
        let view = twoColumns(box)
        _ = frame(view, context)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 0, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 6, y: 1))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 6, y: 1))
        #expect(box.visibility == .detailOnly)
    }
}
