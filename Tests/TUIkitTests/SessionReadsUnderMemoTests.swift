//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SessionReadsUnderMemoTests.swift
//
//  What a view reads from a per-app SESSION while it renders — the drag in
//  flight, the tooltip being hovered — is state no memo keys on and no `@State`
//  write reports. So is what a control draws from its own HANDLER object when
//  an input moves it without focusing the control: the gap a drag from
//  elsewhere opens in a list, the offset the wheel scrolls, the scrollbar
//  arrow the pointer lifts, the grip it lights on a resizable view's edge. A
//  row memoized above such a read was served as it was stored when the state
//  moved. Each test here plays one gesture against
//  two apps, one keeping its render cache and one emptying it before every
//  frame, and holds them to drawing the same thing, styling included, on every
//  frame: the oracle the Stress sessions use, for gestures no session plays.
//  The gestures whose state IS written where the cache sees it — a hover face,
//  a list reorder, a menu — are pinned beside them as controls.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitView

/// One script, played against an app that keeps its render cache and one that
/// empties it before every frame.
@MainActor
private final class Twin<A: App> {
    let warm: HeadlessApp<A>
    let cold: HeadlessApp<A>
    /// On the monotonic clock's own scale, so a deadline a session counts from
    /// `FrameClock.nowNanos` — a tooltip's delay — falls among these frames.
    private(set) var now = FrameClock.nowNanos
    /// Every frame on which the two drew different screens, described.
    private(set) var divergences: [String] = []
    private var frames = 0

    init(_ make: () -> A, width: Int = 60, height: Int = 16) {
        warm = HeadlessApp(make(), width: width, height: height)
        cold = HeadlessApp(make(), width: width, height: height)
        cold.clearsRenderCacheEachFrame = true
        frame()
    }

    /// One frame of each, 1/60 s after the last, compared.
    func frame() {
        now += 16_666_667
        frames += 1
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(frames) / 60)
        warm.frame(atNanos: now, date: date)
        cold.frame(atNanos: now, date: date)
        // Styled, not stripped: a scrollbar lit under the pointer is the same
        // text in other colours.
        let (w, c) = (warm.screen, cold.screen)
        guard w != c, let row = w.indices.first(where: { $0 >= c.count || w[$0] != c[$0] }) else { return }
        let (kept, wanted) = (w[row].stripped, row < c.count ? c[row].stripped : "")
        let styled = kept == wanted ? " (the same text, styled differently)" : ""
        divergences.append("frame \(frames), row \(row)\(styled): kept \"\(kept)\", cold \"\(wanted)\"")
    }

    func frames(_ count: Int) {
        for _ in 0..<count { frame() }
    }

    /// Delivers `event` to both.
    func send(_ event: MouseEvent) {
        _ = warm.send(event)
        _ = cold.send(event)
    }

    /// Where `text` first appears on the cold screen: column and row.
    func position(of text: String) -> (x: Int, y: Int)? {
        for (row, line) in cold.screen.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (line.distance(from: line.startIndex, to: range.lowerBound), row)
            }
        }
        return nil
    }
}

// MARK: - The pages

private struct Card: Identifiable, Equatable {
    let id: Int
    var title: String { "card \(id)" }
}

private let cards = (0..<4).map(Card.init(id:))

/// A column of draggable cards, each a `ForEach` row memoized by its card, over
/// a zone that takes whatever is dropped on it.
private struct CardsApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards) { card in
                    Text(verbatim: card.title).draggable(card.title)
                }
                Spacer()
                Text("drop zone").dropDestination(for: String.self) { _, _ in
                    Drops.taken += 1
                    return true
                }
            }
        }
    }
}

/// How many drops the zones have taken, in every app.
@MainActor
private enum Drops {
    static var taken = 0
}

/// A column of rows with help text, shown in `style` once the pointer rests on
/// the row it explains.
private struct HelpApp: App {
    let style: TooltipStyle

    init() { self.init(style: .popover) }

    init(style: TooltipStyle) { self.style = style }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards) { card in
                    Text(verbatim: card.title).help("about \(card.title)")
                }
                Spacer()
            }
            .tooltipStyle(style)
        }
        // Motion reporting, which a live app turns on for the frame after a
        // view asks; a headless one applies only what the scene says.
        .mouseSupport(.full)
    }
}

/// A column of buttons, each lit by the pointer over it.
private struct ButtonsApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards) { card in
                    Button(card.title) {}
                }
                Spacer()
            }
        }
        .mouseSupport(.full)
    }
}

/// Two columns of cards, each a `ForEach` row memoized by its column, holding
/// a list the pointer reorders.
private struct ColumnsApp: App {
    var body: some Scene {
        WindowGroup {
            HStack(alignment: .top, spacing: 1) {
                ForEach(["left", "right"], id: \.self) { title in
                    ReorderColumn(title: title)
                }
            }
        }
    }
}

private struct ReorderColumn: View {
    let title: String
    @State private var items = ["a", "b", "c", "d"]

    var body: some View {
        List {
            ForEach(items, id: \.self) { Text(verbatim: "\(title) \($0)") }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        }
        .frame(width: 20, height: 8)
    }
}

/// A card beside three columns, each a `ForEach` row memoized by its title,
/// holding a list or a table whose rows take a drop between them. The "idle"
/// column's drop takes nothing, so only the gap tells a drop happened there.
private struct BoardApp: App {
    let table: Bool
    /// Rows per column: four fit, twelve scroll.
    let rows: Int

    init() { self.init(table: false) }

    init(table: Bool, rows: Int = 4) {
        self.table = table
        self.rows = rows
    }

    var body: some Scene {
        WindowGroup {
            HStack(alignment: .top, spacing: 1) {
                Text("card X").draggable("card X")
                ForEach(["left", "right", "idle"], id: \.self) { title in
                    DropColumn(title: title, table: table, rows: rows)
                }
            }
        }
    }
}

private struct Named: Identifiable, Hashable {
    let id: String
}

private struct DropColumn: View {
    let title: String
    let table: Bool
    @State private var items: [String]

    init(title: String, table: Bool, rows: Int) {
        self.title = title
        self.table = table
        _items = State(initialValue: (0..<rows).map { String(UnicodeScalar(UInt8(97 + $0))) })
    }

    private func take(_ values: [String], at index: Int) {
        guard title != "idle" else { return }
        items.insert(contentsOf: values, at: index)
    }

    var body: some View {
        if table {
            Table(items.map(Named.init(id:))) {
                TableColumn("Name") { (item: Named) in "\(title) \(item.id)" }
            }
            .dropDestination(for: String.self) { take($1, at: $0) }
            .frame(width: 20, height: 9)
        } else {
            List {
                ForEach(items, id: \.self) { Text(verbatim: "\(title) \($0)") }
                    .dropDestination(for: String.self) { take($1, at: $0) }
            }
            .frame(width: 20, height: 8)
        }
    }
}

/// Which scrollable ``ScrollersApp`` puts in each column.
enum ScrollerKind: CaseIterable, Sendable {
    case list, table, scrollView
    /// A scroll view that pages from its "N more" lines.
    case textIndicators
    /// A scroll view that scrolls sideways, with a bar along its bottom.
    case sideways
}

/// Two columns, each a `ForEach` row memoized by its title, holding a
/// scrollable taller than its frame. The left one takes the focus, so the
/// right one's column is stored.
private struct ScrollersApp: App {
    let kind: ScrollerKind

    init() { self.init(kind: .list) }

    init(kind: ScrollerKind) { self.kind = kind }

    var body: some Scene {
        WindowGroup {
            HStack(alignment: .top, spacing: 1) {
                ForEach(["left", "right"], id: \.self) { title in
                    ScrollerColumn(title: title, kind: kind)
                }
            }
        }
        // Motion reporting, for the scrollbar's lift.
        .mouseSupport(.full)
    }
}

/// One scrollable, alone on the page: no `ForEach` row or other memo around
/// it.
private struct BareScrollerApp: App {
    let kind: ScrollerKind

    init() { self.init(kind: .list) }

    init(kind: ScrollerKind) { self.kind = kind }

    var body: some Scene {
        WindowGroup {
            ScrollerColumn(title: "bare", kind: kind)
        }
        .mouseSupport(.full)
    }
}

private struct ScrollerColumn: View {
    let title: String
    let kind: ScrollerKind

    private var rows: [Named] { (0..<20).map { Named(id: "\(title) \($0)") } }

    var body: some View {
        switch kind {
        case .list:
            List {
                ForEach(rows) { Text(verbatim: $0.id) }
            }
            .frame(width: 20, height: 8)
        case .table:
            Table(rows) {
                TableColumn("Name") { (row: Named) in row.id }
            }
            .frame(width: 20, height: 9)
        case .scrollView:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { Text(verbatim: $0.id) }
                }
            }
            .frame(width: 20, height: 8)
        case .textIndicators:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { Text(verbatim: $0.id) }
                }
            }
            .scrollIndicatorStyle(.text)
            .frame(width: 20, height: 8)
        case .sideways:
            ScrollView(.horizontal) {
                Text(verbatim: "\(title) " + String(repeating: "-", count: 60))
            }
            .frame(width: 20, height: 3)
        }
    }
}

/// A column of cards, each a `ForEach` row memoized by its card, that the
/// pointer can resize by an edge or the corner.
private struct ResizableApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards) { card in
                    Text(verbatim: card.title).frame(width: 12, height: 2).userResizable()
                }
                Spacer()
            }
        }
        // Motion reporting, for the grip's lift.
        .mouseSupport(.full)
    }
}

/// A column of rows, each with a menu and a context menu.
private struct MenusApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards) { card in
                    HStack(spacing: 1) {
                        Menu("menu \(card.id)") {
                            Button("one") {}
                            Button("two") {}
                        }
                        Text(verbatim: "ctx \(card.id)")
                            .contextMenu {
                                Button("three") {}
                            }
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - The gestures

@MainActor
@Suite("What a view reads from a session is drawn as a cold frame draws it")
struct SessionReadsUnderMemoTests {
    /// A card being carried has left its place: it floats at the pointer, and
    /// the row it came from draws blank. The blanking asks the drag session,
    /// which nothing the row memo keys on reports, so a memoized row went on
    /// drawing the card beside its own floating preview — and, stored blank
    /// while the drag lasted, went on drawing nothing once it was over.
    ///
    /// Both ends: released over nothing, the preview flies home and the row
    /// stays blank until it lands; released over the zone, the drop is taken
    /// and the row is drawn again at once.
    @Test(
        "A card drawn blank while it is carried, and drawn again once it is home",
        arguments: [false, true])
    func draggedCard(dropped: Bool) throws {
        let twin = Twin(CardsApp.init)
        twin.frames(3)
        let card = try #require(twin.position(of: "card 1"))
        let zone = try #require(twin.position(of: "drop zone"))
        let x = card.x + 2
        let end = dropped ? zone : (x: x, y: card.y + 8)
        twin.send(MouseEvent(button: .left, phase: .pressed, x: x, y: card.y))
        twin.frame()
        for step in 1...4 {
            let y = card.y + (end.y - card.y) * step / 4
            twin.send(MouseEvent(button: .left, phase: .dragged, x: dropped ? zone.x + 2 : x, y: y))
            twin.frame()
        }
        let takenBefore = Drops.taken
        twin.send(MouseEvent(button: .left, phase: .released, x: dropped ? zone.x + 2 : x, y: end.y))
        #expect(
            Drops.taken - takenBefore == (dropped ? 2 : 0),
            "precondition: the drop is taken exactly when it lands on the zone")
        twin.frames(24)
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
        #expect(twin.warm.screen.map(\.stripped).contains { $0.contains("card 1") }, "the card never came back")
    }

    /// A tooltip appears once the pointer has rested on the view it explains.
    /// The hover lands in the tooltip session, which no memo keys on, so a row
    /// memoized above the view was served as stored: no wake declared for the
    /// end of the delay — the run loop slept past it — and, as a popover, no
    /// popover when a frame came anyway.
    ///
    /// The wake is asked of each app's scheduler, because a harness draws
    /// whenever it is told to and so cannot see a frame the app would not have
    /// drawn; in the status bar, where the loop draws the tooltip itself, the
    /// wake is all there is to lose.
    @Test(
        "A tooltip appears over a memoized row the pointer rests on, on time",
        arguments: [TooltipStyle.popover, .statusBar])
    func helpTooltip(style: TooltipStyle) throws {
        let twin = Twin { HelpApp(style: style) }
        twin.frames(3)
        let row = try #require(twin.position(of: "card 2"))
        twin.send(MouseEvent(button: .none, phase: .moved, x: row.x + 1, y: row.y))
        twin.frame()
        // The delay runs from the hover's own arrival, on the real clock, and
        // the two apps took it microseconds apart: the same wake, to a
        // millisecond.
        let coldWake = try #require(twin.cold.nextWake(after: twin.now), "precondition: the cold app asks to be woken")
        let warmWake = twin.warm.nextWake(after: twin.now)
        #expect(
            warmWake.map { abs($0 - coldWake) < 1_000_000 } == true,
            "the kept app did not ask to be woken for the tooltip: \(String(describing: warmWake)) against \(coldWake)")
        twin.frames(60)
        #expect(
            twin.cold.screen.map(\.stripped).contains { $0.contains("about card 2") },
            "precondition: the cold app shows the tooltip, or this proves nothing")
        twin.send(MouseEvent(button: .none, phase: .moved, x: row.x + 1, y: row.y + 6))
        twin.frames(10)
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// A drag from elsewhere hovering a list opens a gap where it would land.
    /// The slot is the list's handler's, moved by the drop target's hover:
    /// neither a `@State` write nor anything a memo keys on. A list that does
    /// not hold the focus makes only replayable registrations, so the column
    /// around it is stored, and was served as it was stored — the rows closed
    /// up under the pointer while the drop still landed between them.
    ///
    /// Every way the slot moves: the pointer arriving over a row, leaving the
    /// list, and a drop the app takes nothing from, whose gap closes with no
    /// `@State` write to redraw the list. The table variant is the same code
    /// in `Table`.
    @Test("A drag from elsewhere opens and closes its gap in a list inside a memoized row", arguments: [false, true])
    func externalDropGap(table: Bool) throws {
        let twin = Twin({ BoardApp(table: table) }, width: 72, height: 14)
        twin.frames(3)
        let card = try #require(twin.position(of: "card X"))
        let right = try #require(twin.position(of: "right b"))
        let idle = try #require(twin.position(of: "idle b"))
        let home = (x: card.x + 2, y: card.y)
        twin.send(MouseEvent(button: .left, phase: .pressed, x: home.x, y: home.y))
        twin.frame()
        drag(twin, from: home, to: (right.x + 2, right.y))
        #expect(
            twin.position(of: "right b")?.y == right.y + 1,
            "precondition: the cold app opened the gap above the row, or this proves nothing")
        drag(twin, from: (right.x + 2, right.y), to: home)
        #expect(
            twin.position(of: "right b")?.y == right.y,
            "precondition: the cold app closed the gap when the pointer left, or this proves nothing")
        drag(twin, from: home, to: (idle.x + 2, idle.y))
        twin.send(MouseEvent(button: .left, phase: .released, x: idle.x + 2, y: idle.y))
        twin.frames(3)
        #expect(
            twin.position(of: "idle b")?.y == idle.y && twin.position(of: "card X")?.y == card.y,
            "precondition: the idle column took nothing and closed its gap, or this proves nothing")
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// Carries the held button from `start` to `end` in four steps, a frame
    /// after each, and two more once it is there.
    private func drag<A: App>(_ twin: Twin<A>, from start: (x: Int, y: Int), to end: (x: Int, y: Int)) {
        for step in 1...4 {
            let x = start.x + (end.x - start.x) * step / 4
            let y = start.y + (end.y - start.y) * step / 4
            twin.send(MouseEvent(button: .left, phase: .dragged, x: x, y: y))
            twin.frame()
        }
        twin.frames(2)
    }

    /// The wheel scrolls whatever it is over, focused or not. The offset it
    /// moves is the scrollable's handler's, which is no `@State` write, and a
    /// scrollable that does not hold the focus makes only replayable
    /// registrations: the column around it was stored, and served unscrolled
    /// for as long as the wheel turned.
    @Test(
        "The wheel scrolls a scrollable that does not hold the focus inside a memoized row",
        arguments: [ScrollerKind.list, .table, .scrollView, .textIndicators])
    func wheelOverUnfocusedScroller(kind: ScrollerKind) throws {
        let twin = Twin({ ScrollersApp(kind: kind) }, width: 50, height: 14)
        twin.frames(3)
        let row = try #require(twin.position(of: "right 2"))
        for _ in 0..<3 {
            twin.send(MouseEvent(button: .scrollDown, phase: .pressed, x: row.x + 2, y: row.y))
            twin.frame()
        }
        twin.send(MouseEvent(button: .scrollUp, phase: .pressed, x: row.x + 2, y: row.y))
        twin.frames(2)
        #expect(
            twin.position(of: "right 2")?.y != row.y,
            "precondition: the cold app scrolled, or this proves nothing")
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// The report the wheel makes is for a memo that might have stored the
    /// scrollable, and each one walks the whole cache. With no memo around the
    /// scrollable — held focused or not — there is nothing to drop, and the
    /// wheel reports nothing; inside a memoized row it reports each tick that
    /// moved it (the control, so that the count is the report's).
    @Test(
        "The wheel reports only a scrollable a memo could have stored",
        arguments: [ScrollerKind.list, .table, .scrollView], [false, true])
    func wheelReportsOnlyUnderAMemo(kind: ScrollerKind, underMemo: Bool) throws {
        func reported<A: App>(_ twin: Twin<A>, at title: String) throws -> Int {
            twin.frames(3)
            let row = try #require(twin.position(of: "\(title) 2"))
            var reports = 0
            for _ in 0..<3 {
                let before = twin.warm.renderCache.stats.subtreeClears
                twin.send(MouseEvent(button: .scrollDown, phase: .pressed, x: row.x + 2, y: row.y))
                reports += twin.warm.renderCache.stats.subtreeClears - before
                twin.frame()
            }
            #expect(
                twin.position(of: "\(title) 2")?.y != row.y,
                "precondition: the cold app scrolled, or this proves nothing")
            #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
            return reports
        }
        if underMemo {
            let reports = try reported(Twin({ ScrollersApp(kind: kind) }, width: 50, height: 14), at: "right")
            #expect(reports == 3, "the wheel under a memo reported \(reports) of its 3 ticks")
        } else {
            let reports = try reported(Twin({ BareScrollerApp(kind: kind) }, width: 50, height: 14), at: "bare")
            #expect(reports == 0, "the wheel over a scrollable no memo holds walked the cache \(reports) times")
        }
    }

    /// The pointer over a scroll view's scrollbar lifts the arrow under it —    /// The pointer over a scroll view's scrollbar lifts the arrow under it —
    /// the handler's hovered cell, set by the bar's own handler as the pointer
    /// passes, and another write the render cache never heard. Both bars: the
    /// vertical one's up arrow, and the sideways one's left arrow.
    @Test(
        "A scroll view's scrollbar arrow lifts under the pointer inside a memoized row",
        arguments: [false, true])
    func scrollbarLiftsUnderThePointer(sideways: Bool) throws {
        let twin = Twin({ ScrollersApp(kind: sideways ? .sideways : .scrollView) }, width: 50, height: 14)
        twin.frames(3)
        let (arrow, x, y) = try arrowOfTheRightScrollView(in: twin, sideways: sideways)
        let resting = twin.cold.screen
        twin.send(MouseEvent(button: .none, phase: .moved, x: x + (sideways ? 1 : -1), y: y + (sideways ? -1 : 1)))
        twin.frame()
        twin.send(MouseEvent(button: .none, phase: .moved, x: x, y: y))
        twin.frames(2)
        #expect(
            twin.cold.screen != resting,
            "precondition: the cold app lifted the \(arrow) arrow, or this proves nothing")
        twin.send(MouseEvent(button: .none, phase: .moved, x: x + (sideways ? 1 : -1), y: y + (sideways ? -1 : 1)))
        twin.frames(2)
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// Where the right-hand scroll view draws its up arrow — or, `sideways`,
    /// its left arrow — on the cold screen.
    private func arrowOfTheRightScrollView(
        in twin: Twin<ScrollersApp>, sideways: Bool
    ) throws -> (arrow: Character, x: Int, y: Int) {
        let arrow: Character = sideways ? "◀" : "▲"
        let top = try #require(twin.position(of: "right"))
        let lines = twin.cold.screen.map(\.stripped)
        for y in top.y..<lines.count {
            let line = lines[y]
            guard let index = line.lastIndex(of: arrow) else { continue }
            let x = line.distance(from: line.startIndex, to: index)
            if x >= top.x - 1 { return (arrow, x, y) }
        }
        Issue.record("precondition: the right scroll view draws its \(arrow) arrow")
        throw CancellationError()
    }

    /// A click on a scroll view's "N lines below" line pages it — without
    /// focusing it, so the page it lands on was never drawn inside a memoized
    /// row.
    @Test("A click on a scroll view's \"lines below\" line pages it inside a memoized row")
    func textIndicatorPages() throws {
        let twin = Twin({ ScrollersApp(kind: .textIndicators) }, width: 50, height: 14)
        twin.frames(3)
        let top = try #require(twin.position(of: "right 0"))
        let lines = twin.cold.screen.map(\.stripped)
        let belowY = try #require(
            lines.indices.dropFirst(top.y).first { lines[$0].contains("below") },
            "precondition: the right scroll view draws a \"lines below\" line")
        let below = (x: top.x + 2, y: belowY)
        twin.send(MouseEvent(button: .left, phase: .pressed, x: below.x, y: below.y))
        twin.frame()
        twin.send(MouseEvent(button: .left, phase: .released, x: below.x, y: below.y))
        twin.frames(2)
        #expect(
            twin.position(of: "right 0") == nil,
            "precondition: the cold app paged the scroll view, or this proves nothing")
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// A drag held at the edge of a list scrolls it, to bring the rows past the
    /// edge within reach. A drag from elsewhere does not focus the list, and
    /// the tick that scrolls it is no `@State` write, so the column around it
    /// was served unscrolled while the cold app's rows streamed past.
    @Test(
        "A drag held at the edge of a list inside a memoized row scrolls it",
        arguments: [false, true])
    func dragAutoScroll(table: Bool) throws {
        let twin = Twin({ BoardApp(table: table, rows: 12) }, width: 72, height: 14)
        twin.frames(3)
        let card = try #require(twin.position(of: "card X"))
        let right = try #require(twin.position(of: "right b"))
        let home = (x: card.x + 2, y: card.y)
        twin.send(MouseEvent(button: .left, phase: .pressed, x: home.x, y: home.y))
        twin.frame()
        // Onto the rows, then down to the last line of them, and held there.
        drag(twin, from: home, to: (right.x + 2, right.y))
        let edge = (x: right.x + 2, y: right.y + (table ? 5 : 5))
        drag(twin, from: (right.x + 2, right.y), to: edge)
        twin.frames(60)
        #expect(
            twin.position(of: "right a") == nil,
            "precondition: the cold app scrolled the list under the held drag, or this proves nothing")
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
        twin.send(MouseEvent(button: .left, phase: .released, x: edge.x, y: edge.y))
        twin.frames(3)
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// The pointer on a resizable view's edge or corner lights its grip — the
    /// resize handler's hover, set by the edge's own handler as the pointer
    /// arrives, which is no `@State` write. An unfocused resizable view makes
    /// only replayable registrations, so the card's row was stored and served
    /// with the grip at rest.
    @Test("A resizable view's grip lights under the pointer inside a memoized row")
    func resizeGripLightsUnderThePointer() throws {
        let twin = Twin(ResizableApp.init)
        twin.frames(3)
        let card = try #require(twin.position(of: "card 2"))
        let resting = twin.cold.screen
        // The corner: eleven cells along the twelve-wide frame, on its second line.
        twin.send(MouseEvent(button: .none, phase: .moved, x: card.x + 11, y: card.y + 1))
        twin.frames(3)
        #expect(twin.cold.screen != resting, "precondition: the cold app lit the grip, or this proves nothing")
        twin.send(MouseEvent(button: .none, phase: .moved, x: card.x + 20, y: card.y + 1))
        twin.frames(3)
        #expect(twin.cold.screen == resting, "precondition: the cold app put the grip back to rest")
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// A button's hover face is the button's own state, written as the pointer
    /// arrives — a write the render cache sees. Pinned as a control.
    @Test("A button's hover face follows the pointer through a memoized row")
    func hoveredButton() throws {
        let twin = Twin(ButtonsApp.init)
        twin.frames(3)
        let button = try #require(twin.position(of: "card 3"))
        twin.send(MouseEvent(button: .none, phase: .moved, x: button.x + 1, y: button.y))
        twin.frames(3)
        twin.send(MouseEvent(button: .none, phase: .moved, x: button.x + 1, y: button.y + 6))
        twin.frames(3)
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// A row lifted out of a list and carried to another place: the gap it
    /// leaves, the slot it would land in and the lifted picture are the list's
    /// handler's, which the drag moves every step. Pinned as a control.
    @Test("A list reordered by the pointer inside a memoized row draws each step of the drag")
    func reorderedList() throws {
        let twin = Twin(ColumnsApp.init, width: 50, height: 14)
        twin.frames(3)
        let row = try #require(twin.position(of: "right b"))
        let x = row.x + 2
        twin.send(MouseEvent(button: .left, phase: .pressed, x: x, y: row.y))
        twin.frame()
        for step in 1...3 {
            twin.send(MouseEvent(button: .left, phase: .dragged, x: x, y: row.y + step))
            twin.frame()
        }
        twin.send(MouseEvent(button: .left, phase: .released, x: x, y: row.y + 3))
        twin.frames(20)
        #expect(
            twin.position(of: "right b")?.y != row.y,
            "precondition: the cold app moved the row, or this proves nothing")
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }

    /// A menu opened by a click, and a context menu by the right button, from
    /// a memoized row, and closed again. Pinned as controls.
    @Test("Menus opened from a memoized row draw open, and closed again")
    func menus() throws {
        let twin = Twin(MenusApp.init)
        twin.frames(3)
        let menu = try #require(twin.position(of: "menu 1"))
        twin.send(MouseEvent(button: .left, phase: .pressed, x: menu.x + 1, y: menu.y))
        twin.frame()
        twin.send(MouseEvent(button: .left, phase: .released, x: menu.x + 1, y: menu.y))
        twin.frames(3)
        #expect(
            twin.cold.screen.map(\.stripped).contains { $0.contains("one") },
            "precondition: the cold app shows the menu open, or this proves nothing")
        _ = twin.warm.send(KeyEvent(key: .escape))
        _ = twin.cold.send(KeyEvent(key: .escape))
        twin.frames(3)
        let context = try #require(twin.position(of: "ctx 2"))
        twin.send(MouseEvent(button: .right, phase: .pressed, x: context.x + 1, y: context.y))
        twin.frame()
        twin.send(MouseEvent(button: .right, phase: .released, x: context.x + 1, y: context.y))
        twin.frames(3)
        #expect(
            twin.cold.screen.map(\.stripped).contains { $0.contains("three") },
            "precondition: the cold app shows the context menu open, or this proves nothing")
        _ = twin.warm.send(KeyEvent(key: .escape))
        _ = twin.cold.send(KeyEvent(key: .escape))
        twin.frames(3)
        #expect(twin.divergences.isEmpty, "\(twin.divergences.prefix(4))")
    }
}
