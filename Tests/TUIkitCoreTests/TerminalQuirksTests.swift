//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalQuirksTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The hand-buildable advance model — what somebody sitting in front of an
/// unmeasured terminal assembles by trying switches.
///
/// The value of it rests on two things: that each switch moves exactly the
/// class it names and nothing else (otherwise the experiment misleads), and
/// that the result can express a terminal TUIkit already knows about
/// (otherwise the export it produces is not actionable).
@Suite("Terminal quirks")
struct TerminalQuirksTests {

    private static let vs16: Character = "🖥️"
    private static let bare: Character = "🛡"
    private static let loneRI: Character = "🇦"
    private static let flag: Character = "🇺🇸"
    private static let keycap: Character = "1️⃣"
    private static let chrome: Character = "⬛\u{FE0E}"
    private static let sfSymbol: Character = "\u{100038}"

    @Test("No quirks means nothing is claimed to diverge")
    func emptyIsInert() {
        let quirks = TerminalQuirks()
        #expect(quirks.isEmpty)
        for cluster: Character in [Self.vs16, Self.bare, Self.loneRI, Self.flag, Self.keycap, "a", "中"] {
            #expect(quirks.cursorAdvance(of: cluster) == cluster.terminalWidth)
        }
    }

    @Test("Each switch moves its own class and no other")
    func switchesAreIndependent() {
        // The property that makes the experiment trustworthy: a user turning on
        // one switch must see exactly one class of glyph change, or they cannot
        // attribute what they see.
        let cases: [(TerminalQuirks, Character, String)] = [
            (TerminalQuirks(vs16Pictographs: true), Self.vs16, "VS-16"),
            (TerminalQuirks(barePictographs: true), Self.bare, "bare pictograph"),
            (TerminalQuirks(vs15ChromeGlyphs: true), Self.chrome, "VS-15 chrome"),
            (TerminalQuirks(loneRegionalIndicators: true), Self.loneRI, "lone RI"),
            (TerminalQuirks(flagPairs: true), Self.flag, "flag pair"),
            (TerminalQuirks(keycapSequences: true), Self.keycap, "keycap"),
            (TerminalQuirks(planeSixteenPUA: true), Self.sfSymbol, "SF Symbol"),
        ]
        let everything: [Character] = [
            Self.vs16, Self.bare, Self.chrome, Self.loneRI, Self.flag, Self.keycap, Self.sfSymbol,
        ]
        for (quirks, target, label) in cases {
            #expect(quirks.cursorAdvance(of: target) == 1, "\(label) should under-advance")
            for other in everything where other != target {
                #expect(
                    quirks.cursorAdvance(of: other) == other.terminalWidth,
                    "\(label) must not move \(other.unicodeScalars.map { "U+\(String($0.value, radix: 16))" })")
            }
        }
    }

    @Test("A lone regional indicator and a flag are separate switches")
    func loneIndicatorIsNotAFlag() {
        // Not a nicety: an earlier model in this repo treated the pair like the
        // lone case, and the injected CUF pushed everything after a flag one
        // cell right.
        let lone = TerminalQuirks(loneRegionalIndicators: true)
        #expect(lone.cursorAdvance(of: Self.loneRI) == 1)
        #expect(lone.cursorAdvance(of: Self.flag) == Self.flag.terminalWidth)
    }

    @Test("Only the enabled class gets a cursor move")
    func compensationFollowsTheSwitches() {
        let row = "│\(Self.vs16)\(Self.loneRI)│"
        let vs16Only = row.withCursorCompensation(for: TerminalQuirks(vs16Pictographs: true))
        #expect(vs16Only.contains("\(Self.vs16)\u{1B}[1C"))
        #expect(!vs16Only.contains("\(Self.loneRI)\u{1B}[1C"))

        let both = row.withCursorCompensation(
            for: TerminalQuirks(vs16Pictographs: true, loneRegionalIndicators: true))
        #expect(both.contains("\(Self.vs16)\u{1B}[1C"))
        #expect(both.contains("\(Self.loneRI)\u{1B}[1C"))
    }

    @Test("The background erase is opt-in, and precedes the glyph")
    func erasingIsOptional() {
        let row = "│\(Self.vs16)│"
        let plain = row.withCursorCompensation(for: TerminalQuirks(vs16Pictographs: true))
        #expect(!plain.contains("\u{1B}[2X"))

        let erased = row.withCursorCompensation(
            for: TerminalQuirks(vs16Pictographs: true, erasesUnderGlyphs: true))
        // ECH paints the cells and does NOT move the cursor, so it has to come
        // before the glyph — after it, the glyph would be the thing erased.
        #expect(erased.contains("\u{1B}[2X\(Self.vs16)\u{1B}[1C"))
    }

    @Test(
        "Skin tones are stripped by plane, as each measured host needs",
        arguments: [
            (TerminalQuirks.SkinTones.keep, true, true),
            (TerminalQuirks.SkinTones.stripAll, false, false),
            (TerminalQuirks.SkinTones.stripBMPBases, true, false),
        ])
    func skinTonePlanes(setting: TerminalQuirks.SkinTones, keepsSMP: Bool, keepsBMP: Bool) {
        var quirks = TerminalQuirks()
        quirks.skinTones = setting
        // 👍🏽 has an SMP base; ✊🏻's is BMP — the distinction tmux needs.
        let smp = "👍🏽".withCursorCompensation(for: quirks)
        let bmp = "✊🏻".withCursorCompensation(for: quirks)
        #expect(smp.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) } == keepsSMP)
        #expect(bmp.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) } == keepsBMP)
    }

    @Test("A hand-built set can express a terminal TUIkit already measured")
    func canReproduceAMeasuredHost() {
        // The test that makes the export worth exporting: if the switches
        // cannot describe a host whose model is already written down, they
        // cannot describe a new one either. Apple Terminal's under-advancing
        // classes, transcribed.
        let appleTerminal = TerminalQuirks(
            vs16Pictographs: true,
            barePictographs: true,
            loneRegionalIndicators: true,
            planeSixteenPUA: true,
            skinTones: .stripAll,
            erasesUnderGlyphs: true)
        for cluster in [Self.vs16, Self.bare, Self.loneRI, Self.sfSymbol] {
            #expect(
                appleTerminal.cursorAdvance(of: cluster) == cluster.terminalAppCursorAdvance,
                "hand-built model disagrees with the measured one for \(cluster)")
        }
        // And the classes Apple Terminal gets right stay right.
        for cluster in [Self.flag, "a", "中", "👍"] as [Character] {
            #expect(appleTerminal.cursorAdvance(of: cluster) == cluster.terminalAppCursorAdvance)
        }
    }

    @Test("A row with no quirky glyphs is returned untouched")
    func asciiIsUntouched() {
        let row = "│ Plain ASCII row │"
        let all = TerminalQuirks(
            vs16Pictographs: true, barePictographs: true, vs15ChromeGlyphs: true,
            loneRegionalIndicators: true, flagPairs: true, keycapSequences: true,
            planeSixteenPUA: true, skinTones: .stripAll, erasesUnderGlyphs: true)
        #expect(row.withCursorCompensation(for: all) == row)
    }

    @Test("Escape sequences are copied through, not rewritten")
    func escapesSurvive() {
        let row = "\u{1B}[38;5;42m\(Self.vs16)\u{1B}[0m"
        let out = row.withCursorCompensation(for: TerminalQuirks(vs16Pictographs: true))
        #expect(out.hasPrefix("\u{1B}[38;5;42m"))
        #expect(out.hasSuffix("\u{1B}[0m"))
    }
}

// MARK: - Every corpus cluster under every mechanism

/// The permutation coverage: representative quirk sets — every real host's
/// shape, each new mechanism alone, everything at once — crossed with the
/// full width corpus.
///
/// Two properties hold for every combination, and they are the two that
/// briefly-shipped defects have violated:
///
/// - **Conservation**: the emission's internal advance, summed under the same
///   quirk model that produced it, equals the cells its visible content
///   claims. An emission that sums high wraps full-width rows (white cells at
///   the row's end); one that sums low shears.
/// - **Content preservation**: unless a strip was explicitly selected, every
///   scalar the user wrote survives into the emission.
@Suite("Quirk permutations over the corpus")
struct QuirkPermutationTests {

    /// Every quirk-set shape worth holding the properties over: the measured
    /// hosts, each mechanism in isolation, and the kitchen sink.
    static let sets: [(String, TerminalQuirks)] = [
        ("none", TerminalQuirks()),
        ("apple", TerminalQuirks(
            vs16Pictographs: true, barePictographs: true,
            loneRegionalIndicators: true, planeSixteenPUA: true,
            zwjSequences: true, tagFlags: true, paintShortComposites: true,
            skinTones: .pullBack, erasesUnderGlyphs: true)),
        ("iterm2", TerminalQuirks(
            vs16Pictographs: true, keycapSequences: true, planeSixteenPUA: true,
            skinTones: .stripAll)),
        ("ghostty", TerminalQuirks(vs15ChromeGlyphs: true, planeSixteenPUA: true)),
        ("warp", TerminalQuirks(
            loneRegionalIndicators: true, planeSixteenPUA: true,
            skinTones: .stripAll)),
        ("tmux", TerminalQuirks(
            loneRegionalIndicators: true, planeSixteenPUA: true,
            skinTones: .stripBMPBases)),
        ("zwj-alone", TerminalQuirks(zwjSequences: true)),
        ("tagflags-alone", TerminalQuirks(tagFlags: true)),
        ("nudge-alone", TerminalQuirks(paintShortComposites: true)),
        ("pullback-alone", TerminalQuirks(skinTones: .pullBack)),
        ("everything", TerminalQuirks(
            vs16Pictographs: true, barePictographs: true, vs15ChromeGlyphs: true,
            loneRegionalIndicators: true, flagPairs: true, keycapSequences: true,
            planeSixteenPUA: true, zwjSequences: true, tagFlags: true,
            paintShortComposites: true, skinTones: .pullBack,
            erasesUnderGlyphs: true)),
    ]

    @Test("Every emission conserves its quirk model's internal column",
          arguments: sets, TerminalWidthCorpus.all)
    func conserves(set: (String, TerminalQuirks), entry: TerminalWidthCorpus.Entry) {
        let (name, quirks) = set
        let emission = entry.text.withCursorCompensation(for: quirks)
        let advance = emission.cursorAdvance { quirks.cursorAdvance(of: $0) }
        #expect(
            advance == emission.strippedLength,
            """
            \(entry) under '\(name)': emission sums to \(advance) against \
            \(emission.strippedLength) visible cells — a full-width row \
            \(advance > emission.strippedLength ? "wraps" : "shears").
            """)
    }

    @Test("Every scalar survives unless a strip was selected",
          arguments: sets, TerminalWidthCorpus.all)
    func preservesContent(set: (String, TerminalQuirks), entry: TerminalWidthCorpus.Entry) {
        let (name, quirks) = set
        guard quirks.skinTones == .keep || quirks.skinTones == .pullBack else { return }
        let emission = entry.text.withCursorCompensation(for: quirks)
        let emitted = Set(emission.unicodeScalars.map(\.value))
        for scalar in entry.text.unicodeScalars {
            #expect(
                emitted.contains(scalar.value),
                "\(entry) under '\(name)': U+\(String(scalar.value, radix: 16, uppercase: true)) was dropped")
        }
    }

    /// The mirror pin: the Apple-shaped switch set must reproduce the REAL
    /// Apple Terminal walk exactly — model for model and emission for
    /// emission — because the app exists so somebody can dial in a measured
    /// host's behaviour and see precisely what TUIkit would do.
    @Test("The Apple-shaped set reproduces the real Apple walk",
          arguments: TerminalWidthCorpus.all)
    func appleShapeMatchesTheRealWalk(entry: TerminalWidthCorpus.Entry) {
        let apple = Self.sets.first { $0.0 == "apple" }!.1
        #expect(
            apple.cursorAdvance(of: entry.character)
                == entry.character.terminalAppCursorAdvance,
            "\(entry): hand-built model diverges from the measured one")
        #expect(
            entry.text.withCursorCompensation(for: apple)
                == entry.text.withTerminalAppCursorCompensation(),
            "\(entry): hand-built emission diverges from the real walk")
    }
}
