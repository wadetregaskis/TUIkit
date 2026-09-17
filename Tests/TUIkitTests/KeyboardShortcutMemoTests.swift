//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardShortcutMemoTests.swift
//
//  The shortcut registry is emptied before every walk, so a `Button` with a
//  `.keyboardShortcut` that was served from the render cache left its shortcut
//  unregistered — which is why the registration declared a render side effect
//  and no memo holding such a button could store at all. It is replayed now,
//  like every other per-frame registration, but ONLY when the modifier that
//  carries it is planted inside the same memo: planted above, the carrier is
//  claimable by anything that renders under it on a served frame, and the key
//  cannot see it change.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// What fired, in order.
private final class FireLog: @unchecked Sendable {
    var fired: [String] = []
}

/// A memoizable card holding one shortcut-bearing button. Equality is by title,
/// so nothing in the VALUE changes frame to frame and the memo always wants to
/// hit.
private struct ShortcutCard: View, @MainActor Equatable {
    let title: String
    let log: FireLog

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title && lhs.log === rhs.log }

    var body: some View {
        Button(title) { [title, log] in log.fired.append(title) }
            .keyboardShortcut("s", modifiers: [])
    }
}

/// The same button with no shortcut of its own, for the arrangement that plants
/// the carrier ABOVE the memo boundary.
private struct PlainCard: View, @MainActor Equatable {
    let title: String
    let log: FireLog

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title && lhs.log === rhs.log }

    var body: some View {
        Button(title) { [title, log] in log.fired.append(title) }
    }
}

/// Renders frames the way `RenderLoop` brackets them, with the shortcut registry
/// and the focus ring emptied before every walk.
@MainActor
private final class LoopHarness {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()

    var cache: RenderCache { tuiContext.renderCache }
    var shortcuts: KeyboardShortcutRegistry { tuiContext.keyboardShortcuts }

    /// Renders one frame and returns how many memo lookups missed — zero when
    /// every memoized subtree was served.
    ///
    /// No mouse dispatcher: wherever one is wired a `Button` also registers a
    /// hit-test handler and asks for motion, and both are declarations of their
    /// own — so leaving it out keeps every expectation below about what the
    /// shortcut declared. The region itself no longer decides anything; see
    /// `MouseRegionMemoTests`.
    ///
    /// Which is why the context is built from the environment rather than from
    /// the `TUIContext`: `RenderContext.init(…tuiContext:)` injects the
    /// services itself, `mouseEventDispatcher` among them, so it puts back the
    /// dispatcher removed on the line above. `applyRuntimeServices` has already
    /// wired everything a `Button` reads, the shortcut registry included.
    @discardableResult
    func frame(_ view: some View) -> Int {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.mouseEventDispatcher = nil
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, identity: ViewIdentity(path: "Root"))
        let missesBefore = cache.stats.misses
        tuiContext.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        focusManager.beginSceneRender()
        shortcuts.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        cache.removeInactive()
        return cache.stats.misses - missesBefore
    }

    /// Fires a bare key equivalent the way `InputHandler` does once the focused
    /// control has let the key fall through.
    func press(_ character: Character) -> Bool {
        shortcuts.trigger(for: KeyEvent(character: character))
    }
}

@MainActor
@Suite("Keyboard shortcuts through the render memo")
struct KeyboardShortcutMemoTests {

    /// The stop ahead takes the focus as the first registrant, so the button in
    /// the memo renders unfocused — a focused control's buffer draws the focus
    /// ring and is never stored, which would hide what this suite asks about.
    @MainActor
    private static func page(_ log: FireLog) -> some View {
        VStack {
            Text("ahead").focusable()
            ShortcutCard(title: "one", log: log).equatable()
        }
    }

    @Test("A memoized button's shortcut still fires on the frames the cache serves")
    func shortcutSurvivesServedFrames() {
        let harness = LoopHarness()
        let log = FireLog()
        for number in 1...3 {
            let misses = harness.frame(Self.page(log))
            if number > 1 {
                #expect(misses == 0, "frame \(number) rendered the memoized button again")
            }
            // The registry is emptied before every walk, so a shortcut that
            // fires here was registered on THIS frame — by the render on frame
            // one and by the replay afterwards.
            #expect(harness.press("s"), "frame \(number) left the shortcut unregistered")
            #expect(
                log.fired.count == number,
                "frame \(number) ran the action \(log.fired.count) times in total")
        }
        #expect(!harness.cache.isEmpty, "the button carrying a shortcut was never stored")
    }

    @Test("A shortcut planted ABOVE the memo keeps declining, and still fires")
    func shortcutAboveTheBoundaryDeclines() {
        let harness = LoopHarness()
        let log = FireLog()
        // The carrier is claimable by the first control that renders under it.
        // On a served frame nothing renders under it, so it would sit unclaimed
        // while the replay registered anyway — and a change to it is invisible
        // to a key made of the view value below it.
        let view = VStack {
            Text("ahead").focusable()
            PlainCard(title: "one", log: log).equatable()
                .keyboardShortcut("s", modifiers: [])
        }
        for number in 1...3 {
            harness.frame(view)
            #expect(harness.press("s"), "frame \(number) left the shortcut unregistered")
            #expect(log.fired.count == number, "frame \(number) ran the action twice")
            #expect(
                harness.cache.isEmpty,
                "frame \(number) stored a subtree whose shortcut was planted above it")
        }
    }
}
