//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeasuringWithoutRGBTests.swift
//
//  The contrast floor, `readableText(on:)` and the two hover derivations, where
//  one of the colours they measure has no RGB: `Color.default`, or the terminal's
//  own foreground or background before it has reported them. There is no ratio
//  and no lightness to walk, so each hands back the colour it was given (or the
//  resting face) instead of guessing, which used to mean RGB white.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// A page the terminal decides, with an ink and an accent that are RGB.
private struct TerminalPagePalette: Palette {
    let id = "terminal-page"
    let name = "Terminal page"
    let background = Color(value: .terminalBackground)
    let foreground = Color.rgb(20, 20, 20)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// An RGB page, with an accent the terminal decides.
private struct TerminalAccentPalette: Palette {
    let id = "terminal-accent"
    let name = "Terminal accent"
    let background = Color.rgb(40, 44, 52)
    let foreground = Color.rgb(171, 178, 191)
    let accent = Color.default
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@Suite("Measuring against a colour with no RGB")
struct MeasuringWithoutRGBTests {

    private static let ink = Color(value: .terminalForeground)
    private static let paper = Color(value: .terminalBackground)

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    /// 2.53:1 on One Dark's page, so a floor of 3 has something to do once the
    /// page is known.
    private static let red = Color.rgb(200, 40, 40)

    @Test("The contrast floor leaves an RGB ink alone on a page that cannot be measured")
    func floorKeepsTheInkOnAnUnmeasurablePage() {
        TerminalColors.withCurrent(.unknown) {
            for page in [Self.paper, Color.default] {
                #expect(Self.red.ensuringContrast(atLeast: 3, against: page) == Self.red, "on \(page)")
                #expect(Self.red.ensuringRenderedContrast(atLeast: 3, against: page) == Self.red, "rendered, on \(page)")
                let faded = Self.red.opacity(0.5)
                #expect(faded.ensuringContrast(atLeast: 3, against: page) == faded, "alpha 128, on \(page)")
            }
        }
        // `.default` has no RGB even here; the terminal's background does.
        TerminalColors.withCurrent(Self.reported) {
            #expect(Self.red.ensuringContrast(atLeast: 3, against: .default) == Self.red)
            let floored = Self.red.ensuringContrast(atLeast: 3, against: Self.paper)
            #expect(floored != Self.red, "the fixture: a reported page must move the ink")
            #expect(floored == Self.red.ensuringContrast(atLeast: 3, against: .rgb(40, 44, 52)))
        }
    }

    /// Already so before the page rule: the walk needs the ink's own RGB, and
    /// returned the ink without it.
    @Test("The contrast floor leaves an ink that cannot be measured alone")
    func floorKeepsAnUnmeasurableInk() {
        TerminalColors.withCurrent(.unknown) {
            for ink in [Self.ink, Color.default] {
                #expect(ink.ensuringContrast(atLeast: 3, against: .rgb(40, 44, 52)) == ink, "\(ink)")
                #expect(ink.ensuringRenderedContrast(atLeast: 3, against: .rgb(40, 44, 52)) == ink, "\(ink) rendered")
            }
        }
    }

    @Test("readableText(on:) is the palette's foreground on a surface that cannot be measured")
    func readableTextIsTheForeground() {
        let palette = TerminalPagePalette()
        TerminalColors.withCurrent(.unknown) {
            #expect(palette.readableText(on: Self.paper) == palette.foreground)
            #expect(palette.readableText(on: .default) == palette.foreground)
        }
        TerminalColors.withCurrent(Self.reported) {
            // 1.32:1 on the reported page, so the floor lifts it.
            #expect(palette.readableText(on: Self.paper) != palette.foreground, "the fixture")
            #expect(palette.readableText(on: .default) == palette.foreground)
        }
    }

    @Test("A hover lift leaves the ink alone when it or the page cannot be measured")
    func hoverLiftKeepsTheInk() {
        let terminalPage = TerminalPagePalette()
        let rgbPage = TerminalAccentPalette()
        TerminalColors.withCurrent(.unknown) {
            #expect(terminalPage.hoveredForeground(Self.ink) == Self.ink)
            #expect(terminalPage.hoveredForeground(Self.red) == Self.red)
            #expect(terminalPage.hoveredForeground(.default) == .default)
            #expect(rgbPage.hoveredForeground(Self.ink) == Self.ink)
            #expect(rgbPage.hoveredForeground(.default) == .default)
            let faded = Self.red.opacity(0.5)
            #expect(terminalPage.hoveredForeground(faded) == faded)
        }
        TerminalColors.withCurrent(Self.reported) {
            #expect(terminalPage.hoveredForeground(Self.ink) != Self.ink, "the fixture: both reported, so it lifts")
            #expect(terminalPage.hoveredForeground(Self.red) != Self.red, "the fixture: a reported page")
            #expect(rgbPage.hoveredForeground(.default) == .default)
        }
    }

    /// Output-neutral while a blend with an unmeasurable side returns its `from`:
    /// every tint of the walk is then the accent itself, and the walk finds
    /// nothing to step to. The guard is for when a blend snaps to the heavier
    /// end instead, which puts the page at rest and the whole accent a step
    /// past half.
    @Test("A hovered control face stays at rest when the accent or the page cannot be measured")
    func hoveredFaceStaysAtRest() {
        let terminalPage = TerminalPagePalette()
        let terminalAccent = TerminalAccentPalette()
        TerminalColors.withCurrent(.unknown) {
            #expect(terminalPage.hoveredControlFace == terminalPage.restingControlFace)
            #expect(terminalAccent.hoveredControlFace == terminalAccent.restingControlFace)
        }
        TerminalColors.withCurrent(Self.reported) {
            #expect(
                terminalPage.hoveredControlFace != terminalPage.restingControlFace,
                "the fixture: a reported page walks")
            #expect(terminalAccent.hoveredControlFace == terminalAccent.restingControlFace)
        }
    }
}
