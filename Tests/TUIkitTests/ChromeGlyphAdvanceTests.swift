//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeGlyphAdvanceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

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
/// Measured: **all twenty-nine advance exactly one cell on all four hosts.** The
/// claim is right and no row shifts anywhere. Whatever Ghostty does with `↵` it
/// does to the INK alone, which is a different measurement (`landing`/`ink`,
/// still outstanding — see `TerminalLedgerConformanceTests`).
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

    private static let hosts: [(name: String, file: String)] = [
        ("Ghostty", "ghostty-1.3.1-advance.json"),
        ("iTerm2", "iTerm2-advance.json"),
        ("Apple Terminal", "Apple-Terminal-advance.json"),
        ("Warp", "Warp-advance.json"),
    ]

    private static let records: [(name: String, advances: [String: Advance])] = {
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
            return (host.name, record.advances)
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

    @Test("The framework claims what the terminals do")
    func theClaimMatchesTheMeasurement() {
        for row in Self.chromeRows {
            let claimed = Character(row.text).terminalWidth
            for host in Self.records {
                guard let measured = host.advances[row.id] else { continue }
                #expect(
                    claimed == measured.advance,
                    "\(row.id) \(row.text): claimed \(claimed), \(host.name) advanced \(measured.advance)")
            }
        }
    }
}
