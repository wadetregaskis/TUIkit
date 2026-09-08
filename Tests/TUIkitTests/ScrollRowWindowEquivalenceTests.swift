//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollRowWindowEquivalenceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `ScrollRowWindow` replaced three separately-written copies of one rule. This
/// sweeps it against a transcription of each, over every shape they can be
/// asked about, so "the extraction is inert" is a checked claim rather than an
/// argument.
///
/// A transcription is a weak regression test on its own — it pins the mechanism,
/// bugs included, and can only catch a transcription slip. That is exactly what
/// is wanted HERE, where the claim under test is equivalence with what was
/// deleted; the behaviour is pinned by the drawn-picture suites that already
/// exist for both views. These transcriptions are frozen: they are copies of
/// code at `36beb39a` and must never be "fixed" to match a future
/// `ScrollRowWindow`. If one starts disagreeing, that is the finding.
@Suite("The shared row window matches the three it replaced")
struct ScrollRowWindowEquivalenceTests {

    // MARK: - The three originals, transcribed

    /// `Table.rowWindow` — the variable-height copy, and the closest thing to a
    /// general form the codebase already had.
    private static func legacyMultiLineTable(
        scrollOffset: Int, count: Int, contentHeight: Int, topClip: Int,
        drawsTextIndicators: Bool, height: (Int) -> Int
    ) -> (range: Range<Int>, showAbove: Bool, showBelow: Bool, topClip: Int) {
        guard count > 0 else { return (0..<0, false, false, 0) }
        let clamped = min(max(0, scrollOffset), count - 1)
        let (offset, topClip) =
            drawsTextIndicators
            ? ScrollWindowOrigin.absorbing(
                offset: clamped, topClip: topClip, firstRowHeight: height(0))
            : (clamped, topClip)
        let showAbove = offset > 0 || topClip > 0

        func fill(budget: Int) -> Int {
            var used = -topClip
            var end = offset
            while end < count {
                let rowH = height(end)
                if used + rowH > budget && end > offset {
                    if used < budget { end += 1 }
                    break
                }
                used += rowH
                end += 1
            }
            return max(offset + 1, end)
        }

        let aboveReserve = (showAbove && drawsTextIndicators) ? 1 : 0
        var end = fill(budget: contentHeight - aboveReserve)
        if end < count, drawsTextIndicators {
            end = fill(budget: contentHeight - aboveReserve - 1)
        }
        return (offset..<min(count, end), showAbove, end < count, topClip)
    }

    /// `_ListCore.calculateVisibleRows` — reduced to the index range it emits.
    private static func legacyListFill(
        offset: Int, topClip: Int, count: Int, viewportHeight: Int, height: (Int) -> Int
    ) -> Int {
        var linesUsed = -topClip
        var currentIndex = offset
        while currentIndex < count && linesUsed < viewportHeight {
            let rowHeight = height(currentIndex)
            if linesUsed + rowHeight <= viewportHeight {
                linesUsed += rowHeight
                currentIndex += 1
            } else {
                currentIndex += 1  // the straddling row is emitted, then break
                break
            }
        }
        return currentIndex
    }

    /// `_ListCore.resolveVisibleWindow`, plus the branch its CALLER made between
    /// the reserving and non-reserving paths — the two together are the rule.
    private static func legacyList(
        offset: Int, topClip: Int, count: Int, contentHeight: Int,
        drawsTextIndicators: Bool, overflowing: Bool, height: (Int) -> Int
    ) -> Range<Int> {
        guard drawsTextIndicators else {
            return offset..<legacyListFill(
                offset: offset, topClip: topClip, count: count,
                viewportHeight: contentHeight, height: height)
        }
        guard overflowing else {
            return offset..<legacyListFill(
                offset: offset, topClip: topClip, count: count,
                viewportHeight: contentHeight, height: height)
        }
        let aboveLines = (offset > 0 || topClip > 0) ? 1 : 0
        let withoutBelow = legacyListFill(
            offset: offset, topClip: topClip, count: count,
            viewportHeight: max(1, contentHeight - aboveLines), height: height)
        guard offset + (withoutBelow - offset) < count else { return offset..<withoutBelow }
        return offset..<legacyListFill(
            offset: offset, topClip: topClip, count: count,
            viewportHeight: max(1, contentHeight - aboveLines - 1), height: height)
    }

    /// `_TableCore.reserveIndicatorLines` — the uniform single-line copy, which
    /// answers in counts rather than a range.
    private static func legacySingleLineTable(
        scrollOffset: Int, count: Int, contentHeight: Int, drawsText: Bool
    ) -> (viewport: Int, origin: Int) {
        let origin =
            drawsText
            ? ScrollWindowOrigin.absorbing(
                offset: scrollOffset, topClip: 0, firstRowHeight: 1
            ).offset
            : scrollOffset
        let aboveLines = (drawsText && origin > 0) ? 1 : 0
        let remaining = count - origin
        let rowsWithoutBelow = min(remaining, max(1, contentHeight - aboveLines))
        let belowShown = origin + rowsWithoutBelow < count
        let visibleRowCount =
            belowShown && drawsText
            ? max(1, contentHeight - aboveLines - 1)
            : rowsWithoutBelow
        return (max(1, min(visibleRowCount, remaining)), origin)
    }

    // MARK: - The sweep

    /// Height profiles: uniform (both Table paths and a plain List), varied, a
    /// tall first row (which is what the absorb turns on), and one row taller
    /// than any viewport swept.
    private static var profiles: [(name: String, height: @Sendable (Int) -> Int)] {
        [
            ("uniform 1", { _ in 1 }),
            ("uniform 3", { _ in 3 }),
            ("alternating 1/2", { $0.isMultiple(of: 2) ? 1 : 2 }),
            ("tall first", { $0 == 0 ? 5 : 1 }),
            ("one giant row", { $0 == 3 ? 40 : 1 }),
            ("growing", { 1 + $0 % 4 }),
        ]
    }

    /// Whether `(offset, topClip, contentHeight, drawsTextIndicators)` is a shape
    /// any of the three callers can actually be in. Two invariants, both checked
    /// against the code that enforces them rather than assumed:
    ///
    /// - `ItemListHandler.clampTopClip()` sets
    ///   `scrollTopClipLines = min(clip, max(0, max(1, rowHeight(offset)) - 1))`,
    ///   so a clip is strictly less than the height of the row it clips. A clip
    ///   of 2 on a one-line row is not a state that exists.
    /// - `ResolvedScrollIndicators.fitting(contentHeight:)` withholds the "N more"
    ///   lines below `minimumTextHeight == 3` — the decision that a viewport too
    ///   short for two indicators and a row shows content instead of neither — so
    ///   text indicators imply a content area of at least three lines.
    ///
    /// Outside those the three copies disagree, and `degenerateShapesAreDecided`
    /// below records which answer this one gives and why.
    private static func reachable(
        offset: Int, topClip: Int, contentHeight: Int, drawsTextIndicators: Bool,
        height: (Int) -> Int
    ) -> Bool {
        guard topClip < height(offset) else { return false }
        return !drawsTextIndicators || contentHeight >= ResolvedScrollIndicators.minimumTextHeight
    }

    @Test("It agrees with Table.rowWindow on every shape")
    func matchesMultiLineTable() {
        var compared = 0
        for (name, height) in Self.profiles {
            for count in [1, 2, 3, 7, 20] {
                for offset in 0..<min(count + 2, 9) {
                    for topClip in [0, 1, 2] {
                        for contentHeight in [1, 2, 3, 5, 12] {
                            for draws in [false, true] {
                                guard
                                    Self.reachable(
                                        offset: offset, topClip: topClip,
                                        contentHeight: contentHeight,
                                        drawsTextIndicators: draws, height: height)
                                else { continue }
                                let legacy = Self.legacyMultiLineTable(
                                    scrollOffset: offset, count: count,
                                    contentHeight: contentHeight, topClip: topClip,
                                    drawsTextIndicators: draws, height: height)
                                let shared = ScrollRowWindow.resolve(
                                    scrollOffset: offset, count: count,
                                    contentHeight: contentHeight, topClip: topClip,
                                    drawsTextIndicators: draws, height: height)
                                compared += 1
                                #expect(
                                    shared.range == legacy.range
                                        && shared.showsAbove == legacy.showAbove
                                        && shared.showsBelow == legacy.showBelow
                                        && shared.topClip == legacy.topClip,
                                    """
                                    \(name) count=\(count) offset=\(offset) \
                                    clip=\(topClip) h=\(contentHeight) draws=\(draws): \
                                    shared \(shared) vs legacy \(legacy)
                                    """)
                            }
                        }
                    }
                }
            }
        }
        #expect(compared > 700, "the sweep collapsed to \(compared) cases")
    }

    /// The List copy, whose `overflowing` gate the caller folds into the
    /// `drawsTextIndicators` argument.
    @Test("It agrees with _ListCore's window on every shape")
    func matchesList() {
        for (name, height) in Self.profiles {
            for count in [1, 2, 3, 7, 20] {
                for offset in 0..<min(count, 7) {
                    for topClip in [0, 1, 2] {
                        for contentHeight in [1, 2, 3, 5, 12] {
                            for draws in [false, true] {
                                for overflowing in [false, true] {
                                    guard
                                        Self.reachable(
                                            offset: offset, topClip: topClip,
                                            contentHeight: contentHeight,
                                            drawsTextIndicators: draws && overflowing,
                                            height: height)
                                    else { continue }
                                    // The absorb runs inside the shared version
                                    // and ran in `windowOrigin` before it, so
                                    // the legacy transcription is fed the same
                                    // resolved origin its caller would have.
                                    let resolved =
                                        draws && overflowing
                                        ? ScrollWindowOrigin.absorbing(
                                            offset: offset, topClip: topClip,
                                            firstRowHeight: height(0))
                                        : (offset: offset, topClip: topClip)
                                    let legacy = Self.legacyList(
                                        offset: resolved.offset, topClip: resolved.topClip,
                                        count: count, contentHeight: contentHeight,
                                        drawsTextIndicators: draws, overflowing: overflowing,
                                        height: height)
                                    let shared = ScrollRowWindow.resolve(
                                        scrollOffset: offset, count: count,
                                        contentHeight: contentHeight, topClip: topClip,
                                        drawsTextIndicators: draws && overflowing,
                                        height: height)
                                    #expect(
                                        shared.range == legacy,
                                        """
                                        \(name) count=\(count) offset=\(offset) \
                                        clip=\(topClip) h=\(contentHeight) draws=\(draws) \
                                        overflowing=\(overflowing): \
                                        shared \(shared.range) vs legacy \(legacy)
                                        """)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The uniform single-line copy, which answers in counts.
    @Test("It agrees with Table.reserveIndicatorLines on every shape")
    func matchesSingleLineTable() {
        for count in [1, 2, 3, 7, 20, 50] {
            for offset in 0..<min(count, 9) {
                for contentHeight in [1, 2, 3, 5, 12] {
                    for draws in [false, true]
                    where Self.reachable(
                        offset: offset, topClip: 0, contentHeight: contentHeight,
                        drawsTextIndicators: draws, height: { _ in 1 })
                    {
                        let legacy = Self.legacySingleLineTable(
                            scrollOffset: offset, count: count,
                            contentHeight: contentHeight, drawsText: draws)
                        let shared = ScrollRowWindow.resolve(
                            scrollOffset: offset, count: count,
                            contentHeight: contentHeight, topClip: 0,
                            drawsTextIndicators: draws, height: { _ in 1 })
                        #expect(
                            max(1, shared.range.count) == legacy.viewport
                                && shared.range.lowerBound == legacy.origin,
                            """
                            count=\(count) offset=\(offset) h=\(contentHeight) \
                            draws=\(draws): shared \
                            (\(max(1, shared.range.count)), \(shared.range.lowerBound)) \
                            vs legacy \(legacy)
                            """)
                    }
                }
            }
        }
    }

    /// The one region where the three copies did NOT agree, and what this one
    /// answers there.
    ///
    /// A content area of one line with something hidden above it: the reservation
    /// would take the only line the rows have. `_ListCore` floored the budget at
    /// 1 and drew as many rows as fit; both `Table` paths let it go to 0 and drew
    /// exactly one. Neither is reachable — `fitting(contentHeight:)` withholds the
    /// indicator below three lines, so nothing is ever reserved out of a
    /// one-line area — so this is not a bug fixed, it is a disagreement removed.
    ///
    /// `_ListCore`'s floor is the one kept, because a budget that can go negative
    /// is the sharper edge to leave lying around: with a clip in play the
    /// unfloored version starts at `-topClip` against a negative budget, and
    /// which rows come out of that is not something anyone reasoned about. Pinned
    /// so a future reader can see the choice was made rather than inherited.
    @Test("The shape the three disagreed about has a decided answer")
    func degenerateShapesAreDecided() {
        // Unreachable by construction, and asserted anyway.
        #expect(
            ResolvedScrollIndicators(bar: false, text: true).fitting(contentHeight: 1).text
                == false,
            "a one-line content area is supposed to withhold the text indicators")

        let window = ScrollRowWindow.resolve(
            scrollOffset: 2, count: 7, contentHeight: 1, topClip: 0,
            drawsTextIndicators: true, height: { _ in 1 })
        #expect(
            window.range == 2..<3,
            "the floored budget admits the one row a one-line area can hold: \(window.range)")
        #expect(window.showsAbove && window.showsBelow)
    }

    /// The bound that makes the extraction safe for `_ListCore`, whose `height`
    /// RENDERS the row it is asked about. A loop that peeked one row past the
    /// window would render one row more per frame than the old code did — which
    /// is invisible in every range comparison above.
    @Test("It never asks the height of a row beyond the window")
    func asksNoRowBeyondTheWindow() {
        for count in [1, 3, 7, 20] {
            for offset in 0..<min(count, 5) {
                for contentHeight in [1, 3, 5, 12] {
                    for draws in [false, true] {
                        var asked = Set<Int>()
                        let window = ScrollRowWindow.resolve(
                            scrollOffset: offset, count: count,
                            contentHeight: contentHeight, topClip: 0,
                            drawsTextIndicators: draws,
                            height: { asked.insert($0); return 1 })
                        // Row 0 is fair game whatever the window: the absorb
                        // asks for its height to decide whether to swallow it.
                        let allowed = Set(window.range).union(draws ? [0] : [])
                            // …and the row that straddles the end, which has to
                            // be measured to be found.
                            .union([window.range.upperBound])
                        #expect(
                            asked.subtracting(allowed).isEmpty,
                            """
                            count=\(count) offset=\(offset) h=\(contentHeight) \
                            draws=\(draws): asked \(asked.sorted()) beyond \
                            \(window.range) — a List renders every row it asks about
                            """)
                    }
                }
            }
        }
    }
}
