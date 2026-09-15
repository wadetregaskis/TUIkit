//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BlendEndsTests.swift
//
//  What a blend answers from its ends: `lerp`, `interpolate` (and so `mix` and a
//  gradient), `opacity(_:over:)` and `compositing(_:over:)`. An end comes back as
//  it is spelled, so a terminal slot at phase 0 is still that slot. A side with no
//  RGB (`Color.default`, or the terminal's own colours before it reports them) has
//  nothing to mix, so the blend takes the heavier end: `from` through phase ½, `to`
//  past it. Two RGB ends blend exactly as they always have.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

/// A page the terminal decides, with an ink and an accent that are RGB.
private struct TerminalPagePalette: Palette {
    let id = "blend-terminal-page"
    let name = "Blend terminal page"
    let background = Color(value: .terminalBackground)
    let foreground = Color.rgb(20, 20, 20)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@Suite("Blends keep their ends, and snap across a side with no RGB")
struct BlendEndsTests {

    private static let ink = Color(value: .terminalForeground)
    private static let paper = Color(value: .terminalBackground)

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    private static func isRGB(_ colour: Color) -> Bool {
        if case .rgb = colour.value { return true }
        return false
    }

    // MARK: - Ends

    @Test("An opaque terminal slot composited at full strength is that slot")
    func fullStrengthKeepsTheSlot() {
        #expect(Color.ansi(.red).opacity(1, over: .white) == Color.ansi(.red))
        #expect(Color.ansi(.red).compositing(1, over: .white) == Color.ansi(.red))
        #expect(Color.palette(9).opacity(1, over: .black) == Color.palette(9))
        #expect(Color.white.opacity(0, over: .ansi(.blue)) == Color.ansi(.blue))
        #expect(Color.white.compositing(0, over: .ansi(.blue)) == Color.ansi(.blue))
    }

    @Test("lerp, interpolate and mix return their ends as spelled at phase 0 and 1")
    func endsKeepTheirSpelling() {
        let pairs: [(from: Color, to: Color)] = [
            (Color.ansi(.red), Color.ansi(.blue)),
            (Color.rgb(10, 20, 30), Color.ansi(.green)),
            (Color.palette(200), Color.rgb(1, 2, 3)),
            (Color.ansi(.brightWhite), Color.palette(3)),
            (Color.ansi(.red).opacity(0.5), Color.ansi(.cyan)),
        ]
        for (from, to) in pairs {
            #expect(Color.lerp(from, to, phase: 0) == from, "\(from) → \(to)")
            #expect(Color.lerp(from, to, phase: 1) == to, "\(from) → \(to)")
            #expect(Color.lerp(from, to, phase: -3) == from, "clamped, \(from) → \(to)")
            #expect(Color.lerp(from, to, phase: 2) == to, "clamped, \(from) → \(to)")
            #expect(Color.lerp(from, to, phase: .nan) == from, "NaN, \(from) → \(to)")
            for space in [Gradient.ColorSpace.device, Gradient.ColorSpace.perceptual] {
                #expect(Color.interpolate(from, to, phase: 0, in: space) == from, "\(space), \(from) → \(to)")
                #expect(Color.interpolate(from, to, phase: 1, in: space) == to, "\(space), \(from) → \(to)")
            }
            #expect(from.mix(with: to, by: 0) == from, "\(from) → \(to)")
            #expect(from.mix(with: to, by: 1) == to, "\(from) → \(to)")
            // Only the ends: a measurable pair still blends as RGB between them.
            #expect(Self.isRGB(Color.lerp(from, to, phase: 0.5)), "\(from) → \(to)")
            #expect(Self.isRGB(from.mix(with: to, by: 0.5)), "\(from) → \(to)")
        }
    }

    @Test("Equal ends keep their spelling and interpolate only the alpha")
    func equalEndsKeepTheirSpelling() {
        let solid = Color.ansi(.red)
        let clearish = Color.ansi(.red).opacity(0)
        let halfway = Color.lerp(solid, clearish, phase: 0.5)
        #expect(halfway.value == solid.value)
        #expect(halfway.alpha == 128)
        let quarter = solid.mix(with: clearish, by: 0.25)
        #expect(quarter.value == solid.value)
        #expect(quarter.alpha == 191)
        #expect(Color.ansi(.red).opacity(0.3, over: .ansi(.red)) == Color.ansi(.red))
        #expect(Color.ansi(.red).compositing(0.3, over: .ansi(.red)) == Color.ansi(.red))
        // With no RGB as well: nothing is mixed, so there is nothing to snap.
        TerminalColors.withCurrent(.unknown) {
            let fading = Color.lerp(Self.ink, Self.ink.opacity(0), phase: 0.75)
            #expect(fading.value == Self.ink.value)
            #expect(fading.alpha == 64)
            let fadingDefault = Color.lerp(Color.default, Color.default.opacity(0), phase: 0.5)
            #expect(fadingDefault.value == Color.default.value)
            #expect(fadingDefault.alpha == 128)
        }
    }

    // MARK: - RGB, unchanged

    private static func mixed(_ start: UInt8, _ end: UInt8, _ phase: Double) -> UInt8 {
        UInt8(min(255, max(0, (Double(start) + (Double(end) - Double(start)) * phase).rounded())))
    }

    private static func referenceLerp(_ from: Color, _ to: Color, _ phase: Double) -> Color {
        let clamped = min(1, max(0, phase))
        guard let lhs = from.rgbComponents, let rhs = to.rgbComponents else { return from }
        var result = Color.rgb(
            mixed(lhs.red, rhs.red, clamped), mixed(lhs.green, rhs.green, clamped),
            mixed(lhs.blue, rhs.blue, clamped))
        result.alpha = mixed(from.alpha, to.alpha, clamped)
        return result
    }

    private static func referencePerceptual(_ from: Color, _ to: Color, _ phase: Double) -> Color {
        let clamped = min(1, max(0, phase))
        guard let lhs = from.rgbComponents, let rhs = to.rgbComponents else { return from }
        let start = Color.oklab(red: lhs.red, green: lhs.green, blue: lhs.blue)
        let end = Color.oklab(red: rhs.red, green: rhs.green, blue: rhs.blue)
        let blended = Color.fromOKLab(
            l: start.l + (end.l - start.l) * clamped, a: start.a + (end.a - start.a) * clamped,
            b: start.b + (end.b - start.b) * clamped)
        var result = Color.rgb(blended.red, blended.green, blended.blue)
        result.alpha = mixed(from.alpha, to.alpha, clamped)
        return result
    }

    private static func referenceOpacity(_ colour: Color, _ opacity: Double, over surface: Color) -> Color {
        let coverage = Double(colour.alpha) / 255 * min(1, max(0, opacity))
        var result = referenceLerp(colour, surface, 1 - coverage)
        result.alpha = .max
        return result
    }

    private static func referenceCompositing(_ colour: Color, _ opacity: Double, over surface: Color) -> Color {
        guard let source = colour.rgbComponents, let behind = surface.rgbComponents else { return colour }
        let alpha = min(1, max(0, opacity))
        func channel(_ over: UInt8, _ under: UInt8) -> UInt8 {
            Color.encodedChannel(alpha * Color.linearChannel(over) + (1 - alpha) * Color.linearChannel(under))
        }
        return Color.rgb(
            channel(source.red, behind.red), channel(source.green, behind.green),
            channel(source.blue, behind.blue))
    }

    /// The arithmetic each blend did before any end was kept, written out here, over
    /// a grid of RGB pairs, alphas and phases, including equal ends, the clamped
    /// range and NaN. Keeping an end's spelling must not move a single RGB byte.
    @Test("Two RGB ends blend byte for byte as they did")
    func rgbBlendsAreUnchanged() {
        let bases: [Color] = [
            Color.rgb(0, 0, 0), Color.rgb(255, 255, 255), Color.rgb(1, 2, 3),
            Color.rgb(200, 40, 40), Color.rgb(37, 128, 254), Color.rgb(128, 128, 128),
        ]
        let colours = bases.flatMap { [$0, $0.opacity(0.5), $0.opacity(0)] }
        let phases: [Double] = [-0.5, 0, 0.001, 0.2, 0.5, 0.6, 0.999, 1, 1.5, .nan]
        var mismatches: [String] = []
        for from in colours {
            for to in colours {
                for phase in phases {
                    let checks: [(String, Color, Color)] = [
                        ("lerp", Color.lerp(from, to, phase: phase), Self.referenceLerp(from, to, phase)),
                        (
                            "perceptual", Color.interpolate(from, to, phase: phase, in: .perceptual),
                            Self.referencePerceptual(from, to, phase)
                        ),
                        (
                            "opacity(_:over:)", from.opacity(phase, over: to),
                            Self.referenceOpacity(from, phase, over: to)
                        ),
                        (
                            "compositing", from.compositing(phase, over: to),
                            Self.referenceCompositing(from, phase, over: to)
                        ),
                    ]
                    for (name, got, want) in checks where got != want {
                        mismatches.append("\(name)(\(from), \(to), \(phase)): \(got) != \(want)")
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(4))")
    }

    // MARK: - No RGB

    @Test("Across a side with no RGB a blend takes the heavier end, from through phase ½")
    func unmeasurableSideSnaps() {
        TerminalColors.withCurrent(.unknown) {
            #expect(Self.ink.opacity(0.6, over: Self.paper) == Self.ink)
            #expect(Self.ink.opacity(0.5, over: Self.paper) == Self.ink)
            #expect(Self.ink.opacity(0.4, over: Self.paper) == Self.paper)
            #expect(Self.ink.opacity(ViewConstants.disabledForeground, over: Self.paper) == Self.ink)
            #expect(Self.ink.compositing(0.5, over: Self.paper) == Self.ink)
            #expect(Self.ink.compositing(0.4, over: Self.paper) == Self.paper)

            // One side with no RGB is enough.
            let red = Color.rgb(200, 40, 40)
            #expect(Color.lerp(red, Color.default, phase: 0.5) == red)
            #expect(Color.lerp(red, Color.default, phase: 0.51) == Color.default)
            #expect(Color.lerp(Self.paper, red, phase: 0.2) == Self.paper)
            #expect(red.mix(with: Self.paper, by: 0.5) == red)
            #expect(red.mix(with: Self.paper, by: 0.7) == Self.paper)
            #expect(red.opacity(0.4, over: Self.paper) == Self.paper)
            #expect(Self.ink.opacity(0.4, over: red) == red)

            // The end comes back whole, alpha and all; `opacity(_:over:)` then spends it.
            let fadedRed = red.opacity(0.5)
            #expect(Color.lerp(Color.default, fadedRed, phase: 0.9) == fadedRed)
            #expect(Self.ink.opacity(0.5).opacity(1, over: Self.paper) == Self.ink)
        }
    }

    @Test("Reported terminal colours keep their ends and blend as RGB between them")
    func reportedColoursBlendBetweenExactEnds() {
        TerminalColors.withCurrent(Self.reported) {
            #expect(Self.ink.opacity(1, over: Self.paper) == Self.ink)
            #expect(Self.ink.opacity(0, over: Self.paper) == Self.paper)
            #expect(Self.ink.compositing(1, over: Self.paper) == Self.ink)
            let between = Self.ink.opacity(0.6, over: Self.paper)
            #expect(Self.isRGB(between))
            #expect(between == Color.rgb(171, 178, 191).opacity(0.6, over: .rgb(40, 44, 52)))
            #expect(
                Self.ink.compositing(0.6, over: Self.paper)
                    == Color.rgb(171, 178, 191).compositing(0.6, over: .rgb(40, 44, 52)))
            // `.default` never measures, reported or not.
            #expect(Color.lerp(Color.default, Self.ink, phase: 0.6) == Self.ink)
        }
    }

    @Test("A semantic side leaves the blend at its from colour, at every phase")
    func semanticSideReturnsFrom() {
        let accent = Color(value: .semantic(.accent))
        let rgb = Color.rgb(1, 2, 3)
        #expect(Color.lerp(rgb, accent, phase: 0.9) == rgb)
        #expect(Color.lerp(rgb, accent, phase: 1) == rgb)
        #expect(Color.lerp(accent, rgb, phase: 1) == accent)
        #expect(Color.lerp(accent, accent.opacity(0), phase: 0.5) == accent)
        #expect(rgb.mix(with: accent, by: 1) == rgb)
        #expect(accent.compositing(0, over: rgb) == accent)
        #expect(rgb.compositing(0, over: accent) == rgb)
    }

    @Test("A gradient stop with no RGB is a hard edge at the middle of its segment")
    func gradientStopWithoutRGBIsAnEdge() {
        TerminalColors.withCurrent(.unknown) {
            let black = Color.rgb(0, 0, 0)
            for space in [Gradient.ColorSpace.device, Gradient.ColorSpace.perceptual] {
                let ramp = Gradient(colors: [black, Self.paper], colorSpace: space)
                #expect(ramp.color(at: 0.5) == black, "\(space)")
                #expect(ramp.color(at: 0.75) == Self.paper, "\(space)")
                #expect(ramp.sampled(count: 5) == [black, black, black, Self.paper, Self.paper], "\(space)")
            }
        }
    }

    /// `restingControlFace` (0.20) and `focusBackground` (0.30) sit under half, so over a
    /// page with no RGB each is the page. Neither pulse can breathe there, so both hold
    /// their bright end: the accent, since the fill's bright end is exactly half and the
    /// tie keeps it.
    @Test("Over a page with no RGB the derived tints are the page and both pulses hold the accent")
    func derivedTintsOverAnUnmeasurablePage() {
        let palette = TerminalPagePalette()
        TerminalColors.withCurrent(.unknown) {
            #expect(palette.restingControlFace == palette.background)
            #expect(palette.focusBackground == palette.background)
            let fill = palette.accentFillPulse()
            #expect(fill.dim == palette.accent)
            #expect(fill.bright == palette.accent)
            let mark = palette.accentPulse()
            #expect(mark.dim == palette.accent)
            #expect(mark.bright == palette.accent)
        }
    }

    // MARK: - Breath ends

    /// A breath's dim end is a composite toward its ground, which over a side with no RGB
    /// snaps to the ground, so the breath would blink between the ground and the colour.
    @Test("A breath with a side that has no RGB holds its bright end")
    func breathWithoutRGBHoldsTheBrightEnd() {
        let page = Color.rgb(20, 20, 30)
        TerminalColors.withCurrent(.unknown) {
            for colour in [Color.default, Self.ink] {
                let ends = colour.breathEnds(dimmedTo: 0.35, over: page)
                #expect(ends.dim == colour && ends.bright == colour, "\(colour): \(ends)")
            }
            let accent = Color.rgb(0, 122, 255)
            let overPaper = accent.breathEnds(dimmedTo: 0.22, over: Self.paper)
            #expect(overPaper.dim == accent && overPaper.bright == accent, "\(overPaper)")
            // A translucent colour spends its alpha against the ground first: at ½ or more
            // it is the colour, below that the ground, and both ends agree either way.
            let heavy = Color.default.opacity(0.6).breathEnds(dimmedTo: 0.35, over: page)
            #expect(heavy.dim == Color.default && heavy.bright == Color.default, "\(heavy)")
            let light = Color.default.opacity(0.4).breathEnds(dimmedTo: 0.35, over: page)
            #expect(light.dim == page && light.bright == page, "\(light)")
        }
    }

    /// Measurable on both sides, the ends are what they were: a reported terminal colour
    /// dims to RGB, and RGB pairs are byte for byte the composite and the spent colour.
    @Test("A breath whose sides both measure keeps its dim end")
    func measuredBreathKeepsItsDimEnd() {
        TerminalColors.withCurrent(Self.reported) {
            let ends = Self.ink.breathEnds(dimmedTo: 0.35, over: .rgb(20, 20, 30))
            #expect(ends.bright == Self.ink)
            #expect(Self.isRGB(ends.dim), "\(ends)")
            let fill = TerminalPagePalette().accentFillPulse()
            #expect(fill.dim != fill.bright && Self.isRGB(fill.dim), "\(fill)")
        }
        let pairs = [
            (Color.rgb(0, 122, 255), Color.rgb(20, 20, 30)),
            (Color.rgb(200, 40, 40).opacity(0.5), Color.rgb(250, 250, 250)),
        ]
        for (colour, ground) in pairs {
            for factor in [0.2, 0.22, 0.35] {
                let ends = colour.breathEnds(dimmedTo: factor, over: ground)
                #expect(ends.dim == colour.opacity(factor, over: ground), "\(colour) at \(factor)")
                #expect(ends.bright == colour.spendingAlpha(over: ground), "\(colour) at \(factor)")
            }
        }
    }

    /// A breath between two colours chosen apart is blended by its cycle, and a blend with
    /// an end that has no RGB snaps, so it would blink between the two ends.
    @Test("A breath between two colours holds its bright end where either has no RGB")
    func breathBetweenTwoColoursHoldsWithoutRGB() {
        let label = Color.rgb(220, 220, 220)
        TerminalColors.withCurrent(.unknown) {
            for (dim, bright) in [(label, Self.ink), (Self.paper, label), (Color.default, Self.ink)] {
                let ends = Color.breathEnds(dim: dim, bright: bright)
                #expect(ends.dim == bright && ends.bright == bright, "\(dim) to \(bright): \(ends)")
            }
            // Two RGB ends move, whatever the terminal has said.
            let rgb = Color.breathEnds(dim: label, bright: .rgb(0, 122, 255))
            #expect(rgb.dim == label && rgb.bright == .rgb(0, 122, 255), "\(rgb)")
            // A semantic end is left alone: its blend is already `from` at every phase.
            let semantic = Color.breathEnds(dim: Self.ink, bright: .palette.accent)
            #expect(semantic.dim == Self.ink && semantic.bright == .palette.accent, "\(semantic)")
        }
        TerminalColors.withCurrent(Self.reported) {
            let ends = Color.breathEnds(dim: label, bright: Self.ink)
            #expect(ends.dim == label && ends.bright == Self.ink, "\(ends)")
        }
    }
}
