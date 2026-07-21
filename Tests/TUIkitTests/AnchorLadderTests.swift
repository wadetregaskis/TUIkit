//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnchorLadderTests.swift
//
//  §5f of "Locating things without drawing them": the anchor names a ROW.
//  Inserting data above it must not move what's on screen (§6d — the
//  property browsers built scroll anchoring to patch); deleting the anchored
//  row falls to the nearest surviving neighbour from last frame's ladder;
//  replacing the whole list degrades to the clamped index, without crashing.
//  Plus a seeded storm mixing scrolls, jumps, and data edits, holding the
//  invariants no single-shot test can.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Rows keyed by stable id; each row's height follows its ID (i%3+1), so
/// heights travel with rows across edits and the stack is never uniform.
private struct LadderItem {
    let id: Int
}

@MainActor
@Suite("anchor ladder (§5f)")
struct AnchorLadderTests {
    private static let viewport = 6

    @discardableResult
    private func renderFrame(
        items: [Int], tuiContext: TUIContext, offset: Int
    ) -> [String] {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.self) { i in
                Text("row \(i)").frame(height: i % 3 + 1)
            }
        }
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: offset, viewportHeight: Self.viewport)
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

    private func shownIDs(_ slice: [String]) -> [Int] {
        slice.compactMap { line in
            line.hasPrefix("row ") ? Int(line.dropFirst(4)) : nil
        }
    }

    /// The DEFAULT anchor mode is Window (`Documentation/Scroll-anchoring.md`
    /// §1.1): technically *no* anchor — the position stays where it is in LINE
    /// coordinates, so prepending rows shifts what is on screen rather than
    /// holding the row that was there.
    ///
    /// This test previously asserted the opposite ("prepending must hold the
    /// view"). That was the anchored path's *placeholder* policy, which §2 of
    /// the spec explicitly flags as Row semantics applied silently as the
    /// default, to be corrected when this feature landed — it now is. The
    /// row-holding counterpart belongs to Row mode, which has no public
    /// designator yet (spec guardrail #1: it arrives via its own API, not by
    /// overloading the `UnitPoint` anchor), so it is deliberately not asserted
    /// here rather than faked through a mode that merely happens to re-bind.
    @Test("Window mode (the default): prepending shifts the view, line-coordinate stable")
    func insertAboveShiftsTheViewInWindowMode() {
        let tuiContext = TUIContext()
        var items = Array(1_000..<1_400)  // 400 rows, variable heights

        renderFrame(items: items, tuiContext: tuiContext, offset: 0)
        renderFrame(items: items, tuiContext: tuiContext, offset: 300)
        let before = renderFrame(items: items, tuiContext: tuiContext, offset: 300)
        #expect(!shownIDs(before).isEmpty, "anchored mid-list: \(before)")

        // Prepend 60 rows. Window keeps the ordinal, so the same slice of the
        // (now longer) list shows — i.e. earlier rows than before.
        items.insert(contentsOf: 0..<60, at: 0)
        let after = renderFrame(items: items, tuiContext: tuiContext, offset: 300)
        #expect(!shownIDs(after).isEmpty, "still rendering rows: \(after)")
        #expect(
            after != before,
            "Window holds the POSITION, not the row: before=\(before) after=\(after)")
        if let firstBefore = shownIDs(before).first, let firstAfter = shownIDs(after).first {
            #expect(
                firstAfter < firstBefore,
                "the same ordinal now names an earlier row (60 were prepended)")
        }
    }

    @Test("Window mode never re-binds; the row-holding modes do")
    func modePolicyBranch() {
        #expect(ScrollAnchorMode.window.holdsRowIdentity == false)
        #expect(ScrollAnchorMode.row.holdsRowIdentity == true)
        // No anchor asked for → Window, the spec's default.
        #expect(ScrollAnchorMode.resolved(defaultScrollAnchor: nil) == .window)
        #expect(ScrollAnchorMode.resolved(defaultScrollAnchor: .bottom) == .bottom)
        #expect(ScrollAnchorMode.resolved(defaultScrollAnchor: .top) == .top)
        // Mid-content has no edge meaning — still Window.
        #expect(ScrollAnchorMode.resolved(defaultScrollAnchor: .center) == .window)
    }

    @Test("Deleting the anchored row falls to its nearest surviving neighbour")
    func deleteAnchorFallsToNeighbour() {
        let tuiContext = TUIContext()
        var items = Array(1_000..<1_400)

        renderFrame(items: items, tuiContext: tuiContext, offset: 0)
        renderFrame(items: items, tuiContext: tuiContext, offset: 300)
        let before = renderFrame(items: items, tuiContext: tuiContext, offset: 300)
        let visible = shownIDs(before)
        guard let anchorID = visible.first else {
            Issue.record("nothing visible: \(before)")
            return
        }

        items.removeAll { $0 == anchorID }
        let after = renderFrame(items: items, tuiContext: tuiContext, offset: 300)
        let survivors = shownIDs(after)
        #expect(!survivors.contains(anchorID), "the deleted row is gone")
        #expect(
            !Set(survivors).isDisjoint(with: visible.dropFirst()),
            "the view stayed in the anchored neighbourhood: was \(visible), now \(survivors)")
    }

    @Test("Replacing the whole list degrades to the clamped index, no crash")
    func wholesaleReplacementClamps() {
        let tuiContext = TUIContext()
        let items = Array(1_000..<1_400)

        renderFrame(items: items, tuiContext: tuiContext, offset: 0)
        renderFrame(items: items, tuiContext: tuiContext, offset: 300)

        let replaced = Array(50_000..<50_400)  // disjoint id namespace
        let after = renderFrame(items: replaced, tuiContext: tuiContext, offset: 300)
        let shown = shownIDs(after)
        #expect(shown.allSatisfy { $0 >= 50_000 }, "shows the new data: \(after)")
    }

    @Test("Storm: scrolls, jumps, and data edits hold the invariants")
    func anchorStorm() {
        let tuiContext = TUIContext()
        var items = Array(1_000..<1_400)
        var nextID = 2_000
        var offset = 0
        var seed: UInt64 = 0x5EED_CAFE_F00D_D00D
        func random(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(1, bound)))
        }

        for iteration in 0..<250 {
            switch random(6) {
            case 0: offset = max(0, offset - (1 + random(3)))       // scroll up
            case 1: offset += 1 + random(3)                          // scroll down
            case 2: offset = random(700)                             // jump
            case 3:                                                  // insert block
                let at = random(items.count)
                items.insert(contentsOf: nextID..<(nextID + 20), at: at)
                nextID += 20
            case 4:                                                  // remove block
                if items.count > 300 {
                    let at = random(items.count - 20)
                    items.removeSubrange(at..<(at + 20))
                }
            default:                                                 // quiet frame
                break
            }

            let slice = renderFrame(items: items, tuiContext: tuiContext, offset: offset)
            let shown = shownIDs(slice)
            // Invariants: every visible row exists in the data, in data order,
            // without duplicates. (Emptiness is legal only past the content.)
            let itemSet = Set(items)
            #expect(
                shown.allSatisfy { itemSet.contains($0) },
                "iteration \(iteration): ghost rows \(shown)")
            #expect(
                Set(shown).count == shown.count,
                "iteration \(iteration): duplicate rows \(shown)")
            let positions = shown.compactMap { items.firstIndex(of: $0) }
            #expect(
                positions == positions.sorted(),
                "iteration \(iteration): rows out of order \(shown)")
        }
    }
}
