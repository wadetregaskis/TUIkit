//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AccentFillBreath.swift
//
//  The shares of the accent a fill's breath runs between, chosen as a 256-colour
//  terminal draws the breath.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The two shares of the accent, over a ground, that a fill's breath runs between
/// (``Palette/accentFillPulse(over:)``), chosen as the terminal least able to show a
/// breath draws it: on 256 colours, as the shades
/// ``Color/pulseRamp(from:to:depth:samples:)`` walks, each moved onto the cube.
///
/// The breath is ``ViewConstants/focusPulseMin`` to ``ViewConstants/focusPulseMax``
/// wherever that holds as drawn. Two fixed shares were all it used to be, chosen and
/// audited in truecolour, and the cube keeps neither a share's colour nor the text's: it
/// moves each onto one of its entries. So where the plain breath does not hold, its ends
/// walk, a hundredth at a time:
///
/// - **The text stays readable.** Every shade keeps the row's text at
///   ``ViewConstants/rowBreathPeakContrastFloor``, the floor the top was only ever
///   audited at in truecolour. Where one does not, the top comes down until none fails.
///   Violet's breath passed through `#5F5F87` under its `#AF5FFF` text, 1.70:1, and
///   now tops out at 37%; Red Sands' reached `#D78700` under `#D7D7AF`, 1.93:1, and
///   tops out at 46%. Every shade, not only the top's: the cube does not keep a lerp's
///   order. Violet's top floored in lightness alone
///   (``Color/ensuringRenderedContrast(atLeast:against:)``) is `#4E3B61`, drawn
///   `#5F0087`, and the breath to it still passes through `#5F5F87` on the way.
///
/// Measured through the cube on every terminal, not only where the depth demands it, so a
/// breath looks the same everywhere: the rule ``Palette/hoveredControlFace`` and
/// ``Color/ensuringRenderedContrast(atLeast:against:)`` follow, for the same reason.
/// Sixteen colours are not promised.
///
/// The walk asks for up to one ramp per hundredth it tries, so its answer is kept
/// (``ends(accent:ground:text:)``).
struct AccentFillBreath {
    /// The colour the breath is a share of.
    let accent: Color

    /// What the breath is drawn over.
    let ground: Color

    /// The row's text as the cube draws it, or `nil` where it has no RGB to measure, and
    /// no floor is kept.
    let text: Color?

    init(accent: Color, ground: Color, text: Color) {
        self.accent = accent
        self.ground = ground
        let drawn = text.downsampledToPalette256()
        self.text = drawn.rgbComponents == nil ? nil : drawn
    }

    /// `share` hundredths of the accent over the ground.
    func tint(_ share: Int) -> Color {
        accent.opacity(Double(share) / 100, over: ground)
    }

    /// The entries a 256-colour terminal draws for a breath from `dim` to `bright`
    /// hundredths.
    func shades(_ dim: Int, _ bright: Int) -> [Color] {
        Color.pulseRamp(from: tint(dim), to: tint(bright), depth: .palette256)
            .map { $0.downsampledToPalette256() }
    }

    /// Whether a breath from `dim` to `bright` hundredths keeps the row's text readable
    /// on every shade.
    func holds(_ dim: Int, _ bright: Int) -> Bool {
        guard let text else { return true }
        let floor = ViewConstants.rowBreathPeakContrastFloor
        return !shades(dim, bright).contains { text.contrastRatio(against: $0) < floor }
    }

    /// The breath's two shares, in hundredths.
    var shares: (dim: Int, bright: Int) {
        let dim = Self.hundredths(ViewConstants.focusPulseMin)
        var bright = Self.hundredths(ViewConstants.focusPulseMax)
        // The top comes down until the breath holds. Where no share above the dim end
        // does, it stays where it was asked: the floor makes no promise it cannot keep.
        if !holds(dim, bright),
            let readable = stride(from: bright - 1, to: dim, by: -1).first(where: { holds(dim, $0) })
        {
            bright = readable
        }
        return (dim, bright)
    }

    /// The breath's two ends.
    var ends: (dim: Color, bright: Color) {
        let (dim, bright) = shares
        return (tint(dim), tint(bright))
    }

    /// `value` in whole hundredths.
    private static func hundredths(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }
}

// MARK: - The answer, kept

extension AccentFillBreath {
    /// The ends of the breath of `accent` over `ground` under `text`: ``ends``, kept.
    ///
    /// A breath is asked for every frame by every highlight that draws one, and where the
    /// plain shares do not hold, the walk tries a ramp per hundredth — up to one per
    /// share between the ends. Kept for colours whose rendering nothing can move: none of
    /// them the terminal's own. A colour the terminal decides measures as whatever it last
    /// reported, including under a task-scoped pin (`TerminalColors.withCurrent`), which
    /// moves no generation a key could hold; such a breath is walked each time.
    static func ends(accent: Color, ground: Color, text: Color) -> (dim: Color, bright: Color) {
        guard !accent.isTerminalDefined, !ground.isTerminalDefined, !text.isTerminalDefined else {
            return AccentFillBreath(accent: accent, ground: ground, text: text).ends
        }
        let key = Key(accent: accent, ground: ground, text: text)
        if let kept = cacheLock.withLock({ cache[key] }) { return kept }
        let answer = AccentFillBreath(accent: accent, ground: ground, text: text).ends
        cacheLock.withLock {
            // A backstop against unbounded growth, as for `Color.pulseRamp`'s cache: an
            // app has a handful of accents over a handful of grounds.
            if cache.count > 128 { cache.removeAll(keepingCapacity: true) }
            cache[key] = answer
        }
        return answer
    }

    private struct Key: Hashable {
        let accent: Color
        let ground: Color
        let text: Color
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: (dim: Color, bright: Color)] = [:]
}
