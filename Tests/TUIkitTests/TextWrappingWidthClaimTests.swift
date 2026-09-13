//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextWrappingWidthClaimTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// `TextWrapping`'s wrap and fit memos are keyed on the text and the budget,
/// and the answer also depends on the host's width CLAIM, which
/// `TerminalClient.simulated` moves at runtime. A memo filled under one host
/// and served under another hands back the old host's line breaks and widths:
/// the stale half of the diagnostic app's client picker, where `RenderCache`
/// dropped its own sizes and re-asked `Text`, and `Text` re-asked a memo that
/// had not been told.
///
/// The oracle is a COLD measure under the claim in force, not a literal, so
/// the expectations hold whatever host the test process starts as; the
/// `#require` is what stops a claim pair that happens to agree about this text
/// from passing vacuously.
///
/// `.serialized` and `@MainActor` because every test moves the PROCESS traits,
/// which other suites' width reads see, and restores them — the treatment
/// `TerminalWidthTraitsProcessTests` gets. The moved claim is in force for
/// exactly one measure.
@Suite("Text wrapping follows the width claim", .serialized)
@MainActor
struct TextWrappingWidthClaimTests {

    /// 👍🏽 — two cells where the skin tone merges, four where it detaches.
    private static let toned: Character = "\u{1F44D}\u{1F3FD}"

    /// Fits a budget of eight on one line under the 2-cell claim (4 + 1 + 2),
    /// and does not under a wider one (4 + 1 + 4 = 9 detached, 10 separated).
    private static let text = "memo \u{1F44D}\u{1F3FD}"
    private static let width = 8

    /// One measure on each side of a host switch, plus the cold oracle.
    private struct AcrossASwitch {
        /// Measured while the moved claim was in force: the old host.
        let underOldHost: TextWrapping.Wrapped
        /// Measured after switching back — what the memo serves.
        let served: TextWrapping.Wrapped
        /// Measured after switching back with both memos emptied first.
        let cold: TextWrapping.Wrapped
    }

    /// `traits` with the skin-tone rule moved to whichever side of the 2-cell
    /// answer `traits` is not on, so the cluster's claim changes by at least
    /// two cells from any starting host.
    private static func movedClaim(from traits: TerminalWidthTraits) -> TerminalWidthTraits {
        var moved = traits
        let isTwoCells = TerminalWidthTraits.withTraits(traits) { toned.terminalWidth == 2 }
        moved.skinTone = isTwoCells ? .detached : .merged
        return moved
    }

    /// Measures once under a moved claim, switches the process back, then
    /// measures twice more: once as the memo serves it, once cold.
    private func acrossAHostSwitch(_ measure: () -> TextWrapping.Wrapped) -> AcrossASwitch {
        let saved = TerminalWidthTraits.current
        TextWrapping.clearWrapCache()

        TerminalWidthTraits.current = Self.movedClaim(from: saved)
        let underOldHost = measure()
        TerminalWidthTraits.current = saved

        let served = measure()
        TextWrapping.clearWrapCache()
        return AcrossASwitch(underOldHost: underOldHost, served: served, cold: measure())
    }

    @Test("A wrap memoized under one host's claim is not served under another's")
    func wrapFollowsTheClaim() throws {
        let measured = acrossAHostSwitch {
            TextWrapping.wrapMeasured(Self.text, width: Self.width)
        }
        try #require(
            measured.underOldHost.lines != measured.cold.lines,
            "the two claims must break this text differently, or nothing here can go stale")
        // From a composing start, the stale memo served the detached host's
        // break — ["memo", "👍🏽"] at [4, 4] — for a line the claim in force
        // fits whole at 7.
        #expect(measured.served.lines == measured.cold.lines)
        #expect(measured.served.widths == measured.cold.widths)
    }

    @Test("A line-limited fit memoized under one host's claim is not served under another's")
    func fitFollowsTheClaim() throws {
        let measured = acrossAHostSwitch {
            TextWrapping.fitMeasured(Self.text, width: Self.width, maxLines: 1)
        }
        try #require(
            measured.underOldHost.lines != measured.cold.lines,
            "the two claims must fit this text differently, or nothing here can go stale")
        // The fit memo returns before the wrap is asked, so it needs a check of
        // its own. From a composing start, the stale memo served "memo…": text
        // the claim in force fits whole, cut to an ellipsis because it
        // overflowed another host's line.
        #expect(measured.served.lines == measured.cold.lines)
        #expect(measured.served.widths == measured.cold.widths)
    }
}
