//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyPressMemoTests.swift
//
//  Tests for onKeyPress interacting with the render memos and the measure
//  pass. The key dispatcher clears its handlers before every walk, so an
//  onKeyPress inside a value-memoized row once went dead on the first
//  cache-hit frame; it then declined the cache instead; and now the memo
//  stores the row and replays its registration on every hit. A measure-pass
//  render once registered a second handler, running the action twice per
//  keypress.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// What the handlers under test saw, in the order they ran.
private final class KeyLog: @unchecked Sendable {
    var entries: [String] = []
}

/// Renders frames the way `RenderLoop` brackets them: one pass per frame, the
/// key dispatcher and focus sections emptied before every walk.
@MainActor
private final class LoopHarness {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()

    var dispatcher: KeyEventDispatcher { tuiContext.keyEventDispatcher }
    var cache: RenderCache { tuiContext.renderCache }

    /// Renders one frame of `walks` walks and returns how many memo lookups
    /// (buffer and size halves together) missed. A frame whose memoized
    /// subtrees were all served takes none.
    @discardableResult
    func frame(
        _ view: some View, walks: Int = 1, isMeasuring: Bool = false,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> Int {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.installVolatileReadTracker(VolatileReadTracker())
        configure(&environment)
        var context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, tuiContext: tuiContext)
        context.isMeasuring = isMeasuring
        let missesBefore = cache.stats.misses
        tuiContext.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        for _ in 0..<walks {
            dispatcher.clearHandlers()
            focusManager.beginSceneRender()
            _ = renderToBuffer(view, context: context)
        }
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        cache.removeInactive()
        return cache.stats.misses - missesBefore
    }

    /// Dispatches one key and returns what the log gained.
    func press(_ log: KeyLog, sectionID: String? = nil) -> [String] {
        log.entries = []
        if let sectionID { dispatcher.grabInput(sectionID: sectionID) }
        _ = dispatcher.dispatch(KeyEvent(character: "x"))
        return log.entries
    }
}

/// Rows keyed on their names, each logging its name and declining the key.
@MainActor
private func loggingRows(_ names: [String], _ log: KeyLog) -> some View {
    ForEach(names, id: \.self) { name in
        Text(name).onKeyPress { _ in
            log.entries.append(name)
            return false
        }
    }
}

/// An `.equatable()` subtree whose handler logs `name`, equal to any other
/// with the same log.
private struct LoggingLeaf: View, @MainActor Equatable {
    let name: String
    let log: KeyLog

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.log === rhs.log }

    var body: some View {
        Text("leaf").onKeyPress { [name, log] _ in
            log.entries.append(name)
            return false
        }
    }
}

/// An outer memo around rows that capture its title, keyed on title and names.
private struct Board: View, @MainActor Equatable {
    let title: String
    let names: [String]
    let log: KeyLog

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.names == rhs.names && lhs.log === rhs.log
    }

    var body: some View {
        VStack {
            Text(title)
            ForEach(names, id: \.self) { name in
                Text(name).onKeyPress { [title, log] _ in
                    log.entries.append("\(title):\(name)")
                    return false
                }
            }
        }
    }
}

/// A leaf that registers a key handler or not, while comparing equal either
/// way: the kind of lie the render-memo verifier exists to catch.
private struct FlagLeaf: View, @MainActor Equatable {
    let handles: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        if handles {
            Text("x").onKeyPress { _ in false }
        } else {
            Text("x")
        }
    }
}

@MainActor
@Suite("onKeyPress through the render memos")
struct KeyPressMemoTests {
    @Test("A memoized row's key handler stays registered across cache-hit frames")
    func handlerSurvivesRowMemo() {
        nonisolated(unsafe) var handled = 0
        let tuiContext = TUIContext()
        func frame() {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.keyEventDispatcher.clearHandlers()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            let view = VStack {
                ForEach(["row"], id: \.self) { name in
                    Text(name).onKeyPress { _ in
                        handled += 1
                        return true
                    }
                }
            }
            _ = renderToBuffer(view, context: context)
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }

        for expected in 1...3 {
            frame()
            _ = tuiContext.keyEventDispatcher.dispatch(KeyEvent(character: "x"))
            #expect(handled == expected, "frame \(expected): the handler is live, got \(handled)")
        }
    }

    @Test("A measure-pass render does not register a duplicate handler")
    func measurePassDoesNotDuplicate() {
        nonisolated(unsafe) var count = 0
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        var context = RenderContext(
            availableWidth: 30, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)

        tuiContext.keyEventDispatcher.clearHandlers()
        let view = Text("x").onKeyPress { _ in
            count += 1
            return false
        }
        context.isMeasuring = true
        _ = renderToBuffer(view, context: context)  // a render-to-measure ancestor's render
        context.isMeasuring = false
        _ = renderToBuffer(view, context: context)  // the real render
        _ = tuiContext.keyEventDispatcher.dispatch(KeyEvent(character: "y"))

        #expect(count == 1, "one keypress runs the handler exactly once, got \(count)")
    }

    // MARK: - Served and replayed

    @Test("A memoized row with onKeyPress is served, and its handler is live on every frame")
    func rowWithKeyHandlerIsServed() {
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack { loggingRows(["row"], log) }

        for number in 1...3 {
            let hitsBefore = harness.cache.stats.hits
            let misses = harness.frame(view)
            if number > 1 {
                #expect(misses == 0, "frame \(number) rendered the row again: \(misses) misses")
                #expect(harness.cache.stats.hits > hitsBefore, "frame \(number) served nothing")
            }
            #expect(harness.dispatcher.handlerCount == 1, "frame \(number)")
            #expect(harness.press(log) == ["row"], "frame \(number): the handler is not live")
        }
        #expect(!harness.cache.isEmpty, "the row was never stored")
    }

    @Test("Dispatch order is the same on the frame that renders the rows and the frames that serve them")
    func dispatchOrderSurvivesReplay() {
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack {
            Text("before").onKeyPress { _ in
                log.entries.append("before")
                return false
            }
            loggingRows(["r1", "r2"], log)
            Text("after").onKeyPress { _ in
                log.entries.append("after")
                return false
            }
        }
        .onKeyPress { _ in
            log.entries.append("outer")
            return false
        }

        var orders: [[String]] = []
        for number in 1...3 {
            let misses = harness.frame(view)
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the rows again") }
            orders.append(harness.press(log))
        }
        // Newest registration first: the replayed rows sit exactly where they
        // rendered, between the two plain handlers, inside the outer one.
        #expect(orders[0] == ["after", "r2", "r1", "before", "outer"])
        #expect(orders[1] == orders[0], "the first served frame dispatched in another order")
        #expect(orders[2] == orders[0], "the second served frame dispatched in another order")
    }

    @Test("The same memoized subtree under a different focus section registers in the new section")
    func sectionChangeMisses() {
        let harness = LoopHarness()
        let log = KeyLog()
        func view(_ section: String) -> some View {
            LoggingLeaf(name: "leaf", log: log).equatable().focusSection(section)
        }

        harness.frame(view("s1"))
        #expect(harness.cache.count == 1, "the subtree was not stored")
        #expect(harness.press(log, sectionID: "s1") == ["leaf"])

        // The key compares equal, but the section its handler was recorded in
        // is not the one in force: serving it would file the handler in s1.
        let misses = harness.frame(view("s2"))
        #expect(misses > 0, "a subtree recorded in s1 was served in s2")
        #expect(harness.press(log, sectionID: "s2") == ["leaf"], "the handler is not in s2")
        #expect(harness.press(log, sectionID: "s1").isEmpty, "the handler is still in s1")

        // The section's ACTIVE-ness settles a pass behind the section itself: s2
        // registered on the frame above while the manager still named s1, and
        // only afterwards did s2 become the active one. So this is the first
        // frame on which the section indicator's answer changes, and that answer
        // is published to the memo now (`RenderContext.publishSectionIndicator`)
        // rather than assigned silently — so the subtree is rendered again
        // instead of being served the picture drawn while its section held
        // nothing. It draws no ● itself; the clear is conservative, exactly as
        // `publishIsFocused`'s is, because only the border below knows whether
        // it would have drawn one.
        #expect(harness.frame(view("s2")) > 0, "the indicator's arrival did not re-render the subtree")
        #expect(harness.press(log, sectionID: "s2") == ["leaf"], "the handler left s2")
        #expect(harness.press(log, sectionID: "s1").isEmpty, "the handler went back to s1")

        // And it SETTLES, which is the half worth pinning: once the active
        // section stops moving the subtree is served again. Were the indicator
        // noted as the breathing colour rather than as the gated Bool, this
        // would clear on every frame and the fix would have cost the cache every
        // sectioned subtree in the app.
        #expect(harness.frame(view("s2")) == 0, "a settled, unchanged section was not served")
        #expect(harness.press(log, sectionID: "s2") == ["leaf"], "the replay left s2")
        #expect(harness.press(log, sectionID: "s1").isEmpty, "the replay went back to s1")
    }

    @Test("A frame of two walks leaves exactly one handler per row")
    func twoWalkFrameLeavesOneHandler() {
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack { loggingRows(["row"], log) }

        for number in 1...2 {
            let misses = harness.frame(view, walks: 2)
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the row again") }
            #expect(harness.dispatcher.handlerCount == 1, "frame \(number)")
            #expect(harness.press(log) == ["row"], "frame \(number)")
        }
        #expect(!harness.cache.isEmpty, "the row was never stored")
    }

    @Test("A row under a presented sheet puts no handler in the live dispatcher, served or not")
    func rowUnderSheetStaysIsolated() {
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack { loggingRows(["row"], log) }
            .sheet(isPresented: .constant(true)) { Text("sheet") }

        for number in 1...3 {
            let misses = harness.frame(view) { environment in
                environment.terminalWidth = 40
                environment.overlayContentHeight = 20
            }
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the page's row again") }
            #expect(harness.press(log).isEmpty, "frame \(number): the row under the sheet took the key")
        }
        #expect(!harness.cache.isEmpty, "the page's row was never stored")
    }

    @Test("A dimmed row is stored, and its handler never reaches the live dispatcher")
    func dimmedRowIsStoredButInert() {
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name)
                    .onKeyPress { _ in
                        log.entries.append(name)
                        return true
                    }
                    .dimmed()
            }
        }

        for number in 1...3 {
            let misses = harness.frame(view)
            if number > 1 { #expect(misses == 0, "frame \(number) rendered the dimmed row again") }
            // Replayed from the row's own position, the handler recorded into
            // the dimmed content's throwaway dispatcher would land here.
            #expect(harness.dispatcher.handlerCount == 0, "frame \(number)")
            #expect(harness.press(log).isEmpty, "frame \(number): a dimmed row took the key")
        }
        #expect(!harness.cache.isEmpty, "the dimmed row was never stored")
    }

    @Test("onKeyPress counts as replayable, and cacheUnsafeCount moves on a miss and on a hit")
    func keyPressCountsAsReplayable() {
        let harness = LoopHarness()
        let view = VStack { loggingRows(["row"], KeyLog()) }

        for number in 1...2 {
            let tracker = VolatileReadTracker()
            harness.frame(view) { $0.installVolatileReadTracker(tracker) }
            // The size memo, the measure memo and List's hug-width memo read
            // `cacheUnsafeCount` and replay nothing, so it must move exactly as
            // it did when the handler declined the cache: on the frame that
            // renders the row, and on the frame that serves it.
            #expect(tracker.replayableEffects == 1, "frame \(number)")
            #expect(tracker.sideEffects == 0, "frame \(number)")
            #expect(tracker.cacheUnsafeCount == tracker.reads + 1, "frame \(number)")
        }
    }

    @Test("A measure pass that hits a stored row replays nothing")
    func measurePassHitReplaysNothing() {
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack { loggingRows(["row"], log) }

        harness.frame(view)
        #expect(!harness.cache.isEmpty, "the row was never stored")
        harness.frame(view, isMeasuring: true)
        #expect(harness.dispatcher.handlerCount == 0, "a measure pass registered a handler")
    }

    @Test("An outer memo that misses while its rows are served keeps the rows' handlers")
    func nestedMemoKeepsReplayedHandlers() {
        let harness = LoopHarness()
        let log = KeyLog()
        func view(_ title: String) -> some View {
            Board(title: title, names: ["r1", "r2"], log: log).equatable()
        }

        #expect(harness.frame(view("a")) > 0)
        #expect(harness.press(log) == ["a:r2", "a:r1"])
        #expect(harness.frame(view("a")) == 0, "the unchanged board was not served")
        #expect(harness.press(log) == ["a:r2", "a:r1"])

        // The board misses and renders again; its rows are served. That the
        // handlers still log the title they were RENDERED with shows they were
        // replayed, not rendered — and the outer memo, recording, has to keep
        // those replays for the frame that serves the board.
        #expect(harness.frame(view("b")) > 0, "the changed board was served")
        #expect(harness.press(log) == ["a:r2", "a:r1"], "the rows rendered again")
        #expect(harness.frame(view("b")) == 0, "the board was not stored again")
        #expect(harness.dispatcher.handlerCount == 2, "the served board lost its rows' handlers")
        #expect(harness.press(log) == ["a:r2", "a:r1"])
    }

    // MARK: - Verify mode

    @Test("Under the render-memo verifier a hit renders fresh and registers once, not twice")
    func verifierRegistersOnce() {
        let was = RenderCache.verifiesRenderMemo
        defer { RenderCache.verifiesRenderMemo = was }
        let harness = LoopHarness()
        let log = KeyLog()
        let view = VStack { loggingRows(["row"], log) }

        RenderCache.verifiesRenderMemo = false
        harness.frame(view)
        RenderCache.verifiesRenderMemo = true
        #expect(harness.frame(view) == 0, "the row was not served")
        #expect(harness.dispatcher.handlerCount == 1, "the verifier's render and a replay both registered")
        #expect(harness.press(log) == ["row"])
        #expect(harness.cache.renderMemoMismatches.isEmpty, "\(harness.cache.renderMemoMismatches)")
    }

    @Test("The render-memo verifier reports a hit whose fresh render registers other effects")
    func verifierReportsEffectMismatch() {
        let was = RenderCache.verifiesRenderMemo
        defer { RenderCache.verifiesRenderMemo = was }
        let harness = LoopHarness()

        RenderCache.verifiesRenderMemo = false
        harness.frame(FlagLeaf(handles: false).equatable())
        #expect(harness.cache.count == 1, "the handler-free leaf was not stored")
        RenderCache.verifiesRenderMemo = true
        harness.frame(FlagLeaf(handles: true).equatable())
        let report = harness.cache.renderMemoMismatches
        #expect(report.count == 1, "\(report)")
        #expect(report.first?.contains("onKeyPress") == true, "\(report)")
    }
}
