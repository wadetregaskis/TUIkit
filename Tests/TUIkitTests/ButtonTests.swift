//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    @Test("A plain button lifts its label colour under the pointer")
    func plainButtonHoverLiftsTheLabel() {
        // A plain button draws straight onto the page — no caps, no fill — so
        // the face swap the standard style uses has nothing to swap. Its label
        // colour is the whole affordance, and before this it had none at all:
        // `.buttonStyle(.plain)` (and therefore every `Link`) simply did not
        // answer the pointer.
        withColorDepth(.truecolor) {
            let context = createTestContext()
            let dispatcher = context.environment.mouseEventDispatcher!
            dispatcher.setActiveSupport(.full)
            context.environment.focusManager!.register(FocusSentinel())

            let view = Button("Plain") {}.buttonStyle(.plain)
            let before = ansiRendered(view, context: context)
            let regions = renderToBuffer(view, context: context).hitTestRegions
            dispatcher.setRegions(regions)
            guard let region = regions.first else {
                Issue.record("expected a hit-test region from a plain Button")
                return
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .none, phase: .moved,
                    x: region.offsetX + 1, y: region.offsetY))
            let after = ansiRendered(view, context: context)

            let palette = context.environment.palette
            func code(_ color: Color) -> String {
                let rgb = color.resolve(with: palette).rgbComponents!
                return "38;2;\(rgb.red);\(rgb.green);\(rgb.blue)"
            }
            #expect(before.contains(code(palette.accent)), "accent at rest: \(before)")
            #expect(
                after.contains(code(palette.hoveredForeground(palette.accent))),
                "lifted under the pointer: \(after)")
        }
    }

    /// Hovers the first hit region of `view` and returns the render before and the
    /// buffer after. `focused`: whether the button is the first registrant, and so
    /// takes the focus, or a sentinel holds it.
    private func hovered<V: View>(_ view: V, focused: Bool) -> (before: String, after: FrameBuffer)? {
        let context = createTestContext()
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        if !focused { context.environment.focusManager!.register(FocusSentinel()) }
        let before = ansiRendered(view, context: context)
        let regions = renderToBuffer(view, context: context).hitTestRegions
        dispatcher.setRegions(regions)
        guard let region = regions.first else {
            Issue.record("expected a hit-test region from the button")
            return nil
        }
        _ = dispatcher.dispatch(
            MouseEvent(button: .none, phase: .moved, x: region.offsetX + 1, y: region.offsetY))
        return (before, renderToBuffer(view, context: context))
    }

    /// `hoveredControlFace`'s fallback returned the RAW accent when no tint step
    /// cleared the colour cube, which `.tint(.clear)` guarantees. An unfocused cap is
    /// drawn in the face itself, so hover ALONE put a transparent colour into the
    /// caps' emitter on the string path — and on the view path claimed ink 0 (§49).
    @Test("A hovered button under a fully transparent tint draws opaque caps and claims nothing")
    func hoveredClearTintButton() {
        withColorDepth(.truecolor) {
            for label in ["string", "view"] {
                for focused in [false, true] {
                    let result =
                        label == "string"
                        ? hovered(Button("Save") {}.tint(.clear), focused: focused)
                        : hovered(Button {} label: { Text("Save") }.tint(.clear), focused: focused)
                    guard let after = result?.after else { continue }
                    #expect(
                        after.opacityRegions.isEmpty,
                        "\(label) label, focused \(focused): \(after.opacityRegions)")
                    if focused {
                        // The caps' two runs — and NOT `expectAnimates`: at `.clear`
                        // both ends of the breath are the page, so the frames are
                        // identical and the runs do not move.
                        #expect(after.animatedCells.count == 2, "\(label): \(after.animatedCells.count) runs")
                        expectReplayIsIdentity(after)
                    } else {
                        #expect(after.animatedCells.isEmpty, "\(label): a still button has no runs")
                    }
                }
            }
            // The control: at `.clear` a hovered face can be the same bytes as a
            // resting one, so show that this harness does hover — a red tint must
            // change what is drawn.
            if let red = hovered(Button("Save") {}.tint(.red), focused: false) {
                #expect(
                    red.before != red.after.lines.joined(separator: "\n"),
                    "the pointer changed nothing, so the clear-tint case proves nothing")
            }
        }
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

// MARK: - Button Row Content Tests

@MainActor
@Suite("ButtonRow content")
struct ButtonRowContentTests {

    private func render(_ view: some View, width: Int = 40) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 4))
    }

    @Test("A row of plain buttons still lays out from the leading edge")
    func plainButtons() {
        let buffer = render(
            ButtonRow {
                Button("A") {}
                Button("B") {}
            })
        let line = buffer.lines.first?.stripped ?? ""
        #expect(line.contains("A") && line.contains("B"), "line: \(line)")
        // Two buttons, two clickable regions — each keeps its own identity.
        #expect(buffer.hitTestRegions.count == 2, "regions: \(buffer.hitTestRegions.count)")
    }

    @Test("A row's buttons can carry modifiers, including a presentation")
    func modifiedButtons() {
        // The reason the `@ButtonRowBuilder` taking `Button...` had to go: a
        // dialog's footer is exactly where a "More options…" button belongs,
        // and `.sheet` / `.contextMenu` return `some View`, so every one of
        // these was a compile error.
        let buffer = render(
            ButtonRow {
                Button("Cancel") {}
                Button("Advanced…") {}
                    .modal(isPresented: .constant(true)) {
                        Dialog(title: "Advanced") { Text("x") }
                    }
            })
        #expect(
            buffer.overlays.contains { $0.level == .modal },
            "the footer's presentation did not reach the root")
    }

    @Test("A conditional row builds through the ViewBuilder")
    func conditionalContent() {
        func row(showingReset: Bool) -> some View {
            ButtonRow {
                Button("OK") {}
                if showingReset {
                    Button("Reset") {}
                }
            }
        }
        #expect(render(row(showingReset: true)).hitTestRegions.count == 2)
        #expect(render(row(showingReset: false)).hitTestRegions.count == 1)
    }

    @Test("A ForEach row builds too")
    func forEachContent() {
        let buffer = render(
            ButtonRow {
                ForEach(["A", "B", "C"], id: \.self) { label in
                    Button(label) {}
                }
            })
        #expect(buffer.hitTestRegions.count == 3)
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
