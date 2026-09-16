//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HoverLadderTests.swift
//
//  `Palette.hoveredForeground(_:)` for a colour the terminal decides: a slot, a
//  256-colour index below 16, or the default foreground. It is not stepped in RGB,
//  which would re-spell a name the user's profile keeps as a triple. It climbs a
//  ladder instead: a standard slot, its bright twin, then 39. Unreported, the first
//  rung spelled differently; reported, the first that is visibly different and no
//  harder to read against the page.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// An RGB ink and accent over `background`.
private struct LadderPalette: Palette {
    let id = "hover-ladder"
    let name = "Hover ladder"
    let background: Color
    let foreground = Color.rgb(220, 220, 220)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@Suite("A colour the terminal decides lifts up a ladder of names under the pointer")
struct HoverLadderTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Terminal-compatibility.md, "Apple Terminal.app 455.1, Basic").
    private static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    /// Apple Terminal "Basic" as it reports itself: black on white, and its sixteen.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255), slots: TerminalColors.Slots(appleBasic))

    /// The same sixteen under a white foreground on a dark page.
    private static let appleSlotsWhiteInk = TerminalColors(
        foreground: rgb(255, 255, 255), background: rgb(40, 44, 52), slots: TerminalColors.Slots(appleBasic))

    /// Ghostty 1.3.1's default, as measured on 2026-09-14 (Terminal-compatibility.md).
    private static let ghostty = TerminalColors(
        foreground: rgb(255, 255, 255), background: rgb(40, 44, 52),
        slots: TerminalColors.Slots([
            rgb(0x1D, 0x1F, 0x21), rgb(0xCC, 0x66, 0x66), rgb(0xB5, 0xBD, 0x68), rgb(0xF0, 0xC6, 0x74),
            rgb(0x81, 0xA2, 0xBE), rgb(0xB2, 0x94, 0xBB), rgb(0x8A, 0xBE, 0xB7), rgb(0xC5, 0xC8, 0xC6),
            rgb(0x66, 0x66, 0x66), rgb(0xD5, 0x4E, 0x53), rgb(0xB9, 0xCA, 0x4A), rgb(0xE7, 0xC5, 0x47),
            rgb(0x7A, 0xA6, 0xDA), rgb(0xC3, 0x97, 0xD8), rgb(0x70, 0xC0, 0xB1), rgb(0xEA, 0xEA, 0xEA),
        ]))

    private static let paper = Color(value: .terminalBackground)
    private static let dark = Color.rgb(20, 20, 30)
    private static let light = Color.rgb(250, 250, 250)

    // MARK: - Unreported

    @Test("Unreported, a standard slot lifts to its bright twin, a bright slot to 39, and 39 stays")
    func unreportedLadder() {
        TerminalColors.withCurrent(.unknown) {
            for page in [Self.paper, Self.dark, Color.default] {
                let palette = LadderPalette(background: page)
                for slot in ANSIColor.allCases {
                    let byName = palette.hoveredForeground(.ansi(slot))
                    let byIndex = palette.hoveredForeground(.palette(slot.rawValue))
                    if slot.isBright {
                        #expect(byName == .default, "\(slot) on \(page)")
                        #expect(byIndex == .default, "palette \(slot.rawValue) on \(page)")
                    } else {
                        #expect(byName == .ansi(slot.brightTwin), "\(slot) on \(page)")
                        #expect(byIndex == .palette(slot.rawValue | 8), "palette \(slot.rawValue) on \(page)")
                    }
                }
                // 39 as ink, spelled either way: no rung above it.
                #expect(palette.hoveredForeground(.default) == .default, "on \(page)")
                let ink = Color(value: .terminalForeground)
                #expect(palette.hoveredForeground(ink) == ink, "on \(page)")
                // The page as ink is also 39 until the terminal reports it, so 39 is
                // not spelled differently either.
                #expect(palette.hoveredForeground(Self.paper) == Self.paper, "on \(page)")
            }
        }
    }

    @Test("A lifted slot keeps its alpha")
    func ladderCarriesAlpha() {
        TerminalColors.withCurrent(.unknown) {
            let palette = LadderPalette(background: Self.paper)
            #expect(palette.hoveredForeground(.ansi(.red).opacity(0.5)) == .ansi(.brightRed).opacity(0.5))
            #expect(palette.hoveredForeground(.ansi(.brightRed).opacity(0.5)) == Color.default.opacity(0.5))
        }
    }

    // MARK: - Reported

    /// On Apple's white page slot 1 (153, 0, 0) reads at 8.92:1 and its twin
    /// (230, 0, 0) at 4.81:1, so the twin is refused and 39, black, is taken.
    /// Slot 0 is black, and so is 39: the same entry, not a visible step.
    @Test("Reported, a rung must be visibly different and no harder to read")
    func reportedLadderOnALightPage() {
        TerminalColors.withCurrent(Self.appleTerminal) {
            let palette = LadderPalette(background: Self.paper)
            #expect(palette.hoveredForeground(.ansi(.red)) == .default)
            #expect(palette.hoveredForeground(.ansi(.white)) == .default)
            #expect(palette.hoveredForeground(.ansi(.brightBlack)) == .default)
            #expect(palette.hoveredForeground(.ansi(.black)) == .ansi(.black))
            #expect(palette.hoveredForeground(.default) == .default)
            // 39 measured is still no rung above itself.
            let ink = Color(value: .terminalForeground)
            #expect(palette.hoveredForeground(ink) == ink)
        }
    }

    @Test("Reported on a dark page, the twin is the lift, and 39 only where it reads better")
    func reportedLadderOnADarkPage() {
        TerminalColors.withCurrent(Self.appleSlotsWhiteInk) {
            let palette = LadderPalette(background: Self.dark)
            #expect(palette.hoveredForeground(.ansi(.red)) == .ansi(.brightRed))
            #expect(palette.hoveredForeground(.palette(1)) == .palette(9))
            #expect(palette.hoveredForeground(.ansi(.brightRed)) == .default)
        }
        // Black 39 on a dark page is harder to read than slot 9, so nothing is taken.
        TerminalColors.withCurrent(Self.appleTerminal) {
            let palette = LadderPalette(background: Self.dark)
            #expect(palette.hoveredForeground(.ansi(.brightRed)) == .ansi(.brightRed))
        }
    }

    @Test("A twin the terminal paints as its standard slot is no step, so 39 is tried")
    func identicalTwinIsSkipped() {
        var slots = Self.appleBasic
        slots[9] = slots[1]
        let terminal = TerminalColors(
            foreground: Self.rgb(255, 255, 255), background: Self.rgb(40, 44, 52),
            slots: TerminalColors.Slots(slots))
        TerminalColors.withCurrent(terminal) {
            #expect(LadderPalette(background: Self.dark).hoveredForeground(.ansi(.red)) == .default)
        }
    }

    // MARK: - Properties

    /// What a colour measures as drawn as ink: 39 is the reported foreground.
    private static func inkLuminance(_ colour: Color) -> Color? {
        guard case .terminalDefault = colour.value else {
            return colour.rgbComponents.map { .rgb($0.red, $0.green, $0.blue) }
        }
        return TerminalColors.current.foreground.map { .rgb($0.red, $0.green, $0.blue) }
    }

    @Test("A colour the terminal decides never lifts to RGB, nor to a harder read where both measure")
    func neverRGBNeverHarder() {
        let inks: [Color] =
            ANSIColor.allCases.map { Color.ansi($0) } + (0..<16).map { Color.palette(UInt8($0)) }
            + [.default, Color(value: .terminalForeground), Self.paper]
        for terminal in [TerminalColors.unknown, Self.appleTerminal, Self.appleSlotsWhiteInk, Self.ghostty] {
            TerminalColors.withCurrent(terminal) {
                for page in [Self.paper, Self.dark, Self.light] {
                    let palette = LadderPalette(background: page)
                    for ink in inks {
                        let lifted = palette.hoveredForeground(ink)
                        #expect(lifted.isTerminalDefined, "\(ink) on \(page) → \(lifted)")
                        if let before = Self.inkLuminance(ink), let after = Self.inkLuminance(lifted),
                            let ground = page.rgbComponents.map({ Color.rgb($0.red, $0.green, $0.blue) })
                        {
                            #expect(
                                after.contrastRatio(against: ground) >= before.contrastRatio(against: ground),
                                "\(ink) on \(page) → \(lifted)")
                        }
                    }
                }
            }
        }
    }

    /// The ladder is for what the terminal decides. An RGB ink keeps the RGB lift, and
    /// every palette that STATES its own colours states RGB roles, so none of their
    /// hovers climbs it. A palette that states none of its own is the other case, and
    /// is pinned with the palette rather than here.
    @Test("An RGB ink still lifts in RGB, and every stated palette's accent tint measures")
    func rgbInksKeepTheirLift() {
        TerminalColors.withCurrent(.unknown) {
            for palette in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
                #expect(palette.accentTintIsMeasurable, "\(palette.id)")
                for role in [palette.foreground, palette.foregroundSecondary, palette.accent, palette.border] {
                    #expect(!palette.hoveredForeground(role).isTerminalDefined, "\(palette.id): \(role)")
                }
            }
        }
    }
}
