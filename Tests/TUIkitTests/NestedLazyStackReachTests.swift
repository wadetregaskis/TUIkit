//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NestedLazyStackReachTests.swift
//
//  A lazy stack that is NOT a scroll view's direct content is drawn whole, by
//  the classic append-while-fits walk, into whatever height its parent gave it
//  — and its parent gives it the height it MEASURED. Above 256 rows that
//  measure was the anchored path's sixteen-row estimate, which is honest only
//  where the windowed render is its reader: nested below a header, or in a row
//  of an outer lazy stack, the estimate became the stack's actual height, and
//  the rows past it were drawn nowhere and could not be scrolled to. These
//  drive the whole app, frame by frame, and look at the screen — and count the
//  rows built, since the exact measure costs a walk the estimate did not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A header, then a lazy stack of `rows` rows below it — so the stack is one
/// sibling among two and not the scroll view's direct content. The anchored
/// estimate samples the first sixteen rows; `tallFirst` decides whether those
/// are the one-line rows (the rows after them are taller, and the estimate
/// UNDER-reports) or the two-line ones (it over-reports).
private struct NestedLazyApp: App {
    let rows: Int
    let tallFirst: Bool
    let bottomAnchored: Bool

    init() { self.init(rows: 300, tallFirst: false, bottomAnchored: true) }
    init(rows: Int, tallFirst: Bool, bottomAnchored: Bool) {
        self.rows = rows
        self.tallFirst = tallFirst
        self.bottomAnchored = bottomAnchored
    }

    var body: some Scene {
        WindowGroup {
            NestedLazyPage(rows: rows, tallFirst: tallFirst)
                .defaultScrollAnchor(bottomAnchored ? .bottom : nil)
        }
    }
}

private struct NestedLazyPage: View {
    let rows: Int
    let tallFirst: Bool

    var body: some View {
        ScrollView {
            NestedLazyContent(rows: rows, tallFirst: tallFirst)
        }
    }
}

/// The scroll view's content: a header over a lazy stack of variable rows.
private struct NestedLazyContent: View {
    let rows: Int
    let tallFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("header")
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { index in
                    Text((index < 16) == tallFirst ? "row \(index)\nsecond line" : "row \(index)")
                }
            }
        }
    }
}

/// Counts row-builder calls. `@unchecked`: driven on the main actor.
private final class RowBuilds: @unchecked Sendable {
    var count = 0
}

/// A lazy stack of `groups` rows, each a header over a NESTED lazy stack of
/// three hundred rows (a few more per group, so no two groups are alike) — the
/// outer stack is the scroll view's direct content and windows; the inner ones
/// are drawn whole whenever their group is. A `@State` above the scroll view
/// (`t`) writes on demand, so every memo beneath it is cleared and the next
/// frame measures from scratch: the frame a live app pays on every write.
private struct GroupsApp: App {
    let groups: Int
    let tallAfterSixteen: Bool
    let builds: RowBuilds

    init() { self.init(groups: 1, tallAfterSixteen: false, builds: RowBuilds()) }
    init(groups: Int, tallAfterSixteen: Bool, builds: RowBuilds) {
        self.groups = groups
        self.tallAfterSixteen = tallAfterSixteen
        self.builds = builds
    }

    var body: some Scene {
        WindowGroup {
            GroupsPage(groups: groups, tallAfterSixteen: tallAfterSixteen, builds: builds)
        }
    }
}

private struct GroupsPage: View {
    let groups: Int
    let tallAfterSixteen: Bool
    let builds: RowBuilds
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("group \(group)")
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(0..<(300 + group), id: \.self) { index in
                                    builds.count += 1
                                    return Text(
                                        tallAfterSixteen && index >= 16
                                            ? "g\(group) r\(index)\nsecond" : "g\(group) r\(index)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onKeyPress(.character("t")) { tick += 1 }
    }
}

/// Variable-height rows as the scroll view's DIRECT content, and a hundred
/// thousand of them — the stack its window bands, whose measure must stay the
/// estimate — under a `@State` that `t` writes. Every other row is two lines
/// from the very first, so the band on screen refutes the uniform-height
/// hypothesis and the measure is the anchored path's, where the gate is asked.
private struct DirectLazyApp: App {
    let builds: RowBuilds

    init() { self.init(builds: RowBuilds()) }
    init(builds: RowBuilds) { self.builds = builds }

    var body: some Scene {
        WindowGroup { DirectLazyPage(builds: builds) }
    }
}

private struct DirectLazyPage: View {
    let builds: RowBuilds
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<100_000, id: \.self) { index in
                        builds.count += 1
                        return Text(
                            index.isMultiple(of: 2) ? "row \(index)" : "row \(index)\nsecond line")
                    }
                }
            }
        }
        .onKeyPress(.character("t")) { tick += 1 }
    }
}

/// A page whose data moves: `a` appends rows, `t` writes a counter above the
/// scroll view. Either a header over one nested stack (`grouped: false`) or
/// a few groups, each a header over a nested stack, in an outer lazy stack.
/// Bottom-anchored, so appends are followed.
private struct MovingApp: App {
    let grouped: Bool

    init() { self.init(grouped: false) }
    init(grouped: Bool) { self.grouped = grouped }

    var body: some Scene {
        WindowGroup { MovingPage(grouped: grouped) }
    }
}

private struct MovingPage: View {
    let grouped: Bool
    @State private var count = 300
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            ScrollView {
                if grouped {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<(count / 60), id: \.self) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text("group \(group)")
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(0..<(260 + group * 7), id: \.self) { index in
                                        Text(
                                            index.isMultiple(of: 5)
                                                ? "row \(group * 1000 + index)\nx"
                                                : "row \(group * 1000 + index)")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    NestedLazyContent(rows: count, tallFirst: false)
                }
            }
            .defaultScrollAnchor(.bottom)
        }
        .onKeyPress(.character("a")) { count += 61 }
        .onKeyPress(.character("t")) { tick += 1 }
    }
}

/// The screen's lines, styling stripped.
@MainActor
private func visible<A: App>(_ app: HeadlessApp<A>) -> [String] {
    app.screen.map(\.stripped)
}

/// The row numbers drawn on `screen`: every `row N` label, however the line
/// around it is dressed (a scrollbar column sits at its right edge).
private func rowsDrawn(on screen: [String]) -> Set<Int> {
    var rows = Set<Int>()
    for line in screen {
        for match in line.matches(of: /row (\d+)/) {
            if let number = Int(match.1) { rows.insert(number) }
        }
    }
    return rows
}

@MainActor
@Suite("A lazy stack below other content reaches every row")
struct NestedLazyStackReachTests {
    private static let frame: Int64 = 16_666_667

    @Test("Bottom-anchored: the last of 300 rows is drawn when the first 16 are shorter")
    func bottomAnchoredDrawsTheLastRow() {
        // The estimate prices every row at one line (the sample's); rows 16…
        // are two. Pre-fix the stack was given 300 lines, drew rows 0–157 into
        // them, and the bottom of the scroll view was row 157.
        let app = HeadlessApp(
            NestedLazyApp(rows: 300, tallFirst: false, bottomAnchored: true), width: 30, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frame)
        let screen = visible(app)
        let rows = rowsDrawn(on: screen)
        #expect(rows.contains(299), "the tail is drawn: \(screen)")
        #expect(!rows.contains(157), "not stopped at the estimate's end: \(screen)")
    }

    @Test("End reaches the last of 300 rows when the first 16 are shorter")
    func endReachesTheLastRow() {
        let app = HeadlessApp(
            NestedLazyApp(rows: 300, tallFirst: false, bottomAnchored: false), width: 30, height: 10)
        app.frame(atNanos: 0)
        #expect(visible(app).contains { $0.contains("header") }, "precondition: the top is drawn")
        app.send(KeyEvent(key: .end))
        app.frame(atNanos: Self.frame)
        app.frame(atNanos: 2 * Self.frame)
        let screen = visible(app)
        #expect(rowsDrawn(on: screen).contains(299), "End reaches the tail: \(screen)")
    }

    @Test("End lands on the last row, not on blank lines, when the first 16 are taller")
    func endLandsOnTheLastRowWhenTheEstimateOverReports() {
        // The mirror: the sample sees two-line rows and prices all 300 at two,
        // so the stack claimed 600 lines and drew 316 into them. The scroll
        // range follows the drawn buffer, so that over-claim never showed here;
        // this pins that the exact measure, which now claims 316, still lands
        // End on the real last row.
        let app = HeadlessApp(
            NestedLazyApp(rows: 300, tallFirst: true, bottomAnchored: false), width: 30, height: 10)
        app.frame(atNanos: 0)
        app.send(KeyEvent(key: .end))
        app.frame(atNanos: Self.frame)
        app.frame(atNanos: 2 * Self.frame)
        let screen = visible(app)
        let rows = rowsDrawn(on: screen)
        #expect(rows.contains(299), "End reaches the tail: \(screen)")
        #expect(rows.contains(298), "rows above the tail fill the viewport: \(screen)")
    }

    @Test("Paging down a nested stack draws every one of its rows")
    func pagingDrawsEveryRow() {
        // Collect what each page drew: no row may be skipped. The content is
        // 585 lines (a header, sixteen one-line rows, 284 two-line ones), and
        // eighty pages of a viewport this size cover it with room to spare.
        let app = HeadlessApp(
            NestedLazyApp(rows: 300, tallFirst: false, bottomAnchored: false), width: 30, height: 12)
        app.frame(atNanos: 0)
        var seen = rowsDrawn(on: visible(app))
        for page in 1...80 {
            app.send(KeyEvent(key: .pageDown))
            app.frame(atNanos: Int64(page) * Self.frame)
            seen.formUnion(rowsDrawn(on: visible(app)))
        }
        let missing = (0..<300).filter { !seen.contains($0) }
        #expect(missing.isEmpty, "rows never drawn: \(missing.prefix(20))")
    }

    @Test("A nested stack in each row of an outer lazy stack draws every one of its rows")
    func rowsOfAnOuterLazyStackReachEveryRow() {
        // The outer stack windows; each group it draws is drawn whole, its
        // inner stack into the height the OUTER stack's slot walk measured for
        // it. Pre-fix that was the inner stack's estimate, and 427 of the 903
        // rows were never drawn: every group stopped at its row 157.
        let app = HeadlessApp(
            GroupsApp(groups: 3, tallAfterSixteen: true, builds: RowBuilds()), width: 30, height: 12)
        app.frame(atNanos: 0)
        var seen = Set<String>()
        func collect() {
            for line in visible(app) {
                for match in line.matches(of: /g(\d+) r(\d+)/) { seen.insert("\(match.1)-\(match.2)") }
            }
        }
        collect()
        // 3 groups of 1 + 16 + 2 × 284 (or 285, 286) lines: 1,764 lines, which
        // 200 pages of ten cover with room to spare.
        for page in 1...400 {
            app.send(KeyEvent(key: .pageDown))
            app.frame(atNanos: Int64(page) * Self.frame)
            collect()
        }
        var missing: [String] = []
        for group in 0..<3 {
            for row in 0..<(300 + group) where !seen.contains("\(group)-\(row)") {
                missing.append("\(group)-\(row)")
            }
        }
        #expect(missing.isEmpty, "\(missing.count) rows never drawn: \(missing.prefix(10))")
    }

    @Test("The scroll view's direct content is still estimated after a write above it")
    func directContentKeepsTheEstimate() {
        // The fix measures a NESTED stack over every row it will draw; the
        // stack at the scroll origin is drawn as a band, and must keep the
        // sample. Told apart wrongly, it would be walked up every rung of the
        // natural-extent ladder — all 100,000 rows.
        //
        // Pinned on the frame after a write ABOVE the scroll view, which
        // clears every memo beneath it, so that frame measures from scratch —
        // the frame the gate decides. (Not frame 1: its discarded walk for the
        // app header's height renders with `isMeasuring` set, which already
        // takes a lazy stack's classic walk and builds every row, gate or no
        // gate. And not a quiet frame: its measures are all served.)
        let builds = RowBuilds()
        let app = HeadlessApp(DirectLazyApp(builds: builds), width: 30, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frame)
        let before = builds.count
        app.send(KeyEvent(key: .character("t")))
        app.frame(atNanos: 2 * Self.frame)
        let perFrame = builds.count - before
        let screen = visible(app)
        #expect(screen.contains { $0.contains("tick 1") }, "precondition: the write landed: \(screen)")
        #expect(rowsDrawn(on: screen).contains(3), "precondition: the band is drawn: \(screen)")
        #expect(perFrame < 500, "a banded frame built \(perFrame) rows")
    }

    @Test("A nested stack is walked once per width a frame, not once per ask")
    func nestedStackIsWalkedOncePerWidth() {
        // A scroll view asks its content its height at several budgets a frame
        // — each rung of the natural-extent ladder at each scrollbar
        // candidate's width, then the outer stack's slot walk at the canvas it
        // settled on — and a walk that stopped nowhere claims a natural size,
        // so the per-pass memo serves the later asks at the same width: one
        // walk per width. The two groups on screen are measured and drawn once
        // more by their own render, which builds them afresh (a freshly built
        // view is a new memo key), and each group's first eight rows answer the
        // scroll view's ideal-size ask.
        //
        // Twenty groups, 6,190 rows: 13,762 built a frame with the claim. Without
        // it 32,332 — this content is past the ladder's 4,096-line first rung,
        // so each width took two rungs, and the slot walk a fifth walk.
        let builds = RowBuilds()
        let groups = 20
        let app = HeadlessApp(
            GroupsApp(groups: groups, tallAfterSixteen: false, builds: builds), width: 30, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frame)
        let before = builds.count
        app.send(KeyEvent(key: .character("t")))
        app.frame(atNanos: 2 * Self.frame)
        let perFrame = builds.count - before
        let rows = (0..<groups).reduce(0) { $0 + 300 + $1 }
        #expect(visible(app).contains { $0.contains("g0 r0") }, "precondition: the first group is drawn")
        #expect(perFrame * 2 < 5 * rows, "an invalidated frame built \(perFrame) rows of \(rows)")
    }

    @Test(
        "A memoised nested stack draws what a cache-cleared twin draws, and every size it is served is fresh",
        arguments: [false, true])
    func memoisedFramesMatchAFreshTwin(grouped: Bool) {
        // The walk's natural-size claim lets the per-pass memo answer later
        // asks at other budgets. This drives two copies of one app through
        // scrolls, writes above the scroll view, appends and a resize — one
        // with its render cache cleared before every frame — and compares
        // every frame; both measure-memo verifiers re-measure every size
        // served, per pass and across frames, and report any that differ.
        let wasVerifyingMeasures = RenderCache.verifiesMeasureMemo
        let wasVerifyingRenders = RenderCache.verifiesRenderMemo
        RenderCache.verifiesMeasureMemo = true
        RenderCache.verifiesRenderMemo = true
        defer {
            RenderCache.verifiesMeasureMemo = wasVerifyingMeasures
            RenderCache.verifiesRenderMemo = wasVerifyingRenders
        }
        let cached = HeadlessApp(MovingApp(grouped: grouped), width: 30, height: 10)
        let fresh = HeadlessApp(MovingApp(grouped: grouped), width: 30, height: 10)
        fresh.clearsRenderCacheEachFrame = true
        let script: [KeyEvent?] = [
            nil, nil, KeyEvent(key: .pageUp), KeyEvent(key: .pageUp), KeyEvent(key: .character("t")),
            KeyEvent(key: .character("a")), nil, KeyEvent(key: .end), KeyEvent(key: .character("a")),
            KeyEvent(key: .home), KeyEvent(key: .pageDown), KeyEvent(key: .character("t")), nil,
            KeyEvent(key: .end), KeyEvent(key: .up), KeyEvent(key: .up), KeyEvent(key: .character("a")),
        ]
        var diverged: [String] = []
        for (step, event) in script.enumerated() {
            if step == 12 {
                cached.resize(width: 22, height: 9)
                fresh.resize(width: 22, height: 9)
            }
            if let event {
                cached.send(event)
                fresh.send(event)
            }
            cached.frame(atNanos: Int64(step) * Self.frame)
            fresh.frame(atNanos: Int64(step) * Self.frame)
            if visible(cached) != visible(fresh) {
                diverged.append("step \(step): \(visible(cached)) vs \(visible(fresh))")
            }
        }
        #expect(diverged.isEmpty, "\(diverged.prefix(2))")
        #expect(cached.renderCache.measureMemoMismatches.isEmpty, "\(cached.renderCache.measureMemoMismatches)")
        #expect(cached.renderCache.renderMemoMismatches.isEmpty, "\(cached.renderCache.renderMemoMismatches)")
    }

    @Test("A scroll view's ideal height is the height its nested lazy stack draws")
    func idealHeightIsTheDrawnHeight() {
        // SwiftUI: a scroll view's ideal size is its content's. Its content is
        // asked under the same origin as every other ask the scroll view makes,
        // so the stack gives the answer it draws to — 1 + 16 + 2 × 284 lines —
        // and not the sixteen-row estimate (301), which is the answer the memo
        // would also have kept for it.
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 4_096, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let size = measureChild(
            ScrollView { NestedLazyContent(rows: 300, tallFirst: false) },
            proposal: ProposedSize(width: 30, height: nil), context: context)
        tui.stateStorage.endRenderPass()
        #expect(size.height == 1 + 16 + 2 * 284)
    }
}
