//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewMemoTests.swift
//
//  A split view's registrations and the render memos. Its sidebar chords go
//  into a shortcut registry emptied before every walk, which a memo serving the
//  split would have to fill again; its column sections and its divider and edge
//  registrations go into a focus manager emptied the same way, which no memo
//  may serve.
//
//  No split view can be served today: its buffer carries hit-test regions (3
//  for an enabled two-column split, 2 for a disabled one, measured with the
//  environment's mouse dispatcher set to nil), and a buffer with regions is
//  never stored. So these tests pin the declarations and the recorded chords
//  themselves, rather than a served frame. The day the hit-region gate goes,
//  they are what keeps a served split correct.
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

    func frame(_ view: some View, tracker: VolatileReadTracker = VolatileReadTracker()) {
        var context = self.context
        context.environment.installVolatileReadTracker(tracker)
        beginWalk()
        _ = renderToBuffer(view, context: context)
        focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
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

    @Test("A split's sidebar chords count as a replayable effect, and nothing else in it declares without a focus manager")
    func chordsCountAsReplayable() {
        let harness = SplitHarness(focus: false)
        let tracker = VolatileReadTracker()
        harness.frame(split(VisibilityBox()), tracker: tracker)
        #expect(tracker.replayableEffects == 1)
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
        #expect(entries.map(\.kind.name) == ["sidebarChords"])

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
}
