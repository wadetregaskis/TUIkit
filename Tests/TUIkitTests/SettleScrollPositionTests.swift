//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SettleScrollPositionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `settleScrollPosition` is the once-per-frame sequence `List` and both of
/// `Table`'s paths run over their scroll offset: clamp, clamp the top clip, snap
/// off the resting duplicate, apply the anchor.
///
/// Both of the things it promises were documented at length and pinned by
/// nothing. Reordering the sequence, and deleting the measure-pass guard
/// outright, each left the whole 6,258-test suite green — so the two rules with
/// the loudest comments in this area were the two nothing checked. These are the
/// checks.
@MainActor
@Suite("The scroll-position settle")
struct SettleScrollPositionTests {

    /// A handler whose offset is out of range, which is what a clamp is for.
    private func strandedHandler(
        itemCount: Int = 40, viewportHeight: Int = 8, offset: Int
    ) -> ItemListHandler<Int> {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: itemCount, viewportHeight: viewportHeight,
            selectionMode: .single, canBeFocused: true)
        handler.scrollOffset = offset
        return handler
    }

    /// The rule with the described symptom: a `List` with no explicit height that
    /// shares space with a flexible sibling is MEASURED with the full available
    /// height and rendered into less, so a measure-pass clamp resolves
    /// `maxOffset` against a viewport that is not the real one and drags the
    /// offset back every frame. The list then cannot be scrolled its last
    /// screenful. Nothing asserted it.
    @Test("A measuring pass changes nothing at all")
    func measuringPassIsInert() {
        let handler = strandedHandler(offset: 99)
        let stranded = handler.scrollOffset
        #expect(stranded > handler.maxOffset, "the fixture really is out of range")

        handler.settleScrollPosition(
            measuring: true, overflowing: true, drawsTextIndicators: true, firstRowHeight: 1)
        #expect(
            handler.scrollOffset == stranded,
            "a measure pass must not touch the persistent offset, got \(handler.scrollOffset)")

        // …and the same call on the render pass does the clamp it was holding
        // back, so the guard is the only difference between the two.
        handler.settleScrollPosition(
            measuring: false, overflowing: true, drawsTextIndicators: true, firstRowHeight: 1)
        #expect(
            handler.scrollOffset <= handler.maxOffset,
            "the render pass clamps, got \(handler.scrollOffset) of \(handler.maxOffset)")
    }

    /// The order inside the sequence. The snap tests `scrollOffset == 1`, and the
    /// clamp is one of the things that can PRODUCE 1 — so an offset stranded
    /// above a `maxOffset` of 1 lands on 1 and must then be snapped to 0. Run the
    /// snap first and it sees 99, does nothing, and the frame rests on the offset
    /// whose indicator line hides the only row it could show.
    @Test("The clamp runs before the resting snap, which is why the snap sees 1")
    func clampFeedsTheSnap() {
        // 10 rows in a 9-row viewport: maxOffset is 1, so a stranded offset
        // clamps to exactly the value the snap is about.
        let handler = strandedHandler(itemCount: 10, viewportHeight: 9, offset: 99)
        #expect(handler.maxOffset == 1, "the fixture's maxOffset is the snap's value")

        handler.settleScrollPosition(
            measuring: false, overflowing: true, drawsTextIndicators: true, firstRowHeight: 1)
        #expect(
            handler.scrollOffset == 0,
            "clamped to 1, then snapped off it, got \(handler.scrollOffset)")
    }

    /// The snap's own exceptions still apply through the shared sequence — it is
    /// the same call, and this says so rather than leaving the reader to check.
    @Test("A scrollbar spends no line, so the sequence leaves the offset at 1")
    func noTextIndicatorNoSnap() {
        let handler = strandedHandler(itemCount: 10, viewportHeight: 9, offset: 99)
        handler.settleScrollPosition(
            measuring: false, overflowing: true, drawsTextIndicators: false, firstRowHeight: 1)
        #expect(
            handler.scrollOffset == 1,
            "nothing to save, nothing to snap, got \(handler.scrollOffset)")
    }

    /// The anchor step is IN the sequence — a follow-the-log view opens glued to
    /// the tail through one `settleScrollPosition` and nothing else.
    ///
    /// From offset 0 on purpose. A stranded offset above the tail proves nothing
    /// here: the clamp alone lands it on `maxOffset`, so the assertion passes with
    /// `applyAnchorHold` deleted outright — which is how the first version of
    /// this test was written, and what it was worth.
    ///
    /// This does NOT pin the anchor's POSITION in the sequence, only its
    /// presence. Moving it above the clamp changes nothing measurable here or
    /// anywhere in the suite; the case that would tell them apart is a `.row`
    /// anchor whose placement carries a top clip that a later `clampTopClip`
    /// would shrink, and that fixture is not yet written.
    @Test("The anchor step is part of the sequence: a .bottom view opens on the tail")
    func anchorRunsInTheSequence() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8,
            selectionMode: .single, canBeFocused: true)
        handler.declaredAnchorMode = .bottom
        #expect(handler.scrollOffset == 0, "starts at the top, where a clamp leaves it")

        handler.settleScrollPosition(
            measuring: false, overflowing: true, drawsTextIndicators: true, firstRowHeight: 1)
        #expect(
            handler.scrollOffset == handler.maxOffset,
            "glued to the tail, got \(handler.scrollOffset) of \(handler.maxOffset)")
    }
}
