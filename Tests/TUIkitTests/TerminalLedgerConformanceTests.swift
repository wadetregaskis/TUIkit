//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalLedgerConformanceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - The models against the measurements

/// Every per-host cursor model, checked against what the terminal was measured
/// to actually do — the records under `Tools/TerminalProbes/data/`.
///
/// ## Why this exists next to `CursorAdvanceConservationTests`
///
/// That suite proves TUIkit agrees with itself: the claim and the compensation
/// are both ours, so a model that is wrong *about the terminal* satisfies it
/// perfectly and still renders wrong. It has been demonstrated: with Warp's
/// Plane-16 case removed, every row still summed to the terminal width while
/// every SF Symbol sheared a cell. Self-consistency is not correctness, and
/// only a measurement separates them.
///
/// ## What the numbers mean
///
/// Each record holds several per-cluster measurements, and confusing them is
/// how this project has arrived at wrong conclusions in every direction it has
/// so far managed:
///
/// - **`advance`** — the INTERNAL column, what DSR reports. It governs when a
///   row WRAPS, so a walk that leaves it past the claim makes every full-width
///   row carrying the cluster wrap and show default-background cells at its
///   right edge. This is what ``TerminalClient/cursorAdvance(of:on:)`` returns,
///   and what the conservation suite sums. (A briefly-shipped model returned
///   `landing` from it instead; conservation then verified paint and was blind
///   to the wrap.)
/// - **`landing`** — measured from pixels. Where the next character is actually
///   painted. On iTerm2, Ghostty and Warp it equals `advance` for every corpus
///   cluster; on Apple Terminal it diverges on 25, and the walk closes the gap
///   per class with measured move sequences (`CUB`, or `CUB`+`CUF` for the
///   classes that paint short of the claim even after the pull-back).
/// - **`ink`** — measured from pixels; how many cells the glyph covers.
///   Recorded but **not asserted on**: the reading is a coverage threshold over
///   an antialiased glyph and is not yet reliable.
/// - **`reserve`** — the wrap threshold of the raw cluster, which tracks
///   `advance`; the edge-of-row guard in `ansiAwarePrefixForTerminalApp` exists
///   because the wrap can fire mid-cluster, before any compensation runs.
@Suite("Terminal ledger conformance")
struct TerminalLedgerConformanceTests {

    // MARK: - Reading the records

    struct Measurement: Decodable, Sendable {
        let `class`: String
        let advance: Int
        let landing: Int
        let ink: Int?
        let reserve: Int?
    }

    struct Record: Decodable, Sendable {
        let measurements: [String: Measurement]
    }

    /// One measured host: which `Program` it is, and what it did.
    struct Ledger: Sendable, CustomStringConvertible {
        let program: TerminalClient.Program
        let measurements: [String: Measurement]
        var description: String { program.rawValue }
    }

    /// The record filename for each host, under `Tools/TerminalProbes/data/`.
    ///
    /// A host with no record is not skipped silently — ``ledgers`` fails if a
    /// named file is missing, because "the measurements have not been taken"
    /// and "the measurements pass" must not look the same.
    static let records: [(TerminalClient.Program, String)] = [
        (.appleTerminal, "apple-terminal-455.1-alternate-landing.json"),
        (.iTerm2, "iterm2-3.6.11-alternate-landing.json"),
        (.ghostty, "ghostty-1.3.1-alternate-landing.json"),
        (.warp, "warpterminal-v0.2026.07.08.17.54.stable_02-alternate-landing.json"),
    ]

    static let ledgers: [Ledger] = {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TUIkitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data")
        return records.map { program, name in
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(Record.self, from: data)
            else {
                fatalError("Cannot read the measurement record \(url.path)")
            }
            return Ledger(program: program, measurements: record.measurements)
        }
    }()

    private static let corpus: [String: WidthCorpus.Entry] =
        Dictionary(uniqueKeysWithValues: WidthCorpus.clusters.map { ($0.id, $0) })

    /// Divergences that are measured, real, and not yet modelled — recorded
    /// here rather than quietly excluded, so the debt is visible and a *new*
    /// divergence still fails.
    ///
    /// All of these predate the landing measurements; none is a regression from
    /// them. They are here because the instrument can finally see them:
    ///
    /// - **Warp's `vs16_wide_exception`, keycaps and tag-sequence flags** paint
    ///   the next character at 3 against a claim of 2. Already documented in
    ///   `Documentation/Terminal-compatibility.md` as Warp limitations; each
    ///   needs the claim widened for its class, which
    ///   ``TUIkitCore/TerminalWidthTraits`` does not express yet.
    /// - **`warp/shovel`** (🪉 U+1FA89) paints at 1 where 🪈 U+1FA88 beside it
    ///   paints at 2 — Warp's width data disagreeing with the toolchain's about
    ///   one recent codepoint. Fixing it for one codepoint would be worse than
    ///   not fixing it; what it needs is a sweep of recent additions through
    ///   this same probe, which is a corpus change rather than a model change.
    /// - **`tone_point_up_vs16`** (☝️🏽) on Ghostty and iTerm2: a
    ///   text-presentation base promoted by VS-16 and then given a modifier.
    ///   One cluster, two hosts, two different answers (4 and 3), and no other
    ///   cluster in its class to generalise from.
    /// The model reports a different value than the terminal was measured to.
    static let knownAdvanceDivergences: Set<String> = [
        "warp/vs16_wavy_dash", "warp/vs16_part_alt",
        "warp/vs16_congrat", "warp/vs16_secret",
        "warp/keycap_one", "warp/keycap_hash", "warp/flag_scotland",
        "warp/shovel",
        "ghostty/tone_point_up_vs16", "iTerm2/tone_point_up_vs16",
    ]

    /// The claim is *narrower* than where the terminal paints, which no forward
    /// move can correct. A strict subset of ``knownAdvanceDivergences``: the two
    /// it leaves out (`iTerm2/tone_point_up_vs16` and `warp/shovel`) are
    /// mis-modelled but still claimed widely enough, so they must keep failing
    /// this one if they ever start to.
    static let knownNarrowClaims: Set<String> = [
        "warp/vs16_wavy_dash", "warp/vs16_part_alt",
        "warp/vs16_congrat", "warp/vs16_secret",
        "warp/keycap_one", "warp/keycap_hash", "warp/flag_scotland",
        "ghostty/tone_point_up_vs16",
    ]

    // MARK: - The assertions

    @Test("Each host's advance model reports the measured INTERNAL column",
          arguments: ledgers)
    func modelsMatchInternalAdvance(ledger: Ledger) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: ledger.program)) {
            for (id, measurement) in ledger.measurements.sorted(by: { $0.key < $1.key }) {
                guard let entry = Self.corpus[id] else {
                    Issue.record("\(ledger): measured \(id), which is not in the corpus")
                    continue
                }
                let modelled = TerminalClient.cursorAdvance(
                    of: entry.character, on: ledger.program)
                withKnownIssue(
                    "\(ledger)/\(id) is a recorded divergence",
                    isIntermittent: false
                ) {
                    #expect(
                        modelled == measurement.advance,
                        """
                        \(ledger)/\(id) (\(measurement.class)): the model says \
                        \(modelled), DSR measured \(measurement.advance). \
                        (Paint lands at \(measurement.landing).)
                        """)
                } when: {
                    Self.knownAdvanceDivergences.contains("\(ledger)/\(id)")
                }
            }
        }
    }

    /// The other half of the Apple Terminal contract: every cluster in the
    /// stored-wide set — the ones whose row store keeps a column more than
    /// they paint, repaired with `CUB(1)` `DCH(1)` `CUF(1)` — must have been
    /// measured to land its follower short of the claim, because that surplus
    /// column is exactly what pushes the follower left. The measured landings
    /// are the records'; the surgery policy is
    /// ``Swift/Character/terminalAppStoresWiderThanPainted``.
    @Test("Apple Terminal's stored-wide set matches the measured landings")
    func appleTerminalStoredWideSetMatchesMeasurement() {
        guard let ledger = Self.ledgers.first(where: { $0.program == .appleTerminal }) else {
            Issue.record("no Apple Terminal ledger")
            return
        }
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: .appleTerminal)) {
            for (id, measurement) in ledger.measurements.sorted(by: { $0.key < $1.key }) {
                guard let entry = Self.corpus[id] else { continue }
                // Only one direction is mechanically checkable: everything in
                // the stored-wide set must have been measured to land short of
                // its COMPOSED claim. (The converse does not hold — skin tones
                // and ZWJ sequences land short raw too, and they are treated
                // by rewriting rather than store surgery.) The composed claim,
                // not the traits-widened one: the landings were measured
                // against the raw cluster.
                let claim = TerminalWidthTraits.withTraits(.composing) {
                    entry.character.terminalWidth
                }
                if entry.character.terminalAppStoresWiderThanPainted {
                    #expect(
                        measurement.landing < claim,
                        "\(id) carries the store surgery but lands at \(measurement.landing) of \(claim)")
                }
            }
        }
    }

    /// The compensation walks can only push the cursor **forward** — measured:
    /// a backward move on Apple Terminal moves the paint position by an amount
    /// that depends on what the glyph did, so `CUB(advance − claim)` lands seven
    /// of twenty-five clusters somewhere other than the claim. Forward moves are
    /// exactly linear (`paint = landing + move`) on every host measured. A claim
    /// below the landing would need a backward move, so it must never happen.
    @Test("No claim is narrower than where the terminal paints", arguments: ledgers)
    func claimIsNeverBelowLanding(ledger: Ledger) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: ledger.program)) {
            for (id, measurement) in ledger.measurements.sorted(by: { $0.key < $1.key }) {
                guard let entry = Self.corpus[id] else { continue }
                let claim = entry.character.terminalWidth
                withKnownIssue(
                    "\(ledger)/\(id) is a recorded divergence",
                    isIntermittent: false
                ) {
                    #expect(
                        claim >= measurement.landing,
                        """
                        \(ledger)/\(id): claims \(claim) cells but the terminal \
                        paints the next character at \(measurement.landing), which \
                        would need a backward move to correct.
                        """)
                } when: {
                    Self.knownNarrowClaims.contains("\(ledger)/\(id)")
                }
            }
        }
    }
}
