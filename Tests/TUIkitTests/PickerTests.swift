//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PickerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context with a fresh FocusManager for isolated testing.
private func createTestContext(width: Int = 80, height: Int = 24) -> RenderContext {
    makeRenderContext(width: width, height: height)
}

// MARK: - Tag Modifier Tests

@MainActor
@Suite("Tag Modifier Tests")
struct TagModifierTests {

    @Test("tag renders its content transparently")
    func tagIsTransparent() {
        let context = createTestContext()

        let tagged = renderToBuffer(Text("Hello").tag(42), context: context)
        let plain = renderToBuffer(Text("Hello"), context: context)

        #expect(tagged.lines.joined().stripped == plain.lines.joined().stripped)
    }
}

// MARK: - Picker Rendering Tests

@MainActor
@Suite("Picker Tests", .serialized)
struct PickerTests {

    @Test("Menu picker renders a collapsed line showing the selection")
    func menuPickerCollapsed() {
        let context = createTestContext()
        var choice = "a"
        let binding = Binding(get: { choice }, set: { choice = $0 })

        // No .pickerStyle() — the automatic style resolves to a menu.
        let picker = Picker("Fruit", selection: binding) {
            Text("Apple").tag("a")
            Text("Banana").tag("b")
        }
        let buffer = renderToBuffer(picker, context: context)
        let visible = buffer.lines.joined().stripped

        // Heading line + a single collapsed control line.
        #expect(buffer.height == 2)
        #expect(visible.contains("Fruit"))
        #expect(visible.contains("Apple"))
        #expect(!visible.contains("Banana"))
    }

    @Test("Radio-group picker renders every option")
    func radioGroupPickerListsOptions() {
        let context = createTestContext()
        var choice = "a"
        let binding = Binding(get: { choice }, set: { choice = $0 })

        let picker = Picker("Fruit", selection: binding) {
            Text("Apple").tag("a")
            Text("Banana").tag("b")
            Text("Cherry").tag("c")
        }
        .pickerStyle(.radioGroup)

        let buffer = renderToBuffer(picker, context: context)
        let visible = buffer.lines.joined().stripped

        #expect(visible.contains("Apple"))
        #expect(visible.contains("Banana"))
        #expect(visible.contains("Cherry"))
        // Heading + one line per option.
        #expect(buffer.height >= 4)
    }

    @Test("Picker extracts options provided by a ForEach")
    func pickerExtractsForEachOptions() {
        let context = createTestContext()
        var choice = "y"
        let binding = Binding(get: { choice }, set: { choice = $0 })

        let picker = Picker("Letter", selection: binding) {
            ForEach(["x", "y", "z"], id: \.self) { letter in
                Text(letter.uppercased()).tag(letter)
            }
        }
        .pickerStyle(.radioGroup)

        let visible = renderToBuffer(picker, context: context).lines.joined().stripped
        #expect(visible.contains("X"))
        #expect(visible.contains("Y"))
        #expect(visible.contains("Z"))
    }

    @Test("Disabled picker still renders its options")
    func disabledPickerRenders() {
        let context = createTestContext()
        var choice = "a"
        let binding = Binding(get: { choice }, set: { choice = $0 })

        // `.disabled()` is a Picker modifier, so it must precede the
        // environment-based `.pickerStyle(_:)`.
        let picker = Picker("Fruit", selection: binding) {
            Text("Apple").tag("a")
            Text("Banana").tag("b")
        }
        .disabled()
        .pickerStyle(.radioGroup)

        let visible = renderToBuffer(picker, context: context).lines.joined().stripped
        #expect(visible.contains("Apple"))
        #expect(visible.contains("Banana"))
    }

    @Test("Menu picker emits the drop-down as an overlay layer when opened")
    func menuPickerOpensAsOverlay() throws {
        let context = createTestContext()
        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })

        let entries: [_PickerEntry<AnyHashable>] = [
            _PickerEntry.option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            _PickerEntry.option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries,
            selection: binding,
            focusID: "menu-picker",
            isDisabled: false
        )

        // First render creates and registers the persistent handler.
        let closed = renderToBuffer(core, context: context)
        #expect(closed.height == 1)
        #expect(closed.overlays.isEmpty)

        // Reach the persisted handler and open the drop-down.
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let dummySelection = Binding<AnyHashable>(get: { AnyHashable("") }, set: { _ in })
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker",
                selection: dummySelection,
                itemValues: [],
                canBeFocused: true
            )
        )
        box.value.isOpen = true

        let open = renderToBuffer(core, context: context)

        // The in-flow control stays a single line — opening the picker never
        // disturbs the layout of sibling views.
        #expect(open.height == 1)

        // The drop-down rides as a single popover overlay layer, anchored one
        // row below the collapsed control.
        #expect(open.overlays.count == 1)
        let layer = try #require(open.overlays.first)
        #expect(layer.level == .popover)
        #expect(layer.offsetX == 0)
        #expect(layer.offsetY == 1)
        #expect(layer.anchorHeight == 1)
        #expect(layer.content.lines.joined().stripped.contains("Banana"))

        // The collapsed control and every drop-down line share one width, so
        // the bordered popup aligns cleanly under the control.
        let popupWidths = Set(layer.content.lines.map(\.strippedLength))
        #expect(popupWidths.count == 1)
        #expect(popupWidths.first == open.width)
    }

    @Test("A long drop-down windows its options, shows a scrollbar, and scrolls")
    func longDropDownWindowsAndScrolls() throws {
        var context = createTestContext(height: 8)
        // The drop-down sizes to the overlay content area (above the status bar),
        // not the full terminal height; an 8-row area windows to ≈ 6 rows of
        // options after the drop-down's own top/bottom border.
        context.environment.overlayContentHeight = 8
        var choice = AnyHashable("opt-0")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })
        let entries = (0..<20).map {
            _PickerEntry.option(tag: AnyHashable("opt-\($0)"), label: AnyView(Text("Option \($0)")))
        }
        let core = _PickerMenuCore(
            entries: entries, selection: binding, focusID: "menu-picker", isDisabled: false)

        _ = renderToBuffer(core, context: context)  // create the persistent handler
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let dummy = Binding<AnyHashable>(get: { AnyHashable("") }, set: { _ in })
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker", selection: dummy, itemValues: [], canBeFocused: true))
        box.value.isOpen = true

        let popup = try #require(renderToBuffer(core, context: context).overlays.first).content
        let popupText = popup.lines.map(\.stripped).joined()

        #expect(popup.lines.count < entries.count, "menu is windowed, not all 20 options")
        #expect(
            popup.lines.count <= 8,
            "the drop-down fits within the overlay content height (not clipped behind the status bar)")
        #expect(popupText.contains("Option 0"), "the window starts at the selected option")
        #expect(!popupText.contains("Option 19"), "the last option is off-screen initially")
        #expect(
            popupText.contains("▼") || popupText.contains("▲"),
            "the drop-down draws a scrollbar: \(popupText)")
        // The scrollbar is wired for the mouse: a one-column hit region down the
        // right interior edge.
        #expect(
            popup.hitTestRegions.contains { $0.width == 1 && $0.offsetX == popup.width - 2 },
            "the scrollbar column has its own hit region")

        // End jumps the highlight to the last option; the window follows it.
        _ = box.value.handleKeyEvent(KeyEvent(key: .end))
        let scrolled = try #require(renderToBuffer(core, context: context).overlays.first).content
        let scrolledText = scrolled.lines.map(\.stripped).joined()
        #expect(scrolledText.contains("Option 19"), "after End the last option is visible: \(scrolledText)")
        #expect(!scrolledText.contains("Option 0"), "after End the first option scrolled off")
    }

    @Test("Clicking the collapsed control closes an open drop-down")
    func clickingControlClosesOpenDropDown() throws {
        let context = createTestContext()
        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })
        let entries: [_PickerEntry<AnyHashable>] = [
            _PickerEntry.option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            _PickerEntry.option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries, selection: binding, focusID: "menu-picker", isDisabled: false)

        _ = renderToBuffer(core, context: context)  // create the persistent handler
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let dummy = Binding<AnyHashable>(get: { AnyHashable("") }, set: { _ in })
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker", selection: dummy, itemValues: [], canBeFocused: true))
        box.value.isOpen = true

        let open = renderToBuffer(core, context: context)
        #expect(box.value.isOpen, "precondition: drop-down open")

        let dispatcher = try #require(context.environment.mouseEventDispatcher)
        dispatcher.setRegions(open.hitTestRegions)
        // The collapsed control is the row-0 hit region.
        let control = try #require(open.hitTestRegions.first { $0.offsetY == 0 })
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: control.offsetX, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: control.offsetX, y: 0))

        #expect(box.value.isOpen == false, "clicking the control must close the open drop-down")
    }

    @Test("Clicking OUTSIDE an open drop-down closes it and consumes the click")
    func clickingOutsideClosesOpenDropDown() throws {
        let context = createTestContext()
        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })
        let entries: [_PickerEntry<AnyHashable>] = [
            _PickerEntry.option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            _PickerEntry.option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries, selection: binding, focusID: "menu-picker", isDisabled: false)

        _ = renderToBuffer(core, context: context)
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let dummy = Binding<AnyHashable>(get: { AnyHashable("") }, set: { _ in })
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker", selection: dummy, itemValues: [], canBeFocused: true))
        box.value.isOpen = true

        // The dismissal backdrop rides in the popup OVERLAY, so composite
        // like the render loop does before extracting regions.
        let open = renderToBuffer(core, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
        #expect(box.value.isOpen, "precondition: drop-down open")

        let dispatcher = try #require(context.environment.mouseEventDispatcher)
        dispatcher.setRegions(open.hitTestRegions)

        // A press well away from the control and its popup: macOS
        // behaviour — the menu closes and the click goes nowhere else.
        let consumed = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 70, y: 20))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 70, y: 20))
        #expect(box.value.isOpen == false, "an outside click closes the drop-down")
        #expect(consumed, "the closing click is consumed, not delivered underneath")

        // The selection is untouched — closing is all the click did.
        #expect(choice == AnyHashable("a"))
    }

    @Test("Clicking the collapsed control opens a closed drop-down")
    func clickingControlOpensClosedDropDown() throws {
        let context = createTestContext()
        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })
        let entries: [_PickerEntry<AnyHashable>] = [
            _PickerEntry.option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            _PickerEntry.option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries, selection: binding, focusID: "menu-picker", isDisabled: false)

        let closed = renderToBuffer(core, context: context)  // closed; control at row 0
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let dummy = Binding<AnyHashable>(get: { AnyHashable("") }, set: { _ in })
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker", selection: dummy, itemValues: [], canBeFocused: true))
        #expect(box.value.isOpen == false, "precondition: closed")

        let dispatcher = try #require(context.environment.mouseEventDispatcher)
        dispatcher.setRegions(closed.hitTestRegions)
        let control = try #require(closed.hitTestRegions.first { $0.offsetY == 0 })
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: control.offsetX, y: 0))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: control.offsetX, y: 0))

        #expect(box.value.isOpen == true, "clicking the control must open a closed drop-down")
    }

    @Test("Open menu picker writes the transient ESC label on the status bar")
    func menuPickerSetsEscapeLabelOverrideWhenOpen() {
        let context = createTestContext()
        // The default StatusBarState is shared across tests via the
        // environment-key default value, so explicitly reset what we care
        // about before checking it.
        context.environment.statusBar.escapeLabelOverride = nil
        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })

        let entries: [_PickerEntry<AnyHashable>] = [
            _PickerEntry.option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            _PickerEntry.option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries,
            selection: binding,
            focusID: "menu-picker",
            isDisabled: false
        )

        // First render registers the handler; the picker is closed, so it
        // should leave the override untouched (nil by default).
        _ = renderToBuffer(core, context: context)
        #expect(context.environment.statusBar.escapeLabelOverride == nil)

        // Flip the persisted handler open and re-render — the picker should
        // post the override so a page-level ESC handler reads "close menu".
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
        let dummySelection = Binding<AnyHashable>(get: { AnyHashable("") }, set: { _ in })
        let box: StateBox<_PickerMenuHandler> = context.environment.stateStorage!.storage(
            for: key,
            default: _PickerMenuHandler(
                focusID: "menu-picker",
                selection: dummySelection,
                itemValues: [],
                canBeFocused: true
            )
        )
        box.value.isOpen = true
        _ = renderToBuffer(core, context: context)
        #expect(context.environment.statusBar.escapeLabelOverride == "close drop-down menu")
    }

    @Test("A closed picker leaves the existing ESC label override alone")
    func closedPickerDoesNotTouchEscapeLabelOverride() {
        // The override is owned by the render loop: it clears it at the
        // start of every frame, and any open modal surface writes the
        // label it wants while rendering. A closed picker must therefore
        // be a no-op so it does not stomp on whatever else is active —
        // for example a Dialog further down the same frame.
        let context = createTestContext()
        context.environment.statusBar.escapeLabelOverride = "dismiss"

        var choice = AnyHashable("a")
        let binding = Binding<AnyHashable>(get: { choice }, set: { choice = $0 })
        let entries: [_PickerEntry<AnyHashable>] = [
            _PickerEntry.option(tag: AnyHashable("a"), label: AnyView(Text("Apple"))),
            _PickerEntry.option(tag: AnyHashable("b"), label: AnyView(Text("Banana"))),
        ]
        let core = _PickerMenuCore(
            entries: entries,
            selection: binding,
            focusID: "menu-picker",
            isDisabled: false
        )

        _ = renderToBuffer(core, context: context)
        #expect(context.environment.statusBar.escapeLabelOverride == "dismiss")
    }
}

// MARK: - Picker Menu Handler Tests

@MainActor
@Suite("Picker Menu Handler Tests")
struct PickerMenuHandlerTests {

    /// Builds a handler over three string options with the given selection.
    private func makeHandler(
        selected: String,
        onChange: @escaping (AnyHashable) -> Void = { _ in }
    ) -> _PickerMenuHandler {
        let binding = Binding<AnyHashable>(
            get: { AnyHashable(selected) },
            set: { onChange($0) }
        )
        return _PickerMenuHandler(
            focusID: "picker",
            selection: binding,
            itemValues: [AnyHashable("a"), AnyHashable("b"), AnyHashable("c")],
            canBeFocused: true
        )
    }

    @Test("A closed picker does NOT open on the Down key (Down moves focus)")
    func downDoesNotOpen() {
        let handler = makeHandler(selected: "a")
        #expect(handler.isOpen == false)

        // Down on a closed picker must not be consumed, so focus can move on.
        let consumed = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(consumed == false)
        #expect(handler.isOpen == false)
    }

    @Test("A closed picker opens on Enter or Space")
    func opensOnEnterOrSpace() {
        let handler = makeHandler(selected: "a")
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(handler.isOpen == true)

        let handler2 = makeHandler(selected: "a")
        #expect(handler2.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(handler2.isOpen == true)
    }

    @Test("A closed picker lets Tab propagate for focus navigation")
    func closedPickerPassesTab() {
        let handler = makeHandler(selected: "a")
        let consumed = handler.handleKeyEvent(KeyEvent(key: .tab))
        #expect(consumed == false)
        #expect(handler.isOpen == false)
    }

    @Test("Arrow keys move the highlight while open")
    func arrowsMoveHighlight() {
        let handler = makeHandler(selected: "a")
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))  // open at index 0
        #expect(handler.highlightedIndex == 0)

        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.highlightedIndex == 1)

        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.highlightedIndex == 0)

        // Up from the first option wraps to the last.
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.highlightedIndex == 2)
    }

    @Test("Enter commits the highlighted option and closes")
    func enterCommitsSelection() {
        var committed: AnyHashable?
        let handler = makeHandler(selected: "a", onChange: { committed = $0 })

        _ = handler.handleKeyEvent(KeyEvent(key: .enter))  // open
        _ = handler.handleKeyEvent(KeyEvent(key: .down))  // highlight "b"
        let consumed = handler.handleKeyEvent(KeyEvent(key: .enter))

        #expect(consumed == true)
        #expect(handler.isOpen == false)
        #expect(committed == AnyHashable("b"))
    }

    @Test("Escape closes the drop-down without changing the selection")
    func escapeCancels() {
        var committed: AnyHashable?
        let handler = makeHandler(selected: "a", onChange: { committed = $0 })

        _ = handler.handleKeyEvent(KeyEvent(key: .enter))  // open
        _ = handler.handleKeyEvent(KeyEvent(key: .down))  // highlight "b"
        let consumed = handler.handleKeyEvent(KeyEvent(key: .escape))

        #expect(consumed == true)
        #expect(handler.isOpen == false)
        #expect(committed == nil)
    }

    @Test("Losing focus closes an open drop-down")
    func focusLossCloses() {
        let handler = makeHandler(selected: "a")
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(handler.isOpen == true)

        handler.onFocusLost()
        #expect(handler.isOpen == false)
    }
}
