//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BoldSafetyTests.swift
//
//  A half-block image cell is emitted bold, to close a rasterisation gap under
//  SF Mono in Terminal.app. Bold is not only a weight: xterm and most of its
//  descendants implement "bold means bright", so SGR 1 over a foreground named
//  as one of the sixteen paints the BRIGHT twin instead.
//
//  These are the cases that decide where that weight may be spent. They are
//  worth pinning because the failure is invisible on the host the workaround
//  was written for and ruins the picture on the ones it was not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitStyling

@testable import TUIkitImage

@Suite("Where a half block may be emitted bold")
struct BoldSafetyTests {

    /// A four-cell-tall grey ramp, which `.blocks(.fine)` renders as `▄` with a
    /// distinct colour above and below in every cell.
    private func ramp(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<height {
            for _ in 0..<width {
                let v = UInt8(clamping: y * (255 / max(1, height - 1)))
                pixels.append(RGBA(r: v, g: v, b: v))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func converted(_ mode: ASCIIColorMode) -> String {
        let converter = ASCIIConverter(characterSet: .blocks(.fine), colorMode: mode)
        return converter.convert(ramp(width: 8, height: 8), width: 8, height: 4).lines
            .joined(separator: "\n")
    }

    private let bold = "\u{1B}[1m"

    // MARK: - The rule

    /// The three modes that state a foreground no bright twin can be
    /// substituted for: a triple, or a 256-cube index at 16 or above.
    @Test("Bold is safe where the foreground is not one of the sixteen")
    func safeModes() {
        #expect(ASCIIColorMode.trueColor.foregroundSurvivesBold)
        #expect(ASCIIColorMode.ansi256.foregroundSurvivesBold)
        #expect(ASCIIColorMode.grayscale.foregroundSurvivesBold)
        #expect(ASCIIColorMode.mono.foregroundSurvivesBold)
    }

    /// And the one that states exactly those names.
    @Test("Bold is unsafe in ansi16")
    func ansi16IsUnsafe() {
        #expect(!ASCIIColorMode.ansi16.foregroundSurvivesBold)
    }

    /// `.ansi256`'s safety rests on its palette never OFFERING one of the
    /// sixteen: `ASCIIPalette.ansi256` holds indices 16…255 and nothing below,
    /// and `Color`'s own search over the same entries starts at 16 too. Swept
    /// rather than argued, because a single index below 16 would put bold back
    /// over a name.
    @Test("The 256-colour quantiser never lands on one of the sixteen")
    func quantiserAvoidsTheSixteen() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        for red in stride(from: 0, through: 255, by: 5) {
            for green in stride(from: 0, through: 255, by: 5) {
                for blue in stride(from: 0, through: 255, by: 5) {
                    let pixel = RGBA(r: UInt8(red), g: UInt8(green), b: UInt8(blue))
                    let code = converter.foregroundColorCode(for: pixel, mode: .ansi256)
                    let index = Int(code.dropFirst(2).dropLast().split(separator: ";").last ?? "")
                    #expect((index ?? 0) >= 16, "\(pixel) quantised to \(code)")
                }
            }
        }
    }

    // MARK: - Palettes, which are only as safe as their least safe entry

    @Test("A palette of triples is safe; one naming an ANSI colour is not")
    func paletteSafety() {
        #expect(ASCIIPalette([.rgb(10, 20, 30), .rgb(200, 200, 200)]).foregroundSurvivesBold)
        #expect(!ASCIIPalette([.rgb(10, 20, 30), .black]).foregroundSurvivesBold)
        #expect(!ASCIIPalette([.brightWhite]).foregroundSurvivesBold)
        #expect(!ASCIIPalette.ansi16.foregroundSurvivesBold)
    }

    /// A 256-cube index is a name below 16 and a colour at or above it, and the
    /// palette has to read it that way round.
    @Test("A 256-palette entry is safe only from index 16 up")
    func palette256Boundary() {
        #expect(!ASCIIPalette([.palette(15)]).foregroundSurvivesBold)
        #expect(ASCIIPalette([.palette(16)]).foregroundSurvivesBold)
    }

    /// The trap that makes this more than a static property of the mode: a
    /// palette chosen as triples becomes sixteen names on a 16-colour terminal,
    /// and the emission has to follow it down.
    @Test("Downsampling a safe palette to 16 colours makes it unsafe")
    func downsamplingRemovesTheSafety() {
        let palette = ASCIIPalette([.rgb(10, 20, 30), .rgb(200, 30, 30)])
        #expect(palette.foregroundSurvivesBold)
        #expect(!palette.downsampled(to: .basic16).foregroundSurvivesBold)
    }

    // MARK: - What actually reaches the terminal

    /// The emission itself, which is the only thing a terminal sees. Both
    /// halves matter: dropping the weight everywhere would give up the
    /// Terminal.app workaround that earned it.
    @Test("A 16-colour image carries no bold, and a true-colour one still does")
    func emissionMatchesTheRule() {
        #expect(!converted(.ansi16).contains(bold), "SGR 1 over SGR 30–37 recolours the cell")
        #expect(converted(.trueColor).contains(bold), "the gap workaround costs nothing here")
        #expect(converted(.grayscale).contains(bold))
    }

    /// The palette case end to end: `themed` is `[.black, accent, .white]`, so
    /// two of its three entries are names and the whole image goes unbolded.
    @Test("A palette naming ANSI colours is emitted without bold")
    func paletteEmissionFollowsTheRule() {
        let named = ASCIIColorMode.palette(ASCIIPalette([.black, .rgb(51, 255, 51), .white]))
        let triples = ASCIIColorMode.palette(ASCIIPalette([.rgb(0, 0, 0), .rgb(255, 255, 255)]))
        #expect(!converted(named).contains(bold))
        #expect(converted(triples).contains(bold))
    }
}
