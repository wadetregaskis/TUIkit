//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UserResizableTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("User-resizable views")
@MainActor
struct UserResizableTests {

    // MARK: - Bounds from ranges

    @Test("Every kind of range says what it says")
    func boundsFromRanges() {
        #expect(ResizeBounds(20...80).minimum == 20)
        #expect(ResizeBounds(20...80).maximum == 80)
        // Half-open: the upper bound is exclusive, so 81 exclusive is 80.
        #expect(ResizeBounds(20..<81).maximum == 80)
        // Open at the top: not a maximum, the ABSENCE of one.
        #expect(ResizeBounds(20...).minimum == 20)
        #expect(ResizeBounds(20...).maximum == nil)
        // Open at the bottom: the floor is the implicit 1, not 0 — a view of
        // zero cells cannot be grabbed to make it bigger again.
        #expect(ResizeBounds(...80).minimum == 1)
        #expect(ResizeBounds(...80).maximum == 80)
    }

    @Test("A minimum below one is raised to one")
    func minimumFloor() {
        #expect(ResizeBounds(0...10).minimum == 1)
        #expect(ResizeBounds(...5).minimum == 1)
    }

    @Test("A maximum below the minimum yields to it")
    func invertedBounds() {
        // A caller's mistake, and the safe reading is the one that leaves the
        // view grabbable.
        let bounds = ResizeBounds(minimum: 30, maximum: 10)
        #expect(bounds.minimum == 30)
        #expect(bounds.maximum == 30)
    }

    @Test("Clamping respects both ends, and an absent one")
    func clamping() {
        let both = ResizeBounds(20...80)
        #expect(both.clamping(5) == 20)
        #expect(both.clamping(50) == 50)
        #expect(both.clamping(500) == 80)

        let floorOnly = ResizeBounds(20...)
        #expect(floorOnly.clamping(5) == 20)
        #expect(floorOnly.clamping(5_000) == 5_000)
    }

    // MARK: - Which axes each spelling enables

    /// The rule the API rests on: naming an axis is what makes it resizable.
    @Test("Naming an axis is what makes it resizable")
    func axesFollowTheSpelling() {
        let text = Text("x")
        #expect(core(text.userResizable()).axes == .all)
        #expect(core(text.userResizable(.horizontal)).axes == .horizontal)
        #expect(core(text.userResizable(.vertical)).axes == .vertical)
        #expect(core(text.userResizable(width: 20...80)).axes == .horizontal)
        #expect(core(text.userResizable(height: 5...30)).axes == .vertical)
        #expect(core(text.userResizable(width: 20...80, height: 5...30)).axes == .all)
    }

    @Test("An axis with no range of its own is unbounded, not unresizable")
    func rangesAttachToTheirOwnAxis() {
        let sized = core(Text("x").userResizable(width: 20...80, height: 5...))
        #expect(sized.widthBounds == ResizeBounds(20...80))
        #expect(sized.heightBounds.minimum == 5)
        #expect(sized.heightBounds.maximum == nil)

        let plain = core(Text("x").userResizable(.horizontal))
        #expect(plain.widthBounds == .unbounded)
    }

    private func core<V: View>(_ view: V) -> _UserResizableCore<Text> {
        guard let core = view as? _UserResizableCore<Text> else {
            Issue.record("expected a _UserResizableCore, got \(type(of: view))")
            return _UserResizableCore(
                content: Text(""), axes: [], widthBounds: .unbounded,
                heightBounds: .unbounded)
        }
        return core
    }

    // MARK: - The handler

    private func handler(
        axes: ResizableAxes = .all,
        width: ResizeBounds = .unbounded,
        height: ResizeBounds = .unbounded,
        at size: (width: Int, height: Int) = (20, 6)
    ) -> _UserResizeHandler {
        let handler = _UserResizeHandler(focusID: "test")
        handler.axes = axes
        handler.widthBounds = width
        handler.heightBounds = height
        handler.currentWidth = size.width
        handler.currentHeight = size.height
        return handler
    }

    @Test("Arrows step one cell, Shift steps five")
    func arrowSteps() {
        let resizer = handler()
        _ = resizer.handleKeyEvent(KeyEvent(key: .right))
        #expect(resizer.requestedWidth == 21)
        _ = resizer.handleKeyEvent(KeyEvent(key: .right, shift: true))
        #expect(resizer.requestedWidth == 26)
        _ = resizer.handleKeyEvent(KeyEvent(key: .down))
        #expect(resizer.requestedHeight == 7)
    }

    @Test("A step starts from the size on screen, not from zero")
    func stepsFromTheRenderedSize() {
        let resizer = handler(at: (width: 40, height: 12))
        _ = resizer.handleKeyEvent(KeyEvent(key: .left))
        #expect(resizer.requestedWidth == 39)
    }

    @Test("An axis that was not named does not move")
    func unnamedAxisIsInert() {
        let resizer = handler(axes: .horizontal)
        #expect(resizer.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(resizer.requestedHeight == nil)
        _ = resizer.handleKeyEvent(KeyEvent(key: .right))
        #expect(resizer.requestedWidth == 21)
    }

    @Test("Bounds hold against the keyboard")
    func keyboardRespectsBounds() {
        let resizer = handler(width: ResizeBounds(18...22))
        _ = resizer.handleKeyEvent(KeyEvent(key: .right, shift: true))
        #expect(resizer.requestedWidth == 22)
        for _ in 0..<10 { _ = resizer.handleKeyEvent(KeyEvent(key: .left, shift: true)) }
        #expect(resizer.requestedWidth == 18)
    }

    @Test("Home and End go to the ends, and an open end defers to the layout")
    func homeAndEnd() {
        let bounded = handler(width: ResizeBounds(10...40))
        _ = bounded.handleKeyEvent(KeyEvent(key: .home))
        #expect(bounded.requestedWidth == 10)
        _ = bounded.handleKeyEvent(KeyEvent(key: .end))
        #expect(bounded.requestedWidth == 40)

        // With no ceiling of its own, End asks for everything and lets the
        // render clamp it to what the terminal has.
        let open = handler(width: ResizeBounds(10...))
        _ = open.handleKeyEvent(KeyEvent(key: .end))
        #expect(open.requestedWidth == Int.max)
    }

    @Test("Escape gives the size back to the layout, and only then")
    func escapeResets() {
        let resizer = handler()
        // Nothing to undo yet, so Escape is not consumed — it belongs to
        // whatever is outside (a sheet, a menu) until there is a resize to drop.
        #expect(resizer.handleKeyEvent(KeyEvent(key: .escape)) == false)
        _ = resizer.handleKeyEvent(KeyEvent(key: .right))
        #expect(resizer.handleKeyEvent(KeyEvent(key: .escape)) == true)
        #expect(resizer.requestedWidth == nil)
        #expect(resizer.requestedHeight == nil)
    }

    // MARK: - Rendering

    /// The corner is where BOTH axes move at once, so it is marked when both
    /// are live and left as the border drew it otherwise. It used to carry `╡`
    /// or `╧` for a single-axis view, which was worse than nothing: the edge
    /// handle already says which edge moves, and a mark on the corner reads as
    /// a corner that moves both.
    @Test("The corner is marked only when both axes move")
    func gripGlyph() {
        let context = makeRenderContext(width: 30, height: 6)
        func lastCell(_ view: some View) -> Character? {
            let buffer = renderToBuffer(view, context: context)
            guard let line = buffer.lines.last else { return nil }
            return line.stripped.last
        }
        let box = Text("hello").frame(width: 12, height: 3).border()
        let plain = lastCell(box)
        #expect(lastCell(box.userResizable()) == "╝")
        #expect(lastCell(box.userResizable(.horizontal)) == plain)
        #expect(lastCell(box.userResizable(.vertical)) == plain)
    }

    @Test("A block border keeps its own glyph and is marked by tint alone")
    func blockBorderKeepsItsFill() {
        let context = makeRenderContext(width: 30, height: 6)
        let view = Text("hello").frame(width: 12, height: 3)
            .border(style: .block)
            .userResizable()
        let buffer = renderToBuffer(view, context: context)
        // Stamping ╝ onto a painted cell would punch a hole in a solid edge —
        // the mark would read as damage. The block stays; the tint marks it.
        #expect(buffer.lines.last?.stripped.last == "█")
    }

    @Test("A disabled view is not resizable and is not in the Tab order")
    func disabledIsInert() {
        let context = makeRenderContext(width: 30, height: 6)
        let view = Text("hello").frame(width: 12, height: 3).border()
            .userResizable()
            .disabled(true)
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.lines.last?.stripped.last != "╝", "a disabled view drew a resize mark")
        #expect(buffer.hitTestRegions.isEmpty, "a disabled view registered a drag target")
    }

    /// The size the user asked for lives in `StateStorage` at the wrapper's OWN
    /// identity, and `FocusRegistration.register` is the only thing in
    /// `_UserResizableCore` that marks that identity active for the end-of-pass
    /// prune. Content that is itself `Renderable` — a `Text` behind nothing but
    /// a frame — hydrates no body there to mark it, so skipping `register` on
    /// the disabled path collected the handler one frame later, and the size
    /// with it. Deliberately no `.border()`: that expands to a `ContainerView`,
    /// which HAS a body and would mark the identity by accident.
    @Test("A disabled resizable keeps the size it was dragged to")
    func disabledKeepsItsStoredSize() {
        let tui = TUIContext()
        let focus = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = StatusBarState()
        let context = RenderContext(
            availableWidth: 60, availableHeight: 4, environment: environment,
            tuiContext: tui
        ).isolatingRenderCache()

        // ONE spelling, so `.disabled(true)` and `.disabled(false)` are the same
        // static type and therefore the same render identity — which is what
        // keys the stored size.
        func pass(disabled: Bool) -> Int {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            focus.beginRenderPass()
            let width = renderToBuffer(
                Text("hello").frame(maxWidth: .infinity)
                    .userResizable(width: 20...80)
                    .disabled(disabled),
                context: context
            ).width
            tui.stateStorage.endRenderPass()
            focus.endRenderPass()
            return width
        }

        // Nothing asked for yet, so the offer is the ceiling clamped to the 60
        // cells the context has.
        #expect(pass(disabled: false) == 60)

        let ids = focus.registeredFocusIDsInActiveSection()
        guard let id = ids.first(where: { $0.hasPrefix("resizable") }) else {
            Issue.record("the resizable did not register: \(ids)")
            return
        }
        focus.focus(id: id)
        guard let handler = focus.currentFocused as? _UserResizeHandler else {
            Issue.record("the focused element is not the resize handler")
            return
        }
        // Home is "as small as allowed": the range's floor, 20.
        #expect(handler.handleKeyEvent(KeyEvent(key: .home)))
        #expect(pass(disabled: false) == 20)

        // The frame it is disabled ON still draws 20 — the handler is still there.
        #expect(pass(disabled: true) == 20)
        // The frame after is the bug: unmarked, the handler was pruned at the end
        // of the one above, so a fresh one asks for nothing and the offer reverts
        // to `widthBounds.maximum` — 80, clamped to 60.
        #expect(pass(disabled: true) == 20, "a disabled resizable forgot its size")
        #expect(pass(disabled: false) == 20, "re-enabling did not bring the size back")
    }

    @Test("The whole of each live edge is a drag target, and the corner is its own")
    func dragTargetCoversTheEdges() {
        let context = makeRenderContext(width: 30, height: 8)
        let view = Text("hello").frame(width: 12, height: 4).border().userResizable()
        let buffer = renderToBuffer(view, context: context)
        // One region for the bottom edge, one for the right — a hit region is a
        // rectangle, and an L-shape is two of them — plus the corner cell they
        // overlap on, which resizes both and so cannot share either's handler.
        #expect(buffer.hitTestRegions.count == 3)
        let bottom = buffer.hitTestRegions.first { $0.height == 1 && $0.width > 1 }
        let right = buffer.hitTestRegions.first { $0.width == 1 && $0.height > 1 }
        let corner = buffer.hitTestRegions.last
        #expect(bottom?.width == buffer.width)
        #expect(bottom?.offsetY == buffer.height - 1)
        #expect(right?.height == buffer.height)
        #expect(right?.offsetX == buffer.width - 1)
        // Two cells square, at the corner: easier to hit than the one cell that
        // carries the mark, and last, because the hit test searches the
        // registrations in reverse and the corner has to be reached before the
        // edges it sits on.
        #expect(corner?.width == 2)
        #expect(corner?.height == 2)
        #expect(corner?.offsetX == buffer.width - 2)
        #expect(corner?.offsetY == buffer.height - 2)
    }

    // MARK: - Dragging

    /// Renders a both-axes resizable, drives one drag through the dispatcher,
    /// and reports the size it draws at afterwards.
    private func drag(
        from: (x: Int, y: Int), to: (x: Int, y: Int)
    ) -> (width: Int, height: Int) {
        dragging(from: from, to: to).size
    }

    /// The same drag, with the viewport-follow signal as well: how many times
    /// the focus manager's interaction generation moved during the gesture.
    private func dragging(
        from: (x: Int, y: Int), to: (x: Int, y: Int)
    ) -> (size: (width: Int, height: Int), interactions: UInt64) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        let focus = FocusManager()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        let statusBar = StatusBarState()
        environment.statusBar = statusBar
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui
        ).isolatingRenderCache()
        tui.mouseEventDispatcher.setActiveSupport(.full)

        let view = Text("hello").frame(width: 20, height: 6).border()
            .userResizable(width: 6...30, height: 3...10)
        tui.mouseEventDispatcher.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)

        let generation = focus.focusedInteractionGeneration
        tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: to.x, y: to.y))
        tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: to.x, y: to.y))

        tui.mouseEventDispatcher.beginRenderPass()
        let after = renderToBuffer(view, context: context)
        return ((after.width, after.height), focus.focusedInteractionGeneration - generation)
    }

    /// The size the fixture draws at before anything is dragged.
    private var restingSize: (width: Int, height: Int) {
        drag(from: (x: 0, y: 0), to: (x: 0, y: 0))
    }

    @Test("A corner drag resizes both dimensions")
    func cornerDragMovesBoth() {
        let resting = restingSize
        // The corner is the bottom-right cell. Dragging it four left and two up
        // takes four off the width and two off the height.
        let result = drag(
            from: (x: resting.width - 1, y: resting.height - 1),
            to: (x: resting.width - 5, y: resting.height - 3))
        #expect(result.width == resting.width - 4)
        #expect(result.height == resting.height - 2)
    }

    @Test("An edge drag moves only its own dimension")
    func edgeDragsStaySingleAxis() {
        let resting = restingSize

        // The right edge, well above the corner. Pressed one row further in
        // than the corner region reaches, and at the far end of the drag the
        // pointer is nowhere near where the press was — which is what proves
        // the delta is measured from the press rather than read off an event
        // that is localised to the region's own top-left.
        let right = drag(from: (x: resting.width - 1, y: 1), to: (x: resting.width - 5, y: 3))
        #expect(right.width == resting.width - 4)
        #expect(right.height == resting.height, "the bottom edge was never touched")

        // The bottom edge, well left of the corner.
        let bottom = drag(from: (x: 3, y: resting.height - 1), to: (x: 7, y: resting.height - 3))
        #expect(bottom.height == resting.height - 2)
        #expect(bottom.width == resting.width, "the right edge was never touched")
    }

    @Test("Only the named axis gets a drag target")
    func singleAxisDragTarget() {
        let context = makeRenderContext(width: 30, height: 8)
        let view = Text("hello").frame(width: 12, height: 4).border()
            .userResizable(width: 4...20)
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.hitTestRegions.count == 1)
        #expect(buffer.hitTestRegions.first?.width == 1, "expected the right edge only")
    }

    // MARK: - Where the handle sits in the Tab order

    /// The focus ring after one render pass of `view`, in the order Tab walks it.
    private func ringOrder(_ view: some View, width: Int = 40, height: Int = 14) -> [String] {
        let tui = TUIContext()
        let focus = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = StatusBarState()
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui
        ).isolatingRenderCache()
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        focus.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        return focus.registeredFocusIDsInActiveSection()
    }

    /// The handle is on the bottom and trailing edges of what it resizes, so reading
    /// order puts it after everything the content holds.
    ///
    /// The ring is registration order, and the handle used to register before its
    /// content rendered: on the Example's Scroll View page Tab reached the grip before
    /// the buttons inside the box and before the ScrollView's own stop.
    @Test("A resize handle comes after everything inside it in the Tab order")
    func handleFollowsItsContent() throws {
        let ids = ringOrder(
            VStack(spacing: 0) {
                Button("inside") {}
            }
            .frame(width: 20, height: 4)
            .border()
            .userResizable(height: 3...10))
        let button = try #require(ids.firstIndex { $0.hasPrefix("button") }, "\(ids)")
        let handle = try #require(ids.firstIndex { $0.hasPrefix("resizable") }, "\(ids)")
        #expect(button < handle, "the handle came before its content: \(ids)")
    }

    /// The owner's case exactly: a resizable ScrollView. Its buttons, then the scroll
    /// view's own stop, then the handle — left to right, top to bottom.
    @Test("A resizable ScrollView's order is its content, the scroller, then the handle")
    func resizableScrollViewOrder() throws {
        let ids = ringOrder(
            ScrollView {
                VStack(spacing: 0) {
                    Button("one") {}
                    Button("two") {}
                }
            }
            .border()
            .userResizable(height: 4...12))
        let lastButton = try #require(ids.lastIndex { $0.hasPrefix("button") }, "\(ids)")
        let scroller = try #require(ids.firstIndex { $0.hasPrefix("scrollview") }, "\(ids)")
        let handle = try #require(ids.firstIndex { $0.hasPrefix("resizable") }, "\(ids)")
        #expect(lastButton < scroller, "\(ids)")
        #expect(scroller < handle, "the handle is last: \(ids)")
    }

    // MARK: - The edge handles

    private enum FocusPick { case none, first, resizable }

    private func gripped(
        _ view: some View, width: Int = 40, height: Int = 14, focusing: FocusPick = .none
    ) -> FrameBuffer {
        let tui = TUIContext()
        let focus = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = StatusBarState()
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui
        ).isolatingRenderCache()
        var buffer = FrameBuffer()
        var ids: [String] = []
        for pass in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            focus.beginRenderPass()
            buffer = renderToBuffer(view, context: context)
            // Collected AFTER the render: `beginRenderPass` clears the
            // section's focusables and the render is what re-registers them.
            if pass == 0 { ids = focus.registeredFocusIDsInActiveSection() }
            tui.stateStorage.endRenderPass()
            focus.endRenderPass()
            switch focusing {
            case .none: break
            case .first: if let id = ids.first { focus.focus(id: id) }
            case .resizable:
                if let id = ids.first(where: { $0.hasPrefix("resizable") }) {
                    focus.focus(id: id)
                }
            }
        }
        return buffer
    }

    private func resizableBox() -> some View {
        Text("hello").frame(width: 24, height: 8).border().userResizable()
    }

    @Test("Each live edge carries a doubled-line handle in its middle")
    func edgesCarryHandles() {
        let buffer = gripped(resizableBox())
        let bottom = buffer.lines.last?.stripped ?? ""
        #expect(bottom.contains(String(repeating: "═", count: 7)))
        // Centred: the same number of border cells either side of it.
        let before = bottom.prefix { $0 != "═" }.count
        let after = bottom.reversed().prefix { $0 != "═" }.count
        #expect(abs(before - after) <= 1, "handle off centre: \(bottom)")

        let rightColumn = buffer.lines.map { line -> Character? in
            let stripped = line.stripped
            return stripped.count == buffer.width ? stripped.last : nil
        }
        #expect(rightColumn.filter { $0 == "\u{2551}" }.count == 3)
    }

    @Test("A single-axis view marks only the edge it actually resizes")
    func singleAxisHandles() {
        let horizontal = gripped(
            Text("hello").frame(width: 24, height: 8).border().userResizable(width: 6...30))
        #expect(!(horizontal.lines.last?.stripped.contains("═") ?? true))
        let vertical = gripped(
            Text("hello").frame(width: 24, height: 8).border().userResizable(height: 3...12))
        #expect(vertical.lines.last?.stripped.contains("═") == true)
        let rightColumn = vertical.lines.compactMap { $0.stripped.last }
        #expect(!rightColumn.contains("\u{2551}"))
    }

    /// The reported case: "a container which is e.g. 3 rows tall has only one
    /// cell for its right border (not counting the corners above & below it),
    /// and we still need the grabber to be shown."
    ///
    /// The handles used to reserve a cell of plain border either side of
    /// themselves, so a box this small carried none at all — and an edge that
    /// can be dragged and does not say so may as well not be draggable.
    @Test("A single border cell between the corners still carries a handle")
    func smallestBoxStillCarriesHandles() {
        // Three rows and four columns of border box: one cell down the right
        // edge between the corners, and two along the bottom.
        let buffer = gripped(Text("xx").frame(width: 2, height: 1).border().userResizable())
        let bottom = buffer.lines.last?.stripped ?? ""
        #expect(bottom.contains("═"), "no handle on the bottom edge: \(bottom)")
        let rightColumn = buffer.lines.compactMap { $0.stripped.last }
        #expect(rightColumn.contains("\u{2551}"), "no handle down the right edge: \(rightColumn)")
    }

    /// The other half of the report: "if the border is double lines, the
    /// grabbers have to be something else."
    @Test("The handles are drawn in a weight that stands out from the border")
    func handlesStandOutFromTheBorder() {
        func handles(_ style: BorderStyle) -> String {
            let buffer = gripped(
                Text("hello").frame(width: 24, height: 8)
                    .border(style: style)
                    .userResizable())
            let rightColumn = String(buffer.lines.compactMap { $0.stripped.last })
            return (buffer.lines.last?.stripped ?? "") + rightColumn
        }
        // Doubled lines over the single-line families…
        #expect(handles(.line).contains("═") && handles(.line).contains("\u{2551}"))
        #expect(handles(.rounded).contains("═"))
        #expect(handles(.heavy).contains("═"))
        // …and heavy ones over the double, where doubles would BE the border.
        let double = handles(.doubleLine)
        #expect(double.contains("━"), "no heavy handle over a double border: \(double)")
        #expect(double.contains("┃"), "no heavy handle over a double border: \(double)")
        #expect(double.contains("┛"), "the corner did not change weight either: \(double)")
    }

    /// Bounds that pin an axis leave nothing to drag, so that axis is not
    /// marked and takes no target — which is how an app turns one axis off
    /// without changing the view's identity, and with it the stored size.
    @Test("An axis pinned by its bounds is inert")
    func fixedAxisIsInert() {
        let buffer = gripped(
            Text("hello").frame(width: 24, height: 8).border()
                .userResizable(width: 12...40, height: 8...8))
        let bottom = buffer.lines.last?.stripped ?? ""
        #expect(!bottom.contains("═"), "a pinned height was still marked: \(bottom)")
        #expect(!bottom.contains("╝"), "a pinned height still claimed the corner: \(bottom)")
        #expect(
            buffer.lines.compactMap { $0.stripped.last }.contains("\u{2551}"),
            "the live axis lost its handle too")
        // One region, for the one live edge — no corner, and no bottom edge.
        #expect(buffer.hitTestRegions.count == 1)
    }

    @Test("A view pinned on every axis is not resizable at all")
    func fullyFixedIsNotResizable() {
        let context = makeRenderContext(width: 40, height: 12)
        // Flexible content, so the offer below is something it can follow — a
        // fixed child is the author saying "this size", which this modifier has
        // no business overruling either way.
        let view = Text("hello").frame(maxWidth: .infinity, maxHeight: .infinity).border()
            .userResizable(width: 30...30, height: 8...8)
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.hitTestRegions.isEmpty, "a view with nothing to move took a drag target")
        // The bounds still bound: this is how `width: 30...30` says "this wide".
        #expect(buffer.width == 30, "the pinned width was not honoured: \(buffer.width)")
        #expect(buffer.height == 8, "the pinned height was not honoured: \(buffer.height)")
    }

    @Test("The handles breathe when the view has the focus, and not before")
    func handlesBreatheWhenFocused() {
        // A button beside the box, so "not focused" is a state the box can
        // actually be in: left alone, the end of the render pass hands the
        // focus to the only thing that can take it.
        let pair = VStack {
            Button("elsewhere") {}
            resizableBox()
        }
        // Counted by glyph rather than by run: the button beside the box
        // breathes its own focus brackets, and those are not what this is about.
        func handleRuns(_ buffer: FrameBuffer) -> Int {
            buffer.animatedCells.count { run in
                run.frames.first.map { frame in
                    frame.contains("═") || frame.contains("\u{2551}") || frame.contains("╝")
                } ?? false
            }
        }
        #expect(handleRuns(gripped(pair, focusing: .first)) == 0)
        // Five runs, not three: a run is a horizontal span of cells, so the
        // three-row handle down the right edge is three of them. Plus the
        // corner and the seven-cell handle along the bottom.
        #expect(handleRuns(gripped(pair, focusing: .resizable)) == 5)
    }

    @Test("A block border keeps its own cells, handles included")
    func blockBorderKeepsItsCells() {
        let buffer = gripped(
            Text("hello").frame(width: 24, height: 8).border(style: .block).userResizable())
        #expect(!(buffer.lines.last?.stripped.contains("═") ?? true))
    }

    @Test("A mouse resize asks the viewport to follow, and a still one does not")
    func mouseResizeAsksTheViewportToFollow() {
        let resting = restingSize
        // Growing by its corner near the bottom of a scroll viewport would
        // otherwise carry the edge under the cursor straight off the screen:
        // the keyboard half already gets this, through the bump every consumed
        // key makes.
        let moved = dragging(
            from: (x: resting.width - 1, y: resting.height - 1),
            to: (x: resting.width - 5, y: resting.height - 3))
        #expect(moved.interactions > 0)

        // A press and release that changed nothing is a click, and a click
        // should not move anybody's viewport.
        let still = dragging(
            from: (x: resting.width - 1, y: resting.height - 1),
            to: (x: resting.width - 1, y: resting.height - 1))
        #expect(still.interactions == 0)
    }
}
