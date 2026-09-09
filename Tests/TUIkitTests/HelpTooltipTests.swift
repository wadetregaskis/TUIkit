//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpTooltipTests.swift
//
//  `help(_:)` publishes a tooltip candidate; it does not draw one. These pin
//  which candidate wins, when the hover delay lets it through, and that the
//  keyboard reveal is a toggle over the FOCUSED view rather than over whatever
//  the pointer last touched.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("help(_:) and tooltip candidates")
struct HelpTooltipTests {

    private static let second: Int64 = 1_000_000_000

    /// A context wired the way a live frame is: a focus manager, a mouse
    /// dispatcher (hover needs one) and a tooltip state.
    private func harness(
        visibility: TooltipVisibility = .automatic, delay: Double = 0.6, now: Int64 = 0
    ) -> (context: RenderContext, tooltips: TooltipState, focus: FocusManager,
        dispatcher: MouseEventDispatcher)
    {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = focus
        env.tooltipVisibility = visibility
        env.tooltipDelay = delay
        env.frameNowNanos = now
        // Motion reporting is unioned in by `AppRunner` each frame from the
        // modifier's `requestFeature(.motion)`; with no run loop here the
        // dispatcher would refuse every `.moved` event, so grant it directly.
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui),
            tui.tooltipState, focus, tui.mouseEventDispatcher
        )
    }

    /// Drives one frame of a view and returns the hit regions it produced, so a
    /// test can synthesise the hover the dispatcher would have delivered.
    private func frame<V: View>(
        _ view: V, _ h: (context: RenderContext, tooltips: TooltipState,
            focus: FocusManager, dispatcher: MouseEventDispatcher)
    ) -> FrameBuffer {
        h.focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: h.context)
        h.focus.endRenderPass()
        h.dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    // MARK: - The focus half

    /// The natural spelling puts `.help` OUTSIDE the control, so the modifier
    /// cannot read `\.isFocused` — that is published inside the control's own
    /// render. It writes `\.helpText` down instead and the focused control claims
    /// it from `FocusRegistration.register`.
    @Test("A focused control claims the help text written outside it")
    func focusedControlClaimsHelp() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index")
        _ = frame(view, h)
        #expect(
            h.tooltips.focused?.text == "Rebuild the index",
            "the focused button claimed it, got \(String(describing: h.tooltips.focused?.text))")
    }

    /// …and an unfocused one does not, so the candidate always belongs to exactly
    /// one control.
    @Test("An unfocused control publishes no focus candidate")
    func unfocusedControlPublishesNothing() {
        let h = harness()
        let view = VStack {
            Button("First") {}
            Button("Second") {}.help("the second one")
        }
        _ = frame(view, h)
        // The first button takes the focus by default, so the second's help is
        // not the candidate.
        #expect(h.tooltips.focused == nil, "nothing focused carries help")
    }

    /// **The one focusable that does not go through the shared seam.**
    ///
    /// A `NavigationSplitView` divider registers with the focus manager directly,
    /// so `FocusRegistration.register`'s help hook never runs for it and `.help`
    /// on one would work on hover and do nothing on the keyboard. That is the
    /// failure `Documentation/Parity-decisions-pending.md` predicted for this
    /// exact site — "would work for every other focusable and silently not for
    /// that one" — and it takes a test rather than a comment, because the next
    /// thing hung off that seam will miss it the same way.
    @Test("A split divider claims its help text too")
    func splitDividerClaimsHelp() {
        let h = harness()
        let view = NavigationSplitView {
            Text("sidebar")
        } detail: {
            Text("detail")
        }
        .help("Drag to resize the sidebar")
        // One frame to register the divider's section, then focus it — a split
        // view opens with the sidebar focused, not the divider.
        _ = frame(view, h)
        let section = dividerSectionID(in: h.focus)
        #expect(section != nil, "the fixture really has a divider")
        h.focus.activateSection(id: section ?? "")
        _ = frame(view, h)
        #expect(
            h.tooltips.focused?.text == "Drag to resize the sidebar",
            "got \(String(describing: h.tooltips.focused?.text))")
    }

    /// A hidden subtree publishes nothing at all — checked on the FOCUS half as
    /// well as the hover half, because the two are gated in different files and
    /// only one of them is obvious.
    @Test("tooltips(.hidden) publishes no candidate")
    func hiddenPublishesNothing() {
        let h = harness(visibility: .hidden)
        let view = Button("Rebuild") {}.help("Rebuild the index")
        _ = frame(view, h)
        #expect(h.tooltips.focused == nil, "focus half is gated")
        // The hover half is gated in a different file, and the Button registers a
        // region of its own for clicks — so the check is that hovering publishes
        // nothing, not that the buffer carries no regions at all.
        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        #expect(h.tooltips.hovered == nil, "hover half is gated too")
    }

    // MARK: - The keyboard reveal

    /// Publishing is not showing. A focus candidate needs the help key.
    @Test("A focus candidate is not shown until the keyboard asks")
    func focusCandidateNeedsTheKey() {
        let h = harness()
        _ = frame(Button("Rebuild") {}.help("Rebuild the index"), h)
        #expect(
            h.tooltips.resolved(nowNanos: 0) == nil,
            "focus alone shows nothing")

        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(
            h.tooltips.resolved(nowNanos: 0)?.text == "Rebuild the index",
            "the key revealed it")
        #expect(h.tooltips.resolved(nowNanos: 0)?.source == .focus)

        // …and it is a toggle.
        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(h.tooltips.resolved(nowNanos: 0) == nil, "toggled off")
    }

    /// Nothing to reveal must report `false`, so the caller lets the key fall
    /// through rather than swallowing it. A key that silently does nothing is the
    /// failure this whole feature is most likely to ship.
    @Test("The help key declines when the focused view has no help")
    func revealDeclinesWithNoHelp() {
        let h = harness()
        _ = frame(Button("Rebuild") {}, h)
        #expect(
            h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID) == false,
            "nothing to reveal")
    }

    /// The reveal belongs to the view it was granted for, so moving the focus
    /// drops it rather than carrying the tooltip along.
    @Test("Moving the focus drops a reveal")
    func revealDoesNotFollowFocus() {
        let h = harness()
        _ = frame(Button("Rebuild") {}.help("Rebuild the index"), h)
        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(h.tooltips.keyboardRevealed)

        h.tooltips.syncReveal(focusID: "somewhere-else")
        #expect(!h.tooltips.keyboardRevealed, "the reveal did not travel")
    }

    // MARK: - The hover half, and its delay

    @Test("A hover tooltip waits for the delay, then shows")
    func hoverWaitsForTheDelay() {
        let h = harness()
        let buffer = frame(Text("Coverage").help("Lines executed at least once"), h)
        #expect(!buffer.hitTestRegions.isEmpty, "help(_:) gave the Text a hit region")

        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        #expect(h.tooltips.hovered?.text == "Lines executed at least once", "the pointer is on it")

        let since = h.tooltips.hovered!.sinceNanos
        #expect(
            h.tooltips.hovered!.showAtNanos == since + Int64(0.6 * Double(Self.second)),
            "the deadline came from the modifier's own tooltipDelay")
        #expect(h.tooltips.resolved(nowNanos: since) == nil, "not yet — the pointer has not rested")
        #expect(
            h.tooltips.resolved(nowNanos: h.tooltips.hovered!.showAtNanos)?.source == .hover,
            "…and now it has")
    }

    /// Hover beats focus: the pointer is a deliberate act aimed at one thing.
    @Test("Hover wins over a revealed focus candidate")
    func hoverBeatsFocus() {
        let h = harness(delay: 0)
        let view = VStack {
            Button("Rebuild") {}.help("Rebuild the index")
            Text("Coverage").help("Lines executed at least once")
        }
        let buffer = frame(view, h)
        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(h.tooltips.resolved(nowNanos: 0)?.source == .focus)

        // Hover the Text on the second row.
        let region = buffer.hitTestRegions.first { $0.offsetY == 1 }
        #expect(region != nil, "the Text's region: \(buffer.hitTestRegions)")
        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 1, y: 1))
        // At the hover candidate's own deadline: the closure stamps the real
        // monotonic clock (the pointer arrived between frames), so a synthetic
        // "now" is not comparable with it. Reading the deadline back is the only
        // honest way to ask "is it due yet" from a test.
        let shown = h.tooltips.resolved(nowNanos: h.tooltips.hovered!.showAtNanos)
        #expect(shown?.source == .hover, "the pointer wins, got \(String(describing: shown))")
        #expect(shown?.text == "Lines executed at least once")
    }

    /// Re-entering the same view must not restart the delay — the dispatcher
    /// synthesises `.entered` on every boundary crossing, and a region
    /// re-registered at a new id this frame is still the same view.
    @Test("Re-entering the same view does not restart the delay")
    func reentryKeepsTheDeadline() {
        // Driven through the state directly: the rule under test is this type's
        // idempotence on re-entry, and the synthetic `.entered` that reaches it
        // is already covered above.
        let h = harness()
        h.tooltips.hovering("Lines executed at least once", handlerID: nil, nowNanos: 7)
        h.tooltips.hovering(
            "Lines executed at least once", handlerID: nil, nowNanos: 7 + Self.second)
        #expect(h.tooltips.hovered?.sinceNanos == 7, "the clock did not restart")

        // …but a DIFFERENT view under the pointer does restart it.
        h.tooltips.hovering("Something else", handlerID: nil, nowNanos: 7 + Self.second)
        #expect(h.tooltips.hovered?.sinceNanos == 7 + Self.second, "a new view, a new deadline")
    }
}

// MARK: - The help key

/// The `?` key, at layer 4 of `InputHandler`, and the hole it has.
@MainActor
@Suite("The help key")
struct HelpKeyTests {

    private struct Fixture {
        let handler: InputHandler
        let tooltips: TooltipState
        let focus: FocusManager
    }

    /// A minimal ``Cyclable``: `ThemeManager` preconditions on a non-empty list.
    private struct FakeCyclable: Cyclable {
        let id: String
        let name: String
    }

    private func makeFixture() -> Fixture {
        let appState = AppState()
        let statusBar = StatusBarState(appState: appState)
        let focus = FocusManager()
        let tooltips = TooltipState()
        let handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: KeyEventDispatcher(),
            focusManager: focus,
            paletteManager: ThemeManager(items: [FakeCyclable(id: "p", name: "p")]),
            appearanceManager: ThemeManager(items: [FakeCyclable(id: "a", name: "a")]),
            keyboardShortcuts: KeyboardShortcutRegistry(),
            dragAndDropSession: nil,
            tooltipState: tooltips,
            onQuit: {}, onSuspend: {})
        return Fixture(handler: handler, tooltips: tooltips, focus: focus)
    }

    /// A candidate, as the focused control would have published it during the
    /// frame.
    private func publishFocusCandidate(_ fixture: Fixture, text: String = "Rebuild the index") {
        fixture.tooltips.focusing(text, handlerID: nil, nowNanos: 0)
    }

    @Test("? reveals the focused view's tooltip, and again hides it")
    func questionMarkToggles() {
        let fixture = makeFixture()
        publishFocusCandidate(fixture)
        #expect(fixture.handler.handle(KeyEvent(key: .character("?"))), "the key was consumed")
        #expect(fixture.tooltips.resolved(nowNanos: 0)?.source == .focus)

        #expect(fixture.handler.handle(KeyEvent(key: .character("?"))))
        #expect(fixture.tooltips.resolved(nowNanos: 0) == nil, "toggled off")
    }

    /// With nothing to reveal the key must fall through rather than report that
    /// something happened — this is the last layer, so a `true` here is a key
    /// that silently does nothing AND wakes the run loop to redraw an identical
    /// frame.
    @Test("? with no help text is not consumed")
    func questionMarkFallsThrough() {
        let fixture = makeFixture()
        #expect(fixture.handler.handle(KeyEvent(key: .character("?"))) == false)
    }

    /// The key is reachable from inside a modal, unlike `t` and `a`. A tooltip
    /// explains the control that has the focus, and inside a modal that is the
    /// control the reader is looking at; it mutates no app state, so the reason
    /// the chrome shortcuts are grounded there does not transfer.
    @Test("? still works behind a modal")
    func questionMarkSurvivesAModal() {
        let fixture = makeFixture()
        publishFocusCandidate(fixture)
        fixture.focus.registerSection(id: "modal")
        fixture.focus.activateSection(id: "modal")
        fixture.focus.markSectionModal(id: "modal")
        #expect(fixture.focus.activeSectionIsModal, "the fixture really is modal")
        #expect(fixture.handler.handle(KeyEvent(key: .character("?"))), "and the key still lands")
    }

    /// **The known caveat, pinned rather than described.**
    ///
    /// `?` is punctuation and layer 0 gives a focused text control first refusal
    /// on every printable key, so inside one the question mark is typed and layer
    /// 4 is never reached. That is the correct precedence — a help key must not
    /// stop the reader typing a `?` — and it is a real hole in the feature: the
    /// controls whose help most needs explaining are the ones the key cannot
    /// reach. Their tooltips remain available by hovering.
    ///
    /// If this test ever fails, the precedence changed and `TextField` stopped
    /// accepting a question mark; that is a worse bug than the one this documents.
    @Test("A focused text field swallows ? — the documented caveat")
    func textFieldSwallowsTheHelpKey() {
        let fixture = makeFixture()
        publishFocusCandidate(fixture)
        var text = ""
        let field = TextFieldHandler(
            focusID: "field", text: Binding(get: { text }, set: { text = $0 }))
        fixture.focus.register(field)
        fixture.focus.focus(field)
        #expect(fixture.focus.hasTextInputFocus, "the fixture really has text-input focus")

        #expect(fixture.handler.handle(KeyEvent(key: .character("?"))), "layer 0 consumed it")
        #expect(text == "?", "…by typing it, got \(text)")
        #expect(
            fixture.tooltips.resolved(nowNanos: 0) == nil,
            "so no tooltip was revealed — the caveat")
    }

    /// The key is the app's to take back, which is the other half of claiming a
    /// bare character by default.
    @Test("An app can disable or move the help key")
    func helpKeyIsConfigurable() {
        let fixture = makeFixture()
        publishFocusCandidate(fixture)
        fixture.tooltips.helpKey = nil
        #expect(fixture.handler.handle(KeyEvent(key: .character("?"))) == false, "disabled")

        fixture.tooltips.helpKey = .f1
        #expect(fixture.handler.handle(KeyEvent(key: .f1)), "moved")
        #expect(fixture.tooltips.resolved(nowNanos: 0)?.source == .focus)
    }
}

// MARK: - The status-bar presentation

/// The tooltip drawn as a row of the status bar, above the shortcut items.
@MainActor
@Suite("Tooltip in the status bar")
struct TooltipStatusBarTests {

    private func bar(
        items: [any StatusBarItemProtocol], tooltipLines: [String],
        style: ChromeStyle = .bordered, width: Int = 40
    ) -> [String] {
        let view = StatusBar(
            userItems: items, style: style, tooltipLines: tooltipLines)
        let context = RenderContext(
            availableWidth: width, availableHeight: view.height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context).lines.map { $0.stripped }
    }

    @Test("The row is drawn above the items, inside the bar's own chrome")
    func rowSitsAboveTheItems() {
        let lines = bar(
            items: [StatusBarItem(shortcut: "q", label: "quit")],
            tooltipLines: ["Rebuild the index"])
        #expect(lines.count == 4, "top border, tooltip, items, bottom border: \(lines)")
        #expect(lines[1].contains("Rebuild the index"), "the tooltip row: \(lines)")
        #expect(lines[2].contains("quit"), "the items below it: \(lines)")
        // Inside the box, not above it — a bordered bar with a bare line over its
        // top border reads as a rendering fault.
        #expect(lines[0].contains("─") || lines[0].contains("━"), "top border first: \(lines)")
    }

    /// Two wrapped lines cost two rows, and `height` has to agree with the render
    /// or the content area is sized against a bar of a different height. This is
    /// the assertion that would fail if the two ever drifted.
    @Test("height counts the wrapped rows, and the render draws exactly that many")
    func heightMatchesTheRender() {
        for rows in [["one"], ["one", "two"], ["one", "two", "three"]] {
            let view = StatusBar(
                userItems: [StatusBarItem(shortcut: "q", label: "quit")], tooltipLines: rows)
            let lines = bar(
                items: [StatusBarItem(shortcut: "q", label: "quit")], tooltipLines: rows)
            #expect(
                view.height == lines.count,
                "\(rows.count) rows: height \(view.height) vs drawn \(lines.count)")
        }
    }

    /// A bar with no items at all still makes room for a tooltip, or the row is
    /// computed and then drawn nowhere.
    @Test("A tooltip shows on an otherwise empty bar")
    func tooltipWithoutItems() {
        let lines = bar(items: [], tooltipLines: ["Nothing else to say"])
        #expect(lines.count == 3, "top border, tooltip, bottom border: \(lines)")
        #expect(lines[1].contains("Nothing else to say"), "\(lines)")
    }

    @Test("Each bar style puts the row above its items")
    func everyStyleDrawsIt() {
        for style in ChromeStyle.allCases {
            let lines = bar(
                items: [StatusBarItem(shortcut: "q", label: "quit")],
                tooltipLines: ["Help me"], style: style)
            let tooltipRow = lines.firstIndex { $0.contains("Help me") }
            let itemRow = lines.firstIndex { $0.contains("quit") }
            #expect(tooltipRow != nil, "\(style): no tooltip row in \(lines)")
            #expect(itemRow != nil, "\(style): no item row in \(lines)")
            if let tooltipRow, let itemRow {
                #expect(tooltipRow < itemRow, "\(style): tooltip must precede items")
            }
        }
    }
}

// MARK: - The popover presentation

/// The tooltip drawn as a panel attached to the control.
@MainActor
@Suite("Tooltip as a popover")
struct TooltipPopoverTests {

    private func harness() -> (context: RenderContext, tooltips: TooltipState,
        focus: FocusManager, dispatcher: MouseEventDispatcher)
    {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = focus
        env.tooltipStyle = .popover
        env.tooltipDelay = 0
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui),
            tui.tooltipState, focus, tui.mouseEventDispatcher
        )
    }

    private func frame<V: View>(
        _ view: V, _ h: (context: RenderContext, tooltips: TooltipState,
            focus: FocusManager, dispatcher: MouseEventDispatcher)
    ) -> FrameBuffer {
        h.focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: h.context)
        h.focus.endRenderPass()
        h.dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// The candidate carries the style it was published under, so a popover
    /// tooltip attaches an overlay and does NOT ask the status bar for a row.
    @Test("A revealed popover tooltip attaches an overlay to its own control")
    func revealAttachesAnOverlay() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index from scratch")
        let first = frame(view, h)
        #expect(first.overlays.isEmpty, "nothing showing yet")
        #expect(h.tooltips.focused?.style == .popover, "the candidate carries the style")

        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        let shown = frame(view, h)
        #expect(shown.overlays.count == 1, "the panel is attached: \(shown.overlays.count)")
        let panel = shown.overlays[0].content.lines.map { $0.stripped }
        #expect(
            panel.contains { $0.contains("Rebuild the index") },
            "and carries the text: \(panel)")
        // Anchored beneath the control, and the anchor is the whole control so a
        // flipped placement clears it.
        #expect(shown.overlays[0].offsetY == first.height)
        #expect(shown.overlays[0].anchorHeight == first.height)
        #expect(shown.overlays[0].level == .popover)
    }

    /// It must steal nothing. A tooltip is not in the focus ring and claims no
    /// keys — the whole reason it is modelled on `TextFieldSuggestions.attach`
    /// rather than on `PopoverPresentationModifier`.
    @Test("A popover tooltip takes no focus and claims no keys")
    func popoverStealsNothing() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index")
        _ = frame(view, h)
        let focusedBefore = h.focus.currentFocusedID
        #expect(h.tooltips.toggleKeyboardReveal(focusID: focusedBefore))
        _ = frame(view, h)

        #expect(h.focus.currentFocusedID == focusedBefore, "the focus did not move")
        #expect(!h.focus.activeSectionIsModal, "no modal section was marked")
        #expect(
            h.context.environment.statusBar?.escapeLabelOverride == nil,
            "Escape still means what it meant")
    }

    /// A short tooltip is a short box: boxed at the widest wrapped line, not at
    /// the wrap width.
    @Test("The panel is only as wide as its text")
    func panelHugsItsText() {
        let h = harness()
        let narrow = TooltipPopover.panel(text: "Hi", maxWidth: 40, context: h.context)
        let wide = TooltipPopover.panel(
            text: String(repeating: "word ", count: 30), maxWidth: 40, context: h.context)
        #expect(narrow.width < wide.width, "\(narrow.width) vs \(wide.width)")
        #expect(narrow.width <= 8, "a two-letter tooltip is a small box, got \(narrow.width)")
        #expect(wide.lines.count > 3, "long text wraps to several rows: \(wide.lines.count)")
    }

    /// Wrapping is capped, so help text does not stretch a panel across a wide
    /// terminal.
    @Test("The panel does not stretch across a wide terminal")
    func panelIsCapped() {
        let h = harness()
        let panel = TooltipPopover.panel(
            text: String(repeating: "word ", count: 60), maxWidth: 300, context: h.context)
        #expect(
            panel.width <= TooltipPopover.maxTextWidth + 4,
            "capped at \(TooltipPopover.maxTextWidth) plus chrome, got \(panel.width)")
    }
}
