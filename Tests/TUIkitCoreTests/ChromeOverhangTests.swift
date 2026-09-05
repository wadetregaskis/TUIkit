//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChromeOverhangTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// A chrome glyph that paints wider than it advances, per host.
///
/// The card (`Tools/TerminalProbes/overhang_card.py`) was read on 2026-09-04 on
/// all four native hosts, and the answer is not one table but four: Ghostty
/// smears `↵` and nothing else, Warp smears seven glyphs that do NOT include
/// `↵`, and Apple Terminal and iTerm2 smear nothing. So the assertions here are
/// a MATRIX — every host against every chrome row — because a single-host test
/// would pass just as happily against the union table that this change exists
/// to rule out.
///
/// Every case pins the traits with ``TerminalWidthTraits/withTraits(_:operation:)``
/// rather than assigning `current`: Swift Testing runs suites in parallel, and a
/// global mutate-and-restore bleeds one host's claim into another test's
/// rendering.
@Suite("Chrome overhang")
struct ChromeOverhangTests {

    private static let chromeRows = TerminalWidthCorpus.all.filter {
        $0.category == "chrome_key" || $0.category == "chrome_glyph"
    }

    /// A measured host: the trait that carries its reading, its advance model,
    /// and the walk that emits for it.
    ///
    /// Spelled here rather than through `TerminalClient.widthTraits(of:)`
    /// because that mapping lives a module up; `TerminalWidthTraitsTests` pins
    /// the two against each other, so a host renamed here cannot quietly stop
    /// describing the program it is named for.
    private struct Host: Sendable {
        let name: String
        let overhang: TerminalWidthTraits.ChromeOverhang
        let advance: @Sendable (Character) -> Int
        let compensate: @Sendable (String) -> String

        var traits: TerminalWidthTraits { TerminalWidthTraits(chromeOverhang: overhang) }
    }

    private static let hosts: [Host] = [
        Host(
            name: "Apple Terminal", overhang: .contained,
            advance: { $0.terminalAppCursorAdvance },
            compensate: { $0.withTerminalAppCursorCompensation() }),
        Host(
            name: "iTerm2", overhang: .contained,
            advance: { $0.iTerm2CursorAdvance },
            compensate: { $0.withITerm2CursorCompensation() }),
        Host(
            name: "Ghostty", overhang: .returnArrow,
            advance: { $0.ghosttyCursorAdvance },
            compensate: { $0.withGhosttyCursorCompensation() }),
        Host(
            name: "Warp", overhang: .keyboardSymbols,
            advance: { $0.warpCursorAdvance },
            compensate: { $0.withWarpCursorCompensation() }),
    ]

    /// Every codepoint any host was measured to smear.
    private static let union = Set(
        TerminalWidthTraits.ChromeOverhang.allCases.flatMap(\.codepoints))

    @Test("The hot path's union shortcut lists exactly what the per-host sets do")
    func theUnionIsDerivedFromTheSets() {
        // `isChromeOverhangCodepoint` rejects against `chromeOverhangUnion`
        // before reading the traits, so a union that lost a row would make that
        // row's host claim one cell and shear — silently, since the per-host
        // set would still say two.
        #expect(Set(chromeOverhangUnion) == Self.union)
        #expect(chromeOverhangUnion.count == Self.union.count, "a codepoint is listed twice")
    }

    // MARK: - The reading

    @Test("The two overhanging sets are disjoint, which is why the claim follows the host")
    func noSingleTableCanBeRight() {
        let ghostty = Set(TerminalWidthTraits.ChromeOverhang.returnArrow.codepoints)
        let warp = Set(TerminalWidthTraits.ChromeOverhang.keyboardSymbols.codepoints)
        #expect(!ghostty.isEmpty && !warp.isEmpty)
        #expect(ghostty.isDisjoint(with: warp), "a union table would be right for one of them")
        // The specific pair the report and the card disagree about, named so
        // that a future edit that "tidies" ↵ into Warp's set fails here with
        // the reason rather than somewhere downstream with a stray blank cell.
        #expect(ghostty.contains(0x21B5) && !warp.contains(0x21B5))
        #expect(TerminalWidthTraits.ChromeOverhang.contained.codepoints.isEmpty)
    }

    @Test("Every listed codepoint is inside the window the hot paths test for")
    func theTableFitsTheWindow() {
        // `loneTerminalWidth` and `Character.isOverhangingChromeGlyph` spell
        // the window as literals rather than reading the globals, because both
        // are per-scalar paths. This is what stops that duplication drifting.
        #expect(
            chromeOverhangFloor == 0x2190 && chromeOverhangCeiling == 0x25EF,
            "the window moved: update the literals in `loneTerminalWidth` and in `Character.isOverhangingChromeGlyph`")
        for value in Self.union {
            #expect(
                value >= chromeOverhangFloor && value <= chromeOverhangCeiling,
                "U+\(String(value, radix: 16, uppercase: true)) is outside the overhang window")
        }
    }

    @Test("Every listed codepoint is a glyph the framework actually draws")
    func theTableOnlyNamesChrome() {
        let corpus = Set(Self.chromeRows.compactMap { $0.text.unicodeScalars.first?.value })
        for value in Self.union {
            let spelled = String(value, radix: 16, uppercase: true)
            #expect(
                corpus.contains(value),
                "U+\(spelled) is not a chrome corpus row, and the card only shows the corpus")
        }
    }

    // MARK: - The claim, host by host

    /// The matrix: 4 hosts × 29 rows, with 8 of the 116 cells claiming two.
    @Test("A chrome glyph claims two cells exactly where its host was measured to smear it")
    func theClaimFollowsTheHost() {
        for host in Self.hosts {
            TerminalWidthTraits.withTraits(host.traits) {
                for row in Self.chromeRows {
                    let character = Character(row.text)
                    let value = row.text.unicodeScalars.first!.value
                    let expected = host.overhang.codepoints.contains(value) ? 2 : 1
                    #expect(
                        character.terminalWidth == expected,
                        "\(host.name)/\(row.id) \(row.text): claimed \(character.terminalWidth)")
                    #expect(character.isOverhangingChromeGlyph == (expected == 2))
                }
            }
        }
    }

    /// The half a per-host claim makes possible to get wrong: a glyph widened
    /// on ANOTHER host must claim one here, or the union table is back by
    /// accident.
    @Test("A host claims one cell for the glyphs only its neighbours smear")
    func aHostDoesNotInheritAnothersOverhang() {
        for host in Self.hosts {
            TerminalWidthTraits.withTraits(host.traits) {
                let mine = Set(host.overhang.codepoints)
                for value in Self.union.subtracting(mine) {
                    let character = Character(Unicode.Scalar(value)!)
                    #expect(
                        character.terminalWidth == 1,
                        "\(host.name): U+\(String(value, radix: 16, uppercase: true)) is not its overhang")
                }
            }
        }
    }

    @Test("An unmeasured host claims one cell for every chrome glyph")
    func nothingIsWidenedWithoutAReading() {
        // The default traits are what tmux, an unidentified host, and every
        // terminal nobody has run the card in get. A row added to a table
        // without a host to attach it to fails here.
        TerminalWidthTraits.withTraits(.composing) {
            for row in Self.chromeRows {
                #expect(Character(row.text).terminalWidth == 1, "\(row.id) \(row.text)")
            }
        }
    }

    // MARK: - The models, which are not what moved

    @Test("Every host's model advances one cell for every listed glyph, whatever the claim")
    func theModelsStillReportTheMeasuredOne() {
        for host in Self.hosts {
            TerminalWidthTraits.withTraits(host.traits) {
                for value in Self.union {
                    let character = Character(Unicode.Scalar(value)!)
                    let spelled = String(value, radix: 16, uppercase: true)
                    for model in Self.hosts {
                        #expect(
                            model.advance(character) == 1,
                            "\(model.name) under \(host.name)'s claim: U+\(spelled)")
                    }
                    #expect(character.tmuxCursorAdvance == 1, "tmux: U+\(spelled)")
                    // No switch turns it off: the shortfall is the claim's, not
                    // a terminal's, so an explored host cannot opt out and shear.
                    #expect(TerminalQuirks().cursorAdvance(of: character) == 1)
                }
            }
        }
    }

    // MARK: - The emission

    @Test("A widened glyph goes out erased, drawn, and pushed")
    func theWalkClosesTheShortfall() {
        for host in Self.hosts {
            TerminalWidthTraits.withTraits(host.traits) {
                for value in host.overhang.codepoints {
                    let glyph = String(Unicode.Scalar(value)!)
                    let row = glyph + " x"
                    #expect(row.utf8MayNeedCompensation, "the gate mask does not admit this glyph")
                    let emitted = host.compensate(row)
                    #expect(
                        emitted == "\u{1B}[2X" + glyph + "\u{1B}[1C" + " x",
                        "\(host.name): |\(emitted)|")
                }
            }
        }
    }

    /// The shape the whole class was reported in: a status bar's shortcut
    /// glyph, a space, and a label. On a host that smears the glyph the row
    /// claims one cell more and the walk emits the push that pays for it; on
    /// the other three the row is untouched, which is the half a union table
    /// would have got wrong.
    @Test("A status-bar row measures and lands where the claim says, on every host")
    func aStatusBarRowConserves() {
        let row = "⎋ back  ↵ activate  ⌘ menu"
        for host in Self.hosts {
            TerminalWidthTraits.withTraits(host.traits) {
                let smeared = row.unicodeScalars.count { host.overhang.codepoints.contains($0.value) }
                #expect(
                    row.strippedLength == 26 + smeared,
                    "\(host.name): claimed \(row.strippedLength) for \(smeared) widened glyphs")
                let emitted = host.compensate(row)
                #expect(
                    emitted.cursorAdvance(perCharacter: host.advance) == row.strippedLength,
                    "\(host.name): the emission lands somewhere other than the claim")
                if smeared == 0 {
                    #expect(emitted == row, "\(host.name) rewrote a row with nothing to repair")
                }
            }
        }
    }

    // MARK: - What the mechanism must never do

    @Test("Box Drawing and Block Elements are refused however the tables are edited")
    func bordersCanNeverBeWidened() {
        // A two-cell border is not a fix but a second defect — every row inside
        // it loses a column. Refused by the predicate, so a mistaken row is
        // inert rather than catastrophic.
        for value: UInt32 in [0x2500, 0x2502, 0x2588, 0x258C, 0x2590, 0x2592, 0x259F] {
            for overhang in TerminalWidthTraits.ChromeOverhang.allCases {
                #expect(!overhang.overhangs(value), "\(overhang.rawValue)")
                TerminalWidthTraits.withTraits(TerminalWidthTraits(chromeOverhang: overhang)) {
                    #expect(Character(Unicode.Scalar(value)!).terminalWidth == 1)
                }
            }
        }
    }

    @Test("The unidentified walk compensates the claim in force and normalizes nothing")
    func theUnidentifiedWalkDoesNotNormalize() {
        // The walk this borrows normalizes as well as compensates, and its own
        // gate admits any line carrying an emoji — so "this host smears
        // nothing" is not by itself enough to make the unidentified path a
        // no-op. A tone cluster with a redundant VS-16 is the case that proved
        // it: the shared walk strips the selector, which is a rewrite no
        // unmeasured terminal asked for.
        for overhang in TerminalWidthTraits.ChromeOverhang.allCases {
            TerminalWidthTraits.withTraits(TerminalWidthTraits(chromeOverhang: overhang)) {
                for row in ["\u{261D}\u{FE0F}\u{1F3FD}", "\u{1F469}\u{200D}\u{1F680}"] {
                    #expect(row.withChromeOverhangCompensation() == row, "the walk rewrote content")
                }
            }
        }
        // Under an unidentified host's own traits a row of chrome comes back
        // byte-identical…
        TerminalWidthTraits.withTraits(.composing) {
            for row in ["↵ select", "│ ─ ▶ ●"] {
                #expect(row.withChromeOverhangCompensation() == row)
            }
        }
        // …and under a pinned host's claim it pays that claim's shortfall,
        // which is the case this walk exists for.
        TerminalWidthTraits.withTraits(TerminalWidthTraits(chromeOverhang: .returnArrow)) {
            #expect(
                "↵ select".withChromeOverhangCompensation() == "\u{1B}[2X↵\u{1B}[1C select")
        }
    }

    // MARK: - The arithmetic, which no reading of the table would exercise

    @Test("The gate mask's bit is the glyph's own second UTF-8 byte")
    func theGateMaskFormulaFindsTheGlyph() {
        // `chromeOverhangGateMask` sets bit `(value >> 6) & 0x3F` and the gate
        // tests bit `secondByte & 0x3F`. Those are the same bit only because a
        // three-byte UTF-8 scalar's second byte is `0x80 | ((value >> 6) &
        // 0x3F)` — asserted here on the glyphs the card is about, whether or
        // not any host's table has them.
        for value: UInt32 in [0x2190, 0x21B5, 0x2318, 0x23CE, 0x2423, 0x25B2, 0x25CF, 0x25EF] {
            let bytes = Array(String(Unicode.Scalar(value)!).utf8)
            #expect(bytes.count == 3 && bytes[0] == 0xE2)
            let bit: UInt64 = 1 << UInt64((value >> 6) & 0x3F)
            let spelled = String(value, radix: 16, uppercase: true)
            #expect(
                bit & (1 << UInt64(bytes[1] & 0x3F)) != 0,
                "U+\(spelled): the mask's bit and the gate's bit are not the same bit")
        }
    }

    @Test("The mask is the union of every host's table, not one host's")
    func theMaskTracksEveryTable() {
        var expected: UInt64 = 0
        for value in Self.union { expected |= 1 << UInt64((value >> 6) & 0x3F) }
        #expect(chromeOverhangGateMask == expected)
        // The union is what makes the gate safe to leave host-independent: it
        // decides only whether the walk RUNS, so admitting a row whose glyph
        // this host draws contained costs a walk that changes nothing, while
        // skipping one it smears shears the row. Asserted rather than argued:
        // every host's own glyphs must be admitted under every host's claim.
        for host in Self.hosts {
            TerminalWidthTraits.withTraits(host.traits) {
                for value in Self.union {
                    let row = "│ " + String(Unicode.Scalar(value)!) + " │"
                    #expect(
                        row.utf8MayNeedCompensation,
                        "\(host.name): the gate skips U+\(String(value, radix: 16, uppercase: true))")
                }
            }
        }
    }
}
