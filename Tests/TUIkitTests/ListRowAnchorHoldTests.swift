//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowAnchorHoldTests.swift
//
//  A `List` (and Table, which shares ItemListHandler) with a bound
//  `.anchorPosition(.row(id))` — set directly, or via the §1.2 selection
//  shadow-switch — must HOLD that row: the scroll offset adjusts so the row
//  keeps its screen line as rows are inserted or removed around it, the same
//  way a windowed LazyVStack does. Before `applyRowAnchorHold`, the List wired
//  the anchor STATE (the shadow-switch flipped the read-out) but never moved
//  the offset, so the row jumped.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List row-anchor hold")
struct ListRowAnchorHoldTests {

    private static let viewport = 8

    /// One rendered frame of a `List` with an optional bound `.row` anchor,
    /// returned as the ANSI-stripped visible lines. The shared `tui`/`fm`
    /// persist the handler across calls (the hold lives on it).
    private func renderFrame(
        items: [Int], anchored: Int?, tui: TUIContext, fm: FocusManager
    ) -> [String] {
        let list = List(selection: .constant(Int?.none)) {
            ForEach(items, id: \.self) { Text("row \($0)") }
        }
        .frame(height: Self.viewport)
        .defaultScrollAnchor(.bottom)
        .anchorPosition(.constant(anchored.map { ScrollAnchor.row($0) }))

        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 24, availableHeight: Self.viewport, environment: env, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(list, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func screenLine(of row: Int, in lines: [String]) -> Int? {
        lines.firstIndex { $0.contains("row \(row)") && !$0.contains("row \(row)0") }
    }

    private func settle(
        items: [Int], anchored: Int, tui: TUIContext, fm: FocusManager
    ) -> (line: Int, lines: [String])? {
        var lines: [String] = []
        for _ in 0..<4 {
            lines = renderFrame(items: items, anchored: anchored, tui: tui, fm: fm)
        }
        guard let line = screenLine(of: anchored, in: lines) else { return nil }
        return (line, lines)
    }

    /// One frame of a MULTI-LINE list, which is where the hold's clamp went
    /// wrong: `viewportHeight` is still the provisional LINE count when the
    /// hold runs, so counting rows against it let the anchored row land far
    /// below the fold.
    private func renderTallFrame(
        items: [Int], anchored: Int?, tui: TUIContext, fm: FocusManager
    ) -> [String] {
        let list = List(selection: .constant(Int?.none)) {
            ForEach(items, id: \.self) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Text("row \(item)")
                    Text("· detail")
                    Text("· detail")
                }
            }
        }
        .frame(height: 20)
        .anchorPosition(.constant(anchored.map { ScrollAnchor.row($0) }))

        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 24, availableHeight: 20, environment: env, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(list, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("A designated row lands inside a multi-line list's viewport")
    func multiLineAnchorLandsOnScreen() {
        let tui = TUIContext()
        let fm = FocusManager()
        let items = Array(0..<40)

        // Frame 1 rests at the top; frame 2 designates a row far below it.
        _ = renderTallFrame(items: items, anchored: nil, tui: tui, fm: fm)
        let after = renderTallFrame(items: items, anchored: 20, tui: tui, fm: fm)

        // The clamp used to be computed against the LINE count (17 − 2 = 15),
        // so the row was "held" at screen row 15 of a viewport that only has
        // five 3-line rows — offset 5, and row 20 nowhere on screen.
        let line = screenLine(of: 20, in: after)
        #expect(line != nil, "the anchored row must be on screen:\n\(after.joined(separator: "\n"))")
        #expect(
            (line ?? 0) >= 10,
            "…and at the BOTTOM of the viewport, where it was held:\n\(after.joined(separator: "\n"))")
    }

    @Test("A row designated far below the fold still lands on screen")
    func farAnchorClearsTheCheapMaxOffsetFloor() {
        let tui = TUIContext()
        let fm = FocusManager()
        let items = Array(0..<50)

        // `maxOffset` early-outs to the cheap floor `itemCount - contentHeight`
        // (50 − 18 = 32) while the offset is nowhere near the tail, so as not to
        // walk tail row heights every frame on a huge list. That floor is a
        // LOWER bound: with 3-line rows only six fit, so the true bound is 44.
        // A hold wanting offset 41 was clamped to 32 and left row 45 off screen.
        _ = renderTallFrame(items: items, anchored: nil, tui: tui, fm: fm)
        let after = renderTallFrame(items: items, anchored: 45, tui: tui, fm: fm)

        // Asserted on the SINGLE frame that follows the designation: settling
        // over several frames would let a later frame's offset creep and mask it.
        #expect(
            screenLine(of: 45, in: after) != nil,
            "the anchored row must be on screen after ONE frame:\n\(after.joined(separator: "\n"))")
    }

    @Test("Inserting rows above the anchored row holds it on its screen line")
    func insertAboveHoldsTheRow() {
        let tui = TUIContext()
        let fm = FocusManager()
        var items = Array(0..<30)
        let anchored = 20

        // The anchor reveals row 20 (off-screen at the top by default) and
        // settles it on a screen line.
        guard let (before, settled) = settle(items: items, anchored: anchored, tui: tui, fm: fm)
        else {
            Issue.record("row \(anchored) never came into view")
            return
        }

        // Insert five rows above it. Its ordinal shifts; its screen line must
        // not move — the List scrolls to compensate.
        items.insert(contentsOf: 100..<105, at: 15)
        let after = renderFrame(items: items, anchored: anchored, tui: tui, fm: fm)
        #expect(
            screenLine(of: anchored, in: after) == before,
            "row \(anchored) moved: was line \(before), settled \(settled), now \(after)")
    }

    @Test("Deleting rows above the anchored row also holds it")
    func deleteAboveHoldsTheRow() {
        let tui = TUIContext()
        let fm = FocusManager()
        var items = Array(0..<30)
        let anchored = 20

        guard let (before, _) = settle(items: items, anchored: anchored, tui: tui, fm: fm) else {
            Issue.record("row \(anchored) never came into view")
            return
        }

        items.removeSubrange(5..<10)
        let after = renderFrame(items: items, anchored: anchored, tui: tui, fm: fm)
        #expect(
            screenLine(of: anchored, in: after) == before,
            "row \(anchored) moved: was line \(before), now \(after)")
    }

    /// The contrast: with no bound row anchor, the List does NOT hold — the
    /// same insert shifts the row. Guards that the hold is what does the work
    /// (and that an un-anchored List is unaffected by the new machinery).
    @Test("Without a bound anchor the same insert DOES move the row")
    func withoutAnchorTheRowMoves() {
        let tui = TUIContext()
        let fm = FocusManager()
        var items = Array(0..<30)

        // Drive to where row 20 is visible (via an anchor), then drop the
        // anchor: the comparison needs the row on screen to begin with.
        _ = settle(items: items, anchored: 20, tui: tui, fm: fm)
        let before = renderFrame(items: items, anchored: nil, tui: tui, fm: fm)
        let lineBefore = screenLine(of: 20, in: before)

        items.insert(contentsOf: 100..<105, at: 5)
        let after = renderFrame(items: items, anchored: nil, tui: tui, fm: fm)
        #expect(
            screenLine(of: 20, in: after) != lineBefore,
            "an un-anchored List holds the position, so the row shifts: \(before) → \(after)")
    }
}
