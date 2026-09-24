//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RegistrationReplayStormTests.swift
//
//  A seeded storm over the render memos' replay journal. Two copies of the same
//  app run side by side, driven by the same random script of state changes,
//  section changes, sheet presentations and key presses: one with the render
//  cache, one whose cache is emptied before every walk, so nothing there is
//  ever served and nothing is ever replayed. After every frame and every key,
//  what the user could observe must be identical: the picture, the status bar
//  items, how many key handlers are live, which section is active, whether the
//  key was consumed, and which handlers, item actions and refreshes ran.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitStyling

// MARK: - The script's model

/// One row: a title and the registrations it makes. `Equatable`, so `ForEach`
/// memoizes it, and everything it draws or registers is in it.
private struct StormRow: Equatable, Sendable {
    let id: Int
    var version = 0
    var key: Character?
    var consumes = false
    var item: Character?
    var refreshable = false
    var dimmed = false
    var boxed = false

    var title: String { "r\(id).\(version)" }
}

/// A group of rows in a focus section, memoized as a whole or not, with its
/// `.focusSection` inside or outside that memo.
private struct StormGroup: Equatable, Sendable {
    var section: String
    var rows: [StormRow]
    var memoized = false
    var sectionInside = false
}

/// Everything the page is built from.
private struct StormPage: Equatable, Sendable {
    var groups: [StormGroup]
    var sheetRows: [StormRow]
    var sheet = false
    var nextID = 0
}

/// What ran, in order. Locked: a refresh runs in a `Task`.
private final class StormLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var count: Int { lock.withLock { entries.count } }
    var all: [String] { lock.withLock { entries } }
}

// MARK: - The page

/// A row's view: its title, and each registration its model asks for.
private struct StormRowView: View, @MainActor Equatable {
    let row: StormRow
    let log: StormLog

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.row == rhs.row && lhs.log === rhs.log }

    var body: some View {
        let row = row
        let log = log
        var view = AnyView(Text(row.title))
        if let key = row.key {
            view = AnyView(
                view.onKeyPress(keys: [.character(key)]) { _ in
                    log.append("key \(row.title)")
                    return row.consumes
                })
        }
        if let item = row.item {
            view = AnyView(
                view.statusBarItems {
                    StatusBarItem(shortcut: String(item), label: row.title) { log.append("item \(row.title)") }
                })
        }
        if row.refreshable {
            view = AnyView(view.refreshable { log.append("refresh \(row.title)") })
        }
        if row.dimmed { view = AnyView(view.dimmed()) }
        return view
    }
}

/// Rows under `ForEach`, each memoized by its element, and some memoized again
/// by `.equatable()`.
@MainActor
private func stormRows(_ rows: [StormRow], log: StormLog) -> some View {
    ForEach(rows, id: \.id) { row in
        if row.boxed {
            StormRowView(row: row, log: log).equatable()
        } else {
            StormRowView(row: row, log: log)
        }
    }
}

/// A group's body. Its key leaves the section out when the section is applied
/// outside it, because then the body does not draw or register it: that is what
/// lets a group memo be served under a section it was not recorded in.
private struct StormGroupView: View, @MainActor Equatable {
    let group: StormGroup
    let log: StormLog

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.log === rhs.log && lhs.group.rows == rhs.group.rows
            && lhs.group.sectionInside == rhs.group.sectionInside
            && (!lhs.group.sectionInside || lhs.group.section == rhs.group.section)
    }

    var body: some View {
        if group.sectionInside {
            VStack(alignment: .leading, spacing: 0) { stormRows(group.rows, log: log) }
                .focusSection(group.section)
        } else {
            VStack(alignment: .leading, spacing: 0) { stormRows(group.rows, log: log) }
        }
    }
}

@MainActor @ViewBuilder
private func stormGroup(_ group: StormGroup, log: StormLog) -> some View {
    switch (group.memoized, group.sectionInside) {
    case (true, true): StormGroupView(group: group, log: log).equatable()
    case (true, false): StormGroupView(group: group, log: log).equatable().focusSection(group.section)
    case (false, true): StormGroupView(group: group, log: log)
    case (false, false): StormGroupView(group: group, log: log).focusSection(group.section)
    }
}

/// Three groups at fixed positions, and a sheet of rows over them.
@MainActor
private func stormPage(_ page: StormPage, log: StormLog, sheet: Binding<Bool>) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        stormGroup(page.groups[0], log: log)
        stormGroup(page.groups[1], log: log)
        stormGroup(page.groups[2], log: log)
    }
    .sheet(isPresented: sheet) {
        VStack(alignment: .leading, spacing: 0) { stormRows(page.sheetRows, log: log) }
    }
}

// MARK: - The script

/// The keys rows listen for, the letters their items bind, and every event the
/// storm presses. No letter the input handler binds globally (`a`, `t`, `q`).
private enum StormKeys {
    static let rowKeys: [Character] = ["1", "2", "3", "4"]
    static let itemKeys: [Character] = ["w", "x", "y", "z"]
    static let events: [KeyEvent] =
        (rowKeys + itemKeys).map { KeyEvent(character: $0) }
        + [KeyEvent(key: .character("r"), ctrl: true), KeyEvent(key: .escape)]

    /// Whether this is the Ctrl-R that `.refreshable` binds — the only press in
    /// this script that can start anything off the main actor. Spelled the way
    /// the binding itself spells it (`RefreshRegistrar.register`: ctrl, and the
    /// letter `r` in either case), so the two cannot drift apart.
    static func startsRefresh(_ event: KeyEvent) -> Bool {
        guard event.ctrl, case .character(let character) = event.key else { return false }
        return character.lowercased() == "r"
    }
}

/// A seeded generator, so a failing step can be replayed.
private struct StormRandom {
    var state: UInt64

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(max(1, bound)))
    }

    /// True one time in `odds`.
    mutating func oneIn(_ odds: Int) -> Bool { next(odds) == 0 }
}

extension StormPage {
    static func initial(_ random: inout StormRandom) -> Self {
        var page = Self(groups: [], sheetRows: [])
        for index in 0..<3 {
            var rows: [StormRow] = []
            for _ in 0..<(2 + random.next(3)) { rows.append(page.makeRow(&random)) }
            page.groups.append(
                StormGroup(
                    section: "s\(index)", rows: rows,
                    memoized: random.oneIn(2), sectionInside: random.oneIn(4)))
        }
        var sheetRows: [StormRow] = []
        for _ in 0..<2 { sheetRows.append(page.makeRow(&random)) }
        page.sheetRows = sheetRows
        return page
    }

    mutating func makeRow(_ random: inout StormRandom) -> StormRow {
        defer { nextID += 1 }
        return StormRow(
            id: nextID,
            key: random.oneIn(2) ? StormKeys.rowKeys[random.next(4)] : nil,
            consumes: random.oneIn(2),
            item: random.oneIn(2) ? StormKeys.itemKeys[random.next(4)] : nil,
            refreshable: random.oneIn(3), dimmed: random.oneIn(4), boxed: random.oneIn(3))
    }

    /// Applies one random change, and says what it was and which section, if
    /// any, to activate once the next frame has registered it.
    mutating func mutate(_ random: inout StormRandom) -> (String, activate: String?) {
        let group = random.next(3)
        switch random.next(11) {
        case 0: return (editRow(&random) { $0.version += 1 }, nil)
        case 1: return (editRow(&random) { $0.key = $0.key == nil ? StormKeys.rowKeys[$0.version % 4] : nil }, nil)
        case 2: return (editRow(&random) { $0.item = $0.item == nil ? StormKeys.itemKeys[$0.id % 4] : nil }, nil)
        case 3: return (editRow(&random) { $0.refreshable.toggle() }, nil)
        case 4: return (editRow(&random) { $0.dimmed.toggle() }, nil)
        case 5: return (editRow(&random) { $0.consumes.toggle(); $0.boxed.toggle() }, nil)
        case 6: return (reshape(group: group, &random), nil)
        case 7:
            let name = "s\(random.next(5))"
            groups[group].section = name
            return ("group \(group) section -> \(name)", name)
        case 8:
            groups[group].memoized.toggle()
            if random.oneIn(2) { groups[group].sectionInside.toggle() }
            return ("group \(group) memoized \(groups[group].memoized) inside \(groups[group].sectionInside)", nil)
        case 9:
            sheet.toggle()
            return ("sheet \(sheet)", nil)
        default:
            let name = "s\(random.next(5))"
            return ("activate \(name)", name)
        }
    }

    /// Edits one row, on the page or in the sheet.
    private mutating func editRow(_ random: inout StormRandom, _ edit: (inout StormRow) -> Void) -> String {
        if random.oneIn(4), !sheetRows.isEmpty {
            let index = random.next(sheetRows.count)
            edit(&sheetRows[index])
            return "sheet row \(sheetRows[index])"
        }
        let group = random.next(3)
        guard !groups[group].rows.isEmpty else { return "no row in group \(group)" }
        let index = random.next(groups[group].rows.count)
        edit(&groups[group].rows[index])
        return "group \(group) row \(groups[group].rows[index])"
    }

    /// Moves a row to another group, adds one, or removes one.
    private mutating func reshape(group: Int, _ random: inout StormRandom) -> String {
        switch random.next(3) {
        case 0 where !groups[group].rows.isEmpty:
            let row = groups[group].rows.remove(at: random.next(groups[group].rows.count))
            let target = (group + 1 + random.next(2)) % 3
            groups[target].rows.insert(row, at: random.next(groups[target].rows.count + 1))
            return "move \(row.id) from \(group) to \(target)"
        case 1 where groups[group].rows.count > 1:
            let row = groups[group].rows.remove(at: random.next(groups[group].rows.count))
            return "remove \(row.id) from \(group)"
        default:
            let row = makeRow(&random)
            groups[group].rows.insert(row, at: random.next(groups[group].rows.count + 1))
            return "add \(row) to \(group)"
        }
    }
}

// MARK: - One copy of the app

/// Everything a frame shows the user, or decides for the next key.
private struct StormFrame: Equatable {
    let lines: [String]
    let items: [String]
    let handlers: Int
    let activeSection: String?
    let sections: [String]
}

/// An app: its own services and log, rendered the way `RenderLoop` brackets a
/// frame and driven through a real `InputHandler`.
@MainActor
private final class StormRun {
    static let width = 60
    static let height = 30

    let caches: Bool
    let tui: TUIContext
    let focusManager: FocusManager
    let statusBar: StatusBarState
    let input: InputHandler
    let log = StormLog()
    var page: StormPage

    init(page: StormPage, caches: Bool) {
        let tui = TUIContext()
        let focusManager = FocusManager()
        let statusBar = StatusBarState()
        statusBar.focusManager = focusManager
        self.tui = tui
        self.focusManager = focusManager
        self.statusBar = statusBar
        self.page = page
        self.caches = caches
        input = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tui.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts,
            dragAndDropSession: tui.dragAndDropSession,
            onQuit: {}, onSuspend: {})
    }

    /// Renders one frame of `walks` walks. The uncached copy empties its cache
    /// before every walk, so it never serves a buffer and never replays.
    func frame(walks: Int) -> StormFrame {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = statusBar
        environment.terminalWidth = Self.width
        environment.overlayContentHeight = Self.height
        let context = RenderContext(
            availableWidth: Self.width, availableHeight: Self.height,
            environment: environment, tuiContext: tui)
        let sheet = Binding(get: { self.page.sheet }, set: { self.page.sheet = $0 })

        focusManager.beginRenderPass()
        tui.lifecycle.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        var buffer = FrameBuffer()
        for _ in 0..<walks {
            if !caches { tui.renderCache.clearAll() }
            tui.keyEventDispatcher.clearHandlers()
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyboardShortcuts.beginRenderPass()
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginSceneRender()
            focusManager.beginSceneRender()
            statusBar.beginSceneRender()
            buffer = renderToBuffer(stormPage(page, log: log, sheet: sheet), context: context)
        }
        focusManager.endRenderPass()
        tui.lifecycle.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()

        let picture = buffer.compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: environment.palette)
        return StormFrame(
            lines: picture.lines,
            items: statusBar.currentUserItems.map { "\($0.shortcut)=\($0.label)" },
            handlers: tui.keyEventDispatcher.handlerCount,
            activeSection: focusManager.activeSectionIdentifier,
            sections: focusManager.sectionIDs)
    }
}

/// Waits for the refresh a Ctrl-R started — the one thing a press here does off
/// the main actor — to have run. Bounded.
///
/// `reaching` is each copy's log count from before the press, plus the entry
/// the refresh that press started will append. GROWTH is the signal, and it has
/// to be: waiting for the two counts to AGREE, which is what this did, is
/// satisfied the instant the press returns, because both copies are then
/// equally stale and equally stale counts are equal. That wait was doing
/// nothing, and the 20 unconditional `Task.yield()`s in front of it were all
/// that let a refresh get going at all — on every press, including the nine in
/// ten that start nothing.
///
/// The expected count is exact, not a guess. `KeyEventDispatcher.dispatch`
/// stops at the FIRST handler that returns true and `.refreshable`'s Ctrl-R
/// binding always returns true, so a CONSUMED Ctrl-R is exactly one run started
/// in that copy, and a run appends exactly one entry. Nothing else in this page
/// can consume a Ctrl-R: no row key and no status-bar item binds `r`, the focus
/// system has no Ctrl binding, and `InputHandler`'s chrome shortcuts require
/// the letter bare. A press that started nothing has nothing to wait for — row
/// handlers and item actions ran inside `handle`, on the main actor — and the
/// loop below then exits without sleeping once.
///
/// Polled, not yielded, deliberately: the action appends its entry and the run
/// marks itself finished a few instructions later, off the main actor. A 1 ms
/// poll cannot observe the first without the second; a yield, being
/// microseconds, could — and a copy still holding a running refresh draws the
/// in-flight spinner that the other one does not. That is also why the shared
/// `settle(until:)` is not used here: it yields on all but every fiftieth
/// iteration, which is the behaviour this one exists to avoid.
///
/// The bound is a HANG-BREAKER, NOT A SCHEDULE, and it used to be a schedule:
/// 200 spins of 1 ms, after which the wait simply returned and the storm
/// compared two copies that had not finished. On a machine where the
/// cooperative pool is contended by eleven other test processes, 200 ms is a
/// budget a healthy refresh can miss, and missing it produced a divergence
/// report about the picture rather than about the wait — the failure blaming
/// the wrong thing. It now waits for the edge it named, and says so if the
/// edge never arrives, so a stuck refresh reads as a stuck refresh.
@MainActor
private func settle(_ cached: StormRun, _ uncached: StormRun, reaching expected: (Int, Int)) async {
    var wait = HangBreaker(timeout: .seconds(60))
    while cached.log.count < expected.0 || uncached.log.count < expected.1 {
        guard !wait.hasTripped else {
            Issue.record(
                """
                a refresh never ran: \(cached.log.count)/\(expected.0) cached and \
                \(uncached.log.count)/\(expected.1) uncached, after \(wait.turns) polls \
                in \(wait.elapsed)
                """)
            return
        }
        wait.nextTurn()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

// MARK: - The storm

@MainActor
@Suite("Registration replay storm", .serialized)
struct RegistrationReplayStormTests {
    static let trials = 8
    static let steps = 80

    @Test("A cached app and an uncached one register, dispatch and draw identically through a storm")
    func cachedMatchesUncached() async {
        var hits = 0
        for trial in 0..<Self.trials {
            var random = StormRandom(state: 0x5EED_0000 &+ UInt64(trial) &* 7919)
            let page = StormPage.initial(&random)
            let cached = StormRun(page: page, caches: true)
            let uncached = StormRun(page: page, caches: false)
            if let failure = await runTrial(cached, uncached, &random) {
                Issue.record("trial \(trial): \(failure)")
            }
            hits += cached.tui.renderCache.stats.hits
            #expect(uncached.tui.renderCache.stats.hits == 0, "trial \(trial): the uncached copy served a buffer")
        }
        // Without hits the two copies are the same program and agree trivially.
        #expect(hits > 1000, "the cached copy served only \(hits) buffers")
    }

    /// Runs one trial's steps, and describes the first divergence.
    private func runTrial(
        _ cached: StormRun, _ uncached: StormRun, _ random: inout StormRandom
    ) async -> String? {
        var page = cached.page
        var history: [String] = []
        for step in 0..<Self.steps {
            let (change, activate) = page.mutate(&random)
            history.append("\(step): \(change)")
            cached.page = page
            uncached.page = page
            for pass in 0..<2 {
                let walks = random.oneIn(5) ? 2 : 1
                let seen = cached.frame(walks: walks)
                let expected = uncached.frame(walks: walks)
                if seen != expected {
                    return describe("frame \(pass), \(walks) walks", seen, expected, history)
                }
                if pass == 0, let activate {
                    cached.focusManager.activateSection(id: activate)
                    uncached.focusManager.activateSection(id: activate)
                }
                for _ in 0...random.next(2) {
                    let event = StormKeys.events[random.next(StormKeys.events.count)]
                    history.append("  press \(event.key)\(event.ctrl ? " ctrl" : "")")
                    let before = (cached.log.count, uncached.log.count)
                    let consumed = (cached.input.handle(event), uncached.input.handle(event))
                    // A consumed Ctrl-R is one refresh started in that copy,
                    // and its entry lands after `handle` has returned; every
                    // other press has already done everything it is going to.
                    let startsRefresh = StormKeys.startsRefresh(event)
                    await settle(
                        cached, uncached,
                        reaching: (
                            before.0 + (startsRefresh && consumed.0 ? 1 : 0),
                            before.1 + (startsRefresh && consumed.1 ? 1 : 0)))
                    if consumed.0 != consumed.1 {
                        return describe("consumed", consumed.0, consumed.1, history)
                    }
                    if cached.log.all != uncached.log.all || cached.page.sheet != uncached.page.sheet {
                        return describe("ran", cached.log.all.suffix(4), uncached.log.all.suffix(4), history)
                    }
                }
            }
            page = cached.page
        }
        return nil
    }

    private func describe<T>(_ what: String, _ cached: T, _ uncached: T, _ history: [String]) -> String {
        """
        \(what) differs
          cached:   \(cached)
          uncached: \(uncached)
          last steps:
            \(history.suffix(12).joined(separator: "\n    "))
        """
    }
}
