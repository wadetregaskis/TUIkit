//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnreportedANSISlotTests.swift
//
//  A terminal slot, `Color.ansi(_:)` or `Color.palette(0...15)`, measures as the colour
//  the terminal reported for it (OSC 4), or as nothing. xterm's table was a guess at
//  what the user's profile paints, and a rule that measures a colour drew on the guess.
//  Each row here is one line of the osc11-v5 design's §2 table, asked twice: of a
//  terminal that has reported nothing, and of Apple Terminal "Basic" with its sixteen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitImage
@testable import TUIkitStyling

/// An RGB page and ink, and a terminal slot for the accent.
private struct SlotAccentPalette: Palette {
    let id = "unreported-slot-accent"
    let name = "Slot accent"
    let background = Color.rgb(20, 20, 30)
    let foreground = Color.rgb(220, 220, 220)
    let foregroundTertiary = Color.rgb(130, 130, 140)
    let accent = Color.ansi(.blue)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@MainActor
@Suite("A terminal slot the terminal has not reported has no RGB")
struct UnreportedANSISlotTests {

    private typealias Triple = (red: UInt8, green: UInt8, blue: UInt8)

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Terminal-compatibility.md, "Apple Terminal.app 455.1, Basic"), in slot
    /// order. Only slot 0 is xterm's value.
    static let appleBasic = [
        rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
        rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
        rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
        rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
    ]

    /// Apple Terminal "Basic" as it reports itself: black on white, and its sixteen.
    static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255), slots: TerminalColors.Slots(appleBasic))

    /// A terminal that reported its default pair and no slots (Warp, measured).
    private static let pairOnly = TerminalColors(foreground: rgb(17, 17, 17), background: rgb(255, 255, 255))

    private static let page = Color.rgb(20, 20, 30)

    private static func channels(_ triple: Triple?) -> [UInt8]? {
        triple.map { [$0.red, $0.green, $0.blue] }
    }

    private static func reported(_ slot: ANSIColor) -> TerminalColors.RGB {
        appleBasic[Int(slot.rawValue)]
    }

    private static func reportedColour(_ slot: ANSIColor) -> Color {
        let rgb = reported(slot)
        return .rgb(rgb.red, rgb.green, rgb.blue)
    }

    private static func isRGB(_ colour: Color) -> Bool {
        if case .rgb = colour.value { return true }
        return false
    }

    // MARK: - What a slot measures as

    @Test("A slot measures as nothing until the terminal reports its sixteen, by name and by index")
    func unreportedSlotHasNoRGB() {
        for terminal in [TerminalColors.unknown, Self.pairOnly] {
            TerminalColors.withCurrent(terminal) {
                for slot in ANSIColor.allCases {
                    #expect(Color.ansi(slot).rgbComponents == nil, "\(slot)")
                    #expect(Color.palette(slot.rawValue).rgbComponents == nil, "palette \(slot.rawValue)")
                    #expect(Color.ansi(slot).relativeLuminance == nil, "\(slot)")
                }
                // The cube and the grey ramp are not slots, and keep their table.
                #expect(Self.channels(Color.palette(16).rgbComponents) == [0, 0, 0])
                #expect(Self.channels(Color.palette(196).rgbComponents) == [255, 0, 0])
                #expect(Self.channels(Color.palette(244).rgbComponents) == [128, 128, 128])
            }
        }
    }

    @Test("A slot the terminal has reported measures as the reported colour, by name and by index")
    func reportedSlotIsTheReport() {
        TerminalColors.withCurrent(Self.appleTerminal) {
            for slot in ANSIColor.allCases {
                let reported = Self.reported(slot)
                let expected: [UInt8] = [reported.red, reported.green, reported.blue]
                #expect(Self.channels(Color.ansi(slot).rgbComponents) == expected, "\(slot)")
                #expect(Self.channels(Color.palette(slot.rawValue).rgbComponents) == expected, "palette \(slot.rawValue)")
            }
        }
    }

    // MARK: - §2, one row a line

    /// Reported, a slot that fails is swapped for another name the terminal keeps, never
    /// walked in RGB; TerminalDefinedContrastFloorTests pins the order.
    @Test("The contrast floor leaves an unreported slot as asked, and swaps a reported one for 39")
    func contrastFloor() {
        let paper = Color.rgb(250, 250, 250)
        TerminalColors.withCurrent(.unknown) {
            #expect(Color.ansi(.brightWhite).ensuringContrast(atLeast: 4.5, against: paper) == .ansi(.brightWhite))
            #expect(Color.rgb(200, 200, 200).ensuringContrast(atLeast: 4.5, against: .ansi(.white)) == .rgb(200, 200, 200))
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(
                Color.ansi(.brightWhite).relativeLuminance == Self.reportedColour(.brightWhite).relativeLuminance)
            let floored = Color.ansi(.brightWhite).ensuringContrast(atLeast: 4.5, against: paper)
            // Slot 15 has no twin above it, and 39 is black here.
            #expect(floored == .terminalForeground, "\(floored)")
            #expect(floored.contrastRatio(against: paper) >= 4.5, "\(floored)")
        }
    }

    @Test("A blend with an unreported slot snaps; with a reported one it mixes between exact ends")
    func blendSnaps() {
        let blue = Color.rgb(0, 0, 255)
        TerminalColors.withCurrent(.unknown) {
            #expect(Color.lerp(.ansi(.red), blue, phase: 0.4) == .ansi(.red))
            #expect(Color.lerp(.ansi(.red), blue, phase: 0.6) == blue)
            #expect(Color.ansi(.red).mix(with: blue, by: 0.4) == .ansi(.red))
            #expect(Color.ansi(.red).opacity(0.5, over: Self.page) == .ansi(.red))
            #expect(Color.ansi(.red).opacity(0.4, over: Self.page) == Self.page)
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(Color.lerp(.ansi(.red), blue, phase: 0) == .ansi(.red))
            #expect(Color.lerp(.ansi(.red), blue, phase: 1) == blue)
            // (153, 0, 0) halfway to (0, 0, 255), rounded to nearest.
            #expect(Color.lerp(.ansi(.red), blue, phase: 0.5) == .rgb(77, 0, 128))
            #expect(Color.ansi(.red).opacity(0.4, over: Self.page) == .rgb(73, 12, 18))
        }
    }

    /// Through a colour's own alpha, which the compositor spends with `opacity(_:over:)`.
    /// A pre-rendered SGR 31 is the next row.
    @Test("A faded slot over an RGB page is a cut at ½ until the terminal reports it")
    func fadeCutsAtHalf() {
        func line(_ alpha: Double) -> String {
            let context = makeRenderContext(width: 12, height: 1) { environment, _ in
                environment.palette = SlotAccentPalette()
            }
            let view = Text("ab").foregroundStyle(Color.ansi(.red).opacity(alpha))
            return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines[0] }
        }
        TerminalColors.withCurrent(.unknown) {
            let faint = line(0.4)
            #expect(faint.contains("38;2;20;20;30"), "below ½ the ink is the page: \(faint.debugDescription)")
            let strong = line(0.6)
            #expect(strong.contains("[31") || strong.contains(";31m") || strong.contains(";31;"),
                "at ½ and above the ink is the slot: \(strong.debugDescription)")
            #expect(!strong.contains("38;2;"), "\(strong.debugDescription)")
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            let faint = line(0.4)
            #expect(faint.contains("38;2;73;12;18"), "\(faint.debugDescription)")
        }
    }

    /// Through the rewrite `.transition(.opacity)` fades text already drawn in a slot with
    /// (`OpacityFade`): it reads SGR 31 back as `.ansi(.red)` and blends it with
    /// `opacity(_:over:)`. Over the terminal's own page, FadeOverUnreportedPageTests.
    @Test("A dissolve of text drawn in an unreported slot is a cut at ½")
    func fadeOfPreRenderedSlotCutsAtHalf() {
        let line = "\u{1B}[31mab\u{1B}[0m"
        func faded(_ factor: Double) -> String {
            OpacityFade.fading(line, by: factor, over: Self.page, defaultForeground: .rgb(220, 220, 220))
        }
        TerminalColors.withCurrent(.unknown) {
            let faint = faded(0.4)
            #expect(faint.contains("38;2;20;20;30") && !faint.contains("[31m"), "\(faint.debugDescription)")
            let strong = faded(0.6)
            #expect(strong.contains("[31m") && !strong.contains("38;2;"), "\(strong.debugDescription)")
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            let faint = faded(0.4)
            #expect(faint.contains("38;2;73;12;18"), "\(faint.debugDescription)")
        }
    }

    @Test("A colour effect leaves an unreported slot as it is, and multiplying by one changes nothing")
    func colourEffects() {
        typealias Effect = _ColorEffectView<Text>.Effect
        let orange = Color.rgb(200, 100, 50)
        TerminalColors.withCurrent(.unknown) {
            #expect(Effect.hueRotation.applied(to: .ansi(.red), amount: 90) == .ansi(.red))
            #expect(Effect.brightness.applied(to: .ansi(.red), amount: 0.2) == .ansi(.red))
            #expect(Effect.multiply(.ansi(.red)).applied(to: orange, amount: 1) == orange)
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(Self.isRGB(Effect.hueRotation.applied(to: .ansi(.red), amount: 90)))
            // (200, 100, 50) × (153, 0, 0) / 255, rounded.
            #expect(Effect.multiply(.ansi(.red)).applied(to: orange, amount: 1) == .rgb(120, 0, 0))
        }
    }

    @Test("A control face tinted with an unreported slot is the page, and hovering it adds no fill")
    func noHoverFill() {
        let palette = SlotAccentPalette()
        TerminalColors.withCurrent(.unknown) {
            #expect(palette.restingControlFace == Self.page)
            #expect(palette.hoveredControlFace == palette.restingControlFace)
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(Self.isRGB(palette.restingControlFace) && palette.restingControlFace != Self.page)
            #expect(palette.hoveredControlFace != palette.restingControlFace)
        }
    }

    /// The render-level rows are SteadyBreathOnUnmeasurableColourTests' and
    /// SteadyBreathCopiesOnUnmeasurableColourTests' `.ansiAccent` fixture.
    @Test("A breath in an unreported slot holds its bright end")
    func steadyBreath() {
        let palette = SlotAccentPalette()
        TerminalColors.withCurrent(.unknown) {
            let ends = Color.ansi(.blue).breathEnds(dimmedTo: 0.2, over: Self.page)
            #expect(ends.dim == .ansi(.blue) && ends.bright == .ansi(.blue), "\(ends)")
            let fill = palette.accentFillPulse()
            #expect(fill.dim == fill.bright, "\(fill)")
            let apart = Color.breathEnds(dim: palette.foreground, bright: .ansi(.blue))
            #expect(apart.dim == .ansi(.blue) && apart.bright == .ansi(.blue), "\(apart)")
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            let ends = Color.ansi(.blue).breathEnds(dimmedTo: 0.2, over: Self.page)
            #expect(Self.isRGB(ends.dim) && ends.bright == .ansi(.blue), "\(ends)")
            let fill = palette.accentFillPulse()
            #expect(fill.dim != fill.bright, "\(fill)")
            let apart = Color.breathEnds(dim: palette.foreground, bright: .ansi(.blue))
            #expect(apart.dim == palette.foreground && apart.bright == .ansi(.blue), "\(apart)")
        }
    }

    @Test("A gradient with an unreported slot stop is drawn as cells, not as a picture")
    func gradientStopDrawsAsCells() {
        func picture() -> GradientRaster.Picture? {
            GradientRaster.picture(
                paint: .gradient(
                    GradientPaint(Gradient(colors: [.ansi(.red), .rgb(0, 0, 255)]), .linear(from: .leading, to: .trailing))),
                frame: GradientFrame(width: 10, height: 1), columns: 10, rows: 1,
                cellPixels: TerminalCellPixels(width: 16, height: 34))
        }
        TerminalColors.withCurrent(.unknown) {
            #expect(picture() == nil)
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(picture() != nil)
        }
    }

    @Test("Lighter and darker leave an unreported slot unchanged, and step from a reported one")
    func lighterAndDarker() {
        TerminalColors.withCurrent(.unknown) {
            #expect(Color.ansi(.red).lighter() == .ansi(.red))
            #expect(Color.ansi(.red).darker() == .ansi(.red))
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            #expect(Color.ansi(.red).lighter() == Self.reportedColour(.red).lighter())
            #expect(Color.ansi(.red).darker() == Self.reportedColour(.red).darker())
        }
    }

    @Test("A 256-grid index on slots 0 to 15 is drawn in the palette's ink until the slots are reported")
    func color256GridLabels() {
        let palette = ThemeProbePalette()
        let ink = palette.foreground.resolve(with: palette)
        TerminalColors.withCurrent(.unknown) {
            for slot in ANSIColor.allCases {
                #expect(ContrastingLabel.on(.palette(slot.rawValue), palette: palette) == ink, "\(slot)")
            }
        }
        TerminalColors.withCurrent(Self.appleTerminal) {
            for slot in ANSIColor.allCases {
                #expect(
                    ContrastingLabel.on(.palette(slot.rawValue), palette: palette)
                        == ContrastingLabel.on(Self.reportedColour(slot), palette: palette), "\(slot)")
            }
        }
    }

    // MARK: - What does not change

    /// A pin: an image palette's candidates read `estimatedRGB`, which N-C0 gave the
    /// reported slot or xterm's value, so each slot's own value still maps to that slot.
    @Test("The sixteen-colour image palette still maps each slot's value to that slot")
    func ansi16MappingIsUnchanged() {
        for (terminal, value) in [
            (TerminalColors.unknown, { (slot: ANSIColor) in slot.xtermRGB }),
            (Self.appleTerminal, { (slot: ANSIColor) in
                let rgb = Self.reported(slot)
                return (red: rgb.red, green: rgb.green, blue: rgb.blue)
            }),
        ] {
            TerminalColors.withCurrent(terminal) {
                let sixteen = ASCIIPalette(ANSIColor.allCases.map(Color.ansi))
                for slot in ANSIColor.allCases {
                    let rgb = value(slot)
                    let index = sixteen.nearestIndex(to: RGBA(r: rgb.red, g: rgb.green, b: rgb.blue))
                    #expect(
                        sixteen.sgrParameters(at: index, background: false) == "\(slot.foregroundCode)",
                        "\(slot) under \(terminal)")
                }
            }
        }
    }

    /// A pin: achromatic by which slot it is, not by what it measures as.
    @Test("Black, white and their bright twins stay achromatic, reported or not")
    func achromaticBySlot() {
        for terminal in [TerminalColors.unknown, Self.appleTerminal] {
            TerminalColors.withCurrent(terminal) {
                for slot in ANSIColor.allCases {
                    let grey = [ANSIColor.black, .white, .brightBlack, .brightWhite].contains(slot)
                    #expect(Color.ansi(slot).isAchromatic == grey, "\(slot)")
                    #expect(Color.palette(slot.rawValue).isAchromatic == grey, "palette \(slot.rawValue)")
                }
            }
        }
    }

    /// A pin: quantising RGB to the sixteen still searches xterm's table (N-C5 makes it
    /// search the reported slots).
    @Test("RGB still quantises to the sixteen by xterm's table")
    func quantisingIsUnchanged() {
        for terminal in [TerminalColors.unknown, Self.appleTerminal] {
            TerminalColors.withCurrent(terminal) {
                for slot in ANSIColor.allCases {
                    let rgb = slot.xtermRGB
                    #expect(Color.rgb(rgb.red, rgb.green, rgb.blue).downsampledToANSI16() == .ansi(slot), "\(slot)")
                }
            }
        }
    }
}
