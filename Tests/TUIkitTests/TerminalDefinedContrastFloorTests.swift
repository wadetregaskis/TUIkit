//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalDefinedContrastFloorTests.swift
//
//  The contrast floor and `readableText(on:)` for an ink the terminal decides: a slot, 39,
//  or the terminal's own foreground or page. Once the terminal has reported what it paints,
//  such an ink that fails the floor is swapped for another name the terminal keeps, never
//  walked in RGB: its bright twin, 39, then slots 0, 7, 8 and 15, and where none of them
//  passes, whichever reads best, the ink itself included.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling
@testable import TUIkitView

/// Grounds and an ink the terminal decides, and slots for the rest: the shape of the
/// plan's LiveTerminalPalette, which is not built yet.
private struct TerminalGroundsPalette: Palette {
    let id = "terminal-grounds"
    let name = "Terminal grounds"
    let background = Color.clear
    let foreground = Color.default
    let accent = Color.ansi(.blue)
    let success = Color.ansi(.green)
    let warning = Color.ansi(.yellow)
    let error = Color.ansi(.red)
    let info = Color.ansi(.cyan)
    let border = Color.ansi(.brightBlack)
}

/// The terminal's page, with an RGB ink.
private struct TerminalPageRGBInkPalette: Palette {
    let id = "terminal-page-rgb-ink"
    let name = "Terminal page, RGB ink"
    let background = Color.terminalBackground
    let foreground = Color.rgb(20, 20, 20)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

/// An RGB page, with 39 as the ink.
private struct DefaultInkRGBPagePalette: Palette {
    let id = "default-ink-rgb-page"
    let name = "39 ink, RGB page"
    let background = Color.rgb(40, 44, 52)
    let foreground = Color.default
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@MainActor
@Suite("The contrast floor swaps an ink the terminal decides for another of its names")
struct TerminalDefinedContrastFloorTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal "Basic": black on white, and its sixteen.
    private static let apple = UnreportedANSISlotTests.appleTerminal

    /// The same sixteen under a white-on-black pair.
    private static let appleDark = TerminalColors(
        foreground: rgb(255, 255, 255), background: rgb(0, 0, 0),
        slots: TerminalColors.Slots(UnreportedANSISlotTests.appleBasic))

    /// A terminal that reported its pair and no slots, as Warp does.
    private static let pairOnly = TerminalColors(foreground: rgb(17, 17, 17), background: rgb(255, 255, 255))

    /// Every ink the terminal decides: the sixteen by name and by index, 39, and the
    /// terminal's foreground and page.
    private static let terminalInks: [Color] =
        ANSIColor.allCases.map(Color.ansi) + (0..<16).map { Color.palette256(UInt8($0)) }
        + [.default, .terminalForeground, .terminalBackground]

    /// The ratio `ink` reads at on `page`, as the terminal paints it: 39 as the foreground
    /// it reported. 0 where either cannot be measured.
    private static func ratio(_ ink: Color, on page: Color) -> Double {
        guard let rgb = ink.inkRGB else { return 0 }
        return Color.rgb(rgb.red, rgb.green, rgb.blue).contrastRatio(against: page)
    }

    private static func isRGB(_ colour: Color) -> Bool {
        if case .rgb = colour.value { return true }
        return false
    }

    // MARK: - The plan's two examples

    @Test("A text field's selection on the terminal's own grounds is 39 at 4.39, not the page's RGB at 4.79")
    func textFieldSelectionIs39() {
        TerminalColors.withCurrent(Self.apple) {
            let palette = GroundedPalette.grounding(TerminalGroundsPalette())
            #expect(palette.background == .terminalBackground, "the fixture: grounded to the terminal's page")
            #expect(palette.foreground == .terminalForeground, "the fixture: 39 as the ink")
            let colours = TextFieldContentRenderer.selectionColors(palette: palette, background: nil)
            // Slot 4, (0, 0, 179), at 0.6 over the white page.
            #expect(colours.background == .rgb(102, 102, 209))
            #expect(colours.foreground == .terminalForeground, "\(colours.foreground)")
            #expect(abs(Self.ratio(colours.foreground, on: colours.background) - 4.3862) < 0.0001)
            // What it was: the page reads better as ink, but the foreground slot spells it
            // as the page's RGB.
            #expect(abs(Self.ratio(.terminalBackground, on: colours.background) - 4.7877) < 0.0001)
        }
        TerminalColors.withCurrent(.unknown) {
            let palette = GroundedPalette.grounding(TerminalGroundsPalette())
            let colours = TextFieldContentRenderer.selectionColors(palette: palette, background: nil)
            // Unreported there is no highlight to floor against at all, so the cell
            // reverses its own pair instead (§87) — whose ink is still plain 39.
            #expect(colours.isReversed, "unreported: stated beside the 7")
            #expect(colours.foreground == .terminalForeground, "unreported: plain 39, as asked")
        }
    }

    @Test("A bright white on slot 9 that no name lifts to 4.5 becomes the best of them, 39, at 4.36")
    func bestRatioWhenNoNamePasses() {
        TerminalColors.withCurrent(Self.apple) {
            let page = Color.palette256(9)
            #expect(abs(Self.ratio(.ansi(.brightWhite), on: page) - 3.8551) < 0.0001, "the fixture")
            for floored in [
                Color.ansi(.brightWhite).ensuringContrast(atLeast: 4.5, against: page),
                Color.ansi(.brightWhite).ensuringRenderedContrast(atLeast: 4.5, against: page),
            ] {
                // Slot 0 is the same black, and 39 comes first.
                #expect(floored == .terminalForeground, "\(floored)")
                #expect(abs(Self.ratio(floored, on: page) - 4.3646) < 0.0001)
            }
            let faded = Color.ansi(.brightWhite).opacity(0.5)
            #expect(faded.ensuringContrast(atLeast: 4.5, against: page) == Color.terminalForeground.opacity(0.5))
        }
    }

    // MARK: - The order

    @Test("The first name that passes, in order: itself, its bright twin, 39, then slots 0, 7, 8 and 15")
    func firstPassingName() {
        TerminalColors.withCurrent(Self.apple) {
            let white = Color.terminalBackground
            // Itself: slot 3 reads at 3.04 on the white page.
            #expect(Color.ansi(.yellow).ensuringContrast(atLeast: 3, against: white) == .ansi(.yellow))
            // Slot 7 at 1.84 and slot 6 at 2.96; their twins read worse, so 39, black here.
            #expect(Color.ansi(.white).ensuringContrast(atLeast: 3, against: white) == .terminalForeground)
            #expect(Color.ansi(.cyan).ensuringContrast(atLeast: 3, against: white) == .terminalForeground)
            // Its twin: on slot 0, slot 1 reads at 2.35 and slot 9 at 4.37.
            #expect(Color.ansi(.red).ensuringContrast(atLeast: 3, against: .ansi(.black)) == .ansi(.brightRed))
            // Slot 7: on slot 0, slot 4 reads at 1.65 and its twin at 2.44, and 39 and
            // slot 0 are the page's black.
            #expect(Color.ansi(.blue).ensuringContrast(atLeast: 3, against: .ansi(.black)) == .ansi(.white))
            // Slot 15: on a mid grey, 39, slot 0 and slot 7 read at 3.55, 3.55 and 3.22.
            #expect(
                Color.ansi(.brightBlack).ensuringContrast(atLeast: 4.5, against: .rgb(100, 100, 100))
                    == .ansi(.brightWhite))
            // Spelled by index, the names stay spelled by index.
            #expect(Color.palette256(1).ensuringContrast(atLeast: 3, against: .palette256(0)) == .palette256(9))
            #expect(Color.palette256(4).ensuringContrast(atLeast: 3, against: .palette256(0)) == .palette256(7))
        }
    }

    // MARK: - The property

    @Test("Floored, an ink the terminal decides never reads worse than it did, and is never RGB or the page")
    func neverWorseNeverRGB() {
        let levels: [UInt8] = [0, 85, 170, 255]
        let rgbPages = levels.flatMap { red in
            levels.flatMap { green in levels.map { blue in Color.rgb(red, green, blue) } }
        }
        let pages = ANSIColor.allCases.map(Color.ansi) + [.terminalForeground, .terminalBackground] + rgbPages
        for terminal in [Self.apple, Self.appleDark, Self.pairOnly] {
            TerminalColors.withCurrent(terminal) {
                for ink in Self.terminalInks {
                    for page in pages {
                        for minimum in [2.4, 3, 4.5, 7] {
                            for rendered in [false, true] {
                                let floored =
                                    rendered
                                    ? ink.ensuringRenderedContrast(atLeast: minimum, against: page)
                                    : ink.ensuringContrast(atLeast: minimum, against: page)
                                let target = rendered ? page.downsampledToPalette256() : page
                                let before = Self.ratio(ink, on: target)
                                let after = Self.ratio(floored, on: target)
                                let label = "\(ink) on \(page) at \(minimum), rendered \(rendered)"
                                #expect(!Self.isRGB(floored), "\(label) -> \(floored)")
                                #expect(floored != .terminalBackground || ink == .terminalBackground, "\(label)")
                                #expect(after >= before, "\(label) -> \(floored): \(after) < \(before)")
                                if before >= minimum { #expect(floored == ink, "\(label) passed already") }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Where the terminal has reported nothing, every ink it decides is left as asked")
    func unreportedLeavesTheInk() {
        TerminalColors.withCurrent(.unknown) {
            for ink in Self.terminalInks {
                for page in [Color.rgb(250, 250, 250), .rgb(20, 20, 30), .ansi(.red), .terminalBackground] {
                    #expect(ink.ensuringContrast(atLeast: 4.5, against: page) == ink, "\(ink) on \(page)")
                    #expect(ink.ensuringRenderedContrast(atLeast: 4.5, against: page) == ink, "\(ink) on \(page)")
                }
            }
        }
        // The pair and no slots: a slot is still unmeasured, and 39 has no other name to
        // measure against, so both stay.
        TerminalColors.withCurrent(Self.pairOnly) {
            #expect(Color.ansi(.yellow).ensuringContrast(atLeast: 4.5, against: .rgb(250, 250, 250)) == .ansi(.yellow))
            #expect(Color.terminalForeground.ensuringContrast(atLeast: 4.5, against: .rgb(20, 20, 30)) == .terminalForeground)
        }
    }

    // MARK: - readableText(on:)

    @Test("readableText(on:) never picks the terminal's page as ink, and measures 39 as the reported foreground")
    func readableTextOnTerminalColours() {
        TerminalColors.withCurrent(Self.apple) {
            // The page, white, reads at 12.72 on slot 4, and the ink at 1.45; the ink is
            // floored in RGB instead, as an RGB ink is.
            let pagePalette = TerminalPageRGBInkPalette()
            let blue = Color.ansi(.blue)
            let onBlue = pagePalette.readableText(on: blue)
            #expect(onBlue != .terminalBackground)
            #expect(Self.isRGB(onBlue), "\(onBlue)")
            #expect(onBlue.contrastRatio(against: blue) >= 4.5, "\(onBlue)")
            // 39, black here, reads at 16.9 on a pale grey, and the RGB page at 11.2.
            let inkPalette = DefaultInkRGBPagePalette()
            #expect(inkPalette.readableText(on: .rgb(230, 230, 230)) == .default)
        }
    }
}
