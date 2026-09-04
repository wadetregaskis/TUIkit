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
        /// Keep every scalar and CLAIM the detached rendering: the base is
        /// drawn and the modifier lands beside it as a swatch, so the cluster
        /// owns the base's width plus two and nothing needs emitting. Warp,
        /// for every base — and what Warp's shipped walk really does. The
        /// caller must publish the matching
        /// ``TerminalWidthTraits/SkinTone/detached`` claim (``widthTraits``
        /// does); without it the claim is two cells short and the swatch
        /// shears the row, which is the case ``stripAll`` exists for.
        case keepDetached
        /// The same, but only for a BMP base (✊🏻 ☝🏽) — an SMP base (👍🏽)
        /// merges into its own width. iTerm2. The split is per plane here,
        /// unlike tmux's, which is per base codepoint
        /// (``stripTmuxDetached``).
        case keepDetachedOnBMPBases
        /// Strip every skin-tone modifier. This is what a claim that does
        /// NOT cover the detached rendering needs — the fallback when no
        /// traits were published — rather than any host's shipped walk.
        case stripAll
        /// Strip only clusters whose base tmux was measured to DETACH,
        /// keeping the 70 bases it merges into the claim
        /// (``Swift/Character/tmuxMergedToneBases``). This is tmux — and the
        /// split is per codepoint, not per plane: 🤙 (SMP) detaches while 🧑
        /// (also SMP) merges, which is what sank the by-plane rule this case
        /// used to encode (`stripBMPBases`, retired 2026-08-28).
        case stripTmuxDetached
        /// Keep every scalar and pull the internal column back to the claim
        /// with `CUB(advance − claim)` after the cluster. Aligned everywhere
        /// measured — and the terminal re-renders the cluster as its bare
        /// base, so the tone does not survive on screen.
        case pullBack
        /// Rewrite every Fitzpatrick cluster as base + ZWNJ + modifier,
        /// claiming the separated width (base + 3 — the ZWNJ takes a
        /// column), so the tone renders as a swatch beside the base. A
        /// text-presentation base (☝🏻) is promoted with VS-16 first — the
        /// bare rewrite was measured to misalign for those, and the old
        /// pull-back re-rendered the narrow monochrome glyph with the tone
        /// lost — and the promoted form then takes the ordinary
        /// erase-and-push (`ECH(5)` + cluster + `CUF(1)`, card-measured
        /// 2026-08-28). Apple Terminal's treatment.
        case separate

        /// Whether a walk driven by this case strips a redundant VS-16 from a
        /// tone cluster (☝️🏽 → ☝🏽) before pricing it, as the shared
        /// forward-compensation walk does — the modifier alone already forces
        /// emoji presentation, and the normalized pair is the one every host
        /// was measured against. The Apple-family cases keep the author's
        /// scalar instead: ``separate`` re-promotes the base itself (both
        /// spellings emit identical bytes) and ``pullBack`` measured
        /// identically either way.
        public var stripsRedundantToneVS16: Bool {
            switch self {
            case .keep, .keepDetached, .keepDetachedOnBMPBases,
                .stripAll, .stripTmuxDetached:
                true
            case .pullBack, .separate:
                false
            }
        }
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

    /// What this terminal does with a keycap — base + U+20E3, with or without
    /// the U+FE0F that makes it emoji-presentation.
    public enum Keycaps: String, Sendable, Equatable, Codable, CaseIterable {
        /// Both spellings land on their claim. Ghostty and Warp.
        case correct
        /// Advance 1 against the 2-cell claim of the FE0F form. iTerm2.
        case underAdvances
        /// Advance 2 whatever the claim — which the FE0F form (claimed 2)
        /// meets and the BARE form (1⃣, claimed 1, the base's own width) runs
        /// one past, so the bare one is pulled back with `CUB(1)`. Apple
        /// Terminal.
        case alwaysTwoColumns
    }

    /// How this terminal handles keycaps — 1️⃣ and its selector-less spelling.
    public var keycaps: Keycaps

    /// Plane-16 Private Use Area — SF Symbols. Painted two cells by any font
    /// that has the glyphs, advanced one on every measured host.
    public var planeSixteenPUA: Bool

    /// Unicode 16.0's new emoji — 🪉 🪏 🪾 🫆 🫜 🫟 🫩. A width table cut before
    /// that release scores them narrow: painted two cells, advanced one. Warp
    /// is the only measured host with it, and a terminal that has not updated
    /// its tables since 2024 will have it too.
    public var preUnicode16WidthTable: Bool

    /// The terminal's INTERNAL column decomposes a ZWJ sequence — advancing
    /// the sum of the segments plus one per joiner — and no cursor repair
    /// squares that with the row's stored content (Apple Terminal:
    /// 👨‍👩‍👧‍👦 internal 11, paint 2, and every `CUB`/`DCH` repair measured
    /// either displaced later writes on the row or re-rendered the cluster
    /// stripped). The walk decomposes the sequence in software instead —
    /// segments emitted as independent clusters, joiners removed — and the
    /// claim follows (``widthTraits``).
    public var zwjSequences: Bool

    /// The same divergence for tag-sequence flags (🏴󠁧󠁢󠁳󠁣󠁴󠁿): internal advance
    /// 2 plus one per tag scalar, painted 2. Apple Terminal. The walk pulls
    /// the column back with `CUB` — measured aligned, stored width included.
    public var tagFlags: Bool

    /// Flag pairs and keycaps are STORED one column wider than they paint, so
    /// everything later on the row — absolutely-addressed writes included —
    /// lands one cell left, whatever the cursor does. The walk deletes the
    /// surplus stored column from inside the cluster: `CUB(1)`, `DCH(1)`,
    /// `CUF(1)`. Apple Terminal.
    public var storesWideComposites: Bool

    /// How this terminal handles skin-tone clusters.
    public var skinTones: SkinTones

    /// A Fitzpatrick cluster on a TEXT-presentation base (☝🏻 ✌🏼 ✍🏽 ⛹🏾, and
    /// the SMP flavour 🏋🏽) merges into **one** cell rather than two: the base
    /// is a narrow text glyph and the host keeps it that way with the modifier
    /// folded in. Claimed 2, so a `CUF` is owed — alignment bought with a
    /// blank cell rather than a shear.
    ///
    /// Orthogonal to ``skinTones`` because one host does both: iTerm2 detaches
    /// a BMP base (``SkinTones/keepDetachedOnBMPBases`` widens that claim, and
    /// a widened claim wins) while merging the SMP form. Ghostty merges both
    /// planes and detaches nothing.
    public var mergesTonesOnTextBases: Bool

    /// The terminal leaves the cells a compensated glyph covers at ITS default
    /// background rather than the one in force, so they have to be erased into
    /// that background before the glyph is drawn.
    ///
    /// Measured on all four native hosts — an earlier note here said "Apple
    /// Terminal and nowhere else", which turned out to mean "nowhere else had
    /// been measured on a coloured run": Apple Terminal first (eight
    /// under-advancing glyphs on a coloured run leave every second cell
    /// unpainted and the row reads as a comb), then 2026-08-28 the same hole
    /// under every SF Symbol on iTerm2 and Ghostty, iTerm2's keycaps and
    /// VS-16 clusters, and the right half of Warp's lone regional indicator.
    /// Only tmux remains unmeasured, and an unmeasured terminal is assumed to
    /// paint correctly — which is why this stays a switch instead of always
    /// riding along with an under-advance.
    public var erasesUnderGlyphs: Bool

    /// A terminal with no known defects — the correct starting point, and the
    /// correct answer for most terminals.
    public init(
        vs16Pictographs: Bool = false,
        barePictographs: Bool = false,
        vs15ChromeGlyphs: Bool = false,
        loneRegionalIndicators: Bool = false,
        flagPairs: Bool = false,
        keycaps: Keycaps = .correct,
        planeSixteenPUA: Bool = false,
        preUnicode16WidthTable: Bool = false,
        zwjSequences: Bool = false,
        tagFlags: Bool = false,
        storesWideComposites: Bool = false,
        skinTones: SkinTones = .keep,
        mergesTonesOnTextBases: Bool = false,
        erasesUnderGlyphs: Bool = false
    ) {
        self.vs16Pictographs = vs16Pictographs
        self.barePictographs = barePictographs
        self.vs15ChromeGlyphs = vs15ChromeGlyphs
        self.loneRegionalIndicators = loneRegionalIndicators
        self.flagPairs = flagPairs
        self.keycaps = keycaps
        self.planeSixteenPUA = planeSixteenPUA
        self.preUnicode16WidthTable = preUnicode16WidthTable
        self.zwjSequences = zwjSequences
        self.tagFlags = tagFlags
        self.storesWideComposites = storesWideComposites
        self.skinTones = skinTones
        self.mergesTonesOnTextBases = mergesTonesOnTextBases
        self.erasesUnderGlyphs = erasesUnderGlyphs
    }

    /// The ``TerminalWidthTraits`` these switches imply — the claims that must
    /// be in force for the mirror walk's emissions to conserve.
    ///
    /// Two switches change what a cluster CLAIMS, not just how it is emitted:
    /// software ZWJ decomposition makes the sequence claim the sum of its
    /// segments, and skin-tone separation makes an emoji-presentation base's
    /// cluster claim the separated width. Whoever renders with a custom quirk
    /// set applies these traits alongside it, exactly as startup applies the
    /// identified host's.
    public var widthTraits: TerminalWidthTraits {
        let skinTone: TerminalWidthTraits.SkinTone =
            switch skinTones {
            case .separate: .separated
            case .keepDetached: .detached
            case .keepDetachedOnBMPBases: .detachedOnBMPBases
            case .keep, .stripAll, .stripTmuxDetached, .pullBack: .merged
            }
        return TerminalWidthTraits(
            zwjSequences: zwjSequences ? .decomposedDroppingJoiners : .composed,
            skinTone: skinTone)
    }

    /// Whether any workaround at all is selected.
    public var isEmpty: Bool { self == Self() }

    /// The value as the Swift expression that produces it — every property
    /// that differs from the default, by name.
    ///
    /// Derived HERE, beside the properties, and not spelled out by hand in the
    /// explorer that writes reports: a hand-written list covered eleven of the
    /// fourteen and dropped `zwjSequences`, `tagFlags` and
    /// `storesWideComposites` from the report, so a session that needed only
    /// one of those was written up as "nothing needed".
    public var swiftLiteral: String {
        var parts: [String] = []
        if vs16Pictographs { parts.append("vs16Pictographs: true") }
        if barePictographs { parts.append("barePictographs: true") }
        if vs15ChromeGlyphs { parts.append("vs15ChromeGlyphs: true") }
        if loneRegionalIndicators { parts.append("loneRegionalIndicators: true") }
        if flagPairs { parts.append("flagPairs: true") }
        if keycaps != .correct { parts.append("keycaps: .\(keycaps.rawValue)") }
        if planeSixteenPUA { parts.append("planeSixteenPUA: true") }
        if preUnicode16WidthTable { parts.append("preUnicode16WidthTable: true") }
        if zwjSequences { parts.append("zwjSequences: true") }
        if tagFlags { parts.append("tagFlags: true") }
        if storesWideComposites { parts.append("storesWideComposites: true") }
        if skinTones != .keep { parts.append("skinTones: .\(skinTones.rawValue)") }
        if mergesTonesOnTextBases { parts.append("mergesTonesOnTextBases: true") }
        if erasesUnderGlyphs { parts.append("erasesUnderGlyphs: true") }
        return parts.isEmpty
            ? "TerminalQuirks()  # nothing needed — this terminal renders correctly"
            : "TerminalQuirks(\(parts.joined(separator: ", ")))"
    }

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
            Character.isPlaneSixteenGlyph(only.value)
        {
            return 1
        }
        if preUnicode16WidthTable, cluster.isUnicode16EmojiOlderTablesMiss { return 1 }
        if keycaps != .correct, scalars.contains(where: { $0.value == 0x20E3 }) {
            return keycaps == .underAdvances ? 1 : 2
        }
        if loneRegionalIndicators, cluster.isLoneRegionalIndicator { return 1 }
        if flagPairs, Self.isFlagPair(cluster) { return 1 }
        // The ZWJ form too: on a host that under-advances a standalone VS-16
        // cluster, a sequence whose FIRST segment carries the selector folds
        // into that same 1 (❤️‍🔥 🏳️‍🌈 ⛓️‍💥). Only reachable when the joiner
        // decomposition above did not claim the cluster.
        if vs16Pictographs, cluster.isVS16UnderAdvancer || cluster.leadsWithVS16Segment {
            return 1
        }
        if barePictographs, cluster.isBarePictographUnderAdvancer { return 1 }
        if vs15ChromeGlyphs, cluster.isVS15ChromeUnderAdvancer { return 1 }
        return width
    }

    /// The composed-cluster rules — joiner decomposition, tag flags, and skin
    /// tones — split from ``cursorAdvance(of:)`` because each is a small rule
    /// and together they were most of that function's branching.
    private func composedAdvance(of cluster: Character, width: Int) -> Int? {
        let scalars = cluster.unicodeScalars

        // Joiner decomposition first — its segments resolve through
        // ``cursorAdvance(of:)``, which is how a skin-toned segment inside a
        // sequence (👩🏽‍🚀) gets both rules at once. The ZWNJ arm prices the
        // separated skin-tone emission (🤙+ZWNJ+🏽: the joiner takes a column,
        // so 2+1+2 = 5).
        let hasZWJ = scalars.contains { $0.value == 0x200D }
        let hasZWNJ = scalars.contains { $0.value == 0x200C }
        // The ZWNJ sum applies under `.pullBack` as well as `.separate`: both
        // describe the same terminal (the internal column sums joiners
        // whatever the walk emits — see the tone arm below), and a
        // pre-separated base+ZWNJ+modifier cluster can arrive in user data.
        // Pricing it 4 under `.pullBack` emitted CUB(2) where the real model
        // sums 5 and the real walk emits CUB(3) — a one-cell mirror drift.
        if (hasZWJ && zwjSequences)
            || (hasZWNJ && !hasZWJ && (skinTones == .separate || skinTones == .pullBack)),
            let summed = Character.summedInternalJoinerAdvance(cluster, segmentAdvance: {
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
        case .pullBack, .separate:
            // Measured on Apple Terminal: the internal column moves the bare
            // base's width plus two. The same number under `.separate`,
            // because it describes the same terminal — the switches differ in
            // what the walk EMITS for it, not in what the host does to the
            // composed cluster.
            return first.properties.isEmojiPresentation ? 4 : 3
        case .stripAll:
            // Stripped before the walk ever sees it, so its advance is the
            // base's — which is the claim, hence no divergence to report.
            return width
        case .stripTmuxDetached:
            // A detached-base cluster is stripped before the walk, so its
            // advance is the base's — the claim. A merged one is kept, and
            // falls through to whatever other switches say about it.
            return Character.tmuxMergedToneBases.contains(first.value) ? nil : width
        case .keepDetached:
            return detachedToneAdvance(of: cluster)
        case .keepDetachedOnBMPBases:
            // Only a BMP base detaches; an SMP one merges into its own width
            // and takes whatever the merge switch below says about it.
            if first.value <= 0xFFFF { return detachedToneAdvance(of: cluster) }
            return mergedToneAdvance(of: cluster, base: first)
        case .keep:
            return mergedToneAdvance(of: cluster, base: first)
        }
    }

    /// What a MERGED skin-tone cluster advances — `nil` when it simply lands
    /// on its claim.
    ///
    /// Split out because two arms of ``composedAdvance(of:width:)`` reach it:
    /// a host that detaches nothing, and one that detaches only BMP bases and
    /// so arrives here for the SMP ones.
    private func mergedToneAdvance(of cluster: Character, base: Unicode.Scalar) -> Int? {
        guard mergesTonesOnTextBases, !base.properties.isEmojiPresentation else { return nil }
        // A redundant VS-16 defeats the merge — the selector promotes the base
        // to its emoji presentation and the modifier detaches beside it, so
        // the cluster is priced as a detached one. Raw-cluster truth only:
        // the walk strips the selector before either merging host sees it.
        guard cluster.unicodeScalars.contains(where: { $0.value == 0xFE0F }) else { return 1 }
        return detachedToneAdvance(of: cluster)
    }

    /// A DETACHED tone cluster's advance: the base drawn at whatever the rest
    /// of this switch set says it costs, plus two per modifier swatch beside
    /// it.
    ///
    /// Compositional rather than a constant because the base's own cost is a
    /// property of the host, and the two rules then compose instead of
    /// duplicating each other: a bare SMP pictograph base under-advances on
    /// Warp (🏋🏽 = 1+2 against a 4-cell claim, so a repair IS owed even though
    /// the tone is claimed detached), a VS-16-promoted base under-advances on
    /// iTerm2 (☝️🏽 = 1+2) and does not on Ghostty (2+2). Stating the
    /// composition is also what keeps a raw-cluster truth out of the claim —
    /// the claim follows the emitted form, which for the spelled clusters is
    /// the selector-stripped one.
    private func detachedToneAdvance(of cluster: Character) -> Int {
        var base = String.UnicodeScalarView()
        var modifiers = 0
        for scalar in cluster.unicodeScalars {
            if (0x1F3FB...0x1F3FF).contains(scalar.value) {
                modifiers += 1
            } else {
                base.append(scalar)
            }
        }
        // Terminates: the base carries no modifier, so it cannot re-enter here.
        return cursorAdvance(of: Character(String(base))) + 2 * modifiers
    }

    /// A flag: exactly two regional indicators.
    static func isFlagPair(_ cluster: Character) -> Bool {
        // On the scalar view directly — no Array. This runs inside
        // `terminalAppStoresWiderThanPainted`, which the Apple walk asks for
        // every visible character of every non-ASCII output line, and the
        // Array copy was a heap allocation per character on that path.
        let scalars = cluster.unicodeScalars
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
    /// first where a strip is selected, software ZWJ decomposition and the
    /// base+ZWNJ+modifier skin-tone rewrite where those are selected,
    /// `ECH`+glyph+`CUF` for under-advancers, the cluster plus `CUB` for
    /// over-advancers (`.pullBack`, tag flags), and the `CUB(1)` `DCH(1)`
    /// `CUF(1)` store surgery for flags and keycaps — so what is seen while
    /// exploring a new terminal is exactly what that terminal would get once
    /// its model was written down. `TerminalQuirksTests` pins the Apple-shaped
    /// set to the real Apple walk, emission for emission, which is what keeps
    /// the mirror from drifting.
    ///
    /// Callers rendering with a claim-changing switch (``TerminalQuirks/zwjSequences``,
    /// ``TerminalQuirks/SkinTones/separate``) must have the matching
    /// ``TerminalQuirks/widthTraits`` in force, exactly as the real walk
    /// requires the identified host's traits.
    public func withCursorCompensation(for quirks: TerminalQuirks) -> String {
        let stripped =
            switch quirks.skinTones {
            case .keep, .keepDetached, .keepDetachedOnBMPBases, .pullBack, .separate: self
            case .stripAll: withSkinToneFallback(scope: .all)
            case .stripTmuxDetached: withSkinToneFallback(scope: .keepingTmuxMerged)
            }
        guard !quirks.isEmpty else { return stripped }

        var result = ""
        result.reserveCapacity(stripped.count + 8)

        func appendCompensated(_ original: Character) {
            var character = original
            // See ``TerminalQuirks/SkinTones/stripsRedundantToneVS16`` for
            // why the families differ here.
            if quirks.skinTones.stripsRedundantToneVS16 {
                character = character.withoutRedundantToneVS16 ?? character
            }
            if quirks.skinTones == .separate,
                let separated = character.separatedSkinToneEmission
            {
                // Falls THROUGH to the arms below, as in the real Apple walk:
                // an emoji-presentation base lands on its claim and goes out
                // plain; a VS-16-promoted text-presentation base
                // under-advances (when the explorer's advance model says so)
                // and takes the ordinary ECH/CUF repair.
                character = Character(separated)
            }
            let claimed = character.terminalWidth
            let advance = quirks.cursorAdvance(of: character)
            if quirks.storesWideComposites, character.terminalAppStoresWiderThanPainted,
                advance == claimed
            {
                // Store surgery presumes the cursor maths already balance; an
                // explorer who has ALSO marked this class as under-advancing
                // (a different terminal's defect) gets the under-advance
                // repair, which is the one their advance model describes.
                result.append(character)
                result += "\u{1B}[1D\u{1B}[1P\u{1B}[1C"
                return
            }
            if claimed > advance {
                if quirks.erasesUnderGlyphs {
                    result += "\u{1B}[\(claimed)X"
                }
                result.append(character)
                result += "\u{1B}[\(claimed - advance)C"
            } else if advance > claimed {
                result.append(character)
                result += "\u{1B}[\(advance - claimed)D"
            } else {
                result.append(character)
            }
        }

        var index = stripped.startIndex
        while index < stripped.endIndex {
            let character = stripped[index]
            if character == "\u{1B}" {
                let sequenceStart = index
                index = stripped.escapeSequenceEnd(from: index)
                result += stripped[sequenceStart..<index]
                continue
            }
            if quirks.zwjSequences, let segments = character.emojiZWJSegments {
                for segment in segments {
                    appendCompensated(segment)
                }
            } else {
                appendCompensated(character)
            }
            index = stripped.index(after: index)
        }
        return result
    }
}
