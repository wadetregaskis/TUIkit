//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TimelineCollectionWidthTests.swift
//
//  A live `TimelineView` in every row of a collection — a log with a "5 min
//  ago" on each line. Its measure says the clock can move its size, so no memo
//  keeps that size for good. The two memos that keep ONE width for the whole
//  collection, a windowed stack's widest row and a hugging `List`'s, keep it
//  until the next entry instead: refused, they walked every row on every frame,
//  and kept for good, they held the width the first entry measured. And each
//  says so when it serves what it kept, or a memo around it keeps it for good.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// How many times each row was built.
@MainActor
private final class RowBuilds {
    private(set) var byRow: [Int: Int] = [:]
    func note(_ index: Int) { byRow[index, default: 0] += 1 }
    func reset() { byRow = [:] }
}

/// A row that is a timeline stepping once a minute. Row 200 is the widest, and
/// off screen: 120 cells in an even minute and 60 in an odd one. Every other
/// row is 8.
private struct StampedRow: View {
    let index: Int
    let builds: RowBuilds

    var body: some View {
        builds.note(index)
        return TimelineView(.everyMinute) { context in
            Text(String(repeating: "\(index % 10)", count: Self.cells(index, at: context.date)))
        }
    }

    static func cells(_ index: Int, at date: Date) -> Int {
        guard index == 200 else { return 8 }
        let minute = Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
        return minute.isMultiple(of: 2) ? 120 : 60
    }
}

/// The rows in a windowed stack in a two-axis scroll view, whose horizontal
/// extent is the widest row's width.
private struct StackPage: App {
    let builds: RowBuilds

    init() { self.init(builds: RowBuilds()) }

    init(builds: RowBuilds) { self.builds = builds }

    var body: some Scene {
        WindowGroup {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<400, id: \.self) { StampedRow(index: $0, builds: builds) }
                }
            }
            .frame(width: 40, height: 12)
        }
    }
}

/// The rows in a `List` that hugs them, beside a label that sits wherever
/// the list ends.
private struct ListPage: App {
    let builds: RowBuilds

    init() { self.init(builds: RowBuilds()) }

    init(builds: RowBuilds) { self.builds = builds }

    var body: some Scene {
        WindowGroup {
            HStack(alignment: .top, spacing: 1) {
                List {
                    ForEach(0..<400, id: \.self) { StampedRow(index: $0, builds: builds) }
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 12)
                Text("detail")
            }
        }
    }
}

/// `StampedRow` for row 200 only, which says when it is built; every other row
/// is plain text, so no row on screen holds a timeline, and nothing drawn
/// reads the clock.
private struct LoneStampedRow: View {
    let index: Int
    let builds: RowBuilds

    var body: some View {
        if index == 200 {
            StampedRow(index: index, builds: builds)
        } else {
            Text(String(repeating: "\(index % 10)", count: 8))
        }
    }
}

/// Content compared equal on every frame, so its memo keeps what it measured
/// and drew until a clear or a refusal says otherwise.
private struct Memoized<Content: View>: View, @preconcurrency Equatable {
    let content: Content

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View { content }
}

/// `StackPage` of lone timelines, memoized whole, under a button that holds
/// the focus: a focused scroll view's registration is never stored, so
/// neither is anything around it.
private struct MemoizedStackPage: App {
    let builds: RowBuilds

    init() { self.init(builds: RowBuilds()) }

    init(builds: RowBuilds) { self.builds = builds }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button("focus") {}
                Memoized(
                    content: ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<400, id: \.self) { LoneStampedRow(index: $0, builds: builds) }
                        }
                    }
                )
                .equatable()
                .frame(width: 40, height: 12)
            }
        }
    }
}

/// `ListPage` of lone timelines, the list memoized, under a button that holds
/// the focus.
private struct MemoizedListPage: App {
    let builds: RowBuilds

    init() { self.init(builds: RowBuilds()) }

    init(builds: RowBuilds) { self.builds = builds }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button("focus") {}
                HStack(alignment: .top, spacing: 1) {
                    Memoized(
                        content: List {
                            ForEach(0..<400, id: \.self) { LoneStampedRow(index: $0, builds: builds) }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 12)
                    )
                    .equatable()
                    Text("detail")
                }
            }
        }
    }
}

/// The top of an even minute, in reference-date seconds.
private let evenMinute: TimeInterval = 13_333_320 * 60

/// Draws `app` at `seconds` past the even minute. The monotonic instant
/// follows the date, as the loop stamps them together.
@MainActor
private func frame<A: App>(_ app: HeadlessApp<A>, at seconds: TimeInterval) {
    app.frame(
        atNanos: 1_000_000_000 + Int64(seconds * 1_000_000_000),
        date: Date(timeIntervalSinceReferenceDate: evenMinute + seconds))
}

@MainActor
@Suite("A width kept for a collection of live timelines lapses at their next entry")
struct TimelineCollectionWidthTests {
    /// Drives `app` for a second inside the even minute and then into the odd
    /// one, and returns how often row 200 was built in that second, and the
    /// screen in the odd minute beside one drawn there from the start.
    ///
    /// A second the app's whole cache was cleared in is driven again, with a
    /// fresh app: a clear drops the kept width with everything else, and row
    /// 200 is rightly built again, but it is not this app that asked. Another
    /// test in the process did — a localization change asks for a clear
    /// through the process-wide `AppState.shared`, and whichever app draws next
    /// takes it. Once, on CI's macOS 26 · Swift 6.4 lane (2026-09-30),
    /// `huggingList` counted two builds of row 200 that no local run of this
    /// suite, alone or beside the rest of its target, ever did; the request was
    /// then an `@AppStorage` or `@SceneStorage` write's, which no longer clears
    /// anything (`StorageWriteScopeTests`).
    private func drive<A: App>(
        _ make: (RowBuilds) -> A, width: Int
    ) -> (widestBuiltInOneMinute: Int, later: [String], control: [String]) {
        var attempt = 0
        while true {
            attempt += 1
            let builds = RowBuilds()
            let app = HeadlessApp(make(builds), width: width, height: 16)
            for tick in 0..<5 { frame(app, at: 10 + Double(tick) / 60) }
            builds.reset()
            let clearsBefore = app.renderCache.stats.clears
            for tick in 5..<65 { frame(app, at: 10 + Double(tick) / 60) }
            let widestBuilt = builds.byRow[200] ?? 0
            if app.renderCache.stats.clears != clearsBefore, attempt < 3 { continue }
            for tick in 0..<3 { frame(app, at: 70 + Double(tick) / 60) }

            let control = HeadlessApp(make(RowBuilds()), width: width, height: 16)
            for tick in 0..<3 { frame(control, at: 70 + Double(tick) / 60) }
            return (widestBuilt, app.screen, control.screen)
        }
    }

    /// Row 200 is off screen, so only the walk over every row builds it. Its
    /// timeline says its size holds until the next minute, and the stack keeps
    /// its widest width until then: refused, every row was built on every
    /// frame, row 200 twice a frame; kept for good, the extent held row 200's
    /// 120 cells into the minute where it has 60, and scrolling right showed
    /// blank columns.
    @Test("A windowed stack of live timelines walks its rows once an entry, and again at the next")
    func windowedStack() {
        let (widestBuilt, later, control) = drive({ StackPage(builds: $0) }, width: 60)
        #expect(widestBuilt == 0, "row 200 was built \(widestBuilt) times in 60 frames of one minute")
        #expect(later == control, "the extent kept the width row 200 had in the minute before")
    }

    /// What a scope may keep, asked of the tracker. The frame's tracker is
    /// shared by every walk, so a scope counts only the instants read inside
    /// it: a clock ticking each second beside a log whose rows move once a
    /// minute must not lapse the log's width each second. And a scope's
    /// instants reach the scopes enclosing it, which measured them too.
    @Test("A scope keeps a size until the earliest instant read inside it, and passes it outward")
    func scopes() {
        let tracker = VolatileReadTracker()
        let (second, minute, sooner) = (
            Date(timeIntervalSinceReferenceDate: 1), Date(timeIntervalSinceReferenceDate: 60),
            Date(timeIntervalSinceReferenceDate: 0.5)
        )
        let outer = tracker.beginScope()
        tracker.recordClockedRead(movingAt: second)

        let quiet = tracker.beginScope()
        #expect(tracker.sizeHold(since: quiet) == .indefinitely, "a scope that read nothing lapses")
        tracker.endScope(quiet)

        let log = tracker.beginScope()
        tracker.recordClockedRead(movingAt: minute)
        #expect(tracker.sizeHold(since: log) == .until(minute), "a scope lapsed at an instant read before it")
        tracker.endScope(log)
        #expect(tracker.sizeHold(since: outer) == .until(second))

        let row = tracker.beginScope()
        tracker.recordClockedRead(movingAt: sooner)
        tracker.endScope(row)
        #expect(tracker.sizeHold(since: outer) == .until(sooner), "an instant read inside a scope did not reach the one around it")

        let viewport = tracker.beginScope()
        tracker.recordClockedRead(movingAt: minute)
        tracker.recordUnkeyedRead()
        #expect(tracker.sizeHold(since: viewport) == nil, "a scope that read more than the clock was kept")
        tracker.endScope(viewport)
        tracker.endScope(outer)
    }

    /// The same rows in a `List` that hugs them: its widest row is kept in the
    /// render cache's size memo, which keeps it until the next minute too.
    /// Refused, every row was built twice a frame; kept for good, the list
    /// stayed wide enough for 120 cells in the minute where row 200 has 60.
    @Test("A hugging List of live timelines measures its rows once an entry, and again at the next")
    func huggingList() {
        let (widestBuilt, later, control) = drive({ ListPage(builds: $0) }, width: 200)
        #expect(widestBuilt == 0, "row 200 was built \(widestBuilt) times in 60 frames of one minute")
        #expect(later == control, "the list kept the width row 200 had in the minute before")
    }

    /// The same two widths under a memo, with a timeline only in row 200, off
    /// screen: nothing drawn reads the clock. A kept width that lapses is an
    /// answer over a part that lapses, and holds no longer than that part —
    /// so what measures and draws around it must not keep it longer either.
    /// Served without saying so, the memo around the stack or the list stored
    /// it from the second frame on with no lapse, and drew it in every minute
    /// after: the horizontal scrollbar, or the list's width, stayed where row
    /// 200's 120 cells had put them.
    @Test("A width kept for a live timeline lapses under a memo around it too", arguments: [false, true])
    func underAMemo(list: Bool) {
        let (widestBuilt, later, control) =
            list
            ? drive({ MemoizedListPage(builds: $0) }, width: 200)
            : drive({ MemoizedStackPage(builds: $0) }, width: 60)
        #expect(widestBuilt == 0, "row 200 was built \(widestBuilt) times in 60 frames of one minute")
        #expect(later == control, "the memo kept the width row 200 had in the minute before")
    }
}
