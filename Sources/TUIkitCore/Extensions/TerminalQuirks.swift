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
    /// get wrong by *over*-advancing rather than under-advancing — the cursor
    /// ends up past where the glyph was claimed to end, and no forward move
    /// can undo that. The only workaround is to not send the modifier.
    public enum SkinTones: String, Sendable, Equatable, Codable, CaseIterable {
        /// The terminal joins the cluster into the two cells claimed for it.
        /// Ghostty is the only measured terminal that does.
        case keep
        /// Strip every skin-tone modifier (iTerm2, Warp, Apple Terminal).
        case stripAll
        /// Strip only clusters whose base is a BMP scalar (✊🏻 ☝🏽), keeping the
        /// SMP-based ones the terminal joins correctly. This is tmux.
        case stripBMPBases
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

        if skinTones != .keep, let first = scalars.first,
            scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) })
        {
            // Stripped before the walk ever sees it, so its advance is the
            // base's — which is the claim, hence no divergence to report.
            if skinTones == .stripAll || first.value <= 0xFFFF { return width }
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

    /// A flag: exactly two regional indicators.
    static func isFlagPair(_ cluster: Character) -> Bool {
        let scalars = Array(cluster.unicodeScalars)
        return scalars.count == 2 && scalars.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.value) }
    }
}

// MARK: - Compensating for them

extension String {

    /// This string with `quirks` compensated for — the generic counterpart of
    /// the per-host walks (``withTerminalAppCursorCompensation(followedByContent:)``
    /// and friends), driven by a set of switches rather than a measured model.
    ///
    /// Applies the skin-tone strip first and then the same CUF injection every
    /// measured host uses, so what is seen while exploring a new terminal is
    /// what that terminal would get once its model was written down.
    public func withCursorCompensation(for quirks: TerminalQuirks) -> String {
        let stripped =
            switch quirks.skinTones {
            case .keep: self
            case .stripAll: withSkinToneFallback(basePlane: .all)
            case .stripBMPBases: withSkinToneFallback(basePlane: .bmpOnly)
            }
        guard !quirks.isEmpty else { return stripped }
        return stripped.withCursorForwardCompensation(
            erasingUnderGlyph: quirks.erasesUnderGlyphs
        ) { quirks.cursorAdvance(of: $0) }
    }
}
