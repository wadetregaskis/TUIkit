//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusRegistrationMemoTests.swift
//
//  The focus ring is rebuilt every pass, so a memoized subtree that served its
//  buffer used to drop its controls out of Tab's order while they were still on
//  screen — which is why a focus registration declined the cache outright. It is
//  replayed now, at the point in the walk where the control would have rendered,
//  so the ring is the same whether a subtree rendered or was served.
//
//  Three shapes still decline, and they are the interesting half: a control that
//  HOLDS the focus, a control registering against the throwaway manager a dimmed
//  backdrop renders under, and a control an offered declaration named.
//
//  A `.defaultFocus` declaration is the same kind of per-frame presence and is
//  replayed the same way. Its failure was the reverse of a dropped registration:
//  the declaration is pruned when a pass does not renew it, and the prune takes
//  the store's applied-once flag with it, so a served frame RE-ARMED a default
//  the user had already moved away from.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A focus stop with no chrome and no hit-test region: it registers through
/// `FocusRegistration.register`, the single registrar every interactive control
/// goes through, and draws whether it holds the focus.
///
/// A real `Button` would do as well — its hit-test region no longer holds it
/// out of the cache (`MouseRegionMemoTests`) — but it would bring a mouse
/// registration and a motion request of its own to cases that are about the
/// focus ring. The mark here is the same width focused or not, so a served
/// buffer reads as the wrong mark rather than as a different layout.
private struct FocusProbe: View, Renderable {
    private enum StateIndex {
        static let focusID = 0
    }

    /// The id this stop declares, or `nil` to take the one a
    /// `.focused(_:equals:)` above offers — the route a real control's id takes
    /// when a `@FocusState` names it, since an explicit id outranks an offer.
    let declaredID: String?

    /// What the stop draws, so two of them are still tellable apart when
    /// neither declares an id.
    let label: String

    /// A stop that declares its own id, which is also what it draws.
    init(focusID: String) {
        declaredID = focusID
        label = focusID
    }

    /// A stop that takes the id offered to it, drawn as `label`.
    init(bound label: String) {
        declaredID = nil
        self.label = label
    }

    var body: Never { fatalError("FocusProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Through `persistFocusID` rather than straight to `register`, because
        // that is where an offered id is claimed — a declared one comes back
        // unchanged.
        let focusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: declaredID, defaultPrefix: "probe",
            propertyIndex: StateIndex.focusID)
        FocusRegistration.register(
            context: context,
            // Honours `.disabled(_:)` as a real control does, so a test can put
            // a stop in the ring that registers but cannot take the focus.
            handler: ActionHandler(
                focusID: focusID, action: {}, canBeFocused: context.environment.isEnabled),
            focusID: focusID)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: focusID)
        return FrameBuffer(text: (isFocused ? "*" : "-") + label)
    }
}

/// A memoizable card holding one focus stop. Equality is by title alone, so
/// nothing in the VALUE changes when the focus moves — which is exactly what
/// lets the memo hit, and what made the stale buffer possible.
private struct ProbeCard: View, @MainActor Equatable {
    let title: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        FocusProbe(focusID: title)
    }
}

/// Which of the bound stops a `@FocusState` names.
private enum ProbeField: Hashable {
    case first, second
}

/// The card's title, held apart from the view so one page instance — and so one
/// `@FocusState` store — can be rendered frame after frame while the test
/// changes what the memoized card is worth.
@MainActor
private final class CardTitle {
    var value = "card"
}

/// A memoizable card whose only per-frame write is a `.defaultFocus`
/// declaration. Equality is by title alone, so nothing in the VALUE moves when
/// the focus does — which is what lets the memo hit while the declaration is
/// live.
private struct DefaultFocusCard: View, @MainActor Equatable {
    let title: String
    let focus: FocusState<ProbeField?>.Binding
    let priority: DefaultFocusEvaluationPriority

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Text(title).defaultFocus(focus, .second, priority: priority)
    }
}

/// Two stops named by a `@FocusState`, and a memoized card declaring the second
/// of them as the default focus.
///
/// The `@FocusState` is deliberately reachable from the test: a test that
/// asserted on the ids the modifier generates would be asserting on a string
/// built from the identity path, and the question here is which value the app
/// sees focused.
private struct DefaultFocusPage: View {
    @FocusState var focus: ProbeField?
    let title: CardTitle
    var priority: DefaultFocusEvaluationPriority = .automatic

    var body: some View {
        VStack {
            FocusProbe(bound: "first").focused($focus, equals: .first)
            FocusProbe(bound: "second").focused($focus, equals: .second)
            DefaultFocusCard(title: title.value, focus: $focus, priority: priority).equatable()
        }
    }
}

/// Renders frames the way `RenderLoop` brackets them: one pass per frame, with
/// the focus ring emptied before every walk.
@MainActor
private final class LoopHarness {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()

    /// How many times the manager announced a focus change — i.e. how many
    /// repaints it asked the run loop for (`onFocusChange` → `setNeedsRender`).
    private(set) var repaintRequests = 0

    var cache: RenderCache { tuiContext.renderCache }

    init() {
        focusManager.onFocusChange = { [weak self] in self?.repaintRequests += 1 }
    }

    /// Renders one frame and returns what it drew, one line per row.
    ///
    /// No mouse dispatcher: a `Button`'s hit-test region is refused by
    /// `isStorable` regardless of anything here, so wiring one would measure
    /// that gate rather than this one.
    @discardableResult
    func frame(
        _ view: some View, configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.mouseEventDispatcher = nil
        environment.installVolatileReadTracker(VolatileReadTracker())
        configure(&environment)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, tuiContext: tuiContext)
        tuiContext.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        focusManager.beginSceneRender()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        cache.removeInactive()
        return buffer.lines.map(\.stripped)
    }

    /// Renders one frame and returns how many memo lookups missed — zero when
    /// every memoized subtree was served.
    @discardableResult
    func misses(_ view: some View) -> Int {
        let before = cache.stats.misses
        frame(view)
        return cache.stats.misses - before
    }
}

@MainActor
@Suite("Focus registration through the render memo")
struct FocusRegistrationMemoTests {

    /// One stop outside the memo and two memoized ones. The first registrant
    /// takes the focus, so both memoized stops render unfocused and can store.
    @MainActor
    private static func page() -> some View {
        VStack {
            FocusProbe(focusID: "outside")
            ProbeCard(title: "one").equatable()
            ProbeCard(title: "two").equatable()
        }
    }

    @Test("A memoized unfocused control keeps its place in the Tab ring on served frames")
    func ringOrderSurvivesReplay() {
        let harness = LoopHarness()
        var rings: [[String]] = []
        for number in 1...3 {
            let misses = harness.misses(Self.page())
            if number > 1 {
                #expect(misses == 0, "frame \(number) rendered the memoized stops again")
            }
            rings.append(harness.focusManager.focusableIDs)
        }
        // Registration order is ring order, and a replay happens where the
        // subtree would have rendered — so serving must not reorder it, drop a
        // stop, or register one twice.
        #expect(rings[0] == ["outside", "one", "two"])
        #expect(rings[1] == rings[0], "the first served frame changed the ring: \(rings[1])")
        #expect(rings[2] == rings[0], "the second served frame changed the ring: \(rings[2])")
        #expect(!harness.cache.isEmpty, "the unfocused stops were never stored")
    }

    @Test("A cached control draws focused on the frame after Tab reaches it")
    func tabRedrawsTheServedControl() {
        let harness = LoopHarness()
        harness.frame(Self.page())
        let served = harness.frame(Self.page())
        #expect(served.contains { $0.contains("-one") }, "the memoized stop drew unfocused: \(served)")

        // Tab off the stop outside the memo and onto the first memoized one. Its
        // cached buffer draws no focus and nothing in the key can see the move,
        // so the frame after this has to render it again.
        harness.focusManager.focusNext()
        let after = harness.frame(Self.page())
        #expect(
            after.contains { $0.contains("*one") },
            "Tab reached the stop and the memo served the frame from before it arrived: \(after)")
        #expect(
            after.contains { $0.contains("-two") },
            "the stop Tab did not reach redrew focused: \(after)")
    }

    @Test("A control that holds the focus is never stored")
    func focusedControlDeclines() {
        let harness = LoopHarness()
        // The memoized stop is the only one, so it is the first registrant of an
        // empty section and takes the focus as it registers.
        harness.frame(ProbeCard(title: "solo").equatable())
        #expect(harness.focusManager.currentFocusedID == "solo", "the arrangement focuses the stop")
        #expect(harness.cache.isEmpty, "a focused control's buffer was stored")
    }

    @Test("A page control stays focused-drawn after a sheet with no focusables is dismissed")
    func pageSurvivesAFocusablelessSheet() {
        let harness = LoopHarness()
        func page(sheet: Bool) -> some View {
            VStack {
                ProbeCard(title: "one").equatable()
                ProbeCard(title: "two").equatable()
            }
            .sheet(isPresented: .constant(sheet)) { Text("no focus stops here") }
        }
        func frame(sheet: Bool) -> [String] {
            harness.frame(page(sheet: sheet)) { environment in
                environment.terminalWidth = 40
                environment.overlayContentHeight = 20
            }
        }

        _ = frame(sheet: false)
        let focused = frame(sheet: false)
        #expect(focused.contains("*one"), "the arrangement focuses the first stop: \(focused)")

        // The page renders as a BACKDROP while the sheet is up: a picture, drawn
        // against a throwaway manager that focuses nothing. Stored, it would be
        // served once the sheet went — and a sheet with no focusables of its own
        // moves no focused id, so no invalidation would ever fire.
        _ = frame(sheet: true)
        _ = frame(sheet: true)

        let dismissed = frame(sheet: false)
        #expect(
            dismissed.contains("*one"),
            "the page was served the unfocused picture it drew behind the sheet: \(dismissed)")
    }

    @Test("Focus taken during a replay asks for a frame, and that frame redraws it")
    func autoFocusDuringReplayRepaints() {
        let harness = LoopHarness()
        // The stop outside the memo takes the focus as the first registrant, so
        // the memoized one renders unfocused and can be stored. Disabling it
        // later leaves it in the ring but unable to hold the focus.
        func view(aheadCanFocus: Bool) -> some View {
            VStack {
                FocusProbe(focusID: "outside").disabled(!aheadCanFocus)
                ProbeCard(title: "solo").equatable()
            }
        }

        harness.frame(view(aheadCanFocus: true))
        #expect(harness.focusManager.currentFocusedID == "outside", "the stop ahead takes the focus")
        #expect(!harness.cache.isEmpty, "the unfocused stop was never stored")

        // Nothing holds the focus now, and the only stop that can take it is the
        // memoized one — whose registration on this frame comes from the replay
        // rather than from a render. So it is auto-focused mid-walk, after its
        // cached, unfocused buffer has already been served.
        harness.focusManager.relinquishFocus()
        let requestsBefore = harness.repaintRequests
        let served = harness.frame(view(aheadCanFocus: false))
        #expect(
            served.contains { $0.contains("-solo") },
            "the served frame drew the stop focused: \(served)")
        #expect(harness.focusManager.currentFocusedID == "solo", "the replay did not focus the stop")
        #expect(
            harness.repaintRequests > requestsBefore,
            "focus arrived during a served frame and no repaint was asked for")

        // And the frame it asked for draws the focus, rather than serving the
        // buffer drawn before it arrived.
        let repainted = harness.frame(view(aheadCanFocus: false))
        #expect(
            repainted.contains { $0.contains("*solo") },
            "the repaint served the buffer drawn before the focus arrived: \(repainted)")
    }

    @Test("An inactive focus section is replayed, and an active one still declines")
    func sectionReplaysWhileInactive() {
        let harness = LoopHarness()
        // Two sections: the first registered becomes the active one, so the
        // second is inactive and can be stored.
        let view = VStack {
            FocusProbe(focusID: "outside").focusSection("first")
            ProbeCard(title: "one").equatable().focusSection("second")
        }

        for number in 1...3 {
            let misses = harness.misses(view)
            if number > 1 {
                #expect(misses == 0, "frame \(number) rendered the inactive section again")
            }
            // Sections are cleared before every walk, so an inactive section
            // that was not registered again simply would not be there.
            #expect(
                harness.focusManager.sectionIDs == ["first", "second"],
                "frame \(number) lost a section: \(harness.focusManager.sectionIDs)")
        }
    }

    @Test("A served frame does not re-arm a spent default focus")
    func defaultFocusStaysSpentAcrossServedFrames() {
        let harness = LoopHarness()
        let title = CardTitle()
        let page = DefaultFocusPage(title: title)

        // Frame 1 declares the default, and `endRenderPass` applies it: the
        // SECOND stop takes the initial focus, rather than the first one the
        // automatic first-focusable choice would have picked.
        harness.frame(page)
        #expect(
            page.focus == .second,
            "the default focus never landed: \(String(describing: page.focus))")

        // Frame 2 serves the card's buffer, so the declaration is not made
        // again by a render.
        #expect(harness.misses(page) == 0, "frame 2 rendered the card again")

        // The user moves the focus. An `.automatic` default is a one-shot: it
        // is spent, and this is where the user takes over for good.
        page.focus = .first
        #expect(page.focus == .first, "the move off the default did not take")

        // One more served frame, and then one the card is rendered on again —
        // a rename is any ordinary content change.
        #expect(harness.misses(page) == 0, "frame 3 rendered the card again")
        title.value = "card renamed"
        #expect(harness.misses(page) > 0, "frame 4 served the card that the rename changed")

        #expect(
            page.focus == .first,
            """
            the default focus was applied a second time and took the focus back \
            from the user: \(String(describing: page.focus))
            """)
    }

    @Test("A default focus rendered behind a sheet is not stored from that render")
    func backdropDefaultFocusIsNotStored() {
        let harness = LoopHarness()
        let title = CardTitle()
        let page = DefaultFocusPage(title: title)
        func frame(sheet: Bool) {
            harness.frame(
                page.sheet(isPresented: .constant(sheet)) { Text("no focus stops here") }
            ) { environment in
                environment.terminalWidth = 40
                environment.overlayContentHeight = 20
            }
        }

        frame(sheet: false)
        #expect(
            page.focus == .second,
            "the default focus never landed: \(String(describing: page.focus))")
        // Off the default, so that what the page focuses after the sheet says
        // WHICH mechanism put it there: the focus the manager remembers across
        // a modal would restore this stop, and only a re-applied default moves
        // to the other one.
        page.focus = .first

        // The page renders as a BACKDROP while the sheet is up: a picture drawn
        // against a throwaway manager, which is told the default and then
        // thrown away with it. The rename is what makes the card render THERE,
        // rather than go on serving the buffer it stored in front of the sheet.
        frame(sheet: true)
        title.value = "card renamed"
        frame(sheet: true)

        // The live manager heard nothing for those frames, so its declaration
        // was pruned and the default re-armed — a re-presented scope focuses
        // its default again. Stored, the backdrop's render would be served
        // here, declaring the default to nobody at all.
        frame(sheet: false)
        #expect(
            page.focus == .second,
            """
            the card was served the render it made behind the sheet, so the \
            re-presented scope never re-applied its default: \
            \(String(describing: page.focus))
            """)
    }

    @Test("A userInitiated default focus still re-asserts itself on served frames")
    func userInitiatedDefaultFocusReassertsOnServedFrames() {
        let harness = LoopHarness()
        let page = DefaultFocusPage(title: CardTitle(), priority: .userInitiated)

        harness.frame(page)
        #expect(
            page.focus == .second,
            "the default focus never landed: \(String(describing: page.focus))")

        // `.userInitiated` is the priority that overrides the user's moves on
        // every render — so a served frame has to take the focus back, which is
        // the opposite of what the automatic default must do, and the half a
        // replay that dropped the priority would get wrong.
        //
        // TWICE, because once does not tell the two priorities apart: a replay
        // that downgraded this declaration to `.automatic` would still take the
        // focus back the first time (the automatic shot is unspent, the first
        // render having been `.userInitiated` and never having spent one) and
        // only then stop.
        for round in 1...2 {
            page.focus = .first
            #expect(harness.misses(page) == 0, "round \(round) rendered the card again")
            #expect(
                page.focus == .second,
                """
                round \(round) let the move stand, so the declaration the served \
                frame replayed was not the userInitiated one: \
                \(String(describing: page.focus))
                """)
        }
    }
}
