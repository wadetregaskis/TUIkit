//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AccentFillBreathTests.swift
//
//  The walk that chooses the shares of the accent a fill's breath runs between
//  (`AccentFillBreath`), on colours no shipped palette has: where the walk has no
//  answer, where the text cannot be measured, and where an end is the terminal's own
//  and its answer must not be kept. `PaletteContrastAuditTests` holds the shipped
//  palettes to what the walk promises.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

@Suite("The accent's fill breath, chosen as 256 colours draw it")
struct AccentFillBreathTests {

    /// Violet's colours: a breath the text floor moves.
    private static let violetAccent = Color.rgb(199, 151, 247)
    private static let violetPage = Color.rgb(8, 5, 10)
    private static let violetText = Color.rgb(178, 117, 240)

    /// The plain breath, ``ViewConstants/focusPulseMin`` to
    /// ``ViewConstants/focusPulseMax`` of `accent` over `ground`.
    private static func plain(_ accent: Color, over ground: Color) -> (dim: Color, bright: Color) {
        (
            accent.opacity(ViewConstants.focusPulseMin, over: ground),
            accent.opacity(ViewConstants.focusPulseMax, over: ground)
        )
    }

    /// The premise the tests below lean on: with Violet's text, the top comes down.
    @Test("Violet's breath is walked where its text is measured")
    func violetIsWalked() {
        let breath = AccentFillBreath(
            accent: Self.violetAccent, ground: Self.violetPage, text: Self.violetText)
        let shares = breath.shares
        #expect(shares.dim == 22 && shares.bright == 37, "\(shares)")
    }

    /// Where the text is `Color.default`, or a colour of the terminal's own that it has
    /// not reported, there is no ratio to keep, and the breath is the plain one, as
    /// `Color.ensuringContrast(atLeast:against:)` leaves a colour it cannot measure.
    @Test("A text with no RGB keeps no floor, and the breath stays plain")
    func unmeasuredTextKeepsNoFloor() {
        TerminalColors.withCurrent(.unknown) {
            for text in [Color.default, Color(value: .terminalForeground)] {
                let ends = AccentFillBreath(accent: Self.violetAccent, ground: Self.violetPage, text: text).ends
                let plain = Self.plain(Self.violetAccent, over: Self.violetPage)
                #expect(ends.dim == plain.dim && ends.bright == plain.bright, "\(text)")
            }
        }
    }

    /// The top is all the walk moves for the text, so a breath whose DIM end is what
    /// the text cannot be read on has no share of the top that holds. It is left where
    /// it was asked rather than walked to the dim end: the floor makes no promise it
    /// cannot keep. Near-black text on a black page, under a white accent: 22% draws
    /// `#3A3A3A`, 1.6:1 against the text, and no top changes that.
    @Test("Where no share of the top holds, the breath stays where it was asked")
    func noAnswerLeavesThePlainBreath() {
        let accent = Color.rgb(255, 255, 255)
        let page = Color.rgb(0, 0, 0)
        let breath = AccentFillBreath(accent: accent, ground: page, text: .rgb(16, 16, 16))
        #expect(!breath.holds(22, 50), "the premise: the plain breath fails")
        let shares = breath.shares
        #expect(shares.dim == 22 && shares.bright == 50, "\(shares)")
    }

    /// An answer is kept only for colours whose rendering nothing can move. A ground the
    /// terminal decides measures as whatever it last reported, and a task-scoped pin
    /// (`TerminalColors.withCurrent`) moves no generation a key could hold, so the same
    /// three colours can need two answers in one process. Kept, the second pin was
    /// handed the first one's.
    @Test("A breath over the terminal's own page is walked under each report, not kept")
    func terminalGroundIsNotKept() {
        let ground = Color(value: .terminalBackground)
        let dark = TerminalColors(
            foreground: TerminalColors.RGB(red: 178, green: 117, blue: 240),
            background: TerminalColors.RGB(red: 8, green: 5, blue: 10))
        let light = TerminalColors(
            foreground: TerminalColors.RGB(red: 178, green: 117, blue: 240),
            background: TerminalColors.RGB(red: 255, green: 255, blue: 255))
        let onDark = AccentFillBreath(accent: Self.violetAccent, ground: Self.violetPage, text: Self.violetText).ends
        let onLight = AccentFillBreath(accent: Self.violetAccent, ground: .rgb(255, 255, 255), text: Self.violetText)
            .ends
        let lightIsPlain = onLight.bright == Self.plain(Self.violetAccent, over: .rgb(255, 255, 255)).bright
        let darkIsPlain = onDark.bright == Self.plain(Self.violetAccent, over: Self.violetPage).bright
        #expect(lightIsPlain && !darkIsPlain, "the premise: one page walks the top and the other does not")
        for (page, colours, expected) in [("dark", dark, onDark), ("light", light, onLight), ("dark", dark, onDark)] {
            TerminalColors.withCurrent(colours) {
                let ends = AccentFillBreath.ends(accent: Self.violetAccent, ground: ground, text: Self.violetText)
                #expect(ends.dim == expected.dim && ends.bright == expected.bright, "on the \(page) page")
            }
        }
    }
}
