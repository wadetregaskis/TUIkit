//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InlineMenuMemoTests.swift
//
//  An inline menu's paging keys and the render memos. The key dispatcher is
//  emptied before every walk, so a memo serving a menu would have to register
//  them again, and the focus manager they page has to be the one in force where
//  the menu is served.
//
//  A styled inline menu can be served: the built-in styles are `Equatable`, so
//  the `any MenuStyle` `.menuStyle(_:)` injects is a value the cache can tell
//  apart from the one it saw last frame. Until it was, no memo holding a menu
//  could store at all, and the first two tests here could only pin what a memo
//  WOULD record and replay. The third pins a served frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Where a probe last rendered.
private final class PathSink {
    var path: String?
}

/// How many times a handler rendered after a menu was asked for a key.
private final class KeyCounter: @unchecked Sendable {
    var count = 0
}

/// Records the identity path it renders at, which lies under its menu's.
private struct PathProbe: View, Renderable {
    let sink: PathSink

    var body: Never { fatalError("PathProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring { sink.path = context.identity.path }
        return FrameBuffer(text: "probe")
    }
}

/// An inline menu with no controls in it.
///
/// A view rather than a function so it can carry an `.equatable()` boundary:
/// two frames of the same sink compare equal, so the second is served.
private struct InlineProbeMenu: View, @MainActor Equatable {
    let sink: PathSink

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.sink === rhs.sink }

    var body: some View {
        Menu("Menu") {
            Text("one")
            PathProbe(sink: sink)
        }
        .menuStyle(.inline)
    }
}

@MainActor
@Suite("Inline menu paging keys and the render memos")
struct InlineMenuMemoTests {
    private let tui = TUIContext()

    private func context(_ manager: FocusManager, tracker: VolatileReadTracker = VolatileReadTracker())
        -> RenderContext
    {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.focusManager = manager
        environment.installVolatileReadTracker(tracker)
        return RenderContext(
            availableWidth: 30, availableHeight: 12, environment: environment, tuiContext: tui)
    }

    /// One whole frame, bracketed as `RenderLoop` brackets one: the per-walk
    /// registries emptied, the view walked, then the pass closed so an entry
    /// nothing visited is collected.
    private func frame(_ manager: FocusManager, _ view: some View) {
        beginWalk(manager)
        _ = renderToBuffer(view, context: context(manager))
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
    }

    /// Empties the per-walk registries, as the render loop does before a walk.
    private func beginWalk(_ manager: FocusManager) {
        manager.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        manager.beginSceneRender()
    }

    @Test("A menu's recorded paging keys, made again in a later walk, page that walk's focus manager")
    func recordedPagingKeysPageTheServingManager() {
        let sink = PathSink()
        let rendering = FocusManager()
        let journal = tui.renderCache.effectJournal

        // What a memo around the menu would store: the entries its render
        // appends while the memo records.
        beginWalk(rendering)
        let start = journal.beginRecording()
        _ = renderToBuffer(InlineProbeMenu(sink: sink), context: context(rendering))
        let entries = Array(journal.entries(since: start))
        journal.endRecording()
        #expect(entries.map(\.kind.name) == ["inlineMenuPaging"])
        guard let path = sink.path else {
            Issue.record("the probe never rendered")
            return
        }

        // A later walk with another manager, as a rebuilt scene would hand the
        // page, served from those entries. The menu's rows are stand-ins
        // registered under its path, as its buttons would be.
        let serving = FocusManager()
        beginWalk(serving)
        for entry in entries { entry.apply(context(serving)) }
        #expect(tui.keyEventDispatcher.handlerCount == 1, "the replay registered no paging keys")
        let rows = [MockFocusable(id: "\(path)#1"), MockFocusable(id: "\(path)#2")]
        for row in rows { serving.register(row, inSection: "menu") }
        #expect(serving.currentFocusedID == rows[0].focusID)

        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .end)), "End was not taken")
        #expect(
            serving.currentFocusedID == rows[1].focusID,
            "End did not move the focus in the manager of the walk that replayed the keys")
    }

    @Test("A served inline menu pages the focus of the walk that served it")
    func servedMenuStillPages() {
        let sink = PathSink()
        let manager = FocusManager()
        let cache = tui.renderCache
        let menu = InlineProbeMenu(sink: sink).equatable()

        // Frame one renders the menu and stores it.
        frame(manager, menu)
        guard let path = sink.path else {
            Issue.record("the probe never rendered")
            return
        }
        #expect(!cache.isEmpty, "the memo stored nothing, so nothing below can be served")

        // Frame two is the same value, so the buffer is served: the menu itself
        // is never walked — the probe does not render — and the paging keys are
        // in the dispatcher only because the memo made the registration again.
        sink.path = nil
        let before = cache.stats
        frame(manager, menu)
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits >= 1, "the second frame was not served: \(delta)")
        #expect(sink.path == nil, "the menu rendered again, so this frame proves nothing")
        #expect(tui.keyEventDispatcher.handlerCount == 1, "the served frame has no paging keys")

        // The rows a menu of Buttons would have, registered under the menu's
        // own path, as its rows are.
        let rows = [MockFocusable(id: "\(path)#1"), MockFocusable(id: "\(path)#2")]
        for row in rows { manager.register(row, inSection: "menu") }
        #expect(manager.currentFocusedID == rows[0].focusID)

        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .end)), "End was not taken")
        #expect(
            manager.currentFocusedID == rows[1].focusID,
            "End did not page the rows of the menu the memo served")
    }

    @Test("A key handler rendered after a served menu still outranks its paging keys")
    func servedMenuKeepsItsPlaceInTheRing() {
        // The precedence a menu's paging keys have is positional: they are
        // ordinary view handlers, and dispatch asks the most recent
        // registration first (`KeyEventDispatcher.dispatch`). A replay happens
        // where the subtree would have rendered, so a handler rendered after
        // the menu must outrank the menu's keys on a served frame exactly as it
        // does on a rendered one — otherwise serving would silently promote the
        // menu.
        let sink = PathSink()
        let manager = FocusManager()
        let later = KeyCounter()
        let page = VStack {
            InlineProbeMenu(sink: sink).equatable()
            Text("after").onKeyPress { [later] _ in
                later.count += 1
                return true
            }
        }

        frame(manager, page)
        guard let path = sink.path else {
            Issue.record("the probe never rendered")
            return
        }
        let rendered = pagingOutcome(manager, path: path, later: later)

        sink.path = nil
        let before = tui.renderCache.stats
        frame(manager, page)
        #expect(
            tui.renderCache.stats.delta(since: before).hits >= 1,
            "the second frame was not served, so it says nothing about a replay")
        #expect(sink.path == nil, "the menu rendered again on the second frame")
        let served = pagingOutcome(manager, path: path, later: later)

        #expect(rendered == (consumed: true, laterSaw: 1, focusMoved: false))
        #expect(served == rendered, "a served menu takes End that a rendered one leaves alone")
    }

    /// Registers stand-in rows, presses End, and reports who took it.
    private func pagingOutcome(
        _ manager: FocusManager, path: String, later: KeyCounter
    ) -> (consumed: Bool, laterSaw: Int, focusMoved: Bool) {
        let rows = [MockFocusable(id: "\(path)#1"), MockFocusable(id: "\(path)#2")]
        for row in rows { manager.register(row, inSection: "menu") }
        later.count = 0
        let consumed = tui.keyEventDispatcher.dispatch(KeyEvent(key: .end))
        return (consumed, later.count, manager.currentFocusedID != rows[0].focusID)
    }

    @Test("An inline menu's paging keys count as a replayable effect")
    func pagingKeysCountAsReplayable() {
        // The style itself no longer declares anything (it is comparable), so
        // the replayable count is the whole of what this render declares.
        let manager = FocusManager()
        let tracker = VolatileReadTracker()
        beginWalk(manager)
        _ = renderToBuffer(
            InlineProbeMenu(sink: PathSink()), context: context(manager, tracker: tracker))
        #expect(tracker.replayableEffects == 1)
    }
}
