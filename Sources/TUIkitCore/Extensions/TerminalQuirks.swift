//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalQuirks.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Terminal Quirks

/// A terminal's cursor-advance defects, as a set of independently-selectable
/// rules — the shape a NEW terminal's support starts as.
///
/// Every terminal TUIkit already knows about has its model written in Swift,
/// measured with `Tools/TerminalProbes/advance_probe.py`. This type is for the
/// terminals it does not know about yet: it decomposes "which workarounds does
/// this host need" into one switch per class of grapheme cluster, so somebody
/// sitting in front of an unmeasured terminal can find the answer by trying the
/// switches and looking at the screen, and send back something actionable.
///
/// Each switch names a class that some measured terminal gets wrong. They are
/// classes rather than characters because the defects are: a terminal that
/// under-advances 🖥️ under-advances every VS-16 pictograph, and no terminal has
/// ever been found to disagree within one of these groups.
///
/// The default is **no quirks at all** — a terminal that renders correctly,
/// which is what any terminal is assumed to be until there is evidence
/// otherwise.
public struct TerminalQuirks: Sendable, Equatable, Codable {

    /// What to do about Fitzpatrick skin-tone clusters (👍🏽), which terminals
    /// get wrong by *over*-advancing: the internal cursor column ends past
    /// where the glyph was claimed to end, and a row carrying one wraps early.
    public enum SkinTones: String, Sendable, Equatable, Codable, CaseIterable {
        /// The terminal joins the cluster into the two cells claimed for it.
        /// Ghostty is the only measured terminal that does.
        case keep
        /// Strip every skin-tone modifier (iTerm2, Warp — their claims cover
        /// the detached rendering instead, so their real output paths keep the
        /// modifier; the strip is what a claim that does NOT cover it needs).
        case stripAll
        /// Strip only clusters whose base is a BMP scalar (✊🏻 ☝🏽), keeping the
        /// SMP-based ones the terminal joins correctly. This is tmux.
        case stripBMPBases
        /// Keep every scalar and pull the internal column back to the claim
        /// with `CUB(advance − claim)` after the cluster — Apple Terminal's
        /// treatment. The advance model is the measured 4 for an
        /// emoji-presentation base and 3 for a text-presentation one.
        case pullBack
    }

    /// `<base>+U+FE0F` pictographs — 🖥️ ❤️ ✏️ ⚠️. Painted two cells, advanced
    /// one. The largest and most visible class: Apple Terminal and iTerm2's
    /// alternate screen both have it.
    public var vs16Pictographs: Bool

    /// Selector-less SMP pictographs — 🖥 🛡 🕹. Painted two cells via emoji
    /// fallback, advanced one.
    public var barePictographs: Bool

    /// VS-15 (text-presentation) chrome glyphs — ⬛︎ ⬜︎. TUIkit draws toggles
    /// with these, so a terminal with this quirk shows `■On` with the label
    /// colliding with the glyph. Ghostty has it.
    public var vs15ChromeGlyphs: Bool

    /// A single regional indicator not paired into a flag — 🇦 on its own.
    /// Apple Terminal, Warp and tmux all under-advance these.
    public var loneRegionalIndicators: Bool

    /// A flag — two regional indicators, 🇺🇸. Measured to advance correctly on
    /// every terminal so far, which is why it is a separate switch from the
    /// lone case: an earlier model treated them together and the injected CUF
    /// pushed everything after a flag one cell right.
    public var flagPairs: Bool

    /// Keycap sequences — 1️⃣ (base + U+FE0F + U+20E3). iTerm2 under-advances
    /// these.
    public var keycapSequences: Bool

    /// Plane-16 Private Use Area — SF Symbols. Painted two cells by any font
    /// that has the glyphs, advanced one on every measured host.
    public var planeSixteenPUA: Bool

    /// The terminal's INTERNAL column decomposes a ZWJ sequence — advancing
    /// the sum of the segments plus one per joiner — while painting the
    /// composed glyph into the claimed cells. Apple Terminal (👨‍👩‍👧‍👦:
    /// internal 11, paint 2). The walk pulls the column back with `CUB`.
    public var zwjSequences: Bool

    /// The same divergence for tag-sequence flags (🏴󠁧󠁢󠁳󠁣󠁴󠁿): internal advance
    /// 2 plus one per tag scalar, painted 2. Apple Terminal.
    public var tagFlags: Bool

    /// Flag pairs, keycaps and ZWJ sequences led by a text-presentation
    /// segment paint the NEXT character one cell short of the internal
    /// column, even after any pull-back. The walk goes one column further
    /// back and steps forward — net zero internally, one more paint cell.
    /// Apple Terminal.
    public var paintShortComposites: Bool

    /// How this terminal handles skin-tone clusters.
    public var skinTones: SkinTones

    /// The terminal leaves the cells a compensated glyph covers at ITS default
    /// background rather than the one in force, so they have to be erased into
    /// that background before the glyph is drawn.
    ///
    /// Measured on Apple Terminal and nowhere else: with the cursor move alone,
    /// eight under-advancing glyphs on a coloured run leave every second cell
    /// unpainted and the row reads as a comb. Every other measured host already
    /// paints every cell a wide glyph covers.
    public var erasesUnderGlyphs: Bool

    /// A terminal with no known defects — the correct starting point, and the
    /// correct answer for most terminals.
    public init(
        vs16Pictographs: Bool = false,
        barePictographs: Bool = false,
        vs15ChromeGlyphs: Bool = false,
        loneRegionalIndicators: Bool = false,
        flagPairs: Bool = false,
        keycapSequences: Bool = false,
        planeSixteenPUA: Bool = false,
        zwjSequences: Bool = false,
        tagFlags: Bool = false,
        paintShortComposites: Bool = false,
        skinTones: SkinTones = .keep,
        erasesUnderGlyphs: Bool = false
    ) {
        self.vs16Pictographs = vs16Pictographs
        self.barePictographs = barePictographs
        self.vs15ChromeGlyphs = vs15ChromeGlyphs
        self.loneRegionalIndicators = loneRegionalIndicators
        self.flagPairs = flagPairs
        self.keycapSequences = keycapSequences
        self.planeSixteenPUA = planeSixteenPUA
        self.zwjSequences = zwjSequences
        self.tagFlags = tagFlags
        self.paintShortComposites = paintShortComposites
        self.skinTones = skinTones
        self.erasesUnderGlyphs = erasesUnderGlyphs
    }

    /// Whether any workaround at all is selected.
    public var isEmpty: Bool { self == Self() }

    /// How far a terminal with these quirks moves the cursor over `cluster`.
    ///
    /// The same question ``Swift/Character/terminalAppCursorAdvance`` and its
    /// siblings answer for the measured hosts, asked of a set of switches
    /// instead of a measurement — which is what lets an unmeasured terminal be
    /// explored before anybody writes its model down.
    public func cursorAdvance(of cluster: Character) -> Int {
        let width = cluster.terminalWidth
        let scalars = cluster.unicodeScalars

        if let composed = composedAdvance(of: cluster, width: width) {
            return composed
        }
        if planeSixteenPUA, scalars.count == 1, let only = scalars.first,
            (0x100000...0x10FFFD).contains(only.value)
        {
            return 1
        }
        if keycapSequences, scalars.contains(where: { $0.value == 0x20E3 }) { return 1 }
        if loneRegionalIndicators, cluster.isLoneRegionalIndicator { return 1 }
        if flagPairs, Self.isFlagPair(cluster) { return 1 }
        if vs16Pictographs, cluster.isVS16UnderAdvancer { return 1 }
        if barePictographs, cluster.isBarePictographUnderAdvancer { return 1 }
        if vs15ChromeGlyphs, cluster.isVS15ChromeUnderAdvancer { return 1 }
        return width
    }

    /// The composed-cluster rules — ZWJ decomposition, tag flags, and skin
    /// tones — split from ``cursorAdvance(of:)`` because each is a small rule
    /// and together they were most of that function's branching.
    private func composedAdvance(of cluster: Character, width: Int) -> Int? {
        let scalars = cluster.unicodeScalars

        // ZWJ decomposition first — its segments resolve through
        // ``cursorAdvance(of:)``, which is how a skin-toned segment inside a
        // sequence (👩🏽‍🚀) gets both rules at once.
        if zwjSequences, scalars.contains(where: { $0.value == 0x200D }),
            let first = scalars.first, first.properties.isEmoji,
            let summed = Character.summedInternalZWJAdvance(cluster, segmentAdvance: {
                self.cursorAdvance(of: $0)
            })
        {
            return summed
        }
        if tagFlags, let first = scalars.first, first.properties.isEmoji {
            let tags = scalars.count { (0xE0020...0xE007F).contains($0.value) }
            if tags > 0 { return 2 + tags }
        }
        guard let first = scalars.first, first.properties.isEmojiModifierBase,
            scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) })
        else { return nil }
        switch skinTones {
        case .pullBack:
            // Measured on Apple Terminal: the internal column moves the bare
            // base's width plus two.
            return first.properties.isEmojiPresentation ? 4 : 3
        case .stripAll:
            // Stripped before the walk ever sees it, so its advance is the
            // base's — which is the claim, hence no divergence to report.
            return width
        case .stripBMPBases:
            return first.value <= 0xFFFF ? width : nil
        case .keep:
            return nil
        }
    }

    /// A flag: exactly two regional indicators.
    static func isFlagPair(_ cluster: Character) -> Bool {
        let scalars = Array(cluster.unicodeScalars)
        return scalars.count == 2 && scalars.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.value) }
    }
}

// MARK: - Compensating for them

extension String {

    /// This string with `quirks` compensated for — the generic counterpart of
    /// the per-host walks (``withTerminalAppCursorCompensation()``
    /// and friends), driven by a set of switches rather than a measured model.
    ///
    /// The walk mirrors the real ones move for move — the skin-tone strip
    /// first where a strip is selected, `ECH`+glyph+`CUF` for under-advancers,
    /// the cluster plus `CUB` for over-advancers (`.pullBack`, ZWJ, tag
    /// flags), and the one-further-back-one-forward nudge for the paint-short
    /// classes — so what is seen while exploring a new terminal is exactly
    /// what that terminal would get once its model was written down.
    /// `TerminalQuirksTests` pins the Apple-shaped set to the real Apple walk,
    /// emission for emission, which is what keeps the mirror from drifting.
    public func withCursorCompensation(for quirks: TerminalQuirks) -> String {
        let stripped =
            switch quirks.skinTones {
            case .keep, .pullBack: self
            case .stripAll: withSkinToneFallback(basePlane: .all)
            case .stripBMPBases: withSkinToneFallback(basePlane: .bmpOnly)
            }
        guard !quirks.isEmpty else { return stripped }

        var result = ""
        result.reserveCapacity(stripped.count + 8)
        var index = stripped.startIndex
        while index < stripped.endIndex {
            let character = stripped[index]
            if character == "\u{1B}" {
                let sequenceStart = index
                index = stripped.csiSequenceEnd(from: index)
                result += stripped[sequenceStart..<index]
                continue
            }
            let claimed = character.terminalWidth
            let advance = quirks.cursorAdvance(of: character)
            let paintsShort =
                quirks.paintShortComposites && character.terminalAppPaintsShortOfClaim
            if claimed > advance {
                if quirks.erasesUnderGlyphs {
                    result += "\u{1B}[\(claimed)X"
                }
                result.append(character)
                result += "\u{1B}[\(claimed - advance)C"
            } else if advance > claimed || paintsShort {
                result.append(character)
                let back = advance - claimed
                if paintsShort {
                    result += "\u{1B}[\(back + 1)D\u{1B}[1C"
                } else {
                    result += "\u{1B}[\(back)D"
                }
            } else {
                result.append(character)
            }
            index = stripped.index(after: index)
        }
        return result
    }
}
