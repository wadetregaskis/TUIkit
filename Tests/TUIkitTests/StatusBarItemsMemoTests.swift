//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarItemsMemoTests.swift
//
//  `.statusBarItems` interacting with the render memos. The status bar's items
//  are cleared and rebuilt every render pass, so a subtree served from the cache
//  has to register its items again or they silently vanish from the bar. The
//  modifier adds no hit region and reads no volatile value, so nothing else
//  about the subtree would notice. It once declared a side effect and declined
//  the cache; now the memo stores the subtree and replays the registration on
//  every hit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Which item actions ran.
private final class ActionLog {
    var entries: [String] = []
}

/// Frames through one `TUIContext`, focus manager and status bar, bracketed the
/// way `RenderLoop` brackets them, counting memo misses.
@MainActor
private final class ServedHarness {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()
    let statusBar = StatusBarState()

    var cache: RenderCache { tuiContext.renderCache }

    /// The shortcuts the bar shows for the active section, or its global items.
    var shortcuts: [String] { statusBar.currentUserItems.map(\.shortcut) }

    /// Renders one frame and returns the memo misses it took (buffer and size
    /// halves together). A frame whose memoized subtrees were all served takes
    /// none.
    @discardableResult
    func frame(_ view: some View, tracker: VolatileReadTracker = VolatileReadTracker()) -> Int {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.statusBar = statusBar
        environment.installVolatileReadTracker(tracker)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)
        let before = cache.stats.misses
        statusBar.focusManager = focusManager
        focusManager.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        tuiContext.keyEventDispatcher.clearHandlers()
        statusBar.beginSceneRender()
        focusManager.beginSceneRender()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        cache.removeInactive()
        return cache.stats.misses - before
    }
}

@MainActor
@Suite("Status bar items through the render memos")
struct StatusBarItemsMemoTests {
    /// One live-loop-shaped frame, returning the items the bar would show.
    private func renderFrame<V: View>(_ view: V, tuiContext: TUIContext) -> [String] {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        // A status bar of this frame's own: the environment no longer
        // hands out a shared instance, which is what let a parallel
        // neighbour's items be read back as this test's.
        environment.statusBar = StatusBarState()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.activeFocusSectionID = "section"
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)

        environment.statusBar?.beginRenderPass()
        // The bar derives its active section from the focus manager, exactly
        // as `RenderLoop.beginRenderPass` wires it.
        environment.statusBar?.focusManager = focusManager
        focusManager.registerSection(id: "section")
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return environment.statusBar?.currentUserItems.map(\.shortcut) ?? []
    }

    @Test("A memoized row's status bar items survive a cache-hit frame")
    func itemsSurviveRowMemo() {
        let tuiContext = TUIContext()
        // An `Equatable` element auto-wires `_MemoizedRow`, so the second
        // frame is a cache hit on an unchanged row — which is exactly when
        // the registration used to be skipped.
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).statusBarItems {
                    StatusBarItem(shortcut: "h", label: "help")
                }
            }
        }

        #expect(renderFrame(view, tuiContext: tuiContext).contains("h"))
        // Frame 2: the row's element is unchanged, so the memo may serve it.
        #expect(
            renderFrame(view, tuiContext: tuiContext).contains("h"),
            "the cache-hit frame dropped the row's status bar items")
    }

    @Test("An .equatable() subtree's status bar items survive a cache-hit frame")
    func itemsSurviveEquatableView() {
        struct Panel: View, Equatable {
            var body: some View {
                Text("panel").statusBarItems {
                    StatusBarItem(shortcut: "p", label: "panel")
                }
            }
        }
        let tuiContext = TUIContext()
        let view = VStack { Panel().equatable() }

        #expect(renderFrame(view, tuiContext: tuiContext).contains("p"))
        #expect(
            renderFrame(view, tuiContext: tuiContext).contains("p"),
            "the cache-hit frame dropped the subtree's status bar items")
    }

    // MARK: - Served and replayed

    @Test("A memoized row with status bar items is served, and its item and action survive every served frame")
    func rowWithItemsIsServed() {
        let harness = ServedHarness()
        let log = ActionLog()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).statusBarItems {
                    StatusBarItem(shortcut: "h", label: "help") { log.entries.append(name) }
                }
            }
        }

        for number in 1...3 {
            let hitsBefore = harness.cache.stats.hits
            let misses = harness.frame(view)
            if number > 1 {
                #expect(misses == 0, "frame \(number) rendered the row again: \(misses) misses")
                #expect(harness.cache.stats.hits > hitsBefore, "frame \(number) served nothing")
            }
            #expect(harness.shortcuts == ["h"], "frame \(number): \(harness.shortcuts)")
            log.entries = []
            #expect(harness.statusBar.handleKeyEvent(KeyEvent(character: "h")), "frame \(number)")
            #expect(log.entries == ["row"], "frame \(number): the item's action did not run")
        }
        #expect(!harness.cache.isEmpty, "the row was never stored")
    }

    @Test("Two memoized rows in one section: the later row's items win on served frames as on the rendering one")
    func perSectionReplaceSurvivesReplay() {
        let harness = ServedHarness()
        let view = VStack {
            ForEach(["a", "b"], id: \.self) { name in
                Text(name).statusBarItems {
                    StatusBarItem(shortcut: name, label: name)
                }
            }
        }
        .focusSection("section")

        var seen: [[String]] = []
        for number in 1...3 {
            let misses = harness.frame(view)
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the rows again: \(misses) misses") }
            harness.focusManager.activateSection(id: "section")
            seen.append(harness.shortcuts)
        }
        // A section's registration REPLACES the one before it in that section,
        // so the last row in render order owns the section's items.
        #expect(seen[0] == ["b"], "\(seen[0])")
        #expect(seen[1] == seen[0], "the first served frame: \(seen[1])")
        #expect(seen[2] == seen[0], "the second served frame: \(seen[2])")
    }

    @Test("A dimmed memoized row is stored, and its item never reaches the live bar")
    func dimmedRowItemsStayOffTheBar() {
        let harness = ServedHarness()
        let log = ActionLog()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name)
                    .statusBarItems {
                        StatusBarItem(shortcut: "h", label: "help") { log.entries.append(name) }
                    }
                    .dimmed()
            }
        }

        for number in 1...3 {
            let misses = harness.frame(view)
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the dimmed row again") }
            // Replayed from the row's own position, the item recorded into the
            // dimmed content's throwaway bar would land here.
            #expect(harness.shortcuts.isEmpty, "frame \(number): \(harness.shortcuts)")
            #expect(!harness.statusBar.handleKeyEvent(KeyEvent(character: "h")), "frame \(number)")
        }
        #expect(log.entries.isEmpty)
        #expect(!harness.cache.isEmpty, "the dimmed row was never stored")
    }

    @Test("Status bar items count as a replayable effect on the frame that renders the row and the frame that serves it")
    func itemsCountAsReplayable() {
        let harness = ServedHarness()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).statusBarItems { StatusBarItem(shortcut: "h", label: "help") }
            }
        }

        for number in 1...2 {
            let tracker = VolatileReadTracker()
            harness.frame(view, tracker: tracker)
            #expect(tracker.replayableEffects == 1, "frame \(number)")
            #expect(tracker.sideEffects == 0, "frame \(number)")
        }
    }
}
