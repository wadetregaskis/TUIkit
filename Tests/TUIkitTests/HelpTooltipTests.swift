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
        trigger: TooltipTrigger = .automatic, delay: Double = 0.6, now: Int64 = 0
    ) -> (context: RenderContext, tooltips: TooltipState, focus: FocusManager,
        dispatcher: MouseEventDispatcher)
    {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = focus
        env.tooltipTrigger = trigger
        env.tooltipDelay = delay
        env.frameNowNanos = now
        // Motion reporting is unioned in by `AppRunner` each frame from the
        // modifier's `requestFeature(.motion)`; with no run loop here the
        // dispatcher would refuse every `.moved` event, so grant it directly.
        tui.mouseEventDispatcher.setActiveSupport(.full)
        // The pointer arrives on the dispatcher's clock, stopped here at the
        // frame's instant, as `HeadlessApp` stops it.
        tui.mouseEventDispatcher.nowNanos = { UInt64(bitPattern: now) }
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

    /// A silenced subtree publishes nothing at all — checked on the FOCUS half
    /// as well as the hover half, because the two are gated in different files
    /// and only one of them is obvious.
    @Test("tooltips(.never) publishes no candidate")
    func neverPublishesNothing() {
        let h = harness(trigger: .never)
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

    /// The delay counts from the pointer's arrival on the dispatcher's clock —
    /// the one a click's multi-click window is read on — which a test or a
    /// headless app can stop. Read off the machine's clock instead, a harness
    /// stepping its own frames could not say when the tooltip was due, and two
    /// apps fed one script put it in different frames.
    @Test("A hover tooltip waits for the delay, counted from the pointer's arrival, then shows")
    func hoverWaitsForTheDelay() {
        let h = harness(now: 7 * Self.second)
        let buffer = frame(Text("Coverage").help("Lines executed at least once"), h)
        #expect(!buffer.hitTestRegions.isEmpty, "help(_:) gave the Text a hit region")

        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        #expect(h.tooltips.hovered?.text == "Lines executed at least once", "the pointer is on it")
        #expect(
            h.tooltips.hovered?.sinceNanos == 7 * Self.second,
            "the arrival was not read on the dispatcher's clock: \(String(describing: h.tooltips.hovered?.sinceNanos))")
        let due = 7 * Self.second + 600_000_000
        #expect(
            h.tooltips.hovered?.showAtNanos == due, "the deadline came from the modifier's own tooltipDelay")
        #expect(h.tooltips.resolved(nowNanos: due - 1) == nil, "not yet — the pointer has not rested")
        #expect(h.tooltips.resolved(nowNanos: due)?.source == .hover, "…and now it has")
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
        // With no delay, due the instant the pointer arrived: the frame's.
        let shown = h.tooltips.resolved(nowNanos: 0)
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

// MARK: - Auto-reveal on focus

/// `tooltips(.onFocus)` — the "beginner mode": a focus candidate shows without
/// the help key. The delay is the whole of the difficulty. The focus slot is
/// cleared and refilled every frame, so a deadline computed at publication would
/// sit permanently in the future and nothing would ever show; and a deadline
/// that survived across a CHANGE of focus would make the second control inherit
/// the first one's wait.
@MainActor
@Suite("Tooltips revealed by focus")
struct TooltipOnFocusTests {

    private static let second: Int64 = 1_000_000_000

    private func harness(trigger: TooltipTrigger = .onFocus, delay: Double = 0.6)
        -> (tui: TUIContext, focus: FocusManager, env: EnvironmentValues)
    {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = focus
        env.tooltipTrigger = trigger
        env.tooltipDelay = delay
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (tui, focus, env)
    }

    /// One frame at `now`, driving the same per-frame clears the run loop does.
    @discardableResult
    private func frame<V: View>(
        _ view: V, _ h: (tui: TUIContext, focus: FocusManager, env: EnvironmentValues),
        at now: Int64
    ) -> FrameBuffer {
        var env = h.env
        env.frameNowNanos = now
        h.tui.tooltipState.beginRenderPass()
        h.tui.tooltipState.syncReveal(focusID: h.focus.currentFocusedID)
        h.focus.beginRenderPass()
        let buffer = renderToBuffer(
            view,
            context: RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: h.tui))
        h.focus.endRenderPass()
        return buffer
    }

    @Test("Under .automatic a focused control shows nothing until the key")
    func automaticStaysQuiet() {
        let h = harness(trigger: .automatic)
        let view = Button("Rebuild") {}.help("Rebuild the index")
        frame(view, h, at: 0)
        frame(view, h, at: 5 * Self.second)
        #expect(h.tui.tooltipState.focused != nil, "the candidate is published")
        #expect(
            h.tui.tooltipState.resolved(nowNanos: 5 * Self.second) == nil,
            "…and stays unrevealed without the help key")
    }

    /// The headline behaviour: no key press, and after the delay it shows.
    @Test("Under .onFocus a focused control reveals itself once the delay passes")
    func revealsAfterTheDelay() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index")
        frame(view, h, at: 0)
        #expect(
            h.tui.tooltipState.resolved(nowNanos: 0) == nil,
            "not immediately — a focus that just arrived has not been rested on")
        // A later frame, still the same control focused.
        frame(view, h, at: Self.second)
        let shown = h.tui.tooltipState.resolved(nowNanos: Self.second)
        #expect(shown?.text == "Rebuild the index", "got \(String(describing: shown?.text))")
        #expect(shown?.source == .focus, "and it is the focus slot, not a hover")
    }

    /// **The bug this design is most likely to have.** The deadline has to
    /// survive `beginRenderPass`'s clear. If it does not, every frame republishes
    /// a deadline `tooltipDelay` into ITS OWN future and the tooltip never
    /// arrives however long the reader waits.
    @Test("The deadline survives the per-frame republication")
    func deadlineSurvivesRepublication() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index")
        // Many frames — a page that is simply redrawing while nothing moves.
        var last: Int64 = 0
        for step in 0..<50 {
            last = Int64(step) * (Self.second / 10)
            frame(view, h, at: last)
        }
        let deadline = h.tui.tooltipState.focused?.showAtNanos
        #expect(
            deadline == Int64(0.6 * Double(Self.second)),
            "still the deadline set on the FIRST frame, got \(String(describing: deadline))")
        #expect(h.tui.tooltipState.resolved(nowNanos: last) != nil, "so it is showing by now")
    }

    /// …and moving the focus does NOT inherit the old deadline, or the second
    /// control would show its help the instant it was reached.
    @Test("Taking the focus starts a fresh delay")
    func focusChangeRestartsTheDelay() {
        let h = harness()
        let view = VStack {
            Button("First") {}.help("the first one")
            Button("Second") {}.help("the second one")
        }
        // Let the first one's delay expire.
        frame(view, h, at: 0)
        frame(view, h, at: Self.second)
        #expect(
            h.tui.tooltipState.resolved(nowNanos: Self.second)?.text == "the first one",
            "the first control's help is up")
        // Tab to the second. Its deadline is measured from HERE.
        h.focus.focusNext()
        frame(view, h, at: Self.second)
        #expect(
            h.tui.tooltipState.resolved(nowNanos: Self.second) == nil,
            "the second control does not inherit the first one's expired wait")
        frame(view, h, at: 2 * Self.second)
        #expect(
            h.tui.tooltipState.resolved(nowNanos: 2 * Self.second)?.text == "the second one",
            "…and shows its own help a delay later")
    }

    /// The help key is not subject to the delay: a press has already waited.
    @Test("The help key ignores the delay")
    func theKeyIgnoresTheDelay() {
        let h = harness(trigger: .automatic, delay: 30)
        let view = Button("Rebuild") {}.help("Rebuild the index")
        frame(view, h, at: 0)
        #expect(
            h.tui.tooltipState.toggleKeyboardReveal(focusID: h.focus.currentFocusedID),
            "there was something to reveal")
        #expect(
            h.tui.tooltipState.resolved(nowNanos: 0)?.text == "Rebuild the index",
            "shown at once, 30s delay notwithstanding")
    }

    /// The demand-driven run loop renders nothing for a focus that is merely
    /// still held, so the reveal needs a wake scheduled against its deadline the
    /// way a hover does. Without this the tooltip appears only if something else
    /// happens to redraw.
    @Test("A pending focus reveal declares a wake deadline")
    func pendingFocusRevealWakes() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index")
        frame(view, h, at: 0)
        #expect(
            h.tui.tooltipState.pendingDeadlineNanos(nowNanos: 0)
                == Int64(0.6 * Double(Self.second)),
            "got \(String(describing: h.tui.tooltipState.pendingDeadlineNanos(nowNanos: 0)))")
        // Once it is showing there is nothing left to wake for.
        frame(view, h, at: Self.second)
        #expect(
            h.tui.tooltipState.pendingDeadlineNanos(nowNanos: Self.second) == nil,
            "no wake once the deadline has passed")
    }

    /// …and under `.automatic` there is nothing to wake for at all, or every
    /// focused control with help would keep the loop turning.
    @Test("Under .automatic a focus candidate declares no wake")
    func automaticDeclaresNoWake() {
        let h = harness(trigger: .automatic)
        let view = Button("Rebuild") {}.help("Rebuild the index")
        frame(view, h, at: 0)
        #expect(h.tui.tooltipState.focused != nil, "the candidate exists")
        #expect(
            h.tui.tooltipState.pendingDeadlineNanos(nowNanos: 0) == nil,
            "but nothing is waiting to show")
    }
}

// MARK: - Every tooltip at once

/// `tooltips(.always)` — the first-launch tour: every `help(_:)` in the subtree
/// draws its own panel, unprompted, for as long as the subtree is on screen.
///
/// This mode does not go through the candidate slots at all, which is what makes
/// it two lines rather than a redesign: there is no "which tooltip is showing" to
/// resolve, so `HelpModifier` simply attaches its own panel.
@MainActor
@Suite("Tooltips shown all at once")
struct TooltipAlwaysTests {

    private func harness(trigger: TooltipTrigger, style: TooltipStyle = .popover)
        -> (tui: TUIContext, context: RenderContext)
    {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = FocusManager()
        env.tooltipTrigger = trigger
        env.tooltipStyle = style
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 12, environment: env, tuiContext: tui)
        )
    }

    private func panels(_ buffer: FrameBuffer) -> [OverlayLayer] {
        buffer.overlays.filter { $0.level == .popover }
    }

    @Test("Every help'd view draws its own panel, with nothing touched")
    func everyPanelDraws() {
        let h = harness(trigger: .always)
        let view = VStack {
            Button("One") {}.help("the first thing")
            Button("Two") {}.help("the second thing")
            Button("Three") {}.help("the third thing")
        }
        let buffer = renderToBuffer(view, context: h.context)
        #expect(panels(buffer).count == 3, "one per help: \(panels(buffer).count)")
    }

    /// …and `.automatic` draws none of them without a hover or the help key, which
    /// is what makes the count above mean something.
    @Test("Under .automatic nothing draws unprompted")
    func automaticDrawsNothing() {
        let h = harness(trigger: .automatic)
        let view = VStack {
            Button("One") {}.help("the first thing")
            Button("Two") {}.help("the second thing")
        }
        #expect(panels(renderToBuffer(view, context: h.context)).isEmpty, "nothing unprompted")
    }

    /// **`.always` forces the popover presentation**, because the status bar has
    /// one row and this mode has many tooltips.
    ///
    /// The override travels on the CANDIDATE rather than being applied by the run
    /// loop, because `tooltipStyle` is a subtree setting and the run loop has only
    /// the root environment — the same reason `Candidate.style` exists. Without it
    /// the bar would show the hovered tooltip as a second, redundant presentation
    /// of a panel already on screen.
    @Test("The status-bar style is overridden rather than doubled up")
    func statusBarStyleIsOverridden() {
        let h = harness(trigger: .always, style: .statusBar)
        let view = Button("One") {}.help("the first thing")
        let buffer = renderToBuffer(view, context: h.context)
        #expect(panels(buffer).count == 1, "the panel drew")
        #expect(
            h.tui.tooltipState.focused?.style == .popover,
            "candidate says popover so the bar declines: \(h.tui.tooltipState.focused?.style as Any)")
    }

    /// `.never` still wins over `.always`, since it is the same axis: nothing is
    /// published and nothing draws.
    @Test("tooltips(.never) beats everything")
    func neverStillWins() {
        let h = harness(trigger: .never)
        let view = Button("One") {}.help("the first thing")
        let buffer = renderToBuffer(view, context: h.context)
        #expect(panels(buffer).isEmpty, "no panel")
        #expect(h.tui.tooltipState.focused == nil, "and no candidate")
    }
}
