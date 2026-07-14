//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonTests.swift
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

/// Renders to a string with ANSI codes preserved so tests can
/// assert about specific colour escapes.
@MainActor
private func ansiRendered<V: View>(_ view: V, context: RenderContext) -> String {
    renderToBuffer(view, context: context).lines.joined(separator: "\n")
}

/// Sentinel focusable used by the hover tests to claim auto-focus
/// before the button under test renders. The first `Focusable` to
/// register with a fresh `FocusManager` is auto-focused (so screens
/// open with a focused element), and a focused `Button` suppresses
/// its hover affordance (see the `isHovered && !isFocused` clamp in
/// the standard button style). Without this sentinel, the button
/// renders identically before and after a hover event because the
/// hover state is silently suppressed.
private final class FocusSentinel: Focusable {
    let focusID = "test-focus-sentinel"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}

// MARK: - Button Tests

@MainActor
@Suite("Button Tests", .serialized)
struct ButtonTests {

    @Test("Button can be created with label and action")
    func buttonCreation() {
        var wasPressed = false
        let button = Button("Click Me") {
            wasPressed = true
        }

        #expect(button.label == "Click Me")
        #expect(button.isDisabled == false)
        button.action()
        #expect(wasPressed == true)
    }

    @Test("Button disabled modifier")
    func buttonDisabledModifier() {
        let button = Button("Test") {}.disabled()
        #expect(button.isDisabled == true)

        let enabledButton = Button("Test") {}.disabled(false)
        #expect(enabledButton.isDisabled == false)
    }

    @Test("Button focusID defaults to nil (auto-generated during rendering)")
    func buttonGeneratesUniqueID() {
        let button1 = Button("One") {}
        let button2 = Button("Two") {}

        // FocusID is now nil by default, allowing auto-generation from context.identity.path
        // during rendering via FocusRegistration.persistFocusID()
        #expect(button1.focusID == nil)
        #expect(button2.focusID == nil)
    }

    @Test("Default button renders as single-line bracket style")
    func defaultButtonRendersBrackets() {
        let context = createTestContext()

        let button = Button("OK") {}
        let buffer = renderToBuffer(button, context: context)

        // Cap-style buttons are single line: ▐ OK ▌
        #expect(buffer.height == 1)
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("OK"))
        #expect(allContent.stripped.contains("\u{2590}"))
        #expect(allContent.stripped.contains("\u{258C}"))
    }

    @Test("Plain button has single line without brackets")
    func plainButtonSingleLine() {
        let context = createTestContext()

        let button = Button("Test") {}.buttonStyle(.plain)
        let buffer = renderToBuffer(button, context: context)

        #expect(buffer.height == 1)
        // Check visible text (stripped of ANSI codes) has no brackets
        let visibleContent = buffer.lines.joined().stripped
        #expect(!visibleContent.contains("["))
        #expect(!visibleContent.contains("]"))
    }

    @Test("Focused button has accent-colored brackets")
    func focusedButtonHasAccentBrackets() {
        let context = createTestContext()

        let button = Button("Focus Me") {}.focusID("focused-button")
        let buffer = renderToBuffer(button, context: context)

        // First button is auto-focused — caps should be styled (contain ANSI codes)
        let allContent = buffer.lines.joined()
        #expect(allContent.stripped.contains("\u{2590}"), "Button should have opening cap")
        #expect(allContent.stripped.contains("\u{258C}"), "Button should have closing cap")
        #expect(allContent.contains("\u{1b}["), "Focused button should have ANSI styling")
    }

    @Test("Unfocused button has border-colored brackets")
    func unfocusedButtonHasBorderBrackets() {
        let context = createTestContext()

        // Create two buttons — second one will be unfocused
        let button1 = Button("First") {}.focusID("first")
        let button2 = Button("Second") {}.focusID("second")

        // Render first to register it (it gets focus)
        _ = renderToBuffer(button1, context: context)
        let buffer2 = renderToBuffer(button2, context: context)

        // Second button is not focused — should still have caps with styling
        let allContent = buffer2.lines.joined()
        #expect(allContent.stripped.contains("\u{2590}"), "Unfocused button should have opening cap")
        #expect(allContent.stripped.contains("\u{258C}"), "Unfocused button should have closing cap")
    }

    @Test("Destructive button uses palette error color, not hardcoded red")
    func destructiveButtonUsesPaletteColor() {
        let context = createTestContext()

        let button = Button("Delete") {}.buttonStyle(.destructive)
        let buffer = renderToBuffer(button, context: context)

        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Delete"))
        // Should contain ANSI color codes (resolved from palette.error)
        #expect(allContent.contains("\u{1b}["))
    }

    @Test("Primary button is bold")
    func primaryButtonIsBold() {
        let context = createTestContext()

        let button = Button("Submit") {}.buttonStyle(.primary)
        let buffer = renderToBuffer(button, context: context)

        let allContent = buffer.lines.joined()
        // Primary style sets isBold = true, rendered as bold ANSI
        #expect(allContent.contains("\u{1b}[1;"))
    }

    @Test("Destructive role renders via the style without an explicit buttonStyle")
    func destructiveRoleRendersViaStyle() {
        let context = createTestContext()

        // No .buttonStyle() — the default style colours destructive roles.
        let button = Button("Delete", role: .destructive) {}
        let buffer = renderToBuffer(button, context: context)

        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Delete"))
        #expect(allContent.contains("\u{1b}["))
    }

    @Test("buttonStyle propagates through a container to nested buttons")
    func buttonStylePropagatesThroughContainer() {
        let context = createTestContext()

        let styled = VStack {
            Button("A") {}
            Button("B") {}
        }
        .buttonStyle(.plain)

        let buffer = renderToBuffer(styled, context: context)
        let visible = buffer.lines.joined().stripped

        // The plain style draws no bracket caps — proof the environment
        // value reached both nested buttons.
        #expect(!visible.contains("\u{2590}"))
        #expect(!visible.contains("\u{258C}"))
        #expect(visible.contains("A"))
        #expect(visible.contains("B"))
    }

    // MARK: - Hover

    @Test("Hover .entered flips Button's hover state and changes its rendered tint")
    func hoverFlipsRenderedTint() {
        let context = createTestContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)

        // Park focus on the sentinel so the button under test
        // is rendered un-focused — see FocusSentinel for why.
        context.environment.focusManager!.register(FocusSentinel())

        let view = Button("Hover me") { /* no-op */ }

        // First render: registers handler + region, default
        // hover state is false → un-hovered tint.
        let pre = ansiRendered(view, context: context)
        // Capture the regions before we re-render (which would
        // clear them in beginRenderPass).
        let regions = renderToBuffer(view, context: context).hitTestRegions
        dispatcher.setRegions(regions)

        guard let buttonRegion = regions.first else {
            Issue.record("expected at least one hit-test region from Button")
            return
        }

        // Dispatch .moved into the region — the dispatcher
        // synthesises .entered for the button's handler, which
        // flips its hover StateBox to true.
        _ = dispatcher.dispatch(
            MouseEvent(
                button: .none,
                phase: .moved,
                x: buttonRegion.offsetX + 1,
                y: buttonRegion.offsetY
            )
        )

        // Second render: hover state is now true → the tint
        // bumps from focusBorderDim (.20) to hoverBackground
        // (.32). The exact ANSI escapes differ.
        let post = ansiRendered(view, context: context)
        #expect(
            pre != post,
            "Button should render differently when hovered; pre and post matched"
        )
    }

    @Test("Hover .exited restores Button's un-hovered tint")
    func hoverExitRestoresTint() {
        let context = createTestContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)

        // Park focus on the sentinel — same reason as the
        // hoverFlipsRenderedTint sibling test above.
        context.environment.focusManager!.register(FocusSentinel())

        let view = Button("Hover me") { /* no-op */ }

        let pre = ansiRendered(view, context: context)
        let regions = renderToBuffer(view, context: context).hitTestRegions
        dispatcher.setRegions(regions)
        guard let buttonRegion = regions.first else { return }

        // Enter
        _ = dispatcher.dispatch(
            MouseEvent(
                button: .none, phase: .moved,
                x: buttonRegion.offsetX + 1, y: buttonRegion.offsetY
            )
        )
        let hovered = ansiRendered(view, context: context)
        #expect(pre != hovered)

        // Re-issue regions after the render (beginRenderPass
        // cleared them) and move the cursor out.
        let regions2 = renderToBuffer(view, context: context).hitTestRegions
        dispatcher.setRegions(regions2)
        _ = dispatcher.dispatch(
            MouseEvent(button: .none, phase: .moved, x: 100, y: 100)
        )
        let restored = ansiRendered(view, context: context)
        #expect(
            restored == pre,
            "Button should return to its un-hovered tint after the cursor leaves"
        )
    }

    @Test("Disabled Buttons do not register a hit-test region (no hover)")
    func disabledButtonNoHover() {
        let context = createTestContext()
        let view = Button("Disabled") { }.disabled()
        let buffer = renderToBuffer(view, context: context)
        #expect(
            buffer.hitTestRegions.isEmpty,
            "Disabled buttons should not emit a hit-test region; got \(buffer.hitTestRegions.count)"
        )
    }
}

// MARK: - Action Handler Tests

@MainActor
@Suite("Action Handler Tests")
struct ActionHandlerTests {

    @Test("ActionHandler handles Enter key")
    func handleEnterKey() {
        var wasTriggered = false
        let handler = ActionHandler(
            focusID: "enter-test",
            action: { wasTriggered = true },
            canBeFocused: true
        )

        let event = KeyEvent(key: .enter)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(wasTriggered == true)
    }

    @Test("ActionHandler handles Space key")
    func handleSpaceKey() {
        var wasTriggered = false
        let handler = ActionHandler(
            focusID: "space-test",
            action: { wasTriggered = true },
            canBeFocused: true
        )

        let event = KeyEvent(key: .space)
        let handled = handler.handleKeyEvent(event)

        #expect(handled == true)
        #expect(wasTriggered == true)
    }

    @Test("ActionHandler ignores other keys")
    func ignoresOtherKeys() {
        var wasTriggered = false
        let handler = ActionHandler(
            focusID: "ignore-test",
            action: { wasTriggered = true },
            canBeFocused: true
        )

        let event = KeyEvent(key: .character("a"))
        let handled = handler.handleKeyEvent(event)

        #expect(handled == false)
        #expect(wasTriggered == false)
    }

    @Test("ActionHandler respects custom trigger keys")
    func customTriggerKeys() {
        var wasTriggered = false
        let handler = ActionHandler(
            focusID: "custom-test",
            action: { wasTriggered = true },
            canBeFocused: true,
            triggerKeys: [Key.enter]  // Only Enter, not Space
        )

        // Space should not trigger
        let spaceEvent = KeyEvent(key: .character(" "))
        let spaceHandled = handler.handleKeyEvent(spaceEvent)
        #expect(spaceHandled == false)
        #expect(wasTriggered == false)

        // Enter should trigger
        let enterEvent = KeyEvent(key: .enter)
        let enterHandled = handler.handleKeyEvent(enterEvent)
        #expect(enterHandled == true)
        #expect(wasTriggered == true)
    }
}

// MARK: - Button Row Tests

@MainActor
@Suite("Button Row Tests")
struct ButtonRowTests {

    @Test("ButtonRow can be created with buttons")
    func buttonRowCreation() {
        let context = createTestContext()

        let row = ButtonRow {
            Button("Cancel") {}
            Button("OK") {}
        }

        let buffer = renderToBuffer(row, context: context)

        // Bracket-style buttons are single line
        #expect(buffer.height == 1)
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Cancel"))
        #expect(allContent.contains("OK"))
    }

    @Test("ButtonRow with custom spacing")
    func buttonRowSpacing() {
        let context = createTestContext()

        let row = ButtonRow(spacing: 5) {
            Button("A") {}
            Button("B") {}
        }
        .buttonStyle(.plain)

        let buffer = renderToBuffer(row, context: context)

        // Both buttons should be present
        #expect(buffer.height == 1)  // plain buttons without border
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("A"))
        #expect(allContent.contains("B"))
    }

    @Test("Empty ButtonRow returns empty buffer")
    func emptyButtonRow() {
        let row = ButtonRow {}
        let context = createTestContext()

        let buffer = renderToBuffer(row, context: context)

        #expect(buffer.isEmpty)
    }

    @Test("ButtonRow renders buttons horizontally")
    func buttonRowHorizontal() {
        let context = createTestContext()

        let row = ButtonRow {
            Button("First") {}
            Button("Second") {}
        }
        .buttonStyle(.plain)

        let buffer = renderToBuffer(row, context: context)

        // Should have same number of lines (horizontal layout)
        // Plain buttons are single line, so the row should be single line
        #expect(buffer.height == 1)
    }

    @Test("ButtonRow with mixed styles has uniform height")
    func buttonRowUniformHeight() {
        let context = createTestContext()

        let row = ButtonRow {
            Button("Default") {}
            Button("Plain") {}
        }

        let buffer = renderToBuffer(row, context: context)

        // Both are now single line (brackets and plain)
        #expect(buffer.height == 1)
    }
}

// MARK: - Button Row Builder Tests

@MainActor
@Suite("Button Row Builder Tests")
struct ButtonRowBuilderTests {

    @Test("ButtonRowBuilder builds array of buttons")
    func builderCreatesArray() {
        let buttons = ButtonRowBuilder.buildBlock(
            Button("A") {},
            Button("B") {},
            Button("C") {}
        )

        #expect(buttons.count == 3)
    }

    @Test("ButtonRowBuilder handles optional")
    func builderHandlesOptional() {
        let buttons: [Button]? = nil
        let result = ButtonRowBuilder.buildOptional(buttons)

        #expect(result.isEmpty)

        let someButtons: [Button]? = [Button("Test") {}]
        let result2 = ButtonRowBuilder.buildOptional(someButtons)

        #expect(result2.count == 1)
    }

    @Test("ButtonRowBuilder handles either first")
    func builderHandlesEitherFirst() {
        let buttons = [Button("First") {}]
        let result = ButtonRowBuilder.buildEither(first: buttons)

        #expect(result.count == 1)
        #expect(result[0].label == "First")
    }

    @Test("ButtonRowBuilder handles either second")
    func builderHandlesEitherSecond() {
        let buttons = [Button("Second") {}]
        let result = ButtonRowBuilder.buildEither(second: buttons)

        #expect(result.count == 1)
        #expect(result[0].label == "Second")
    }

    @Test("ButtonRowBuilder handles array")
    func builderHandlesArray() {
        let groups: [[Button]] = [
            [Button("A") {}],
            [Button("B") {}, Button("C") {}],
        ]
        let result = ButtonRowBuilder.buildArray(groups)

        #expect(result.count == 3)
    }

    @Test("Standard button label truncates with an ellipsis when squeezed")
    @MainActor
    func standardLabelTruncatesWithEllipsis() {
        // The standard chrome is 2 cells of caps + 2 cells of horizontal
        // padding, so an availableWidth of 8 leaves 4 cells for the label.
        let button = Button("Reticulate") {}
        let context = RenderContext(
            availableWidth: 8, availableHeight: 1, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(button, context: context)
        let stripped = buffer.lines[0].stripped
        #expect(stripped.contains("…"), "Truncated label should carry an ellipsis")
        #expect(buffer.lines[0].strippedLength <= 8, "Button never overflows its allowance")
    }

    @Test("Plain button label truncates with an ellipsis when squeezed")
    @MainActor
    func plainLabelTruncatesWithEllipsis() {
        let button = Button("Reticulate") {}.buttonStyle(.plain)
        let context = RenderContext(
            availableWidth: 5, availableHeight: 1, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(button, context: context)
        let stripped = buffer.lines[0].stripped
        #expect(stripped.contains("…"))
    }
}
