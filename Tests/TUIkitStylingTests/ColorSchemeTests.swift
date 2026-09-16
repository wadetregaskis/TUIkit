//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorSchemeTests.swift
//
//  Which of light and dark a palette reads as: the page it paints where that can
//  be measured, the terminal's own hint where it cannot, and light where nothing
//  said anything at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// A palette that states nothing but a page (and the seven roles with no default).
///
/// The scheme rule reads the page and nothing else, so everything else here is
/// filler — deliberately so: a rule that read a second role would be reading one
/// of these.
private struct PagePalette: Palette, Hashable {
    let id = "page"
    let name = "Page"
    var background: Color
    let foreground = Color.rgb(200, 200, 200)
    let accent = Color.rgb(0, 200, 0)
    let success = Color.rgb(0, 200, 0)
    let warning = Color.rgb(200, 200, 0)
    let error = Color.rgb(200, 0, 0)
    let info = Color.rgb(0, 200, 200)
    let border = Color.rgb(100, 100, 100)
}

/// The same, stating its own scheme instead of leaving it to the page.
private struct StatedSchemePalette: Palette {
    let id = "stated"
    let name = "Stated"
    let colorScheme = ColorScheme.dark
    // Deliberately the page a light reading would come from, so the two answers
    // cannot be confused.
    let background = Color.rgb(250, 250, 250)
    let foreground = Color.rgb(20, 20, 20)
    let accent = Color.rgb(0, 100, 0)
    let success = Color.rgb(0, 100, 0)
    let warning = Color.rgb(100, 100, 0)
    let error = Color.rgb(100, 0, 0)
    let info = Color.rgb(0, 100, 100)
    let border = Color.rgb(150, 150, 150)
}

@Suite("A palette's colour scheme")
struct ColorSchemeTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// A page of one grey, read through the existential the framework reads roles
    /// through.
    private func scheme(ofGrey level: UInt8) -> ColorScheme {
        let palette: any Palette = PagePalette(background: .rgb(level, level, level))
        return palette.colorScheme
    }

    // MARK: - The page, where it can be measured

    /// The crossover is where white ink starts reading better on the page than
    /// black does — WCAG's own equal point, Y ≈ 0.179 — and it falls between these
    /// two greys. Pinned as a pair, because either alone would pass under any
    /// threshold on its side of it.
    @Test("Grey 117 is a dark page and grey 118 a light one")
    func greyCrossover() {
        TerminalColors.withCurrent(.unknown) {
            #expect(scheme(ofGrey: 117) == .dark)
            #expect(scheme(ofGrey: 118) == .light)
            #expect(scheme(ofGrey: 0) == .dark)
            #expect(scheme(ofGrey: 255) == .light)
        }
    }

    /// The page wins over the hint, in both directions: a hint can be a guess from
    /// `COLORFGBG` or an appearance report, and a page the app actually paints is
    /// not a guess about anything.
    @Test("A page that can be measured outranks the terminal's hint")
    func pageOutranksTheHint() {
        let palette: any Palette = PagePalette(background: .rgb(250, 250, 250))
        TerminalColors.withCurrent(TerminalColors(prefersDark: true)) {
            #expect(palette.colorScheme == .light)
        }
        let dark: any Palette = PagePalette(background: .rgb(10, 10, 10))
        TerminalColors.withCurrent(TerminalColors(prefersDark: false)) {
            #expect(dark.colorScheme == .dark)
        }
    }

    /// The page of a palette that names none of its own is the terminal's, which is
    /// measurable exactly once the terminal has reported it. `.clear` is spent over
    /// that page rather than read as the black its components happen to hold.
    @Test("A reported black page is dark, and a reported white one light")
    func reportedPageDecides() {
        let palette: any Palette = LiveTerminalPalette()
        TerminalColors.withCurrent(TerminalColors(background: Self.rgb(0, 0, 0))) {
            #expect(palette.colorScheme == .dark)
        }
        TerminalColors.withCurrent(TerminalColors(background: Self.rgb(255, 255, 255))) {
            #expect(palette.colorScheme == .light)
        }
    }

    // MARK: - The hint, where the page cannot be measured

    @Test("A terminal that only prefers dark makes an unmeasurable page dark")
    func hintDecidesAnUnmeasurablePage() {
        let palette: any Palette = LiveTerminalPalette()
        TerminalColors.withCurrent(TerminalColors(prefersDark: true)) {
            #expect(palette.colorScheme == .dark)
        }
    }

    /// `COLORFGBG=0;15` — black on white — reaches here as `prefersDark: false` and
    /// nothing else. Which of a `?997` report and `COLORFGBG` fills that field is
    /// `TerminalColorQuery.resolve`'s question, and its own suite's.
    @Test("A terminal that only prefers light makes an unmeasurable page light")
    func lightHintDecidesAnUnmeasurablePage() {
        let palette: any Palette = LiveTerminalPalette()
        TerminalColors.withCurrent(TerminalColors(prefersDark: false)) {
            #expect(palette.colorScheme == .light)
        }
    }

    // MARK: - Silence

    /// Nothing is assumed white and nothing is assumed dark: with no page to measure
    /// and no hint, the answer is the one a terminal that says nothing has always
    /// been drawn as.
    @Test("A silent terminal under a page of its own is light")
    func silenceIsLight() {
        TerminalColors.withCurrent(.unknown) {
            let palette: any Palette = LiveTerminalPalette()
            #expect(palette.colorScheme == .light)
        }
    }

    // MARK: - A palette's own opinion

    @Test("A palette that states its own scheme keeps it, page or no page")
    func statedSchemeWins() {
        let palette: any Palette = StatedSchemePalette()
        TerminalColors.withCurrent(.unknown) {
            #expect(palette.colorScheme == .dark)
        }
    }

    // MARK: - The measurement itself

    @Test("A colour with no RGB has no scheme to read")
    func unmeasurableColourHasNoScheme() {
        TerminalColors.withCurrent(.unknown) {
            #expect(ColorScheme(background: .default) == nil)
            #expect(ColorScheme(background: .ansi(.blue)) == nil)
            #expect(ColorScheme(background: .rgb(117, 117, 117)) == .dark)
        }
    }
}
