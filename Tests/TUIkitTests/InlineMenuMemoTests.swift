//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InlineMenuMemoTests.swift
//
//  An inline menu's paging keys and the render memos. The key dispatcher is
//  emptied before every walk, so a memo serving a menu would have to register
//  them again, and the focus manager they page has to be the one in force where
//  the menu is served.
//
//  No styled inline menu can be served today. `.menuStyle(_:)` puts an
//  `any MenuStyle` into the environment, which cannot be compared: applied
//  below a memo it declares a side effect, and applied above one it marks every
//  memo beneath it unable to store. So these tests pin what a memo would
//  record and replay, rather than a served frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Where a probe last rendered.
private final class PathSink {
    var path: String?
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
@MainActor
private func menu(_ sink: PathSink) -> some View {
    Menu("Menu") {
        Text("one")
        PathProbe(sink: sink)
    }
    .menuStyle(.inline)
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
        _ = renderToBuffer(menu(sink), context: context(rendering))
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

    @Test("An inline menu's paging keys count as a replayable effect")
    func pagingKeysCountAsReplayable() {
        // Its style still declares side effects of its own (see the file
        // header), so only the replayable count is pinned here.
        let manager = FocusManager()
        let tracker = VolatileReadTracker()
        beginWalk(manager)
        _ = renderToBuffer(menu(PathSink()), context: context(manager, tracker: tracker))
        #expect(tracker.replayableEffects == 1)
    }
}
