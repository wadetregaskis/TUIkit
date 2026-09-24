//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollEager.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Scroll Eager

/// The eager twin of `scrollfollow`: a vertical `ScrollView` over an EAGER
/// `VStack` of N rows, under a heading — the page an app writes before it
/// reaches for `LazyVStack`.
///
/// Every walk of the content is a walk of every row here, so this is where a
/// change that adds one shows at full size: the enclosing `VStack` asking the
/// scroll view its ideal size, the scroll view's scrollbar reservation, its
/// natural-extent ladder and the render itself each touch all N rows, and the
/// windowed scenarios hide exactly that behind the window. Every row's text
/// moves each tick, as a live table's does, so no row memo can serve it and
/// the walks are paid in full.
enum ScrollEagerScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "scrolleager",
        title: "Scroll Eager",
        blurb: "Vertical ScrollView over an eager VStack of N rows whose text changes every tick.",
        stresses: "whole-content measure walks · scrollbar reservation · ideal-size ask · O(N) per frame",
        make: { config in AnyView(ScrollEagerView(config: config)) }
    )
}

private struct ScrollEagerRow: Identifiable {
    let id: Int
    let text: String
}

private struct ScrollEagerView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let tick = clock.tick
        let count = config.sized(400)
        let rows = (0..<count).map { ScrollEagerRow(id: $0, text: "entry \($0) \(tick % 7)") }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.scrolleager.heading", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in Text(verbatim: row.text) }
                }
            }
        }
    }
}
