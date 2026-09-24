//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionMemoTests.swift
//
//  A removal that plays inside a memoized subtree — a `ForEach` row over
//  `Equatable` data, a `List` row, an `.equatable()` view — plays out frame by
//  frame and is then forgotten, exactly as it does in a subtree nothing memoizes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// One row's data. `Equatable`, so `ForEach` memoizes the row it builds.
private struct Item: Identifiable, Equatable {
    let id: Int
    var expanded: Bool
}

/// Where the view that comes and goes stands, and what memoizes it.
enum MemoizedRemovalShape: String, CaseIterable, Sendable {
    /// `ForEach(items) { VStack { if item.expanded { … } } }`: the `if` is the
    /// row's whole content, which is the shape that snapped before the present
    /// view was given the address its `nil` claims — and so the one a stored
    /// removal would have reached first.
    case forEachRowAlone
    /// `ForEach(items) { VStack { Text; if item.expanded { … } } }`.
    case forEachRowBesideSibling
    /// The same row in a `List`, which memoizes rows of its own.
    case listRow
    /// An `.equatable()` view whose body holds the `if` beside a sibling.
    case equatableView
}

/// A card whose detail comes and goes, memoized by its value.
private struct Card: View, @MainActor Equatable {
    let expanded: Bool
    let transition: AnyTransition

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.expanded == rhs.expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("card")
            if expanded { Text("DETAIL").transition(transition) }
        }
    }
}

private struct RowsPage: View {
    @State private var items = [Item(id: 0, expanded: true), Item(id: 1, expanded: false)]
    let shape: MemoizedRemovalShape
    let transition: AnyTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("toggle") {
                withAnimation(.linear(duration: 1)) { items[0].expanded.toggle() }
            }
            switch shape {
            case .forEachRowAlone:
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        if item.expanded { Text("DETAIL").transition(transition) }
                    }
                }
            case .forEachRowBesideSibling:
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("row \(item.id)")
                        if item.expanded { Text("DETAIL").transition(transition) }
                    }
                }
            case .listRow:
                List {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("row \(item.id)")
                            if item.expanded { Text("DETAIL").transition(transition) }
                        }
                    }
                }
                .frame(height: 6)
            case .equatableView:
                Card(expanded: items[0].expanded, transition: transition).equatable()
            }
            Text("below")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RowsApp: App {
    let shape: MemoizedRemovalShape
    let transition: AnyTransition

    init() { self.init(shape: .forEachRowBesideSibling, transition: .opacity) }

    init(shape: MemoizedRemovalShape, transition: AnyTransition) {
        self.shape = shape
        self.transition = transition
    }

    var body: some Scene {
        WindowGroup { RowsPage(shape: shape, transition: transition) }
    }
}

@MainActor
@Suite("A removal in a memoized subtree plays out and is forgotten")
struct TransitionMemoTests {

    /// The detail starts shown, and one key hides it inside a one-second
    /// `withAnimation`. Every frame for the next 1.25 s is compared with an
    /// instance that clears its render cache each frame — what a frame drawn
    /// without any memo shows — so a memo that stored the removal's first
    /// picture and served it afterwards shows up as the first frame the two
    /// disagree, and a ghost that outlives the removal as the last.
    @Test(
        "Each frame of the removal is the frame an uncached app draws",
        arguments: MemoizedRemovalShape.allCases, [AnyTransition.move(edge: .trailing), .opacity])
    func removalMatchesUncached(shape: MemoizedRemovalShape, transition: AnyTransition) {
        let warm = HeadlessApp(RowsApp(shape: shape, transition: transition), width: 30, height: 14)
        let cold = HeadlessApp(RowsApp(shape: shape, transition: transition), width: 30, height: 14)
        cold.clearsRenderCacheEachFrame = true
        var tick: Int64 = 0
        // Each app presses and draws before the other presses. The change's
        // transaction waits in the process's one pending slot until a frame
        // consumes it, so pressing both first would animate only the app that
        // happened to draw first, and the other would snap.
        func frame(pressing: Bool = false) {
            let now = AnimationClock.nanoseconds(atTick: tick)
            for app in [warm, cold] {
                if pressing { #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key") }
                app.frame(atNanos: now)
            }
            tick += 1
        }
        func showsDetail(_ app: HeadlessApp<RowsApp>) -> Bool {
            app.screen.contains { $0.stripped.contains("DETAIL") }
        }

        frame()
        frame()
        #expect(showsDetail(warm) && showsDetail(cold), "precondition: the detail is shown")

        var differing: [Int64] = []
        for step in 0..<76 {
            frame(pressing: step == 0)
            if warm.screen != cold.screen { differing.append(tick - 1) }
        }
        #expect(
            differing.isEmpty,
            "the cached app drew something else at ticks \(differing):\n\(warm.screen.map(\.stripped))")
        #expect(!showsDetail(warm), "the detail is still drawn after its removal ended")
        #expect(warm.departureCount == 0, "the finished removal is still tracked")
        #expect(warm.renderCache.rowWork.served > 0, "nothing was ever served, so this proved nothing")
    }

    /// The oracle above says the cache changed nothing. This says there was a
    /// removal to change: half-way through, the detail is part-way out and
    /// still holding its row, in the cached app as in the uncached one.
    @Test("Half-way through, the detail is sliding out in its own row", arguments: MemoizedRemovalShape.allCases)
    func removalIsUnderWayHalfWay(shape: MemoizedRemovalShape) {
        let app = HeadlessApp(RowsApp(shape: shape, transition: .move(edge: .trailing)), width: 30, height: 14)
        var tick: Int64 = 0
        func frame() {
            app.frame(atNanos: AnimationClock.nanoseconds(atTick: tick))
            tick += 1
        }
        func row(of text: String) -> (row: Int, column: Int)? {
            for (row, line) in app.screen.map(\.stripped).enumerated() {
                if let range = line.range(of: text) {
                    return (row, line.distance(from: line.startIndex, to: range.lowerBound))
                }
            }
            return nil
        }
        frame()
        frame()
        let shown = row(of: "DETAIL")
        let below = row(of: "below")
        #expect(shown != nil && below != nil, "precondition: the page is drawn")
        guard let shown, let below else { return }

        #expect(app.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        for _ in 0..<31 { frame() }
        let halfWay = row(of: "DET")
        #expect(
            halfWay.map { $0.row == shown.row && $0.column > shown.column } == true,
            "not sliding out half-way:\n\(app.screen.map(\.stripped))")
        #expect(row(of: "below")?.row == below.row, "the page closed up before the removal ended")
    }
}
