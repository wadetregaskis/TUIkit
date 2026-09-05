//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeGlyphAdvanceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore  // `isOverhangingChromeGlyph` — internal to the width layer

/// The framework's own chrome, against what four terminals actually did with it.
///
/// Every glyph TUIkit draws in a status bar, a border, a scrollbar, a track, a
/// radio group or a stepper is claimed at one cell — and until 2026-09-04 that
/// claim had never been checked on any host. Fifteen of the twenty-nine are East
/// Asian **Ambiguous**, whose width is a terminal SETTING rather than a property
/// of the character, so the claim was not obviously safe; and `↵` (U+21B5) was
/// reported painting two cells in Ghostty despite being EAW *Neutral*, which no
/// width table predicts.
///
/// Measured: **all twenty-nine advance exactly one cell on all four hosts.** No
/// row shifts anywhere. Whatever Ghostty does with `↵` it does to the INK
/// alone, which is a different measurement — read from the overhang card on
/// 2026-09-04 (`ChromeOverhangTests`), and the reason the claim asserted here
/// is now the claim of the host whose record is being read rather than one
/// number for all four.
///
/// This reads the `advance_probe.py` records rather than restating their
/// numbers, so re-running the probe on a new version of a host updates the test
/// rather than dating it.
@Suite("Chrome glyph advance")
struct ChromeGlyphAdvanceTests {

    private struct Advance: Decodable { let advance: Int }
    private struct Record: Decodable { let advances: [String: Advance] }

    /// The chrome classes, which is what this suite is about — the rest of the
    /// corpus is measured by `TerminalLedgerConformanceTests` against the
    /// richer landing records.
    private static let chromeClasses: Set<String> = ["chrome_key", "chrome_glyph"]

    /// The program is carried alongside the record because the CLAIM is per
    /// host now: since 2026-09-04 the overhang card's reading widens `↵` on
    /// Ghostty and seven other glyphs on Warp, so "what does the framework
    /// claim for this row" cannot be asked without saying whose terminal.
    private static let hosts: [(name: String, file: String, program: TerminalClient.Program)] = [
        ("Ghostty", "ghostty-1.3.1-advance.json", .ghostty),
        ("iTerm2", "iTerm2-advance.json", .iTerm2),
        ("Apple Terminal", "Apple-Terminal-advance.json", .appleTerminal),
        ("Warp", "Warp-advance.json", .warp),
    ]

    private typealias HostRecord = (
        name: String, program: TerminalClient.Program, advances: [String: Advance]
    )

    private static let records: [HostRecord] = {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TUIkitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Tools/TerminalProbes/data")
        return hosts.map { host in
            let url = directory.appendingPathComponent(host.file)
            guard let data = try? Data(contentsOf: url),
                let record = try? JSONDecoder().decode(Record.self, from: data)
            else {
                // Same rule as the landing ledgers: a missing record is not a
                // skipped test, because "not measured" must not look like
                // "measured and fine".
                fatalError("Cannot read the advance record \(url.path)")
            }
            return (host.name, host.program, record.advances)
        }
    }()

    private static let chromeRows = WidthCorpus.clusters.filter { chromeClasses.contains($0.category) }

    @Test("Every chrome glyph is a corpus row of one of the two chrome classes")
    func theSuiteHasSomethingToMeasure() {
        #expect(Self.chromeRows.count == 29, "\(Self.chromeRows.count) chrome rows")
    }

    @Test("Every host advances one cell for every chrome glyph")
    func chromeAdvancesOneCellEverywhere() {
        for host in Self.records {
            for row in Self.chromeRows {
                guard let measured = host.advances[row.id] else {
                    Issue.record("\(host.name)/\(row.id): the probe recorded no advance")
                    continue
                }
                #expect(
                    measured.advance == 1,
                    "\(host.name)/\(row.id) \(row.text) advanced \(measured.advance)")
            }
        }
    }

    @Test("The framework claims what the terminals do, unless that host's ink says otherwise")
    func theClaimCoversTheMeasurement() {
        for host in Self.records {
            // Under THIS host's claims, because since 2026-09-04 they differ:
            // a glyph in the overhang tables (`ChromeOverhang.swift`) claims
            // the two cells its ink covers on the host that was measured to
            // smear it, while every host still advances it one. Asking the
            // question under the default traits — which is what this test did
            // when the table was empty and host-independent — would assert the
            // claim of a host that is not the one whose record it is reading.
            TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: host.program)) {
                for row in Self.chromeRows {
                    let character = Character(row.text)
                    let claimed = character.terminalWidth
                    guard let measured = host.advances[row.id] else { continue }
                    // The shortfall on a smeared row is what the ECH+CUF walk
                    // exists to close, and `ChromeOverhangTests` is where that
                    // pair is checked. For every other row the two must still
                    // be equal: an unexplained gap is the shear this suite was
                    // written to catch.
                    #expect(
                        claimed >= measured.advance,
                        "\(row.id) \(row.text): claimed \(claimed), \(host.name) advanced \(measured.advance)")
                    if !character.isOverhangingChromeGlyph {
                        #expect(
                            claimed == measured.advance,
                            "\(row.id) \(row.text): claimed \(claimed), \(host.name) advanced \(measured.advance)")
                    }
                }
            }
        }
    }
}
