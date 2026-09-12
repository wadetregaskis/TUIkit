//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewPanelClaimTests.swift
//
//  A TabView's content panel is the selected tab's content, centred, with the rest
//  of every row — and every row a shorter tab leaves under a taller one — filled in
//  the panel's surface. Under a translucent surface every cell of the panel owes the
//  surface's alpha exactly once: the content's own background claims its block, and
//  the pads and fillers around it are claimed separately. Claimed twice, a cell would
//  owe the alpha squared; left out, nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A TabView's panel owes its surface exactly once, everywhere")
struct TabViewPanelClaimTests {

    @Test("Every cell of a compact TabView's panel owes the surface's alpha exactly once")
    func compactPanelOwesItsSurfaceOnce() throws {
        let palette = FadedAll()
        // The palette the view is handed: a translucent ROOT ground is spent where a
        // palette enters the environment (§70.4), and the lifted surface derives from it.
        let seen = GroundedPalette.grounding(palette)
        let surface = seen.liftedBackground.resolve(with: seen)
        let want = owed(surface)
        // A one-cell tab under a wider, taller one: its line is padded on both sides,
        // and the rows the taller one needs are filled beneath it.
        let view = TabView(selection: .constant(0)) {
            Tab("one", value: 0) { Text("a") }
            Tab("two", value: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("a much wider body")
                    Text("x")
                    Text("y")
                }
            }
        }
        .tabViewStyle(.compact)
        let context = makeRenderContext(width: 40, height: 10) { environment, _ in
            environment.palette = palette
        }
        let drawn = renderToBuffer(view, context: context)
        let screen = drawn.lines.map(\.stripped)

        // The panel is everything below the strip: the rows with no chip caps.
        let panel = screen.indices.filter { !screen[$0].contains("▐") && !screen[$0].contains("▌") }
        let content = try #require(panel.first { screen[$0].contains("a") }, "\(screen)")
        #expect(
            screen[content].hasPrefix(" ") && screen[content].hasSuffix(" "),
            "the short tab's line is padded on both sides: \(screen)")
        #expect(
            panel.filter { screen[$0].trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2,
            "a shorter tab under a taller one is filled out: \(screen)")
        var wrong: [String] = []
        for row in panel {
            for column in 0..<screen[row].count {
                let field = owed(atColumn: column, row: row, in: drawn).field
                if field != want { wrong.append("(\(column), \(row)): \(field)") }
            }
        }
        #expect(
            wrong.isEmpty,
            """
            panel cells owing the wrong field, \(wrong.count) of them: \(wrong.prefix(10))
            \(screen.joined(separator: "\n"))
            """)
    }
}
