//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEventTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - Integration: regions propagate through view trees

@MainActor
@Suite("Mouse hit-test region propagation")
struct MouseHitTestPropagationTests {

    private func makeContext(width: Int = 80, height: Int = 24) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = tuiContext.stateStorage
        environment.lifecycle = tuiContext.lifecycle
        environment.keyEventDispatcher = tuiContext.keyEventDispatcher
        environment.mouseEventDispatcher = tuiContext.mouseEventDispatcher
        environment.renderCache = tuiContext.renderCache
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: tuiContext
        )
    }

    @Test("TextField inside HStack inside VStack carries hit-test region")
    func textFieldRegionsPropagateThroughStacks() {
        let binding = State<String>(wrappedValue: "")
        let view = VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 1) {
                Text("Input:")
                TextField("Input", text: binding.projectedValue, prompt: Text("…"))
            }
        }

        let buffer = renderToBuffer(view, context: makeContext())
        #expect(!buffer.hitTestRegions.isEmpty)
    }

    @Test("TextField inside .padding still has hit-test region")
    func textFieldRegionsPropagateThroughPadding() {
        let binding = State<String>(wrappedValue: "")
        let view = VStack(alignment: .leading) {
            TextField("Field", text: binding.projectedValue)
        }
        .padding(.horizontal, 1)

        let buffer = renderToBuffer(view, context: makeContext())
        #expect(!buffer.hitTestRegions.isEmpty)
    }

    /// End-to-end: render → click second TextField → dispatch a
    /// character key through `FocusManager` → verify it lands in
    /// the field that was clicked, not its sibling. Exercises the
    /// full hit-test region → focus switch → key-dispatch → binding
    /// write chain. Originally written while chasing a reported
    /// "I clicked Search but Z showed up in Input" bug; that bug
    /// turned out to be regions being dropped in
    /// `WindowGroup.centerBuffer` (fixed in 7fabfb01), which this
    /// test does NOT exercise because it bypasses WindowGroup. The
    /// regression test for the actual fix lives in `RenderingTests`
    /// (`windowGroupCenteringPreservesHitTestRegions`). Kept as a
    /// useful integration test for the lower-level chain.
    @Test("Typing after click-to-focus lands in the clicked field")
    func typingAfterClickLandsInClickedField() {
        let inputState = State<String>(wrappedValue: "")
        let searchState = State<String>(wrappedValue: "")
        let view = VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading) {
                Text("Cursor Demo")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("Input:")
                        TextField("Input", text: inputState.projectedValue, prompt: Text("Type…"))
                    }
                    HStack(spacing: 1) {
                        Text("Search:")
                        TextField("Search", text: searchState.projectedValue, prompt: Text("Search…"))
                    }
                }
            }
        }
        .padding(.horizontal, 1)

        let context = makeContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        // First render → dispatcher gets regions, focusables registered.
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        let regions = buffer.hitTestRegions
        guard regions.count >= 2 else {
            Issue.record("expected 2 TextField regions, got \(regions.count)")
            return
        }
        // Click the *second* region (Search field — bigger y).
        let secondRegion = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = secondRegion.offsetX + 2
        let y = secondRegion.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        // Now route a character through FocusManager.dispatchKeyEvent —
        // same path InputHandler.handle uses for the text-input layer.
        let typed = KeyEvent(key: .character("Z"))
        _ = context.environment.focusManager.dispatchKeyEvent(typed)

        #expect(
            searchState.wrappedValue == "Z",
            """
            expected typing to land in Search; \
            searchState=\(searchState.wrappedValue), \
            inputState=\(inputState.wrappedValue)
            """
        )
        #expect(inputState.wrappedValue.isEmpty)
    }

    /// Repeated-render variant of the click→focus integration
    /// test: render N times back to back (as the run loop does
    /// every frame) before clicking, to surface any stale focus or
    /// region state that survives render passes.
    @Test("Click after multiple renders still focuses the right TextField")
    func clickAfterMultipleRendersStillFocuses() {
        let a = State<String>(wrappedValue: "")
        let b = State<String>(wrappedValue: "")
        let view = VStack(alignment: .leading, spacing: 1) {
            TextField("A", text: a.projectedValue)
            TextField("B", text: b.projectedValue)
        }

        let context = makeContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        // Several render passes back to back, simulating multiple
        // frames of the run loop.
        for _ in 0..<3 {
            context.environment.focusManager.beginRenderPass()
            dispatcher.beginRenderPass()
            let buf = renderToBuffer(view, context: context)
            dispatcher.setRegions(buf.hitTestRegions)
            context.environment.focusManager.endRenderPass()
        }

        // Now click the second field. Need a fresh render pass with
        // the regions still in the dispatcher (which they are from
        // the last loop iteration).
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        let regions = buffer.hitTestRegions
        guard regions.count >= 2 else {
            Issue.record("expected 2 regions, got \(regions.count)")
            return
        }
        let second = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = second.offsetX + 1
        let y = second.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        guard let focused = context.environment.focusManager.currentFocused as? TextFieldHandler else {
            Issue.record("expected TextFieldHandler in focus, got \(String(describing: context.environment.focusManager.currentFocused))")
            return
        }
        focused.text.wrappedValue = "marker"
        #expect(b.wrappedValue == "marker")
        #expect(a.wrappedValue.isEmpty)
    }

    /// A minimal replica of TextFieldPage's structure — HStack-
    /// wrapped TextFields inside nested VStacks with
    /// `.padding(.horizontal:)` at the top — to make sure the
    /// click-routing chain handles the layout shapes the real
    /// example app uses, not just the trivial flat-stack case.
    @Test("Click on TextField inside the TextFieldPage-shaped tree moves focus")
    func clickInPageShapedTreeMovesFocus() {
        let a = State<String>(wrappedValue: "")
        let b = State<String>(wrappedValue: "")
        let view = VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading) {
                Text("Cursor Demo")
                    .bold()
                    .underline()
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("Input:")
                        TextField("Input", text: a.projectedValue, prompt: Text("Type…"))
                    }
                    HStack(spacing: 1) {
                        Text("Search:")
                        TextField("Search", text: b.projectedValue, prompt: Text("Search…"))
                    }
                }
            }
        }
        .padding(.horizontal, 1)

        let context = makeContext()
        let buffer = renderToBuffer(view, context: context)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        // We expect two hit-test regions, one per TextField. Click the
        // *second* one — the field bound to `b` — and verify focus
        // lands there.
        let regions = buffer.hitTestRegions
        #expect(regions.count == 2, "expected 2 TextField regions, got \(regions.count)")
        guard regions.count >= 2 else { return }
        let second = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = second.offsetX + 2
        let y = second.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        guard let focused = context.environment.focusManager.currentFocused as? TextFieldHandler else {
            Issue.record("expected TextFieldHandler in focus, got \(String(describing: context.environment.focusManager.currentFocused))")
            return
        }
        // Mutate through the focused handler — only the second field's
        // binding should reflect the change.
        focused.text.wrappedValue = "marker"
        #expect(b.wrappedValue == "marker", "expected second field to be focused; b=\(b.wrappedValue), a=\(a.wrappedValue)")
        #expect(a.wrappedValue.isEmpty)
    }

    @Test("Click between TextFields moves focus to the clicked one")
    func clickBetweenTextFieldsMovesFocus() {
        let a = State<String>(wrappedValue: "")
        let b = State<String>(wrappedValue: "")
        let view = VStack(alignment: .leading, spacing: 1) {
            TextField("A", text: a.projectedValue)
            TextField("B", text: b.projectedValue)
        }

        let context = makeContext()
        let buffer = renderToBuffer(view, context: context)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        // After render, both TextFields are registered. The first one
        // is auto-focused. Click the second one.
        let regions = buffer.hitTestRegions
        guard regions.count >= 2 else {
            Issue.record("expected at least two regions, got \(regions.count)")
            return
        }
        // Lower-y region = upper field A, higher-y = lower field B.
        let second = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = second.offsetX + 1
        let y = second.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        guard let focused = context.environment.focusManager.currentFocused as? TextFieldHandler else {
            Issue.record("expected TextFieldHandler in focus, got \(String(describing: context.environment.focusManager.currentFocused))")
            return
        }
        // The text binding pointer identity tells us which field is
        // focused — handler.text is the second field's binding.
        focused.text.wrappedValue = "marker"
        #expect(b.wrappedValue == "marker")
        #expect(a.wrappedValue == "")  // swiftlint:disable:this empty_string
    }

    @Test("View .mouseSupport modifier overrides scene base config")
    func viewMouseSupportOverride() {
        let context = makeContext()
        let dispatcher = context.environment.mouseEventDispatcher!

        // Base = .standard (clicks + scrolling + drag, no motion).
        // Modifier-set override = .full (everything).
        let view = Text("Hi").mouseSupport(.full)
        _ = renderToBuffer(view, context: context)

        let effective = dispatcher.effectiveSupport(baseConfig: .standard)
        #expect(effective.motion == true)
    }

    @Test("Innermost .mouseSupport wins when nested")
    func innermostMouseSupportWins() {
        let context = makeContext()
        let dispatcher = context.environment.mouseEventDispatcher!

        // Outer says .disabled, inner says .standard. Inner is
        // evaluated last during a top-down render and wins.
        let view = VStack {
            Text("Inner")
                .mouseSupport(.standard)
        }
        .mouseSupport(.disabled)
        _ = renderToBuffer(view, context: context)

        let effective = dispatcher.effectiveSupport(baseConfig: .full)
        #expect(effective.clicks == true)
        #expect(effective.scrolling == true)
        #expect(effective.drag == true)
        #expect(effective.motion == false)
    }

    @Test("No .mouseSupport modifier leaves scene base in effect")
    func sceneBaseUntouchedWithoutOverride() {
        let context = makeContext()
        let dispatcher = context.environment.mouseEventDispatcher!

        let view = Text("plain")
        _ = renderToBuffer(view, context: context)

        let effective = dispatcher.effectiveSupport(baseConfig: .standard)
        #expect(effective == MouseSupport.standard)
    }

    @Test("Override is per-render-pass — beginRenderPass clears it")
    func overrideClearedOnRenderPass() {
        let context = makeContext()
        let dispatcher = context.environment.mouseEventDispatcher!

        let view = Text("once").mouseSupport(.disabled)
        _ = renderToBuffer(view, context: context)
        #expect(dispatcher.effectiveSupport(baseConfig: .standard) == .disabled)

        // Frame turnover — without the modifier rendering again, the
        // override should be gone.
        dispatcher.beginRenderPass()
        let plain = Text("again")
        _ = renderToBuffer(plain, context: context)
        #expect(dispatcher.effectiveSupport(baseConfig: .standard) == .standard)
    }

    @Test("Click on TextField actually moves focus to it (end-to-end)")
    func clickMovesFocusToTextField() {
        let binding = State<String>(wrappedValue: "")
        // Build the page-like wrapping that TextFieldPage has: VStack →
        // VStack (DemoSection-style) → HStack → TextField.
        let view = VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading) {
                Text("Cursor Demo")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("Input:")
                        TextField("Input", text: binding.projectedValue)
                    }
                }
            }
        }
        .padding(.horizontal, 1)

        let context = makeContext()
        let buffer = renderToBuffer(view, context: context)

        // Make the dispatcher use what was rendered.
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        // Find a region with non-zero width that looks like the
        // TextField (the TextField is the only registered region
        // here; Text views don't emit regions).
        guard let region = buffer.hitTestRegions.first else {
            Issue.record("No hit-test region found")
            return
        }

        // Click the middle of the region. The TextField handler should
        // claim the press and then focus on release.
        let centerX = region.offsetX + region.width / 2
        let centerY = region.offsetY + region.height / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: centerX, y: centerY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: centerX, y: centerY))

        // The focus manager should now have *some* element focused —
        // specifically the TextField. We don't know its exact id (it's
        // auto-generated from view identity) but we can verify the
        // focused element is a TextFieldHandler.
        let focused = context.environment.focusManager.currentFocused
        #expect(focused != nil)
        #expect(focused is TextFieldHandler)
    }
}

// MARK: - HitTestRegion

@Suite("Hit Test Region")
struct HitTestRegionTests {
    @Test("contains() respects bounds")
    func contains() {
        let region = HitTestRegion(
            offsetX: 5, offsetY: 5, width: 10, height: 3,
            handlerID: HitTestRegion.HandlerID(0))
        #expect(region.contains(x: 5, y: 5))
        #expect(region.contains(x: 14, y: 7))
        #expect(!region.contains(x: 4, y: 5))
        #expect(!region.contains(x: 15, y: 5))
        #expect(!region.contains(x: 5, y: 8))
    }
}

// MARK: - MouseEventDispatcher

@Suite("MouseEventDispatcher")
struct MouseEventDispatcherTests {

    @Test("Dispatch routes event to handler at hit location")
    func dispatchRoutes() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.beginRenderPass()

        var receivedAt: (Int, Int)?
        let id = dispatcher.register { event in
            receivedAt = (event.x, event.y)
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 5, handlerID: id)
        ])

        let event = MouseEvent(button: .left, phase: .pressed, x: 3, y: 2)
        #expect(dispatcher.dispatch(event) == true)
        // Region offset is (0, 0) — localised coords equal absolute.
        #expect(receivedAt?.0 == 3)
        #expect(receivedAt?.1 == 2)
    }

    @Test("Handler receives coordinates local to the region")
    func dispatchLocalizes() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.beginRenderPass()

        var receivedAt: (Int, Int)?
        let id = dispatcher.register { event in
            receivedAt = (event.x, event.y)
            return true
        }
        // Region at screen offset (10, 5).
        dispatcher.setRegions([
            HitTestRegion(offsetX: 10, offsetY: 5, width: 20, height: 3, handlerID: id)
        ])

        // Click at absolute (12, 6) — should arrive as local (2, 1).
        let event = MouseEvent(button: .left, phase: .pressed, x: 12, y: 6)
        #expect(dispatcher.dispatch(event) == true)
        #expect(receivedAt?.0 == 2)
        #expect(receivedAt?.1 == 1)
    }

    @Test("Dispatch ignores events outside any region")
    func dispatchMisses() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.beginRenderPass()
        let id = dispatcher.register { _ in true }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 5, height: 5, handlerID: id)
        ])
        let outside = MouseEvent(button: .left, phase: .pressed, x: 20, y: 20)
        #expect(dispatcher.dispatch(outside) == false)
    }

    @Test("Drag capture routes drag and release back to original handler")
    func dragCapture() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.beginRenderPass()

        var captured: [(MousePhase, Int, Int)] = []
        let id = dispatcher.register { event in
            captured.append((event.phase, event.x, event.y))
            return true
        }
        // Region at screen offset (10, 5) — drag coords stay relative
        // to it even when the cursor leaves.
        dispatcher.setRegions([
            HitTestRegion(offsetX: 10, offsetY: 5, width: 5, height: 5, handlerID: id)
        ])

        // Press inside the region at absolute (12, 7) → local (2, 2).
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 12, y: 7))
        // Drag to a point outside the region → still local to original offset.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 100, y: 100))
        // Release outside — still routed.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 100, y: 100))

        #expect(captured.map(\.0) == [.pressed, .dragged, .released])
        #expect(captured[0].1 == 2 && captured[0].2 == 2)
        #expect(captured[1].1 == 90 && captured[1].2 == 95)
        #expect(captured[2].1 == 90 && captured[2].2 == 95)
    }

    @Test("Innermost region wins when regions nest")
    func innermostWins() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.beginRenderPass()
        // Outer registers first, inner later: dispatch reverses, so the
        // later (inner) entry wins.
        let outer = dispatcher.register { _ in true }
        let inner = dispatcher.register { _ in true }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: outer),
            HitTestRegion(offsetX: 2, offsetY: 2, width: 4, height: 4, handlerID: inner),
        ])

        var sawInner = false
        // Reset and register a handler that records which fired.
        dispatcher.beginRenderPass()
        let outer2 = dispatcher.register { _ in
            return true
        }
        let inner2 = dispatcher.register { _ in
            sawInner = true
            return true
        }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 10, handlerID: outer2),
            HitTestRegion(offsetX: 2, offsetY: 2, width: 4, height: 4, handlerID: inner2),
        ])
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: 3))
        #expect(sawInner == true)
    }

    @Test("beginRenderPass clears handlers")
    func resetClears() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.beginRenderPass()
        let id = dispatcher.register { _ in true }
        dispatcher.setRegions([
            HitTestRegion(offsetX: 0, offsetY: 0, width: 5, height: 5, handlerID: id)
        ])
        dispatcher.beginRenderPass()
        // After reset, nothing should match.
        let result = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: 2))
        #expect(result == false)
    }
}
