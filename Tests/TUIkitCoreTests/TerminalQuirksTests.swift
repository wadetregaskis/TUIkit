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
            (TerminalQuirks(keycaps: .underAdvances), Self.keycap, "keycap"),
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
        "Skin tones are stripped by scope, as each measured host needs",
        arguments: [
            (TerminalQuirks.SkinTones.keep, true, true),
            (TerminalQuirks.SkinTones.stripAll, false, false),
            (TerminalQuirks.SkinTones.stripTmuxDetached, true, false),
        ])
    func skinToneScopes(setting: TerminalQuirks.SkinTones, keepsMerged: Bool, keepsDetached: Bool) {
        var quirks = TerminalQuirks()
        quirks.skinTones = setting
        // 👍 is a base tmux merges; ✊ and 🤙 are ones it detaches — and 🤙 is
        // SMP, which is the row that proves the split is per codepoint, not
        // per plane.
        let merged = "👍🏽".withCursorCompensation(for: quirks)
        let detachedBMP = "✊🏻".withCursorCompensation(for: quirks)
        let detachedSMP = "🤙🏽".withCursorCompensation(for: quirks)
        func hasTone(_ s: String) -> Bool {
            s.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
        }
        #expect(hasTone(merged) == keepsMerged)
        #expect(hasTone(detachedBMP) == keepsDetached)
        #expect(hasTone(detachedSMP) == keepsDetached)
    }

    @Test("A pre-separated tone cluster prices its joiner under .pullBack too")
    func pullBackPricesSeparatedCluster() {
        // 🤙+ZWNJ+🏽 — user-authored, or previously rewritten text fed back
        // in. The ZWNJ occupies its own internal column on the host both
        // switches describe (DSR-measured: the pair advances 5 = 2+1+2), so
        // `.pullBack` must sum it exactly as `.separate` does. It used to
        // fall to the raw-tone arm and price 4, emitting CUB(2) where the
        // real walk under non-separated traits emits CUB(3).
        let cluster = Character("🤙\u{200C}🏽")
        var quirks = TerminalQuirks()
        quirks.skinTones = .pullBack
        #expect(quirks.cursorAdvance(of: cluster) == 5)
        #expect(cluster.terminalAppCursorAdvance == 5, "the real model it mirrors")
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
            loneRegionalIndicators: true, flagPairs: true, keycaps: .alwaysTwoColumns,
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
    ///
    /// The host-named shapes carry the 2026-08-28 erase (all four native
    /// hosts were measured to leave the default background under the cells an
    /// under-advancer skips; tmux stays bare-CUF, unmeasured). All four are
    /// pinned to their real walks emission-for-emission below — "iterm2" and
    /// "warp" were strip-era approximations until the mirror grew the
    /// detached-claim cases and the narrow-base tone merge.
    static let sets: [(String, TerminalQuirks)] = [
        ("none", TerminalQuirks()),
        ("apple", TerminalQuirks(
            vs16Pictographs: true, barePictographs: true,
            loneRegionalIndicators: true, keycaps: .alwaysTwoColumns,
            planeSixteenPUA: true,
            zwjSequences: true, tagFlags: true, storesWideComposites: true,
            skinTones: .separate, erasesUnderGlyphs: true)),
        ("iterm2", TerminalQuirks(
            vs16Pictographs: true, barePictographs: true,
            keycaps: .underAdvances, planeSixteenPUA: true,
            skinTones: .keepDetachedOnBMPBases, mergesTonesOnTextBases: true,
            erasesUnderGlyphs: true)),
        ("ghostty", TerminalQuirks(
            barePictographs: true, vs15ChromeGlyphs: true, planeSixteenPUA: true,
            mergesTonesOnTextBases: true, erasesUnderGlyphs: true)),
        ("warp", TerminalQuirks(
            barePictographs: true, loneRegionalIndicators: true, planeSixteenPUA: true,
            preUnicode16WidthTable: true, zwjSequences: true,
            skinTones: .keepDetached, erasesUnderGlyphs: true)),
        ("tmux", TerminalQuirks(
            loneRegionalIndicators: true, planeSixteenPUA: true,
            skinTones: .stripTmuxDetached)),
        ("zwj-alone", TerminalQuirks(zwjSequences: true)),
        ("tagflags-alone", TerminalQuirks(tagFlags: true)),
        ("trim-alone", TerminalQuirks(storesWideComposites: true)),
        ("pullback-alone", TerminalQuirks(skinTones: .pullBack)),
        ("separate-alone", TerminalQuirks(skinTones: .separate)),
        ("everything", TerminalQuirks(
            vs16Pictographs: true, barePictographs: true, vs15ChromeGlyphs: true,
            loneRegionalIndicators: true, flagPairs: true, keycaps: .alwaysTwoColumns,
            planeSixteenPUA: true, preUnicode16WidthTable: true,
            zwjSequences: true, tagFlags: true,
            storesWideComposites: true, skinTones: .separate,
            erasesUnderGlyphs: true)),
    ]

    @Test("Every emission conserves its quirk model's internal column",
          arguments: sets, TerminalWidthCorpus.all)
    func conserves(set: (String, TerminalQuirks), entry: TerminalWidthCorpus.Entry) {
        let (name, quirks) = set
        // Claim-changing switches only hold together under their own implied
        // claims, exactly as the real walks require the host's traits.
        TerminalWidthTraits.withTraits(quirks.widthTraits) {
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
    }

    /// The mirror shares ``Character/summedInternalJoinerAdvance`` with the
    /// Apple model, and so shared its crash: a truncated or stray-joiner
    /// cluster leaves an empty segment, and `Character("")` is a stdlib
    /// `fatalError`. The summer now declines such clusters, so the mirror
    /// prices and emits them as ordinary unmeasured clusters — nothing to pin
    /// but no-trap and conservation, under every quirk shape.
    @Test("A degenerate joiner cluster neither traps nor drifts",
          arguments: sets,
          ["👨\u{200D}👩\u{200D}", "👍\u{200D}", "👍\u{200C}", "x\u{200D}", "👨\u{200D}\u{200D}"])
    func degenerateJoinerCluster(set: (String, TerminalQuirks), cluster: String) {
        let (name, quirks) = set
        TerminalWidthTraits.withTraits(quirks.widthTraits) {
            let emission = cluster.withCursorCompensation(for: quirks)
            let advance = emission.cursorAdvance { quirks.cursorAdvance(of: $0) }
            #expect(advance == emission.strippedLength, "\(cluster.unicodeScalars) under '\(name)'")
        }
    }

    @Test("Every scalar survives unless a strip or a decomposition was selected",
          arguments: sets, TerminalWidthCorpus.all)
    func preservesContent(set: (String, TerminalQuirks), entry: TerminalWidthCorpus.Entry) {
        let (name, quirks) = set
        switch quirks.skinTones {
        case .keep, .keepDetached, .keepDetachedOnBMPBases, .pullBack, .separate: break
        case .stripAll, .stripTmuxDetached: return
        }
        TerminalWidthTraits.withTraits(quirks.widthTraits) {
            let emission = entry.text.withCursorCompensation(for: quirks)
            let emitted = Set(emission.unicodeScalars.map(\.value))
            for scalar in entry.text.unicodeScalars {
                // Software ZWJ decomposition drops the joiners by design —
                // they are what the host cannot store truthfully.
                if scalar.value == 0x200D && quirks.zwjSequences { continue }
                // The keep-family walks strip a redundant VS-16 from a tone
                // cluster by design (☝️🏽 → ☝🏽 — the modifier alone forces
                // emoji presentation, and the normalized pair is the one the
                // hosts were measured to handle). The Apple-family walks
                // (.separate, .pullBack) keep it.
                if scalar.value == 0xFE0F, quirks.skinTones.stripsRedundantToneVS16,
                    entry.character.withoutRedundantToneVS16 != nil
                {
                    continue
                }
                #expect(
                    emitted.contains(scalar.value),
                    "\(entry) under '\(name)': U+\(String(scalar.value, radix: 16, uppercase: true)) was dropped")
            }
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
        // Same claims as startup publishes for the real host — the quirks' own
        // mapping, pinned equal to `TerminalClient.widthTraits(of:)` by
        // `TerminalWidthTraitsTests`.
        TerminalWidthTraits.withTraits(apple.widthTraits) {
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

    /// The same pin for the Ghostty shape — the drift this would have caught
    /// is real: the shapes carried no `erasesUnderGlyphs` for months after
    /// the real walks grew the measured erase. It carried a skip set for as
    /// long, covering the seven tone rows Ghostty merges into ONE cell; that
    /// is what ``TerminalQuirks/mergesTonesOnTextBases`` now expresses, and
    /// the set is gone.
    @Test("The Ghostty-shaped set reproduces the real Ghostty walk",
          arguments: TerminalWidthCorpus.all)
    func ghosttyShapeMatchesTheRealWalk(entry: TerminalWidthCorpus.Entry) {
        let ghostty = Self.sets.first { $0.0 == "ghostty" }!.1
        TerminalWidthTraits.withTraits(ghostty.widthTraits) {
            #expect(
                ghostty.cursorAdvance(of: entry.character)
                    == entry.character.ghosttyCursorAdvance,
                "\(entry): hand-built model diverges from the measured one")
            #expect(
                entry.text.withCursorCompensation(for: ghostty)
                    == entry.text.withGhosttyCursorCompensation(),
                "\(entry): hand-built emission diverges from the real walk")
        }
    }

    /// The same pin for iTerm2 — the host that needs both new mechanisms at
    /// once, and the reason they are separate switches: a BMP base's tone
    /// DETACHES (the claim widens to cover the swatch, so nothing is emitted)
    /// while the SMP form 🏋🏽 MERGES to one cell against a 2-cell claim and
    /// takes the ordinary erase-and-push.
    @Test("The iTerm2-shaped set reproduces the real iTerm2 walk",
          arguments: TerminalWidthCorpus.all)
    func iTerm2ShapeMatchesTheRealWalk(entry: TerminalWidthCorpus.Entry) {
        let iterm2 = Self.sets.first { $0.0 == "iterm2" }!.1
        TerminalWidthTraits.withTraits(iterm2.widthTraits) {
            #expect(
                iterm2.cursorAdvance(of: entry.character)
                    == entry.character.iTerm2CursorAdvance,
                "\(entry): hand-built model diverges from the measured one")
            #expect(
                entry.text.withCursorCompensation(for: iterm2)
                    == entry.text.withITerm2CursorCompensation(),
                "\(entry): hand-built emission diverges from the real walk")
        }
    }

    /// And for Warp, which detaches every base. Its remaining divergences are
    /// OVER-advances no escape can repair (keycaps, the EAW-base VS-16
    /// exceptions, the tag flag), which both sides leave alone — so they are
    /// agreement, not a skip.
    @Test("The Warp-shaped set reproduces the real Warp walk",
          arguments: TerminalWidthCorpus.all)
    func warpShapeMatchesTheRealWalk(entry: TerminalWidthCorpus.Entry) {
        let warp = Self.sets.first { $0.0 == "warp" }!.1
        TerminalWidthTraits.withTraits(warp.widthTraits) {
            #expect(
                warp.cursorAdvance(of: entry.character) == entry.character.warpCursorAdvance,
                "\(entry): hand-built model diverges from the measured one")
            #expect(
                entry.text.withCursorCompensation(for: warp)
                    == entry.text.withWarpCursorCompensation(),
                "\(entry): hand-built emission diverges from the real walk")
        }
    }
}
