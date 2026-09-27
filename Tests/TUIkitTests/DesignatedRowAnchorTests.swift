//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        return renderVisible(list, anchored: anchored, tuiContext: tuiContext, focusManager: focusManager)
    }

    /// One rendered frame of `list`, with `anchored` designated, as the
    /// VISIBLE lines.
    private func renderVisible<V: View>(
        _ list: V, anchored: Int?, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        if let anchored {
            environment.anchorPosition = AnchorPositionBinding(.constant(.row(AnyHashable(anchored))))
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

    /// Rows above a held row deleted until too few are left to fill its line:
    /// it rides up to where the first row meets the viewport's top, as on the
    /// other two paths — and, as they do, the view scrolls to the top with it.
    /// Every row above it is measured then, so its place is exact. Riding up
    /// at the offset it had, the first row was drawn at that offset — under
    /// "N more lines above", with nothing above it.
    @Test("Anchored walk: a held row whose rows above are deleted rides up to the top, and the view scrolls there")
    func anchoredWalkRideUpScrollsToTheTop() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        var items = Array(0..<400)
        func frame(_ row: Int?) -> [String] {
            let list = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { i in
                        Text("row \(i)").frame(height: i % 3 + 1)
                    }
                }
            }
            .scrollPosition(Binding(get: { position }, set: { position = $0 }))
            .scrollIndicatorStyle(.text)
            .frame(height: Self.viewport)
            return renderVisible(list, anchored: row, tuiContext: tuiContext, focusManager: focusManager)
        }

        _ = frame(nil)
        position.scrollTo(y: 30)
        let scrolled = frame(nil)
        // The row that starts lowest on screen, held where it sits.
        guard
            let heldLine = scrolled.indices.dropFirst(2).last(where: { scrolled[$0].hasPrefix("row ") }),
            let held = Int(scrolled[heldLine].dropFirst(4))
        else {
            Issue.record("no row starts below line 1: \(scrolled)")
            return
        }
        for _ in 0..<3 { _ = frame(held) }
        // One row of one line is left above it.
        let kept = stride(from: held - 1, through: 0, by: -1).first { $0.isMultiple(of: 3) } ?? 0
        items.removeAll { $0 < held && $0 != kept }
        let after = frame(held)
        #expect(scrolled.first?.contains("more") == true, "precondition: \(scrolled)")
        #expect(after.first == "row \(kept)", "the first row on the top line, nothing above it: \(after)")
        #expect(screenLine(of: held, in: after) == 1, "\(after)")
    }

    // MARK: - The contrast: no designation means no holding

    /// Shows the designation is doing the work: with none, the default is
    /// Window, which holds the OFFSET — so the same edit moves the row.
    @Test("Without a designation the same insert DOES move the row (Window default)")
    func withoutDesignationTheRowMoves() throws {
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
        let lineBefore = try #require(
            screenLine(of: 300, in: before),
            "row 300 was not on screen to begin with: \(before)")

        // THREE rows inserted, not the twenty-five this test used to insert.
        // Holding the offset shifts the window by the inserted count, and
        // twenty-five of them past a viewport five rows deep left row 300
        // nowhere on screen: `screenLine` answered nil, so the assertion was
        // `nil != Optional(0)` — true whatever had happened, including a
        // viewport that jumped somewhere else entirely. Three keeps the row
        // visible in both frames, so the control compares two real lines, and
        // `#require` is what keeps it that way.
        items.insert(contentsOf: 1_000..<1_003, at: 10)
        let after = renderFrame(
            items: items, anchored: nil, uniform: false,
            tuiContext: tuiContext, focusManager: focusManager)
        let lineAfter = try #require(
            screenLine(of: 300, in: after),
            "row 300 left the screen entirely: \(after)")

        // Six lines, not three: the window keeps its ORDINAL offset, so it now
        // opens on rows 297, 298 and 299, whose heights under this harness's
        // `i % 3 + 1` are 1, 2 and 3. Row 300 was the top line; it is now the
        // seventh.
        #expect(lineBefore == 0)
        #expect(
            lineAfter == 6,
            "Window holds the offset, so the row shifts down past the rows now above it: \(before) → \(after)")
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

    /// Revealed at the top edge, under the "more above" line, an off-screen
    /// row sits one line down, and the rows above it fill that line — from
    /// where the stack's top is, at the highest. Row 299 is three lines tall:
    /// at the top of the list the rows filling the line would start above the
    /// stack's top, where the fill places none, so the band started at the
    /// row itself and the scroll view showed it from line 0.
    @Test("Anchored walk: a row designated off screen from the top lands under the \"more above\" line, and stays there")
    func anchoredWalkRevealLandsOnItsLine() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let list = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<400, id: \.self) { i in
                    Text("row \(i)").frame(height: i % 3 + 1)
                }
            }
        }
        .scrollPosition(Binding(get: { position }, set: { position = $0 }))
        .scrollIndicatorStyle(.text)
        .frame(height: Self.viewport)
        func frame() -> [String] {
            renderVisible(list, anchored: 300, tuiContext: tuiContext, focusManager: focusManager)
        }

        _ = renderVisible(list, anchored: nil, tuiContext: tuiContext, focusManager: focusManager)
        var held: [String] = []
        for _ in 0..<3 { held = frame() }
        #expect(screenLine(of: 300, in: held) == 1, "row 300 under the \"more above\" line: \(held)")

        // Scrolled back toward the top, where the row cannot stay on its line.
        position.scrollTo(y: 1)
        let scrolled = frame()
        #expect(screenLine(of: 300, in: scrolled) == 1, "\(held) → \(scrolled)")
    }

    /// Within a screen of the end of the data, the rows below a held row cannot
    /// fill the viewport under its line: the row rides down until the data's
    /// last line meets the viewport's, where the other two paths' clamp to the
    /// scrollable range puts it. Held on the line it was revealed on, the band
    /// ended above the viewport's bottom, the content was shorter than the
    /// offset needed, and the scroll view drew the band from its first line
    /// over blank lines — row 399 on line 3, under row 398.
    @Test("Anchored walk: a row designated within a screen of the end, from the top, lands where the data ends")
    func anchoredWalkRevealNearTheEnd() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition()
        let list = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<400, id: \.self) { i in
                    Text("row \(i)").frame(height: i % 3 + 1)
                }
            }
        }
        .scrollPosition(Binding(get: { position }, set: { position = $0 }))
        .scrollIndicatorStyle(.text)
        .frame(height: Self.viewport)

        _ = renderVisible(list, anchored: nil, tuiContext: tuiContext, focusManager: focusManager)
        var held: [String] = []
        for _ in 0..<3 {
            held = renderVisible(list, anchored: 399, tuiContext: tuiContext, focusManager: focusManager)
        }
        #expect(screenLine(of: 399, in: held) == Self.viewport - 1, "on the last line: \(held)")
        #expect(screenLine(of: 398, in: held) == Self.viewport - 4, "the rows above it fill the lines above it: \(held)")
        #expect(screenLine(of: 396, in: held) == 1, "\(held)")
    }
}
