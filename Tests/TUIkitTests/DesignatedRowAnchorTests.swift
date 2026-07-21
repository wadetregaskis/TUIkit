//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DesignatedRowAnchorTests.swift
//
//  `.anchorPosition(.row(id))` designates a SPECIFIC row as the anchor, and the
//  requirement is positional: that row keeps its place on screen while rows are
//  added or removed around it — the scroll position moves, the row does not.
//
//  Before this was wired, `.row` merely switched row-holding ON and the row it
//  held was whatever sat at the top of the viewport, not the designated one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Designated row anchor")
struct DesignatedRowAnchorTests {

    private static let viewport = 10

    /// Renders the windowed stack with a designated anchor row, and reports the
    /// visible slice so a row's SCREEN LINE can be compared across edits.
    private func renderFrame(
        items: [Int], anchored: Int?, tuiContext: TUIContext, offset: Int
    ) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            // Variable heights: the anchor machinery lives on the anchored
            // (non-uniform) path — uniform rows take the arithmetic path,
            // which has no anchor at all.
            ForEach(items, id: \.self) { i in
                Text("row \(i)").frame(height: i % 3 + 1)
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
        if let anchored {
            environment.anchorPosition = .constant(.row(AnyHashable(anchored)))
        }
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8000,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()

        let lines = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= offset + Self.viewport else { return [] }
        return Array(lines[offset..<(offset + Self.viewport)])
    }

    /// The screen line the designated row occupies within the visible slice.
    private func screenLine(of row: Int, in slice: [String]) -> Int? {
        slice.firstIndex(of: "row \(row)")
    }

    @Test("An inserted block above the anchored row leaves it on the same screen line")
    func insertAboveKeepsScreenLine() {
        let tuiContext = TUIContext()
        var items = Array(0..<400)
        let anchored = 300

        // Settle the anchor mid-list.
        _ = renderFrame(items: items, anchored: anchored, tuiContext: tuiContext, offset: 0)
        _ = renderFrame(items: items, anchored: anchored, tuiContext: tuiContext, offset: 595)
        let before = renderFrame(
            items: items, anchored: anchored, tuiContext: tuiContext, offset: 595)
        guard let lineBefore = screenLine(of: anchored, in: before) else {
            Issue.record("anchored row not visible to begin with: \(before)")
            return
        }

        // Insert 25 rows ABOVE it. Its ordinal shifts by 25; its screen line
        // must not move.
        items.insert(contentsOf: (1_000..<1_025), at: 10)
        let after = renderFrame(
            items: items, anchored: anchored, tuiContext: tuiContext, offset: 595)
        #expect(
            screenLine(of: anchored, in: after) == lineBefore,
            "row \(anchored) moved: was line \(lineBefore), slice now \(after)")
    }

    @Test("Deleting rows above the anchored row also leaves it on the same screen line")
    func deleteAboveKeepsScreenLine() {
        let tuiContext = TUIContext()
        var items = Array(0..<400)
        let anchored = 300

        _ = renderFrame(items: items, anchored: anchored, tuiContext: tuiContext, offset: 0)
        _ = renderFrame(items: items, anchored: anchored, tuiContext: tuiContext, offset: 595)
        let before = renderFrame(
            items: items, anchored: anchored, tuiContext: tuiContext, offset: 595)
        guard let lineBefore = screenLine(of: anchored, in: before) else {
            Issue.record("anchored row not visible to begin with: \(before)")
            return
        }

        // Remove 20 rows ABOVE it — the scroll position must come up to
        // compensate.
        items.removeSubrange(10..<30)
        let after = renderFrame(
            items: items, anchored: anchored, tuiContext: tuiContext, offset: 595)
        #expect(
            screenLine(of: anchored, in: after) == lineBefore,
            "row \(anchored) moved: was line \(lineBefore), slice now \(after)")
    }

    /// The contrast that shows the designation is doing the work: with NO
    /// designated row the default is Window, which holds the POSITION — so the
    /// same edit moves that row instead.
    @Test("Without a designation the same insert DOES move the row (Window default)")
    func withoutDesignationTheRowMoves() {
        let tuiContext = TUIContext()
        var items = Array(0..<400)

        _ = renderFrame(items: items, anchored: nil, tuiContext: tuiContext, offset: 0)
        _ = renderFrame(items: items, anchored: nil, tuiContext: tuiContext, offset: 595)
        let before = renderFrame(items: items, anchored: nil, tuiContext: tuiContext, offset: 595)
        let lineBefore = screenLine(of: 300, in: before)

        items.insert(contentsOf: (1_000..<1_025), at: 10)
        let after = renderFrame(items: items, anchored: nil, tuiContext: tuiContext, offset: 595)
        #expect(
            screenLine(of: 300, in: after) != lineBefore,
            "Window holds the position, so the row shifts: \(before) → \(after)")
    }
}
