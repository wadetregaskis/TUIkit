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

    @Test("The corner carries a mark, and it names the axes that work")
    func gripGlyph() {
        let context = makeRenderContext(width: 30, height: 6)
        func lastCell(_ view: some View) -> Character? {
            let buffer = renderToBuffer(view, context: context)
            guard let line = buffer.lines.last else { return nil }
            return line.stripped.last
        }
        let box = Text("hello").frame(width: 12, height: 3).border()
        #expect(lastCell(box.userResizable()) == "╝")
        #expect(lastCell(box.userResizable(.horizontal)) == "╡")
        #expect(lastCell(box.userResizable(.vertical)) == "╧")
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

    @Test("The whole of each live edge is a drag target")
    func dragTargetCoversTheEdges() {
        let context = makeRenderContext(width: 30, height: 8)
        let view = Text("hello").frame(width: 12, height: 4).border().userResizable()
        let buffer = renderToBuffer(view, context: context)
        // One region for the bottom edge, one for the right — a hit region is a
        // rectangle, and an L-shape is two of them.
        #expect(buffer.hitTestRegions.count == 2)
        let bottom = buffer.hitTestRegions.first { $0.height == 1 }
        let right = buffer.hitTestRegions.first { $0.width == 1 }
        #expect(bottom?.width == buffer.width)
        #expect(bottom?.offsetY == buffer.height - 1)
        #expect(right?.height == buffer.height)
        #expect(right?.offsetX == buffer.width - 1)
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
}
