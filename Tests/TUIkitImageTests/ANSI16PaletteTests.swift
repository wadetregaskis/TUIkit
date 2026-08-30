//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSI16PaletteTests.swift
//
//  ``ASCIIPalette/ansi16`` is what every fidelity mode lands on when the
//  terminal has sixteen colours and no more, so it is the difference between
//  an image drawn in colour there and one drawn in a single ink.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitStyling

@testable import TUIkitImage

// MARK: - The terminal's own sixteen

@Suite("ASCIIPalette.ansi16")
struct ASCIIPaletteANSI16Tests {

    /// The whole point of naming the sixteen as `.standard`/`.bright` colours
    /// rather than as RGB triples: they are emitted as SGR 30–37 / 90–97, which
    /// is the only spelling a 16-colour terminal understands — and it means the
    /// image FOLLOWS the user's terminal profile, since those codes name a slot
    /// rather than a colour.
    @Test("Every entry emits as a standard or bright ANSI code")
    func entriesEmitAsANSICodes() {
        let sixteen = ASCIIPalette.ansi16
        #expect(sixteen.colors.count == 16)
        var seen = Set<String>()
        for index in sixteen.colors.indices {
            let parameters = sixteen.sgrParameters(at: index, background: false)
            guard let code = Int(parameters) else {
                Issue.record("entry \(index) emitted '\(parameters)', not a bare SGR code")
                continue
            }
            #expect(
                (30...37).contains(code) || (90...97).contains(code),
                "entry \(index) emitted \(code)")
            seen.insert(parameters)
        }
        #expect(seen.count == 16, "two entries emit the same code")
    }

    /// The backgrounds are the same sixteen slots, and a half-block render
    /// spends both halves of a cell — so a wrong background family would show
    /// as every other row being uncoloured.
    @Test("Backgrounds are the matching 40–47 / 100–107 codes")
    func backgroundsMirrorForegrounds() {
        let sixteen = ASCIIPalette.ansi16
        for index in sixteen.colors.indices {
            let foreground = Int(sixteen.sgrParameters(at: index, background: false)) ?? 0
            let background = Int(sixteen.sgrParameters(at: index, background: true)) ?? 0
            #expect(background == foreground + 10)
        }
    }

    /// Named colours land on themselves — the mapping is nearest-in-OKLab, and
    /// a palette entry is exactly zero from itself, so anything else would mean
    /// the entries' colours and the codes they emit had come apart.
    @Test(
        "A colour that IS one of the sixteen maps to that one",
        arguments: [
            (RGBA(r: 255, g: 0, b: 0), "91"),  // bright red
            (RGBA(r: 0, g: 0, b: 0), "30"),  // black
            (RGBA(r: 255, g: 255, b: 255), "97"),  // bright white
        ])
    func namedColoursMapToThemselves(pixel: RGBA, expected: String) {
        let sixteen = ASCIIPalette.ansi16
        #expect(sixteen.sgrParameters(at: sixteen.nearestIndex(to: pixel), background: false) == expected)
    }

    /// The regression this exists for: on a 16-colour terminal an image used to
    /// come out in one ink whatever mode was asked for, because every fidelity
    /// mode fell all the way to `.mono`.
    @Test("A colour image on a 16-colour terminal is drawn in colour")
    func sixteenColourTerminalGetsColour() {
        let pixels = [
            RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 255, b: 0),
            RGBA(r: 0, g: 0, b: 255), RGBA(r: 255, g: 255, b: 0),
        ]
        let image = RGBAImage(width: 2, height: 2, pixels: pixels)
        let converter = ASCIIConverter(
            characterSet: .blocks(.solid), colorMode: .trueColor, dithering: .none)
        ColorDepth.withCurrent(.basic16) {
            let lines = converter.convert(image, width: 2, height: 2)
            let all = lines.joined()
            // `.solid` fills the cell, so the colour lands in the BACKGROUND
            // family — 40–47 and 100–107.
            var codes = Set<Int>()
            var rest = Substring(all)
            while let open = rest.range(of: "\u{1B}[") {
                rest = rest[open.upperBound...]
                guard let close = rest.firstIndex(of: "m") else { break }
                if let code = Int(rest[rest.startIndex..<close]), code != 0 { codes.insert(code) }
                rest = rest[rest.index(after: close)...]
            }
            #expect(
                codes.count == 4,
                "four distinct colours expected, got \(codes.sorted()) from \(all.debugDescription)")
            for code in codes {
                #expect((40...47).contains(code) || (100...107).contains(code), "code \(code)")
            }
            #expect(!all.contains("48;2;"))
            #expect(!all.contains("48;5;"))
        }
    }
}
