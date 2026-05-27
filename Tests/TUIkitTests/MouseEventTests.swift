//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEventTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - SGR Parsing

@Suite("Mouse Event SGR Parsing")
struct MouseEventSGRParsingTests {

    /// Left button press at column 1, row 1 → 0-indexed (0, 0).
    @Test("Left button press at origin parses to (0, 0)")
    func leftPressOrigin() {
        // ESC [ < 0 ; 1 ; 1 M
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .pressed)
        #expect(event?.x == 0)
        #expect(event?.y == 0)
    }

    /// Lowercase 'm' terminator marks a release.
    @Test("Lowercase m terminator parses as release")
    func releaseTerminator() {
        // ESC [ < 0 ; 5 ; 3 m
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x35, 0x3B, 0x33, 0x6D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .released)
        #expect(event?.x == 4)
        #expect(event?.y == 2)
    }

    /// Wheel up: button code 64.
    @Test("Scroll wheel up parses to .scrollUp")
    func scrollUp() {
        // ESC [ < 64 ; 1 ; 1 M
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x36, 0x34, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .scrollUp)
        #expect(event?.phase == .scrolled)
    }

    /// Wheel down: button code 65 (64 + 1).
    @Test("Scroll wheel down parses to .scrollDown")
    func scrollDown() {
        // ESC [ < 65 ; 1 ; 1 M
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .scrollDown)
        #expect(event?.phase == .scrolled)
    }

    /// Motion with no button held: button code 35 (3 + 32).
    @Test("Motion with no button parses as moved")
    func motionNoButton() {
        // ESC [ < 35 ; 10 ; 5 M
        let bytes: [UInt8] = [
            0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x30, 0x3B, 0x35, 0x4D
        ]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == MouseButton.none)
        #expect(event?.phase == .moved)
        #expect(event?.x == 9)
        #expect(event?.y == 4)
    }

    /// Drag with left button: button code 32 (0 + 32 motion).
    @Test("Drag with left button parses as dragged + .left")
    func leftDrag() {
        // ESC [ < 32 ; 7 ; 4 M
        let bytes: [UInt8] = [
            0x1B, 0x5B, 0x3C, 0x33, 0x32, 0x3B, 0x37, 0x3B, 0x34, 0x4D
        ]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .dragged)
    }

    /// Shift modifier: button code 4 added.
    @Test("Shift modifier flag")
    func shiftModifier() {
        // ESC [ < 4 ; 1 ; 1 M  (button 0 + shift bit 4)
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x34, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.shift == true)
        #expect(event?.button == .left)
    }

    /// Malformed input returns nil.
    @Test("Malformed input returns nil")
    func malformed() {
        #expect(MouseEvent.parseSGR([0x41, 0x42]) == nil)
        // Wrong terminator.
        let bad: [UInt8] = [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x31, 0x3B, 0x31, 0x58]
        #expect(MouseEvent.parseSGR(bad) == nil)
    }

    /// Three-digit coordinates — the longest realistic SGR sequence.
    ///
    /// Regression guard: `Terminal.readBytes` previously defaulted to
    /// an 8-byte buffer cap, which truncated mouse reports at the
    /// first digit and let the trailing bytes leak back as bogus
    /// ASCII keystrokes. Confirms the parser at least accepts the
    /// full sequence; the buffer-size fix lives in `Terminal.swift`.
    @Test("Three-digit coordinates parse correctly")
    func threeDigitCoords() {
        // ESC [ < 35 ; 120 ; 48 M  (15 bytes — would have been
        // truncated by the old 8-byte readBytes default).
        let bytes: [UInt8] = [
            0x1B, 0x5B, 0x3C,
            0x33, 0x35,   // "35"
            0x3B,
            0x31, 0x32, 0x30,  // "120"
            0x3B,
            0x34, 0x38,   // "48"
            0x4D,
        ]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == MouseButton.none)
        #expect(event?.phase == .moved)
        #expect(event?.x == 119)
        #expect(event?.y == 47)
    }

    /// Truncated SGR mouse report must NOT be parsed as a successful
    /// event — the old 8-byte readBytes cap would deliver one of
    /// these to parseSGR and we want the parser to bail rather than
    /// invent coordinates.
    @Test("Truncated SGR sequence is rejected")
    func truncatedRejected() {
        // ESC [ < 35 ; 10  (8 bytes — no terminator at all).
        let truncated: [UInt8] = [
            0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x30,
        ]
        #expect(MouseEvent.parseSGR(truncated) == nil)
    }
}

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
        #expect(a.wrappedValue == "")
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

        var receivedAt: (Int, Int)? = nil
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

        var receivedAt: (Int, Int)? = nil
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
