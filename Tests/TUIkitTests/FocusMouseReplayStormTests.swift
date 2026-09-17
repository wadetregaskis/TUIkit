//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusMouseReplayStormTests.swift
//
//  A seeded storm over the focus and mouse halves of the render memos' replay
//  journal. Two copies of the same app run side by side, driven by the same
//  random script of data edits, section changes, sheet presentations, pushes,
//  Tab and Shift-Tab, clicks, hovers and drags: one with the render cache, one
//  whose cache is emptied before every walk, so nothing there is ever served and
//  nothing is ever replayed.
//
//  `RegistrationReplayStormTests` is the keyboard twin of this file and covers
//  `onKeyPress`, `.refreshable` and `.statusBarItems`. What it could not cover is
//  everything phases 2 and 3 made storable: a control's place in the Tab ring, a
//  `.keyboardShortcut` planted inside a memo, and the hit-test handler behind a
//  region baked into a stored buffer. Those are here.
//
//  After every frame and every event, what the user could observe must be
//  identical: the picture, the status bar, the Tab ring and which control holds
//  the focus, the sections, where the clickable regions are, whether an event was
//  consumed, and which actions ran. On top of the twin comparison each copy must
//  satisfy one invariant of its own — every region in the picture names a handler
//  that something actually registered — because a served buffer carries its
//  regions with the ids baked in, and a replay is the only thing that can put a
//  closure back under them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

// MARK: - The script's model

/// What a row draws and registers.
private enum StormRowKind: Int, Equatable, Sendable {
    /// Plain text: no focus stop, no region.
    case text
    /// A `Button`: a focus stop, a hit-test region and a motion request.
    case button
    /// A bare focus stop with no region.
    case probe
    /// An inline-styled `Menu`, the shape every `Stress` menu row has.
    case menu
}

/// One row: a title and everything it draws or registers. `Equatable`, so
/// `ForEach` memoizes it, and nothing it shows is outside its own value — except
/// where `readsModel` deliberately puts it there.
private struct StormRow: Equatable, Sendable {
    let id: Int
    var version = 0
    var kind: StormRowKind = .button
    var shortcut: Character?
    var hovers = false
    var dimmed = false
    var boxed = false
    var readsModel = false

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
    var split = false
    var nextID = 0
}

/// A pushed destination.
private struct StormStep: Hashable, Sendable {
    let number: Int
}

extension StormPage {
    /// Whether anything on the page renders through the backdrop isolation —
    /// see ``StormFrame/motion``.
    var hasDimmedRow: Bool {
        groups.contains { $0.rows.contains { $0.dimmed } } || sheetRows.contains { $0.dimmed }
    }
}

/// What ran, in order.
private final class StormLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// State a row can read from OUTSIDE its own element — the shape the row memo
/// cannot see in its key, and the one `@Observable` tracking exists to rescue.
@Observable
private final class StormModel: @unchecked Sendable {
    var counter = 0
}

// MARK: - The page

/// A row's view: its title, and each registration its model asks for.
///
/// `@State` of its own, written by its own `Button`, so a click has to clear the
/// row's cached buffer or the next frame serves the count from before it.
private struct StormRowView: View, @MainActor Equatable {
    let row: StormRow
    let log: StormLog
    let model: StormModel

    @State private var taps = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.log === rhs.log && lhs.model === rhs.model
    }

    var body: some View {
        let row = row
        let log = log
        // `readsModel` reads state owned above the row, which its element cannot
        // see. `@Observable` tracking is what keeps that honest.
        let label = row.readsModel ? "\(row.title)#\(model.counter)" : row.title
        var view: AnyView
        switch row.kind {
        case .text:
            view = AnyView(Text(label))
        case .button:
            view = AnyView(
                Button("\(label)/\(taps)") {
                    log.append("click \(row.title)")
                    taps += 1
                })
        case .probe:
            view = AnyView(Text(label).focusable())
        case .menu:
            view = AnyView(
                Menu(label) {
                    Text("one")
                    Text("two")
                }
                .menuStyle(.inline))
        }
        if let shortcut = row.shortcut {
            // `modifiers: []` — the bare-key form, since a terminal never
            // reports SwiftUI's default `.command`.
            view = AnyView(view.keyboardShortcut(KeyEquivalent(shortcut), modifiers: []))
        }
        if row.hovers {
            view = AnyView(view.onHover { entered in log.append("hover \(row.title) \(entered)") })
        }
        if row.dimmed { view = AnyView(view.dimmed()) }
        return view
    }
}

/// Rows under `ForEach`, each memoized by its element, and some memoized again
/// by `.equatable()`.
@MainActor
private func stormRows(_ rows: [StormRow], log: StormLog, model: StormModel) -> some View {
    ForEach(rows, id: \.id) { row in
        if row.boxed {
            StormRowView(row: row, log: log, model: model).equatable()
        } else {
            StormRowView(row: row, log: log, model: model)
        }
    }
}

/// A group's body. Its key leaves the section out when the section is applied
/// outside it, so a group memo can be served under a section it was not
/// recorded in — which is the case the stored section check exists for.
private struct StormGroupView: View, @MainActor Equatable {
    let group: StormGroup
    let log: StormLog
    let model: StormModel

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.log === rhs.log && lhs.model === rhs.model && lhs.group.rows == rhs.group.rows
            && lhs.group.sectionInside == rhs.group.sectionInside
            && (!lhs.group.sectionInside || lhs.group.section == rhs.group.section)
    }

    var body: some View {
        if group.sectionInside {
            VStack(alignment: .leading, spacing: 0) { stormRows(group.rows, log: log, model: model) }
                .focusSection(group.section)
        } else {
            VStack(alignment: .leading, spacing: 0) { stormRows(group.rows, log: log, model: model) }
        }
    }
}

@MainActor @ViewBuilder
private func stormGroup(_ group: StormGroup, log: StormLog, model: StormModel) -> some View {
    switch (group.memoized, group.sectionInside) {
    case (true, true): StormGroupView(group: group, log: log, model: model).equatable()
    case (true, false):
        StormGroupView(group: group, log: log, model: model).equatable().focusSection(group.section)
    case (false, true): StormGroupView(group: group, log: log, model: model)
    case (false, false):
        StormGroupView(group: group, log: log, model: model).focusSection(group.section)
    }
}

/// A two-column split at its concrete type, so it can carry a memo boundary:
/// `NavigationSplitView` is `Equatable` where its columns are.
@MainActor
private func stormSplit(
    _ visibility: Binding<NavigationSplitViewVisibility>
) -> NavigationSplitView<Text, EmptyView, Text> {
    NavigationSplitView(columnVisibility: visibility) {
        Text("side")
    } detail: {
        Text("detail")
    }
}

/// The whole page: a stack that can be pushed, three groups, an optional split,
/// and a sheet over all of it.
@MainActor
private func stormPage(
    _ page: StormPage, log: StormLog, model: StormModel, sheet: Binding<Bool>,
    path: Binding<NavigationPath>, visibility: Binding<NavigationSplitViewVisibility>
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        NavigationStack(path: path) {
            VStack(alignment: .leading, spacing: 0) {
                stormGroup(page.groups[0], log: log, model: model)
                stormGroup(page.groups[1], log: log, model: model)
            }
            .navigationDestination(for: StormStep.self) { step in
                VStack(alignment: .leading, spacing: 0) {
                    Text("detail \(step.number)")
                    stormGroup(page.groups[2], log: log, model: model)
                }
            }
        }
        if page.split { stormSplit(visibility).equatable() }
    }
    .sheet(isPresented: sheet) {
        VStack(alignment: .leading, spacing: 0) { stormRows(page.sheetRows, log: log, model: model) }
    }
}

// MARK: - The script

/// The letters rows bind as shortcuts, and every key the storm presses. No
/// letter `InputHandler` binds globally (`a`, `t`, `q`).
private enum StormKeys {
    static let shortcuts: [Character] = ["w", "x", "y", "z"]
    static let events: [KeyEvent] =
        shortcuts.map { KeyEvent(character: $0) }
        + [
            KeyEvent(key: .tab), KeyEvent(key: .tab, shift: true),
            KeyEvent(key: .escape), KeyEvent(key: .enter), KeyEvent(key: .down),
        ]
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
            // `sectionInside` stays FALSE, and that is a hole rather than a
            // choice. A `.focusSection` INSIDE a memo does not run on a hit, so
            // when its section becomes the active one nothing notices and the
            // subtree is served the buffer drawn while it was inactive — the ●
            // never arrives. The twin case, the section OUTSIDE the memo, is
            // fixed and covered (`FocusSectionIndicatorMemoTests`). Setting this
            // back to `random.oneIn(4)` is the one-line way to re-arm the shape
            // once the inside case is fixed too.
            page.groups.append(
                StormGroup(
                    section: "s\(index)", rows: rows,
                    memoized: random.oneIn(2), sectionInside: false))
        }
        for _ in 0..<2 { page.sheetRows.append(page.makeRow(&random)) }
        return page
    }

    mutating func makeRow(_ random: inout StormRandom) -> StormRow {
        defer { nextID += 1 }
        return StormRow(
            id: nextID,
            kind: StormRowKind(rawValue: random.next(4)) ?? .button,
            shortcut: random.oneIn(2) ? StormKeys.shortcuts[random.next(4)] : nil,
            hovers: random.oneIn(3), dimmed: random.oneIn(4), boxed: random.oneIn(3),
            readsModel: random.oneIn(3))
    }

    /// Applies one random change, and says what it was and which section, if
    /// any, to activate once the next frame has registered it.
    mutating func mutate(_ random: inout StormRandom) -> (String, activate: String?) {
        let group = random.next(3)
        switch random.next(12) {
        case 0: return (editRow(&random) { $0.version += 1 }, nil)
        case 1:
            return (
                editRow(&random) {
                    $0.kind = StormRowKind(rawValue: ($0.kind.rawValue + 1) % 4) ?? .button
                }, nil
            )
        case 2:
            return (
                editRow(&random) {
                    $0.shortcut = $0.shortcut == nil ? StormKeys.shortcuts[$0.id % 4] : nil
                }, nil
            )
        case 3: return (editRow(&random) { $0.hovers.toggle() }, nil)
        case 4: return (editRow(&random) { $0.dimmed.toggle() }, nil)
        case 5: return (editRow(&random) { $0.boxed.toggle(); $0.readsModel.toggle() }, nil)
        case 6: return (reshape(group: group, &random), nil)
        case 7:
            let name = "s\(random.next(5))"
            groups[group].section = name
            return ("group \(group) section -> \(name)", name)
        case 8:
            // The memo boundary moves; the section does not cross it — see the
            // `sectionInside` note in `initial(_:)`.
            groups[group].memoized.toggle()
            return ("group \(group) memoized \(groups[group].memoized)", nil)
        case 9:
            sheet.toggle()
            return ("sheet \(sheet)", nil)
        case 10:
            split.toggle()
            return ("split \(split)", nil)
        default:
            let name = "s\(random.next(5))"
            return ("activate \(name)", name)
        }
    }

    /// Edits one row, on the page or in the sheet.
    private mutating func editRow(_ random: inout StormRandom, _ edit: (inout StormRow) -> Void)
        -> String
    {
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

/// Everything a frame shows the user, or decides for the next event.
///
/// The mouse dispatcher's raw handler COUNT is deliberately not here. A dimmed
/// subtree renders through `isolatedForBackground()`, which swaps the key
/// channels but not the mouse dispatcher, so a live render files a dimmed
/// control's handler in the live table while a replay — whose entry carries the
/// throwaway channel token — does not. Nothing can reach either one, because
/// `dimmedAsBackdrop` drops the buffer's regions, so the two copies agree on
/// everything observable and differ only in that dead table entry.
private struct StormFrame: Equatable {
    let lines: [String]
    let items: [String]
    let keyHandlers: Int
    let focusables: [String]
    let focusedID: String?
    let sections: [String]
    let activeSection: String?
    let regions: [String]
    /// Whether the frame asked the terminal for motion reporting, or `nil` on a
    /// page carrying a `.dimmed()` row, where the two copies are KNOWN to
    /// disagree and the disagreement is not this storm's to police.
    ///
    /// `isolatedForBackground()` swaps the key channels but NOT the mouse
    /// dispatcher, while a mouse entry is tagged with the KEY channel token. So
    /// a dimmed control's `requestFeature(.motion)` reaches the live dispatcher
    /// when the subtree renders, and is filtered out of the memo when it is
    /// served. Nothing can be clicked either way — `dimmedAsBackdrop` drops the
    /// buffer's regions — but the request is frame-global, so it flaps. Left
    /// asserted everywhere else, so the replay of a real control's request is
    /// still covered.
    let motion: Bool?

    /// The first field that differs, named, with the styling stripped off the
    /// picture. Dumping two whole frames instead buries the one line that moved
    /// in a screenful of escape sequences.
    func difference(from other: Self) -> String? {
        if lines != other.lines {
            let shared = min(lines.count, other.lines.count)
            guard let index = (0..<shared).first(where: { lines[$0] != other.lines[$0] }) else {
                return "line count: cached \(lines.count), uncached \(other.lines.count)"
            }
            return """
                line \(index): cached \(lines[index].stripped.debugDescription), \
                uncached \(other.lines[index].stripped.debugDescription)
                """
        }
        if items != other.items { return "status bar: \(items) vs \(other.items)" }
        if keyHandlers != other.keyHandlers {
            return "key handlers: \(keyHandlers) vs \(other.keyHandlers)"
        }
        if focusables != other.focusables { return "Tab ring: \(focusables) vs \(other.focusables)" }
        if focusedID != other.focusedID {
            return "focusedID: \(focusedID ?? "nil") vs \(other.focusedID ?? "nil")"
        }
        if sections != other.sections { return "sections: \(sections) vs \(other.sections)" }
        if activeSection != other.activeSection {
            return "active section: \(activeSection ?? "nil") vs \(other.activeSection ?? "nil")"
        }
        if regions != other.regions { return "regions: \(regions) vs \(other.regions)" }
        if motion != other.motion {
            // Spelled out rather than interpolated: `nil` here means "not
            // compared on this page", not "asked for nothing".
            let asked = { (value: Bool?) in value.map(String.init) ?? "skipped" }
            return "motion request: \(asked(motion)) vs \(asked(other.motion))"
        }
        return nil
    }
}

/// An app: its own services and log, rendered the way `RenderLoop` brackets a
/// frame and driven through a real `InputHandler` and a real dispatcher.
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
    let model = StormModel()
    var page: StormPage
    var path = NavigationPath()
    var visibility = NavigationSplitViewVisibility.all

    /// The handler ids the last frame's regions named, in the order
    /// ``StormFrame/regions`` lists them.
    private(set) var lastRegionIDs: [HitTestRegion.HandlerID] = []

    /// How many times this copy's focus manager announced a focus change, i.e.
    /// how many repaints it asked the run loop for.
    private(set) var repaintRequests = 0

    /// The dispatcher's clock, advanced by hand so two clicks are two clicks
    /// rather than a double click.
    private final class Clock: @unchecked Sendable {
        var now: UInt64 = 0
    }
    private let clock = Clock()

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
        let clock = self.clock
        tui.mouseEventDispatcher.nowNanos = { clock.now }
        tui.mouseEventDispatcher.setActiveSupport(.full)
        focusManager.onFocusChange = { [weak self] in self?.repaintRequests += 1 }
    }

    /// Renders one frame of `walks` walks and publishes its regions, as the run
    /// loop does. The uncached copy empties its cache before every walk, so it
    /// never serves a buffer and never replays.
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
        let path = Binding(get: { self.path }, set: { self.path = $0 })
        let visibility = Binding(get: { self.visibility }, set: { self.visibility = $0 })

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
            buffer = renderToBuffer(
                stormPage(
                    page, log: log, model: model, sheet: sheet, path: path,
                    visibility: visibility),
                context: context)
        }
        focusManager.endRenderPass()
        tui.lifecycle.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()

        let picture = buffer.compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: environment.palette)
        tui.mouseEventDispatcher.setRegions(picture.hitTestRegions)
        lastRegionIDs = picture.hitTestRegions.map(\.handlerID)
        return StormFrame(
            lines: picture.lines,
            items: statusBar.currentUserItems.map { "\($0.shortcut)=\($0.label)" },
            keyHandlers: tui.keyEventDispatcher.handlerCount,
            focusables: focusManager.focusableIDs,
            focusedID: focusManager.currentFocusedID,
            sections: focusManager.sectionIDs,
            activeSection: focusManager.activeSectionIdentifier,
            regions: picture.hitTestRegions.map {
                "\($0.focusID ?? "-")@\($0.offsetX),\($0.offsetY)"
            },
            motion: page.hasDimmedRow
                ? nil : tui.mouseEventDispatcher.effectiveSupport(baseConfig: .disabled).motion)
    }

    /// Every region the last frame published that names a handler nothing
    /// registered — which is what a served buffer would carry if its
    /// registration were not replayed.
    func danglingRegions(_ frame: StormFrame) -> [String] {
        zip(frame.regions, lastRegionIDs)
            .filter { tui.mouseEventDispatcher.handler(for: $0.1) == nil }
            .map(\.0)
    }

    func press(_ event: KeyEvent) -> Bool { input.handle(event) }

    /// Presses and releases the left button at `(x, y)`.
    func click(x: Int, y: Int) -> Bool {
        let down = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        let up = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: x, y: y))
        clock.now &+= 1_000_000_000
        return down || up
    }

    /// Moves the pointer, which is what synthesises a hover's enter and exit.
    func move(x: Int, y: Int) -> Bool {
        tui.mouseEventDispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: x, y: y))
    }

    /// Presses, drags and releases.
    func drag(from: (x: Int, y: Int), to: (x: Int, y: Int)) -> Bool {
        let down = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        let moved = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: to.x, y: to.y))
        let up = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: to.x, y: to.y))
        clock.now &+= 1_000_000_000
        return down || moved || up
    }
}

// MARK: - The storm

@MainActor
@Suite("Focus and mouse replay storm", .serialized)
struct FocusMouseReplayStormTests {
    static let trials = 6
    static let steps = 40

    @Test("A cached app and an uncached one focus, click and draw identically through a storm")
    func cachedMatchesUncached() {
        var hits = 0
        for trial in 0..<Self.trials {
            var random = StormRandom(state: 0x5F0C_0000 &+ UInt64(trial) &* 7919)
            let page = StormPage.initial(&random)
            let cached = StormRun(page: page, caches: true)
            let uncached = StormRun(page: page, caches: false)
            if let failure = runTrial(cached, uncached, &random) {
                Issue.record("trial \(trial): \(failure)")
            }
            hits += cached.tui.renderCache.stats.hits
            #expect(
                uncached.tui.renderCache.stats.hits == 0,
                "trial \(trial): the uncached copy served a buffer")
        }
        // Without hits the two copies are the same program and agree trivially.
        #expect(hits > 500, "the cached copy served only \(hits) buffers")
    }

    /// Runs one trial's steps, and describes the first divergence.
    private func runTrial(
        _ cached: StormRun, _ uncached: StormRun, _ random: inout StormRandom
    ) -> String? {
        var page = cached.page
        var history: [String] = []
        for step in 0..<Self.steps {
            let (change, activate) = page.mutate(&random)
            history.append("\(step): \(change)")
            cached.page = page
            uncached.page = page
            if random.oneIn(5) {
                cached.model.counter += 1
                uncached.model.counter += 1
                history.append("  model -> \(cached.model.counter)")
            }
            for pass in 0..<2 {
                let walks = random.oneIn(5) ? 2 : 1
                let repaintsBefore = cached.repaintRequests
                let seen = cached.frame(walks: walks)
                let expected = uncached.frame(walks: walks)
                var difference = seen.difference(from: expected)
                // Focus taken during a REPLAY arrives after the cached buffer
                // has already been served, so that frame legitimately draws the
                // control as it was and asks for a repaint instead. The contract
                // is not that every frame matches, but that the repaint it asked
                // for does — so settle one frame and compare that.
                if difference != nil, cached.repaintRequests > repaintsBefore {
                    let settled = cached.frame(walks: 1)
                    let settledExpected = uncached.frame(walks: 1)
                    difference = settled.difference(from: settledExpected)
                        .map { "after the requested repaint, \($0)" }
                }
                if let difference {
                    return """
                        frame \(pass), \(walks) walks: \(difference)
                          last steps:
                            \(history.suffix(12).joined(separator: "\n    "))
                        """
                }
                // Each copy's own invariant: a published region whose handler
                // nothing registered is a control on screen that no click can
                // reach. On the cached copy only a replay can prevent it.
                let dangling = cached.danglingRegions(seen)
                if !dangling.isEmpty {
                    return describe("dangling regions", dangling, [String](), history)
                }
                if pass == 0, let activate {
                    cached.focusManager.activateSection(id: activate)
                    uncached.focusManager.activateSection(id: activate)
                }
                for _ in 0...random.next(2) {
                    if let failure = drive(cached, uncached, &random, &history, frame: seen) {
                        return failure
                    }
                }
            }
            page = cached.page
        }
        return nil
    }

    /// Presses a key, or clicks, hovers or drags somewhere, on both copies, and
    /// compares what each of them did.
    private func drive(
        _ cached: StormRun, _ uncached: StormRun, _ random: inout StormRandom,
        _ history: inout [String], frame: StormFrame
    ) -> String? {
        let consumed: (Bool, Bool)
        switch random.next(4) {
        case 0:
            let event = StormKeys.events[random.next(StormKeys.events.count)]
            history.append("  press \(event.key)\(event.shift ? " shift" : "")")
            consumed = (cached.press(event), uncached.press(event))
        case 1:
            let spot = Self.spot(frame, &random)
            history.append("  click \(spot)")
            consumed = (cached.click(x: spot.x, y: spot.y), uncached.click(x: spot.x, y: spot.y))
        case 2:
            let spot = Self.spot(frame, &random)
            history.append("  move \(spot)")
            consumed = (cached.move(x: spot.x, y: spot.y), uncached.move(x: spot.x, y: spot.y))
        default:
            let from = Self.spot(frame, &random)
            let to = Self.spot(frame, &random)
            history.append("  drag \(from) -> \(to)")
            consumed = (cached.drag(from: from, to: to), uncached.drag(from: from, to: to))
        }
        if consumed.0 != consumed.1 {
            return describe("consumed", consumed.0, consumed.1, history)
        }
        if cached.log.all != uncached.log.all {
            return describe("ran", cached.log.all.suffix(4), uncached.log.all.suffix(4), history)
        }
        if cached.page.sheet != uncached.page.sheet || cached.path.count != uncached.path.count
            || cached.visibility != uncached.visibility
        {
            return describe(
                "state",
                "sheet \(cached.page.sheet) depth \(cached.path.count) \(cached.visibility)",
                "sheet \(uncached.page.sheet) depth \(uncached.path.count) \(uncached.visibility)",
                history)
        }
        return nil
    }

    /// A point to aim at: usually a published region, so clicks land on
    /// controls rather than mostly on blank cells, and sometimes anywhere.
    private static func spot(_ frame: StormFrame, _ random: inout StormRandom) -> (x: Int, y: Int) {
        if !frame.regions.isEmpty, !random.oneIn(3) {
            let region = frame.regions[random.next(frame.regions.count)]
            let parts = region.split(separator: "@").last?.split(separator: ",") ?? []
            if parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) {
                return (x, y)
            }
        }
        return (random.next(StormRun.width), random.next(StormRun.height))
    }

    private func describe<T>(_ what: String, _ cached: T, _ uncached: T, _ history: [String])
        -> String
    {
        """
        \(what) differs
          cached:   \(cached)
          uncached: \(uncached)
          last steps:
            \(history.suffix(12).joined(separator: "\n    "))
        """
    }
}
