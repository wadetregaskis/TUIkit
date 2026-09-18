//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewMemoTests.swift
//
//  A split view's registrations and the render memos. Its sidebar chords go
//  into a shortcut registry emptied before every walk, which a memo serving the
//  split would have to fill again; its column sections and its divider and edge
//  registrations go into a focus manager emptied the same way, which no memo
//  may serve.
//
//  A split's buffer carries hit-test regions, and those no longer hold it out
//  of the cache: the handlers behind them are replayed as the chords are. What
//  decides a split now is its focus manager — with one, its sections declare an
//  effect no memo can make again; without one, everything it registers is
//  replayable. These tests pin both, and the recorded chords themselves.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private final class VisibilityBox {
    var visibility = NavigationSplitViewVisibility.all
    var binding: Binding<NavigationSplitViewVisibility> {
        Binding(get: { self.visibility }, set: { self.visibility = $0 })
    }
}

private final class Counter {
    var value = 0
}

/// A two-column split on `box`.
@MainActor
private func split(_ box: VisibilityBox) -> some View {
    NavigationSplitView(columnVisibility: box.binding) {
        Text("side")
    } detail: {
        Text("detail")
    }
}

/// The same split at its concrete type, so it can be wrapped in a memo:
/// `NavigationSplitView` is `Equatable` where its columns are, and both `Text`
/// and the `EmptyView` the two-column init plants are.
@MainActor
private func memoizableSplit(_ box: VisibilityBox) -> NavigationSplitView<Text, EmptyView, Text> {
    NavigationSplitView(columnVisibility: box.binding) {
        Text("side")
    } detail: {
        Text("detail")
    }
}

/// The same split again, spelled so that what a ``NavigationSplitViewStyle``
/// decides can be read straight out of the row: the sidebar is one character
/// wide and the detail is a long run of `D`, so the column the `D`s begin at IS
/// the leading column's width plus its divider.
///
/// A one-character sidebar is what separates
/// ``SizeToFitFromLeftNavigationSplitViewStyle`` from
/// ``AutomaticNavigationSplitViewStyle``, whose proportions it shares exactly:
/// one hugs the content, the other takes the share.
@MainActor
private func measurableSplit(_ box: VisibilityBox) -> NavigationSplitView<Text, EmptyView, Text> {
    NavigationSplitView(columnVisibility: box.binding) {
        Text(verbatim: "S")
    } detail: {
        Text(verbatim: String(repeating: "D", count: 200))
    }
}

/// Where ``measurableSplit(_:)``'s detail column begins in the rendered row.
@MainActor
private func detailStart(_ buffer: FrameBuffer) -> Int {
    let row = buffer.lines.first?.stripped ?? ""
    return row.firstIndex(of: "D").map { row.distance(from: row.startIndex, to: $0) } ?? -1
}

/// Frames bracketed the way `RenderLoop` brackets them, with or without a focus
/// manager and a shortcut registry.
@MainActor
private final class SplitHarness {
    let tui = TUIContext()
    let focusManager: FocusManager?
    let hasShortcutRegistry: Bool

    init(focus: Bool, shortcutRegistry: Bool = true) {
        focusManager = focus ? FocusManager() : nil
        hasShortcutRegistry = shortcutRegistry
    }

    var context: RenderContext {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        if !hasShortcutRegistry { environment.keyboardShortcutRegistry = nil }
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: 60, availableHeight: 8, environment: environment, tuiContext: tui)
    }

    /// Empties the per-walk registries, as the render loop does before a walk.
    func beginWalk() {
        focusManager?.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.keyboardShortcuts.beginRenderPass()
        tui.preferences.beginRenderPass()
        focusManager?.beginSceneRender()
    }

    @discardableResult
    func frame(
        _ view: some View, tracker: VolatileReadTracker = VolatileReadTracker()
    ) -> FrameBuffer {
        var context = self.context
        context.environment.installVolatileReadTracker(tracker)
        beginWalk()
        let buffer = renderToBuffer(view, context: context)
        focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer
    }

    /// Renders one frame and returns how many memo lookups missed — zero when
    /// every memoized subtree was served.
    func misses(_ view: some View) -> Int {
        let before = tui.renderCache.stats.misses
        frame(view)
        return tui.renderCache.stats.misses - before
    }

    func press(_ event: KeyEvent) -> Bool {
        tui.keyboardShortcuts.trigger(for: event)
    }
}

private let controlS = KeyEvent(key: .character("s"), ctrl: true)
private let optionControlS = KeyEvent(key: .character("s"), ctrl: true, alt: true)

@MainActor
@Suite("NavigationSplitView registrations and the render memos")
struct NavigationSplitViewMemoTests {
    @Test(
        "A split view with a focus manager declares its section registrations, with or without its chords",
        arguments: ["enabled", "disabled", "no shortcut registry"])
    func declaresItsSections(shape: String) {
        // The chords used to be the only declaration a split made, and they
        // are skipped under `.disabled()` or with no registry, and replayable
        // now. Its sections are not replayable, so they declare for themselves.
        let harness = SplitHarness(focus: true, shortcutRegistry: shape != "no shortcut registry")
        let box = VisibilityBox()
        let view = shape == "disabled" ? AnyView(split(box).disabled(true)) : AnyView(split(box))

        let tracker = VolatileReadTracker()
        harness.frame(view, tracker: tracker)
        #expect(tracker.sideEffects >= 1, "\(shape): the section registrations were not declared")
    }

    @Test("A split's chords and its mouse handlers are replayable, and without a focus manager nothing in it is not")
    func chordsCountAsReplayable() {
        let harness = SplitHarness(focus: false)
        let tracker = VolatileReadTracker()
        harness.frame(split(VisibilityBox()), tracker: tracker)
        // One for the chords and one per column handler. Counted exactly on
        // purpose: an unreplayable registration hidden among them is what would
        // quietly stop a split being served.
        #expect(tracker.replayableEffects == 3)
        #expect(tracker.sideEffects == 0)
    }

    @Test("A split's recorded chords, made again in a later walk, toggle it with the same precedence")
    func recordedChordsReplayWithTheSamePrecedence() {
        let harness = SplitHarness(focus: false)
        let box = VisibilityBox()
        let journal = harness.tui.renderCache.effectJournal

        // What a memo around the split would store: the entries its render
        // appends while the memo records.
        let start = journal.beginRecording()
        harness.frame(split(box))
        let entries = Array(journal.entries(since: start))
        journal.endRecording()
        // The chords first — registered before any column renders — then a
        // handler per column.
        #expect(entries.map(\.kind.name) == ["sidebarChords", "mouseHandler", "mouseHandler"])

        // A later walk, whose registry is empty, served from those entries.
        harness.beginWalk()
        let context = harness.context
        for entry in entries { entry.apply(context) }
        #expect(harness.press(controlS), "the replayed ⌃S did nothing")
        #expect(box.visibility == .detailOnly)
        box.visibility = .all

        // A focus-holding default registered earlier in the walk still beats
        // the replayed one, and an app shortcut after it beats both, exactly as
        // when the split renders.
        harness.beginWalk()
        let held = Counter()
        let saves = Counter()
        let chord = KeyboardShortcut("s", modifiers: [.command, .control]).resolved(commandKey: .control)!
        harness.tui.keyboardShortcuts.registerDefault(chord, holdsFocus: true) { held.value += 1 }
        for entry in entries { entry.apply(context) }
        #expect(harness.press(controlS))
        #expect(held.value == 1 && box.visibility == .all, "the replayed default beat a focus-holding one")
        harness.tui.keyboardShortcuts.register(chord) { saves.value += 1 }
        #expect(harness.press(controlS))
        #expect(saves.value == 1 && held.value == 1, "an app shortcut did not beat the defaults")
        #expect(harness.press(optionControlS), "the replayed ⌥⌃S did nothing")
        #expect(box.visibility == .detailOnly)
    }

    @Test("A split served from the cache still toggles on the chords its own replay registered")
    func servedSplitStillTogglesOnItsChords() {
        // What the recorded-chords test above could only do by hand, now that a
        // split's hit-test regions no longer hold its buffer out of the cache:
        // the same thing through a real memo, on a frame the cache answered.
        let harness = SplitHarness(focus: false)
        let box = VisibilityBox()
        let view = memoizableSplit(box).equatable()

        harness.frame(view)
        #expect(!harness.tui.renderCache.isEmpty, "the split's buffer was never stored")

        // Nothing under the memo renders on this frame, and `beginWalk` emptied
        // the shortcut registry as the render loop does — so only the replay
        // can have put the chords back.
        #expect(harness.misses(view) == 0, "the split rendered again")
        #expect(harness.press(controlS), "the served frame left ⌃S unregistered")
        #expect(box.visibility == .detailOnly)
        // The visibility the chord just changed lives in a plain box here, so
        // nothing invalidates the entry; in an app it is `@State`, whose write
        // clears the split's cached picture before the next frame can serve it.
    }

    @Test("No built-in split view style stops the split below it being served")
    func builtInStyleKeepsTheSplitCaching() {
        // `.navigationSplitViewStyle(_:)` injects an `any NavigationSplitViewStyle`
        // into the environment, and the render cache refuses to store below a
        // value it cannot compare — see the note under
        // ``NavigationSplitViewStyle``. What decides is the DYNAMIC type's
        // `Equatable` conformance, so each of the four built-ins is asked on its
        // own harness: conforming only one would leave the other three exactly
        // as they were, and asking them together would not say so.
        //
        // Nothing here is a stand-in. What the refusal was costing is a whole
        // split view, and that is what is memoized.
        func storesAndServes<S: NavigationSplitViewStyle>(_ style: S, _ spelling: String) {
            let harness = SplitHarness(focus: false)
            let view = memoizableSplit(VisibilityBox()).equatable().navigationSplitViewStyle(style)

            harness.frame(view)
            #expect(
                !harness.tui.renderCache.isEmpty,
                "a memo under .navigationSplitViewStyle(\(spelling)) must store")
            #expect(
                harness.misses(view) == 0,
                "and must be served next frame: the split under \(spelling) rendered again")
        }

        storesAndServes(.automatic, ".automatic")
        storesAndServes(.balanced, ".balanced")
        storesAndServes(.prominentDetail, ".prominentDetail")
        storesAndServes(.sizeToFitFromLeft, ".sizeToFitFromLeft")
    }

    /// The safety half, and the one pair in this protocol a careless comparison
    /// really would get wrong.
    ///
    /// None of the four styles holds anything, so there is no stored value to
    /// change under a served buffer. What varies is the TYPE — and
    /// ``AutomaticNavigationSplitViewStyle`` and
    /// ``SizeToFitFromLeftNavigationSplitViewStyle`` carry byte-identical
    /// proportions (0.33, and (0.25, 0.25, 0.50)), separated only by
    /// `sizesToFit`, which switches the sizing algorithm outright. An equality
    /// written structurally across the protocol — comparing the proportions, or
    /// a shared `==` on an extension — would call those two equal and serve a
    /// proportionally-sized split where a content-hugging one was asked for.
    /// Per-type equality cannot, because the comparison downcasts to `Self`
    /// first. So this swaps exactly that pair, not a pair that differs in its
    /// numbers.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them.
    @Test("A split laid out by proportion is not served where size-to-fit was asked for")
    func swappingToTheStyleWithTheSameProportionsRedrawsTheSplit() {
        let harness = SplitHarness(focus: false)
        let box = VisibilityBox()

        // Both modifiers sit ABOVE the memo, which is the point: they are what
        // the cache has to compare. `.navigationSplitViewResizable(false)` for
        // the reason the sizing suite gives — no stored-width override, so what
        // is drawn is the style's own default.
        func split(_ style: some NavigationSplitViewStyle) -> some View {
            measurableSplit(box).equatable()
                .navigationSplitViewResizable(false)
                .navigationSplitViewStyle(style)
        }

        let proportional = detailStart(harness.frame(split(.automatic)))
        #expect(proportional > 8, "the automatic style gives the sidebar its share: \(proportional)")
        #expect(!harness.tui.renderCache.isEmpty, "the split's buffer was never stored")

        // The premise, without which the swap below would pass for a split that
        // is never served at all: the SAME style twice is a hit, so there really
        // is a stored buffer for the swap to have to invalidate.
        #expect(harness.misses(split(.automatic)) == 0, "an unchanged style did not serve the memo")

        let fitted = detailStart(harness.frame(split(.sizeToFitFromLeft)))
        #expect(
            fitted < proportional,
            "a proportional split was served under .sizeToFitFromLeft: detail at \(fitted)")
    }

    @Test("A split with a focus manager is never served, because its sections cannot be replayed")
    func splitWithAFocusManagerIsNeverServed() {
        let harness = SplitHarness(focus: true)
        let view = memoizableSplit(VisibilityBox()).equatable()

        harness.frame(view)
        harness.frame(view)
        // The declaration is the only thing standing between a split and the
        // cache now, and this is what it buys: the focus manager is emptied
        // before every walk and a served split would refill it with nothing, so
        // its columns' sections — and the dividers and edge that register in
        // them — have to be rendered rather than served.
        #expect(
            harness.tui.renderCache.isEmpty,
            "a split whose sections no replay can make again was stored")
        #expect(
            harness.focusManager?.sectionIDs.isEmpty == false,
            "the second frame registered no sections: \(harness.focusManager?.sectionIDs ?? [])")
    }
}
