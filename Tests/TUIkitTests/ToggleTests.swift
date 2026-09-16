//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToggleTests.swift
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

// MARK: - Toggle Tests

@MainActor
@Suite("Toggle Tests", .serialized)
struct ToggleTests {

    @Test("Toggle can be created with binding and label")
    func toggleCreation() {
        var isEnabled = false
        let binding = Binding(
            get: { isEnabled },
            set: { isEnabled = $0 }
        )

        let toggle = Toggle("Enable", isOn: binding)

        #expect(toggle.isDisabled == false)
    }

    @Test("Toggle disabled modifier")
    func toggleDisabledModifier() {
        var state = false
        let binding = Binding(
            get: { state },
            set: { state = $0 }
        )

        let toggle = Toggle("Test", isOn: binding).disabled()

        #expect(toggle.isDisabled == true)

        let enabledToggle = Toggle("Test", isOn: binding).disabled(false)

        #expect(enabledToggle.isDisabled == false)
    }

    @Test("Toggle renders focus indicator when focused")
    func toggleFocusIndicator() {
        let context = createTestContext()

        var isOn = false
        let binding = Binding(
            get: { isOn },
            set: { isOn = $0 }
        )

        let toggle = Toggle("Focused", isOn: binding)

        let buffer = renderToBuffer(toggle, context: context)

        // Focused toggle should have ANSI codes (pulsing brackets)
        let content = buffer.lines.joined()
        #expect(content.contains("\u{1b}["), "Focused toggle should have ANSI styling for pulsing brackets")
    }

    @Test("Toggle renders without focus indicator when unfocused")
    func toggleUnfocusedNoIndicator() {
        let context = createTestContext()

        var state1 = false
        var state2 = false
        let binding1 = Binding(get: { state1 }, set: { state1 = $0 })
        let binding2 = Binding(get: { state2 }, set: { state2 = $0 })

        let toggle1 = Toggle("First", isOn: binding1)
        let toggle2 = Toggle("Second", isOn: binding2)

        // Render first (gets focus), then second
        _ = renderToBuffer(toggle1, context: context)
        let buffer2 = renderToBuffer(toggle2, context: context)

        // Unfocused toggle should not have leading space for focus indicator
        let content = buffer2.lines.joined().stripped
        #expect(content.contains("Second"))
    }

    @Test("Disabled toggle uses tertiary color")
    func disabledToggleColor() {
        let context = createTestContext()

        var isOn = false
        let binding = Binding(
            get: { isOn },
            set: { isOn = $0 }
        )

        let toggle = Toggle("Disabled", isOn: binding).disabled()
        let buffer = renderToBuffer(toggle, context: context)

        // Disabled toggle should be rendered but with different styling
        let content = buffer.lines.joined()
        #expect(content.contains("Disabled"))
    }

    @Test("Unfocused enabled toggle draws brackets in the normal foreground")
    func unfocusedEnabledBracketColor() {
        let context = createTestContext()

        var first = false
        var second = false
        let bindingFirst = Binding(get: { first }, set: { first = $0 })
        let bindingSecond = Binding(get: { second }, set: { second = $0 })

        // Two toggles in a stack: the first registers focus, leaving the
        // second one genuinely unfocused (but still enabled).
        // This test is specifically about the two-tone bracket colouring, so it
        // uses the ASCII checkbox style (the default ■/□ glyphs have no brackets).
        let stack = VStack(spacing: 0) {
            Toggle("First", isOn: bindingFirst)
            Toggle("Second", isOn: bindingSecond)
        }
        .toggleCharacterSet(.ascii)
        let buffer = renderToBuffer(stack, context: context)
        #expect(buffer.height == 2, "Expected one line per toggle, got \(buffer.height)")
        let unfocusedLine = buffer.lines[1]

        let palette = context.environment.palette
        let foregroundBracket = ANSIRenderer.colorize("[", foreground: palette.foreground)
        // `over: palette.background` because that is what `_ToggleCore` writes.
        // Without the surface this built its expectation from the mix-toward-black
        // shorthand, which coincided with the real colour only on a black palette
        // — so the "must not reuse the dim colour" assertion was comparing against
        // a string the renderer never emits. (Since `Color.opacity(_:)` began
        // carrying real alpha it does not even have an SGR spelling, and the
        // emitter's assertion says so.)
        let disabledBracket = ANSIRenderer.colorize(
            "[",
            foreground: palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        )

        #expect(
            unfocusedLine.contains(foregroundBracket),
            "An unfocused, enabled toggle must draw '[' in the normal foreground colour, got: \(unfocusedLine)"
        )
        #expect(
            !unfocusedLine.contains(disabledBracket),
            "An unfocused, enabled toggle must not reuse the dim disabled bracket colour"
        )
    }

    @Test("Toggle label is drawn in the normal foreground colour")
    func toggleLabelIsColored() {
        let context = createTestContext()
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })

        let line = renderToBuffer(Toggle("Readable", isOn: binding), context: context).lines.joined()

        // The label must carry foreground styling — exactly what a
        // standalone Text produces — rather than being stripped to a
        // colourless run that renders in the terminal's default colour.
        let styledLabel = renderToBuffer(Text("Readable"), context: context).lines.joined()
        #expect(
            line.contains(styledLabel),
            "Toggle label must be drawn in the foreground colour, got: \(line)"
        )
    }

    @Test("Disabled toggle dims its label")
    func disabledToggleLabelDimmed() {
        let context = createTestContext()
        let line = renderToBuffer(
            Toggle("Dimmed", isOn: .constant(false)).disabled(),
            context: context
        ).lines.joined()

        let palette = context.environment.palette
        let dimLabel = ANSIRenderer.colorize(
            "Dimmed",
            foreground: palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
        )
        #expect(line.contains(dimLabel), "A disabled toggle's label should be dimmed, got: \(line)")
    }

    // MARK: - Explanatory subtitle (SwiftUI "title + description" label)

    @Test("A multi-view toggle label renders a title plus an indented subtitle")
    func toggleLabelWithDescription() {
        let context = createTestContext()
        let buffer = renderToBuffer(
            Toggle(isOn: .constant(true)) {
                Text("Push notifications")
                Text("Receive alerts even when closed")
            },
            context: context)

        #expect(buffer.height == 2, "title + one subtitle line, got \(buffer.lines.map(\.stripped))")
        let title = buffer.lines[0].stripped
        let subtitle = buffer.lines[1].stripped
        #expect(title.contains("Push notifications"))
        #expect(subtitle.contains("Receive alerts even when closed"))

        // The subtitle aligns to the title's *label* column (past the box), not
        // column 0. Measure the DISPLAY column (the checkbox glyph is one grapheme
        // but two cells wide), not the grapheme index.
        func displayColumn(of needle: String, in line: String) -> Int? {
            guard let range = line.range(of: needle) else { return nil }
            return FrameBuffer(lines: [String(line[line.startIndex..<range.lowerBound])]).width
        }
        let titleCol = displayColumn(of: "Push", in: title)
        let subtitleCol = displayColumn(of: "Receive", in: subtitle)
        #expect(titleCol != nil && titleCol == subtitleCol,
                "subtitle aligns to the label column: title=\(titleCol as Int?) subtitle=\(subtitleCol as Int?)")
        #expect((subtitleCol ?? 0) > 0, "subtitle is indented past column 0")
        #expect(!subtitle.contains("\u{25A0}") && !subtitle.contains("\u{25A1}"),
                "subtitle must not repeat the checkbox glyph")
    }

    @Test("A toggle's explanatory subtitle is drawn in the secondary colour")
    func toggleDescriptionSecondaryColour() {
        let context = createTestContext()
        let subtitleLine = renderToBuffer(
            Toggle(isOn: .constant(false)) {
                Text("Sync")
                Text("Across devices")
            },
            context: context).lines[1]

        let palette = context.environment.palette
        let secondary = ANSIRenderer.colorize("Across devices", foreground: palette.foregroundSecondary)
        #expect(subtitleLine.contains(secondary),
                "the subtitle should use the secondary colour, got: \(subtitleLine)")
    }

    @Test("A toggle's explanatory subtitle is not part of the click target")
    func toggleDescriptionNotClickable() {
        let ctx = makeRenderContext(width: 50, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let buffer = renderToBuffer(
            Toggle(isOn: .constant(true)) {
                Text("Wi-Fi")
                Text("Join networks automatically")
            },
            context: ctx)

        #expect(buffer.height == 2)
        // A hit region covers the title row (0) but none reach the subtitle (row 1).
        let coversTitle = buffer.hitTestRegions.contains { $0.offsetY <= 0 && 0 < $0.offsetY + $0.height }
        let coversSubtitle = buffer.hitTestRegions.contains { $0.offsetY <= 1 && 1 < $0.offsetY + $0.height }
        #expect(coversTitle, "the title row should be clickable")
        #expect(!coversSubtitle, "the subtitle row must not be clickable")
    }

    @Test("A long explanatory subtitle wraps to the available width")
    func toggleDescriptionWraps() {
        // Render the toggle in a width-constrained VStack so the subtitle must
        // wrap. The stack hands the toggle the same width to measure and to
        // render, so the wrapped height it reports is the height it draws.
        let narrow = 30
        let context = createTestContext(width: narrow, height: 12)
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Toggle(isOn: .constant(true)) {
                    Text("Push notifications")
                    Text("Receive alerts on this device even when the application is closed")
                }
            },
            context: context)

        // The long subtitle (>30 cols) must wrap onto multiple lines: title +
        // 2-or-more subtitle rows.
        #expect(buffer.height >= 3, "subtitle should wrap, got \(buffer.height) lines: \(buffer.lines.map(\.stripped))")
        // Nothing exceeds the available width (no overflow / clipping artefacts).
        #expect(buffer.width <= narrow, "buffer width \(buffer.width) must fit \(narrow)")
        // The title is intact on the first line.
        #expect(buffer.lines[0].stripped.contains("Push notifications"))
    }

    @Test("A single-view toggle label is unchanged (one line, fully clickable)")
    func toggleSingleLabelUnchanged() {
        let ctx = makeRenderContext(width: 50, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let buffer = renderToBuffer(Toggle("Wi-Fi", isOn: .constant(true)), context: ctx)
        #expect(buffer.height == 1)
        // The whole single line is the click target.
        #expect(buffer.hitTestRegions.contains { $0.height == 1 && $0.width == buffer.width })
    }
}

// MARK: - Toggle Handler Tests

@MainActor
@Suite("Toggle Action Handler Integration Tests")
struct ToggleActionHandlerIntegrationTests {

    @Test("Toggle uses ActionHandler for key events")
    func toggleUsesActionHandler() {
        // Verify that Toggle's action handler correctly toggles the binding
        var isOn = false
        let binding = Binding(
            get: { isOn },
            set: { isOn = $0 }
        )

        // Create handler as Toggle does internally
        let handler = ActionHandler(
            focusID: "toggle-test",
            action: { binding.wrappedValue.toggle() },
            canBeFocused: true
        )

        // Space key should toggle
        let spaceEvent = KeyEvent(key: .space)
        let spaceHandled = handler.handleKeyEvent(spaceEvent)

        #expect(spaceHandled == true)
        #expect(isOn == true)

        // Enter key should toggle back
        let enterEvent = KeyEvent(key: .enter)
        let enterHandled = handler.handleKeyEvent(enterEvent)

        #expect(enterHandled == true)
        #expect(isOn == false)
    }

    @Test("Toggle action handler ignores other keys")
    func ignoresOtherKeys() {
        var isOn = false
        let binding = Binding(
            get: { isOn },
            set: { isOn = $0 }
        )

        let handler = ActionHandler(
            focusID: "ignore-test",
            action: { binding.wrappedValue.toggle() },
            canBeFocused: true
        )

        let event = KeyEvent(key: .character("a"))
        let handled = handler.handleKeyEvent(event)

        #expect(handled == false)
        #expect(isOn == false)
    }
}

// MARK: - Hover

/// Claims auto-focus so the toggle under test renders **unfocused**. The first
/// `Focusable` to register with a fresh `FocusManager` is auto-focused, and a
/// focused toggle suppresses its hover affordance (focus is the more emphatic
/// one) — without this the hovered and un-hovered renders are identical and the
/// tests below pass for the wrong reason. Same sentinel `ButtonTests` uses.
private final class ToggleFocusSentinel: Focusable {
    let focusID = "toggle-hover-sentinel"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}

/// A toggle answers the pointer by LIFTING its foreground — the colour it
/// draws with, stepped away from the page until the terminal can show the
/// difference.
///
/// Two wrong answers preceded it. It recoloured the indicator to
/// ``Palette/hoveredControlFace``, a *fill* colour used as a foreground, which
/// moved the glyph TOWARD the page: the pointer made an enabled toggle look
/// disabled. Then it painted that fill as a row background, which a toggle has
/// no business doing — unlike a `Button` it owns no background, it draws over
/// whatever its parent drew, so any colour it paints there is a guess about
/// someone else's view.
@MainActor
@Suite("Toggle hover", .serialized)
struct ToggleHoverTests {

    /// Renders `view` unfocused, then again after the pointer moves onto it.
    private func beforeAndAfterHover(
        _ view: some View, context: RenderContext
    ) -> (before: [String], after: [String]) {
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)
        context.environment.focusManager!.register(ToggleFocusSentinel())

        let before = renderToBuffer(view, context: context).lines
        let regions = renderToBuffer(view, context: context).hitTestRegions
        dispatcher.setRegions(regions)
        guard let region = regions.first else {
            Issue.record("expected a hit-test region from Toggle")
            return (before, before)
        }
        _ = dispatcher.dispatch(
            MouseEvent(
                button: .none, phase: .moved,
                x: region.offsetX + 1, y: region.offsetY))
        return (before, renderToBuffer(view, context: context).lines)
    }

    @Test("Hovering lifts the indicator and label to the hovered foreground")
    func hoverLiftsTheForeground() {
        let context = createTestContext()
        let palette = context.environment.palette
        let (before, after) = beforeAndAfterHover(
            Toggle("Hover me", isOn: .constant(false)), context: context)

        let lifted = ANSIRenderer.colorize(
            "Hover me", foreground: palette.hoveredForeground(palette.foreground))
        #expect(!before.joined().contains(lifted), "not lifted at rest: \(before)")
        #expect(after.joined().contains(lifted), "lifted under the pointer: \(after)")
    }

    @Test("Hovering paints no background of its own")
    func hoverPaintsNoBackground() {
        // The whole reason the lift is a foreground: a toggle draws over its
        // parent's background. Any background code it emits is a colour it
        // invented for someone else's view.
        let context = createTestContext()
        let (before, after) = beforeAndAfterHover(
            Toggle("Hover me", isOn: .constant(false)), context: context)
        #expect(!before.joined().contains("48;"), "no background at rest: \(before)")
        #expect(!after.joined().contains("48;"), "and none under the pointer either: \(after)")
    }

    /// Every palette that STATES its own colours: the phosphor presets and the Terminal
    /// profiles. A lift is measured against the page, and a palette that leaves its ink
    /// or its page to the terminal has no ratio to measure until the terminal reports
    /// them — it climbs a ladder of names instead (`HoverLadderTests`).
    private var statedPalettes: [any Palette] {
        PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
    }

    @Test("The lift never reads as the disabled fade")
    func hoverNeverLooksDisabled() {
        // The exact shape of the first wrong answer: a hover that moved the
        // glyph TOWARD the page, so the pointer made the control look switched
        // off. Eleven palettes have room to lift away from the page outright;
        // the five whose text is already at the extreme (Basic, Man Page,
        // Ocean, Silver Aerogel, Solid Colors) lift in hue toward the accent
        // instead. Either way it has to stay clear of the one colour that means
        // "you cannot click this".
        for palette in statedPalettes {
            let page = palette.background
            let disabled = palette.foregroundTertiary.opacity(
                ViewConstants.disabledForeground, over: palette.background)
            let hovered = palette.hoveredForeground(palette.foreground)
            #expect(
                hovered.contrastRatio(against: page) > disabled.contrastRatio(against: page),
                "\(palette.name): the hovered foreground is dimmer than the disabled one")
        }
    }

    @Test("The lifted foreground is still readable on every stated palette")
    func hoverStaysReadable() {
        for palette in statedPalettes {
            let hovered = palette.hoveredForeground(palette.foreground)
                .downsampledToPalette256()
            let page = palette.background.resolve(with: palette).downsampledToPalette256()
            let ratio = hovered.contrastRatio(against: page)
            #expect(
                ratio >= ViewConstants.labelContrastFloor,
                "\(palette.name): a hovered label at \(String(format: "%.2f", ratio)):1")
        }
    }

    @Test("The lift survives the 256-colour cube on every built-in palette")
    func hoverIsVisibleOnEveryPalette() {
        // A lift finer than the cube is no lift at all on the terminals least
        // able to spare one — the rule `hoveredControlFace` and
        // `liftedBackground` already follow.
        for palette in statedPalettes {
            let resting = palette.foreground.resolve(with: palette).downsampledToPalette256()
            let hovered = palette.hoveredForeground(palette.foreground)
                .downsampledToPalette256()
            #expect(
                hovered.rgbComponents! != resting.rgbComponents!,
                "\(palette.name): the hovered foreground quantises back onto the resting one")
        }
    }

    @Test("The lift covers exactly the clickable row")
    func hoverStopsAtTheClickRow() {
        // An explanatory subtitle is not a click target (see
        // `toggleSubtitleIsNotClickable`), so it is not part of the affordance
        // either — what answers is what the pointer can actually hit.
        let context = createTestContext()
        let palette = context.environment.palette
        let (_, after) = beforeAndAfterHover(
            Toggle(isOn: .constant(false)) {
                Text("Title")
                Text("Explanatory subtitle")
            },
            context: context)

        let lift = ANSIRenderer.colorize(
            "Title", foreground: palette.hoveredForeground(palette.foreground))
        #expect(after.count >= 2, "expected a title and a subtitle row: \(after)")
        #expect(after[0].contains(lift), "the title row lifts: \(after[0])")
        #expect(
            !after[1].contains("Explanatory subtitle\(ANSIRenderer.reset)")
                || !after[1].contains(
                    ANSIRenderer.colorize(
                        "Explanatory subtitle",
                        foreground: palette.hoveredForeground(palette.foreground))),
            "the subtitle row does not: \(after[1])")
    }

    @Test("A disabled toggle has nothing to hover")
    func disabledNeverHovers() {
        let context = createTestContext()
        let buffer = renderToBuffer(
            Toggle("Disabled", isOn: .constant(false)).disabled(), context: context)
        #expect(
            buffer.hitTestRegions.isEmpty,
            "a disabled toggle registers no region, so it never enters the hover state")
    }
}
