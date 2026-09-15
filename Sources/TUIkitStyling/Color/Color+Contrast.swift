//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+Contrast.swift
//
//  WCAG contrast measurement and a hue-preserving readability floor.
//  Palette derivations use these to guarantee that every colour pair an app
//  actually draws stays readable, while keeping each palette's signature
//  hues — the fix for derived colours that landed unreadably close to their
//  background on mid-tone or saturated profiles (Silver Aerogel's grey,
//  Man Page's pale yellow, Ocean's blue).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {

    // MARK: - Measurement

    /// The WCAG 2.x relative luminance of this colour (0...1), or `nil` for
    /// colours without concrete RGB components (e.g. unresolved semantics).
    public var relativeLuminance: Double? {
        guard let (red, green, blue) = rgbComponents else { return nil }
        return 0.2126 * Self.linearChannel(red) + 0.7152 * Self.linearChannel(green)
            + 0.0722 * Self.linearChannel(blue)
    }

    /// The CIE **L\*** lightness of this colour (0...100), or `nil` for colours
    /// without concrete RGB components.
    ///
    /// The companion to ``relativeLuminance``, and the right measure for a
    /// different question: *are these two colours visibly different shades?*
    /// A contrast **ratio** answers "can text be read on this", and it is
    /// hopeless at the ends of the range — the `+ 0.05` that keeps it finite
    /// also flattens it, so `#05080a` against `#0c1418` scores 1.08 while being
    /// plainly two different colours on screen, and two near-whites score 1.05
    /// while being plainly two different papers. L\* is perceptually spaced, so
    /// the same difference in L\* looks like the same difference anywhere in
    /// the range.
    public var perceivedLightness: Double? {
        guard let luminance = relativeLuminance else { return nil }
        // The CIE cube root, with the linear segment that keeps it from
        // diverging near black.
        let curved =
            luminance > 0.008856
            ? pow(luminance, 1.0 / 3.0)
            : (7.787 * luminance + 16.0 / 116.0)
        return 116 * curved - 16
    }

    /// How far apart two colours are in ``perceivedLightness`` — 0 when either
    /// has no RGB components.
    public func lightnessDifference(from other: Color) -> Double {
        guard let mine = perceivedLightness, let theirs = other.perceivedLightness else { return 0 }
        return abs(mine - theirs)
    }

    /// The WCAG contrast ratio between this colour and `other` (1...21), or
    /// `0` when either colour has no concrete RGB components.
    public func contrastRatio(against other: Color) -> Double {
        guard
            let mine = relativeLuminance,
            let theirs = other.relativeLuminance
        else { return 0 }
        let lighter = max(mine, theirs)
        let darker = min(mine, theirs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// What this colour measures as when it is drawn as INK: its `rgbComponents`,
    /// except for `Color.default`. That measures as nothing on its own, because as a
    /// fill it is the background; as ink it is the terminal's foreground, SGR 39,
    /// which is measured once the terminal reports it.
    var inkRGB: (red: UInt8, green: UInt8, blue: UInt8)? {
        guard case .terminalDefault = value else { return rgbComponents }
        return TerminalColors.current.foreground.map { (red: $0.red, green: $0.green, blue: $0.blue) }
    }

    // MARK: - Readability floor

    /// Returns this colour adjusted — hue and saturation preserved, lightness
    /// moved as little as possible — so its contrast against `background`
    /// reaches at least `minimum`.
    ///
    /// Already-readable colours return unchanged, so applying the floor to a
    /// whole palette only touches the offenders. When both lighter and darker
    /// variants can satisfy the minimum, the nearer one wins (least change to
    /// the palette's feel). If no lightness of this hue can reach the minimum
    /// (extreme minimums against mid-tone backgrounds), the closer of black /
    /// white is returned.
    ///
    /// A colour returns unchanged when it, or `background`, has no RGB
    /// components: an unresolved semantic colour, ``Color/default``, or the
    /// terminal's own foreground or background before the terminal has reported
    /// it. There is no ratio to measure, and the floor makes no guess.
    public func ensuringContrast(atLeast minimum: Double, against background: Color) -> Color {
        flooring(atLeast: minimum, against: background, asRendered: false)
    }

    /// ``ensuringContrast(atLeast:against:)``, judged on the colours the
    /// terminal will actually paint.
    ///
    /// A 256-colour terminal snaps every colour to the 6×6×6 cube, and the snap
    /// is not small. The Green palette's button face is its accent at 20% over
    /// black — `#003300` — and the cube's nearest green level is 95, not 51, so
    /// what is drawn is `#005f00`: **3.5× the luminance** the label was floored
    /// against. A `.destructive` label cleared 3:1 on the colour it was measured
    /// against and landed at 2.61:1 on the one it was read on.
    ///
    /// Compared after downsampling on *every* terminal, not only where the depth
    /// demands it, so a label looks the same everywhere —
    /// ``Palette/hoveredControlFace`` follows the same rule, for the same reason.
    ///
    /// Use this for text drawn **on a fill** (a control's face); the plain floor
    /// is right for deriving a palette, where the pair is a design decision
    /// rather than two specific cells.
    public func ensuringRenderedContrast(
        atLeast minimum: Double, against background: Color
    ) -> Color {
        flooring(atLeast: minimum, against: background, asRendered: true)
    }

    /// The shared walk behind both floors. `asRendered` measures every candidate
    /// — and the background — through the 256-colour cube.
    private func flooring(
        atLeast minimum: Double, against background: Color, asRendered: Bool
    ) -> Color {
        // Both sides measured, or no floor. A side with no RGB has no luminance, so
        // `contrastRatio` answers 0, below any minimum; for an RGB ink on such a page
        // the walk then compared 0 with 0 at every lightness and fell through to RGB
        // white, a guess that the page is dark. `Color.default` never has RGB, and the
        // terminal's own colours have none until it reports them, so what the floor
        // cannot measure it leaves as asked. (An unmeasurable ink always came back
        // unchanged: there was nothing to walk.)
        guard let (red, green, blue) = rgbComponents, background.rgbComponents != nil else { return self }
        let target = asRendered ? background.downsampledToPalette256() : background
        func ratio(_ color: Color) -> Double {
            (asRendered ? color.downsampledToPalette256() : color).contrastRatio(against: target)
        }
        guard ratio(self) < minimum else { return self }
        let (hue, saturation, lightness) = Self.rgbToHSL(red: red, green: green, blue: blue)

        // Walk lightness outward in 1% steps and note the first satisfying
        // value in each direction.
        func firstSatisfying(step: Double) -> Double? {
            var candidate = lightness + step
            while candidate >= 0, candidate <= 100 {
                if ratio(Self.hsl(hue, saturation, candidate)) >= minimum {
                    return candidate
                }
                candidate += step
            }
            return nil
        }

        let up = firstSatisfying(step: 1)
        let down = firstSatisfying(step: -1)
        // One carry at the end rather than one per arm: this switch has four
        // exits and three of them were already the same shape, which is exactly
        // where a per-return field gets forgotten.
        let floored: Color
        switch (up, down) {
        case (let brighter?, let darker?):
            let nearest =
                abs(brighter - lightness) <= abs(darker - lightness) ? brighter : darker
            floored = Self.hsl(hue, saturation, nearest)
        case (let brighter?, nil):
            floored = Self.hsl(hue, saturation, brighter)
        case (nil, let darker?):
            floored = Self.hsl(hue, saturation, darker)
        case (nil, nil):
            let white = Self.rgb(255, 255, 255)
            let black = Self.rgb(0, 0, 0)
            floored = ratio(white) >= ratio(black) ? white : black
        }
        return floored.carryingAlpha(of: self)
    }
}

extension Color {
    /// Whether every channel has reached the end of its range — pure white when
    /// `atWhite`, pure black otherwise — so scaling this colour further in that
    /// direction cannot change it.
    ///
    /// A colour with no RGB components counts as saturated: there is nothing to
    /// scale and no point walking further.
    func isSaturated(atWhite: Bool) -> Bool {
        guard let (red, green, blue) = rgbComponents else { return true }
        let end: UInt8 = atWhite ? 255 : 0
        return red == end && green == end && blue == end
    }
}
