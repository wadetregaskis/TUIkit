//  🖥️ TUIKit — Terminal UI Kit for Swift
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

@testable import TUIkit
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
                name: "tertiary/fieldBackground",  // the prompt text
                foreground: palette.foregroundTertiary, background: palette.fieldBackground,
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
        let pulseDim = palette.accent.opacity(ViewConstants.focusPulseMin, over: background)
        let pulseBright = palette.accent.opacity(ViewConstants.focusPulseMax, over: background)
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
                foreground: palette.foreground, background: pulseBright, minimum: 2.0),
        ]
    }

    /// Every palette the framework ships.
    private static var allPalettes: [any Palette] {
        PaletteRegistry.all
    }

    // MARK: - Report (not an assertion; run with --filter to see the table)

    @Test("Report: contrast table for every shipped palette")
    func report() {
        for palette in Self.allPalettes {
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
        for palette in Self.allPalettes {
            for pair in Self.pairs(for: palette) {
                let ratio = Self.contrast(pair.foreground, pair.background)
                #expect(
                    ratio >= pair.minimum,
                    "\(palette.name): \(pair.name) contrast \(String(format: "%.2f", ratio)) < \(pair.minimum)")
            }
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
        for palette in PaletteRegistry.terminalProfiles {
            print(
                "\(palette.name): bg \(Self.hex(palette.background)) accent \(Self.hex(palette.accent)) "
                    + "statusBar \(Self.hex(palette.statusBarBackground)) appHeader \(Self.hex(palette.appHeaderBackground)) "
                    + "focusBg \(Self.hex(palette.focusBackground)) "
                    + "ok \(Self.hex(palette.success)) warn \(Self.hex(palette.warning)) "
                    + "err \(Self.hex(palette.error)) info \(Self.hex(palette.info))")
        }
    }
}
