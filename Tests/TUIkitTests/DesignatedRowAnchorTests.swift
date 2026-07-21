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
//  Harness note: these render a REAL `ScrollView`, and read the row's line out
//  of the visible output rather than slicing a full-height buffer by hand. That
//  is load-bearing — holding a row means the effective scroll offset MOVES, so
//  a harness that slices at the offset it passed in cannot see the feature work
//  (it reads the pre-correction window and finds blanks). The ScrollView slices
//  at the offset it actually adopted, which is the thing under test.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Designated row anchor")
struct DesignatedRowAnchorTests {

    private static let viewport = 8

    /// One rendered frame of a scrollable list, returned as the VISIBLE lines.
    ///
    /// `uniform` picks the render path under test: equal-height rows take the
    /// arithmetic seek path, variable heights take the anchored walk (over the
    /// 256-row threshold) or the exact walk (under it).
    private func renderFrame(
        items: [Int], anchored: Int?, uniform: Bool,
        tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        let list = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.self) { i in
                    Text("row \(i)").frame(height: uniform ? 1 : i % 3 + 1)
                }
            }
        }
        .frame(height: Self.viewport)

        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        if let anchored {
            environment.anchorPosition = .constant(.row(AnyHashable(anchored)))
        }
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(list, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The screen line the designated row occupies in the visible output.
    private func screenLine(of row: Int, in slice: [String]) -> Int? {
        slice.firstIndex { $0.contains("row \(row)") && !$0.contains("row \(row)0") }
    }

    /// Renders until the view has settled, then reports the anchored row's line.
    /// Returns `nil` when the row never came into view (a test precondition).
    private func settle(
        items: [Int], anchored: Int?, uniform: Bool,
        tuiContext: TUIContext, focusManager: FocusManager
    ) -> (line: Int, lines: [String])? {
        var lines: [String] = []
        for _ in 0..<4 {
            lines = renderFrame(
                items: items, anchored: anchored, uniform: uniform,
                tuiContext: tuiContext, focusManager: focusManager)
        }
        guard let anchored, let line = screenLine(of: anchored, in: lines) else { return nil }
        return (line, lines)
    }

    // MARK: - The requirement, on every render path

    /// The core of the owner's spec: "when a row is anchored it stays in the
    /// same spot on the screen … if other rows are added or deleted around it,
    /// the scroll position actually adjusts as necessary".
    private func expectHoldsScreenLine(
        uniform: Bool, count: Int, anchored: Int,
        edit: (inout [Int]) -> Void, comment: Comment
    ) {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var items = Array(0..<count)

        guard
            let (lineBefore, before) = settle(
                items: items, anchored: anchored, uniform: uniform,
                tuiContext: tuiContext, focusManager: focusManager)
        else {
            Issue.record("\(comment): anchored row never came into view")
            return
        }

        edit(&items)
        let after = renderFrame(
            items: items, anchored: anchored, uniform: uniform,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            screenLine(of: anchored, in: after) == lineBefore,
            """
            \(comment): row \(anchored) moved — was line \(lineBefore).
            before: \(before)
            after:  \(after)
            """)
    }

    @Test("Uniform rows: an insert above the anchored row leaves it on its line")
    func uniformInsertAbove() {
        expectHoldsScreenLine(
            uniform: true, count: 60, anchored: 30,
            edit: { $0.insert(contentsOf: 1_000..<1_025, at: 5) },
            comment: "uniform arithmetic path")
    }

    @Test("Uniform rows: a delete above the anchored row leaves it on its line")
    func uniformDeleteAbove() {
        expectHoldsScreenLine(
            uniform: true, count: 60, anchored: 30,
            edit: { $0.removeSubrange(5..<15) },
            comment: "uniform arithmetic path")
    }

    @Test("Small variable-height list: the exact walk holds the row too")
    func exactWalkHoldsRow() {
        expectHoldsScreenLine(
            uniform: false, count: 60, anchored: 30,
            edit: { $0.insert(contentsOf: 1_000..<1_010, at: 5) },
            comment: "exact full-walk path")
    }

    @Test("Large variable-height list: the anchored walk holds the row")
    func anchoredWalkHoldsRow() {
        expectHoldsScreenLine(
            uniform: false, count: 400, anchored: 300,
            edit: { $0.insert(contentsOf: 1_000..<1_025, at: 10) },
            comment: "anchored walk path")
    }

    @Test("Deleting rows above the anchored row also holds it (anchored walk)")
    func anchoredWalkHoldsOnDelete() {
        expectHoldsScreenLine(
            uniform: false, count: 400, anchored: 300,
            edit: { $0.removeSubrange(10..<30) },
            comment: "anchored walk path")
    }

    // MARK: - Sticky re-anchor when forced off the held line

    /// The priority with a designated row is to minimise ITS visual movement.
    /// So when an edit forces the row off its held line — e.g. rows above it are
    /// deleted until it hits the top — it re-anchors where it landed, and does
    /// NOT spring back to its original line when the rows are restored.
    @Test("A row forced to the top re-anchors there, and does not spring back")
    func stickyReAnchorAfterForcedMove() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var items = Array(0..<40)

        // Designate row 5 while the view is at the top: it settles a few lines
        // down (there is content above it to fill those lines).
        _ = settle(
            items: items, anchored: 5, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        let settled = renderFrame(
            items: items, anchored: 5, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        guard let startLine = screenLine(of: 5, in: settled), startLine > 1 else {
            Issue.record("row 5 should start below the top: \(settled)")
            return
        }

        // Delete most of the rows above it — enough to force it partway up, but
        // leaving some content above so it lands clear of the top indicator
        // (making the held line exact rather than off-by-the-indicator).
        items.removeSubrange(0..<3)
        let forced = renderFrame(
            items: items, anchored: 5, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        guard let forcedLine = screenLine(of: 5, in: forced), forcedLine < startLine else {
            Issue.record("row 5 should have ridden up: \(settled) → \(forced)")
            return
        }

        // Restore rows above it. It must HOLD where it was pushed to, not spring
        // back to `startLine`.
        items.insert(contentsOf: 100..<103, at: 0)
        let restored = renderFrame(
            items: items, anchored: 5, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            screenLine(of: 5, in: restored) == forcedLine,
            "row 5 sprang back toward \(startLine) instead of holding \(forcedLine): \(restored)")
    }

    // MARK: - The contrast: no designation means no holding

    /// Shows the designation is doing the work: with none, the default is
    /// Window, which holds the POSITION — so the same edit moves the row.
    @Test("Without a designation the same insert DOES move the row (Window default)")
    func withoutDesignationTheRowMoves() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var items = Array(0..<400)

        // Drive to where row 300 is visible via a designation, then drop it:
        // the comparison needs the row on screen to begin with.
        _ = settle(
            items: items, anchored: 300, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        let before = renderFrame(
            items: items, anchored: nil, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        let lineBefore = screenLine(of: 300, in: before)

        items.insert(contentsOf: 1_000..<1_025, at: 10)
        let after = renderFrame(
            items: items, anchored: nil, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            screenLine(of: 300, in: after) != lineBefore,
            "Window holds the position, so the row shifts: \(before) → \(after)")
    }

    // MARK: - Adoption

    /// Designating a row that is already visible must NOT jerk the viewport:
    /// the row stays where it sits. This matters most for the §1.2 shadow
    /// switch, which designates the SELECTED row — an adoption that slammed it
    /// to the viewport top would make every first arrow-key press jump.
    @Test("Designating an already-visible row does not move it")
    func adoptionHoldsAVisibleRow() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let items = Array(0..<60)

        // No designation yet: the view sits at the top, so rows 0… are visible.
        let before = renderFrame(
            items: items, anchored: nil, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        guard let lineBefore = screenLine(of: 3, in: before) else {
            Issue.record("row 3 should be visible at the top: \(before)")
            return
        }

        // Now designate row 3 — it must stay exactly where it was.
        let after = renderFrame(
            items: items, anchored: 3, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            screenLine(of: 3, in: after) == lineBefore,
            "adoption moved a visible row: \(before) → \(after)")
    }

    /// The anchored walk (>256 rows, variable heights) must adopt the same way
    /// the offset-correcting paths do: designating a row that is already
    /// visible holds it where it sits, not at the viewport top. Without this,
    /// identical app code jumps or doesn't depending purely on row count, and
    /// the §1.2 selection shadow-switch — which designates the SELECTED row —
    /// makes every first arrow-key press jump.
    @Test("Anchored walk: designating a visible row holds it where it sits")
    func anchoredWalkAdoptionHoldsAVisibleRow() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let items = Array(0..<400)

        // Settle with row 300 designated (it rides to the top from off-screen),
        // then read where a row a little below it sits.
        _ = settle(
            items: items, anchored: 300, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        let settled = renderFrame(
            items: items, anchored: 300, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        guard
            let target = (302...306).first(where: { (screenLine(of: $0, in: settled) ?? 0) >= 2 }),
            let lineBefore = screenLine(of: target, in: settled)
        else {
            Issue.record("no row sits mid-viewport to re-designate: \(settled)")
            return
        }

        // Re-designate that mid-viewport row: it must NOT jump to the top.
        let after = renderFrame(
            items: items, anchored: target, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(
            screenLine(of: target, in: after) == lineBefore,
            "row \(target) jumped on adoption: was line \(lineBefore), slice now \(after)")
    }

    /// The complement: designating an OFF-screen row has to bring it into view
    /// — there is no sensible "hold" for a line that isn't on screen, and the
    /// alternative (holding an out-of-range line) forces a blank viewport.
    @Test("Designating an off-screen row brings it into view")
    func adoptionRevealsAnOffscreenRow() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let items = Array(0..<60)

        let before = renderFrame(
            items: items, anchored: nil, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(screenLine(of: 40, in: before) == nil, "row 40 starts off screen")

        let after = renderFrame(
            items: items, anchored: 40, uniform: true,
            tuiContext: tuiContext, focusManager: focusManager)
        #expect(screenLine(of: 40, in: after) != nil, "designating revealed it: \(after)")
    }
}
