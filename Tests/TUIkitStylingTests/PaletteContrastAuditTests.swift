//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteContrastAuditTests.swift
//
//  Readability floor for every shipped palette: the semantic colour pairs a
//  running app actually draws (text on background, accent on background,
//  focused-row text on the focus highlight, status colours, …) must meet
//  WCAG-style contrast minimums. Mid-tone Terminal.app profiles (Silver
//  Aerogel's grey, Novel's parchment) are the hard cases this pins.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

@MainActor
@Suite("Palette contrast audit")
struct PaletteContrastAuditTests {

    // MARK: - WCAG contrast

    /// WCAG 2.x relative luminance of an sRGB colour (0...1).
    private static func relativeLuminance(_ color: Color) -> Double? {
        guard let (red, green, blue) = color.rgbComponents else { return nil }
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colours (1...21).
    static func contrast(_ a: Color, _ b: Color) -> Double {
        guard
            let la = relativeLuminance(a),
            let lb = relativeLuminance(b)
        else { return 0 }
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - The audited pairs

    /// A colour pair a running app draws, with the minimum contrast it needs
    /// to stay readable. Thresholds are deliberately below the strict WCAG AA
    /// 4.5 for the dimmer roles — tertiary/quaternary text is *meant* to
    /// recede — but nothing that renders as text may fall below 2.4, and the
    /// primary roles hold to body-text standards.
    private struct AuditedPair {
        let name: String
        let foreground: Color
        let background: Color
        let minimum: Double
    }

    private static func pairs(for palette: some Palette) -> [AuditedPair] {
        [
            AuditedPair(
                name: "foreground/background",
                foreground: palette.foreground, background: palette.background, minimum: 4.5),
            AuditedPair(
                name: "secondary/background",
                foreground: palette.foregroundSecondary, background: palette.background,
                minimum: 3.0),
            AuditedPair(
                name: "tertiary/background",
                foreground: palette.foregroundTertiary, background: palette.background,
                minimum: 2.4),
            AuditedPair(
                name: "accent/background",
                foreground: palette.accent, background: palette.background, minimum: 3.0),
            AuditedPair(
                name: "foreground/focusBackground",
                foreground: palette.foreground, background: palette.focusBackground,
                minimum: 3.0),
            AuditedPair(
                name: "foreground/statusBar",
                foreground: palette.foreground, background: palette.statusBarBackground,
                minimum: 4.5),
            AuditedPair(
                name: "foreground/appHeader",
                foreground: palette.foreground, background: palette.appHeaderBackground,
                minimum: 4.5),
            AuditedPair(
                name: "success/background",
                foreground: palette.success, background: palette.background, minimum: 2.7),
            AuditedPair(
                name: "warning/background",
                foreground: palette.warning, background: palette.background, minimum: 2.7),
            AuditedPair(
                name: "error/background",
                foreground: palette.error, background: palette.background, minimum: 2.7),
            AuditedPair(
                name: "info/background",
                foreground: palette.info, background: palette.background, minimum: 2.7),
            AuditedPair(
                name: "foreground/fieldBackground",
                foreground: palette.foreground, background: palette.fieldBackground,
                minimum: 4.5),
            AuditedPair(
                // The prompt text, built the way `TextFieldContentRenderer`
                // builds it: `foregroundTertiary` is derived against the PAGE,
                // and the field is a step off the page, so what is drawn is the
                // tertiary floored against the field it lands on.
                //
                // Measured through the cube, on BOTH sides, because that is the
                // space the renderer's floor is applied in
                // (`ensuringRenderedContrast`) and therefore the only space it
                // promises anything about. Measured raw instead, the pair reads
                // a little under the floor wherever quantisation moved the
                // field toward the text it was floored against — Novel 2.14,
                // Silver Aerogel 2.32 — which is a fact about the recipe, not a
                // palette that needs fixing.
                name: "prompt/fieldBackground",
                foreground: palette.foregroundTertiary.ensuringRenderedContrast(
                    atLeast: ViewConstants.disabledLabelContrastFloor,
                    against: palette.fieldBackground.resolve(with: palette)
                ).downsampledToPalette256(),
                background: palette.fieldBackground.resolve(with: palette)
                    .downsampledToPalette256(),
                minimum: 2.4),
        ] + controlSurfacePairs(for: palette)
    }

    /// The accent-tinted control surfaces, built with the SAME recipes the
    /// views use (`Color.opacity(_:over:)` on the palette background). These
    /// pin the class of bug where a "dim accent" fill was mixed toward black
    /// instead of toward the page — invisible on dark palettes (black page ==
    /// mixing toward black) but dark-on-dark buttons and selections under
    /// light ones (Basic, Silver Aerogel, Solid Colors).
    private static func controlSurfacePairs(for palette: some Palette) -> [AuditedPair] {
        let background = palette.background
        // ButtonStyle / _PickerMenuCore: the ▐…▌ face and its label — the
        // label recipe mirrors the styles' (default colour floored against
        // the face it sits on).
        let buttonFace = palette.accent.opacity(ViewConstants.focusBorderDim, over: background)
        let hoverFace = palette.accent.opacity(ViewConstants.hoverBackground, over: background)
        let buttonLabel = palette.foregroundSecondary.ensuringContrast(atLeast: 3.0, against: buttonFace)
        let hoverLabel = palette.foregroundSecondary.ensuringContrast(atLeast: 3.0, against: hoverFace)
        let pickerFocusedLabel = palette.accent.ensuringContrast(atLeast: 3.0, against: buttonFace)
        // TextField / TextEditor selections: fill + auto-picked text side.
        let selectionFill = palette.accent.opacity(ViewConstants.selectionIndicator, over: background)
        // List / Table rows: unfocused-selected fill, alternating stripe, and
        // the focused-row pulse's two endpoints (content keeps its normal
        // foreground over all of them).
        let selectedRowFill = palette.accent.opacity(ViewConstants.selectedBackground, over: background)
        let alternatingFill = palette.accent.opacity(
            ViewConstants.alternatingRowBackground, over: background)
        // The breath's ends as `Palette.accentFillPulse(over:)` chooses them: the plain
        // shares, or where those fail on 256 colours, the ones it walked to.
        let (pulseDim, pulseBright) = palette.accentFillPulse()
        // The cursor row on a row the selection does not include breathes the focus
        // wash; its dim end is `focusBackground`, audited above, and its bright end is
        // floored for exactly this pair.
        let washPulseBright = palette.focusWashPulse().bright
        return [
            AuditedPair(
                name: "buttonLabel/buttonFace",
                foreground: buttonLabel, background: buttonFace, minimum: 2.7),
            AuditedPair(
                name: "buttonLabel/hoverFace",
                foreground: hoverLabel, background: hoverFace, minimum: 2.7),
            AuditedPair(
                name: "focusedPickerLabel/face",  // focused picker labels use the accent
                foreground: pickerFocusedLabel, background: buttonFace, minimum: 2.7),
            AuditedPair(
                name: "selectionText/selectionFill",
                foreground: palette.readableText(on: selectionFill), background: selectionFill,
                minimum: 3.5),
            AuditedPair(
                name: "foreground/selectedRowFill",
                foreground: palette.foreground, background: selectedRowFill, minimum: 3.0),
            AuditedPair(
                name: "foreground/alternatingRow",
                foreground: palette.foreground, background: alternatingFill, minimum: 3.5),
            AuditedPair(
                name: "foreground/focusPulseDim",
                foreground: palette.foreground, background: pulseDim, minimum: 2.4),
            AuditedPair(
                name: "foreground/focusPulseBright",
                foreground: palette.foreground, background: pulseBright,
                minimum: ViewConstants.rowBreathPeakContrastFloor),
            AuditedPair(
                name: "foreground/focusWashPulseBright",
                foreground: palette.foreground, background: washPulseBright,
                minimum: ViewConstants.rowBreathPeakContrastFloor),
        ]
    }

    /// Every palette that states its own colours: the phosphor presets and the Terminal
    /// profiles. A palette that leaves a role to the terminal has no ratio to measure
    /// until the terminal reports one.
    private static var statedPalettes: [any Palette] {
        PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
    }

    // MARK: - Report (not an assertion; run with --filter to see the table)

    @Test("Report: contrast table for every shipped palette")
    func report() {
        for palette in Self.statedPalettes {
            print("== \(palette.name) ==")
            for pair in Self.pairs(for: palette) {
                let ratio = Self.contrast(pair.foreground, pair.background)
                let flag = ratio < pair.minimum ? "  ← FAIL (min \(pair.minimum))" : ""
                let paddedName = pair.name.padding(toLength: 28, withPad: " ", startingAt: 0)
                print("  \(paddedName) \(String(format: "%5.2f", ratio))\(flag)")
            }
        }
    }

    // MARK: - The floor

    @Test("Every shipped palette meets the readability floor")
    func readabilityFloor() {
        for palette in Self.statedPalettes {
            for pair in Self.pairs(for: palette) {
                let ratio = Self.contrast(pair.foreground, pair.background)
                #expect(
                    ratio >= pair.minimum,
                    "\(palette.name): \(pair.name) contrast \(String(format: "%.2f", ratio)) < \(pair.minimum)")
            }
        }
    }

    // MARK: - The focus wash has to breathe

    /// The cursor row on a row the selection does not include breathes UP from the
    /// wash: its dim end is the wash itself — never fainter than the row has always
    /// been — and its bright end sits further from the page, so on every shipped
    /// palette the breath moves rather than holding one colour, and never toward the
    /// page, where the cursor would all but go out once a cycle. Every shipped palette
    /// states its own wash, so this is the rule's reach beyond the default derivation.
    @Test("The focus wash breathes away from the page on every shipped palette")
    func focusWashBreathesAwayFromThePage() {
        for palette in Self.statedPalettes {
            let ends = palette.focusWashPulse()
            #expect(
                ends.dim == palette.focusBackground.spendingAlpha(over: palette.background),
                "\(palette.name): the breath does not start from the wash")
            #expect(ends.bright != ends.dim, "\(palette.name): the wash does not breathe")
            let dimFromPage = Self.contrast(ends.dim, palette.background)
            let brightFromPage = Self.contrast(ends.bright, palette.background)
            #expect(
                brightFromPage > dimFromPage,
                "\(palette.name): the bright end \(Self.hex(ends.bright)) is no further from the page than the wash")

            // …and on a 256-colour terminal, where the floor bites (as the hover tests
            // below ask it). The breath the terminal draws is the ramp the accent's own
            // breath walks, `Color.pulseRamp`, which keeps only the shades the cube can
            // show and drops the ones that lost their hue: it must hold two, and none
            // of them may be the page's own entry, where the cursor would go out once
            // a cycle. Ocean's held one colour (#0087FF), and Red Sands' dropped its
            // black and held #5F0000. Not "no nearer the page" by contrast, as above:
            // the cube moves hue as well as lightness, and Grass's red wash breathes
            // #D70000 to #FF0000 on its green page, 1.19:1 and 1.13:1 off it by
            // luminance while plainly further from it.
            let page = palette.background.downsampledToPalette256()
            let shades = Color.pulseRamp(from: ends.dim, to: ends.bright, depth: .palette256)
                .map { $0.downsampledToPalette256() }
            #expect(
                shades.count >= 2,
                "\(palette.name): on 256 colours the wash breath holds one colour, \(shades.map(Self.hex))")
            #expect(
                !shades.contains(page),
                "\(palette.name): on 256 colours the wash breath passes through the page's \(Self.hex(page)): \(shades.map(Self.hex))")
        }
    }

    /// The top of the wash's breath is floored where the row's text would be hard to
    /// read on it, and no harder than the top of the accent's breath, which is the
    /// same moment of the same cycle. Floored at a label's 3:1 instead, the breath was
    /// squeezed wherever the wash sits near the text: Novel's moved 1.04:1 (its top
    /// #858509 where the accent's floor gives #696907), Ocean's held one colour on 256
    /// colours (#0397FF for #27A6FF), and Pro's top came in from #A4A4A4 to #8D8D8D.
    @Test("The wash's breath is floored no harder than the accent's")
    func focusWashFlooredLikeTheAccent() {
        for palette in Self.statedPalettes {
            let ends = palette.focusWashPulse()
            guard let wash = ends.dim.rgbComponents,
                let page = palette.background.rgbComponents
            else { continue }
            // Twice the wash's distance from the page, per channel and clamped: the
            // top before any floor (`Palette.focusWashPulse()`).
            func twiceAsFar(_ wash: UInt8, _ page: UInt8) -> UInt8 {
                UInt8(clamping: 2 * Int(wash) - Int(page))
            }
            let unfloored = Color.rgb(
                twiceAsFar(wash.red, page.red), twiceAsFar(wash.green, page.green),
                twiceAsFar(wash.blue, page.blue))
            let floored = unfloored.ensuringContrast(
                atLeast: ViewConstants.rowBreathPeakContrastFloor, against: palette.foreground)
            #expect(
                ends.bright == floored,
                "\(palette.name): the top is \(Self.hex(ends.bright)); at the accent's floor it is \(Self.hex(floored))")
        }
    }

    // MARK: - The accent's breath has to hold on 256 colours

    /// What a breath can get wrong as a 256-colour terminal draws it.
    private enum BreathCriterion: String, CaseIterable {
        /// The row's text falls under ``ViewConstants/rowBreathPeakContrastFloor`` on
        /// some shade.
        case text
        /// The breath holds one shade, so the row does not breathe.
        case shades
        /// A shade is the cube entry the cursor row's ● is drawn in, so the mark goes
        /// out for part of every cycle.
        case mark
        /// A shade is the page's own entry, so the cursor goes out once a cycle.
        case page
    }

    /// The shipped palettes whose accent breath fails a criterion, each as
    /// "<palette>: <criterion>", taken out by the change that fixes it.
    ///
    /// A ledger rather than a failing test, so every commit on the way passes, and a
    /// strict one: a listed failure that no longer happens is an issue of its own
    /// (`withKnownIssue` with no issue recorded), so a fix that forgets to take its
    /// entry out fails here.
    private static let knownAccentBreathFailures: Set<String> = [
        "Red Sands: shades", "Ocean: shades", "Silver Aerogel: mark",
    ]

    /// `body`, whose failure is known where the ledger lists `criterion` for `palette`.
    private static func expecting(
        _ criterion: BreathCriterion, of palette: any Palette, _ body: () -> Void
    ) {
        let entry = "\(palette.name): \(criterion.rawValue)"
        withKnownIssue("\(entry) is a known failure") {
            body()
        } when: {
            knownAccentBreathFailures.contains(entry)
        }
    }

    /// A breath as a 256-colour terminal draws it: the shades `Color.pulseRamp` walks
    /// between its ends, each moved onto the cube, beside the row's text, its ● and the
    /// page, all moved onto the cube too.
    @MainActor
    private struct DrawnBreath {
        let name: String
        let shades: [Color]
        let text: Color
        let mark: Color
        let page: Color

        init(dim: Color, bright: Color, in palette: some Palette) {
            name = palette.name
            shades = Color.pulseRamp(from: dim, to: bright, depth: .palette256)
                .map { $0.downsampledToPalette256() }
            text = palette.foreground.downsampledToPalette256()
            mark = palette.accent.downsampledToPalette256()
            page = palette.background.downsampledToPalette256()
        }

        /// What the breath gets wrong under `criterion`, or `nil` where it holds.
        func failure(_ criterion: BreathCriterion) -> String? {
            let names = shades.map(PaletteContrastAuditTests.hex)
            switch criterion {
            case .text:
                let ratios = shades.map { PaletteContrastAuditTests.contrast(text, $0) }
                guard let worst = ratios.min(), let at = ratios.firstIndex(of: worst),
                    worst < ViewConstants.rowBreathPeakContrastFloor
                else { return nil }
                let ratio = String(format: "%.2f", worst)
                return "\(name): the text \(PaletteContrastAuditTests.hex(text)) is \(ratio):1 on \(names[at]), of \(names)"
            case .shades:
                return shades.count >= 2 ? nil : "\(name): the breath holds one colour, \(names)"
            case .mark:
                return !shades.contains(mark)
                    ? nil
                    : "\(name): the ● \(PaletteContrastAuditTests.hex(mark)) is a shade of the breath, \(names)"
            case .page:
                return !shades.contains(page)
                    ? nil
                    : "\(name): the breath passes through the page's \(PaletteContrastAuditTests.hex(page)): \(names)"
            }
        }
    }

    /// The cursor row on a selected row breathes the accent
    /// (`Palette.accentFillPulse(over:)`), and the pairs above measure that breath's
    /// two ends in truecolour only. A 256-colour terminal — Apple Terminal has nothing
    /// else — draws the shades `Color.pulseRamp` walks between them instead, each
    /// moved onto the cube, and the cube moves the text too. The wash's breath has
    /// been measured that way since it learned to breathe
    /// (``focusWashBreathesAwayFromThePage()``); the accent's never was.
    ///
    /// So, on every shade the terminal can draw — every entry of the ramp, a superset
    /// of the frames the cycle shows — the row's text keeps
    /// ``ViewConstants/rowBreathPeakContrastFloor``; the breath holds two shades or
    /// more; none of them is the entry the ● on that row is drawn in, the accent; and
    /// none is the page's, as for the wash.
    @Test("The accent's breath holds on 256 colours: readable, moving, off its mark and the page")
    func accentBreathHoldsOn256Colours() {
        for palette in Self.statedPalettes {
            let ends = palette.accentFillPulse()
            let drawn = DrawnBreath(dim: ends.dim, bright: ends.bright, in: palette)
            for criterion in BreathCriterion.allCases {
                let failure = drawn.failure(criterion)
                Self.expecting(criterion, of: palette) {
                    #expect(failure == nil, "\(failure ?? "")")
                }
            }
        }
    }

    /// The breath's ends move only where the plain one — ``ViewConstants/focusPulseMin``
    /// to ``ViewConstants/focusPulseMax`` of the accent over the page — fails as a
    /// 256-colour terminal draws it. A palette whose plain breath holds keeps it exactly,
    /// at every depth: twelve of the sixteen shipped palettes.
    @Test("A breath that holds on 256 colours is left at the plain shares")
    func holdingBreathIsNotMoved() {
        for palette in Self.statedPalettes {
            let dim = palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background)
            let bright = palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background)
            let drawn = DrawnBreath(dim: dim, bright: bright, in: palette)
            let holds = BreathCriterion.allCases.allSatisfy { drawn.failure($0) == nil }
            guard holds else { continue }
            let ends = palette.accentFillPulse()
            #expect(
                ends.dim == dim && ends.bright == bright,
                "\(palette.name): moved to \(Self.hex(ends.dim))→\(Self.hex(ends.bright)) from \(Self.hex(dim))→\(Self.hex(bright))")
        }
    }

    // MARK: - Hover has to be visible

    /// Hovering a control tints its face a step further into the accent. The
    /// step used to be a fixed opacity (0.20 → 0.32), which is a clear
    /// difference in 24-bit colour and *no* difference on a 256-colour
    /// terminal for nine of these sixteen palettes — Green, Amber, Red, Violet,
    /// Homebrew, Man Page, Novel, Ocean and Red Sands each quantised both tints
    /// onto one cube entry, so the pointer changed nothing on screen.
    ///
    /// The floor is therefore stated where it bites: after downsampling.
    @Test("Hovering changes the face on every shipped palette")
    func hoverIsVisibleEverywhere() {
        for palette in Self.statedPalettes {
            let resting = palette.restingControlFace.resolve(with: palette)
            let hovered = palette.hoveredControlFace.resolve(with: palette)
            #expect(
                resting.downsampledToPalette256() != hovered.downsampledToPalette256(),
                "\(palette.name): hover \(Self.hex(hovered)) is the same cube entry as rest \(Self.hex(resting))")
        }
    }

    /// …and it goes two visible steps, not one.
    ///
    /// One step is the least the *terminal* can show. It was not what a *person*
    /// notices on a busy page — "the highlight effect for mouse hover is a bit
    /// too subtle" — so the tint walks past the first cube entry that separates
    /// it from rest and stops at the second.
    ///
    /// Stated as a property of the result rather than by re-deriving the walk:
    /// somewhere strictly between the resting tint and the hovered one there
    /// must be a THIRD cube entry, which is what "two steps" means and what a
    /// first-step-only implementation cannot satisfy. The ladder here is finer
    /// than the implementation's, so it cannot miss an entry the implementation
    /// passed through.
    @Test("The hover face walks two visible steps, not the first one it finds")
    func hoverWalksTwoSteps() {
        for palette in Self.statedPalettes {
            let resting = palette.restingControlFace.resolve(with: palette)
                .downsampledToPalette256()
            let hovered = palette.hoveredControlFace.resolve(with: palette)
                .downsampledToPalette256()
            // The palettes with nothing left to give: the walk ran out of range
            // and returned the accent itself. Nothing to count there.
            let accent = palette.accent.resolve(with: palette).downsampledToPalette256()
            if hovered == accent { continue }

            var intermediate = false
            var tint = ViewConstants.hoverBackground
            while tint < 1.0 {
                let entry = palette.accent.opacity(tint, over: palette.background)
                    .resolve(with: palette).downsampledToPalette256()
                if entry == hovered { break }
                if entry != resting { intermediate = true }
                tint += 0.02
            }
            #expect(
                intermediate,
                "\(palette.name): hover \(Self.hex(hovered)) is the first entry that separates from rest \(Self.hex(resting)), not the second")
        }
    }

    // MARK: - One chrome, both ends

    /// The app header and the status bar are the same chrome — one strip at
    /// each end of the page — so a palette must not tint them differently. Both
    /// built-in families used to: the presets lit the status bar to L=10 and
    /// the header to L=7, and the terminal profiles stepped them 0.10 and 0.16
    /// from the page. The result read as an accident, because it was one.
    @Test("Both bars are the same colour in every shipped palette")
    func barsShareOneTone() {
        for palette in Self.statedPalettes {
            #expect(
                palette.statusBarBackground.resolve(with: palette)
                    == palette.appHeaderBackground.resolve(with: palette),
                "\(palette.name): status bar \(Self.hex(palette.statusBarBackground)) ≠ header \(Self.hex(palette.appHeaderBackground))")
        }
    }
}

extension PaletteContrastAuditTests {
    private static func hex(_ color: Color) -> String {
        guard let (r, g, b) = color.rgbComponents else { return "?" }
        return String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
    }

    @Test("Report: key derived colours (hex) for the Terminal profiles")
    func hexReport() {
        for palette in PaletteRegistry.appleTerminalProfiles {
            print(
                "\(palette.name): bg \(Self.hex(palette.background)) accent \(Self.hex(palette.accent)) "
                    + "statusBar \(Self.hex(palette.statusBarBackground)) appHeader \(Self.hex(palette.appHeaderBackground)) "
                    + "focusBg \(Self.hex(palette.focusBackground)) "
                    + "ok \(Self.hex(palette.success)) warn \(Self.hex(palette.warning)) "
                    + "err \(Self.hex(palette.error)) info \(Self.hex(palette.info))")
        }
    }
}
