//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RTLRampTests.swift
//
//  A `.customRamp` of right-to-left letters, and the mark that keeps its
//  picture the right way round.
//
//  A host applying the bidirectional algorithm reverses a run of RTL letters
//  within the columns it occupies. In text that is arguably right; in a picture
//  every character is a pixel, so it mirrors the row. Measured on Apple
//  Terminal with `Tools/TerminalProbes/rtl_image_card.py`: a gradient's flat end
//  came out at the wrong side of every row, and U+200E after each glyph put it
//  back — with the card's alignment column unmoved, so the mark costs no cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitImage

@Suite("A right-to-left image ramp")
struct RTLRampTests {

    private static let mark: Character = "\u{200E}"

    /// A black → white horizontal gradient, so a row uses the whole ramp.
    private func gradient(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        for _ in 0..<height {
            for x in 0..<width {
                let v = UInt8(min(255, x * 255 / max(1, width - 1)))
                pixels.append(RGBA(r: v, g: v, b: v))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func render(_ ramp: String, width: Int = 20, height: Int = 4) -> [String] {
        ASCIIConverter(
            characterSet: .customRamp(ramp), colorMode: .mono, edgeThreshold: nil
        ).convert(gradient(width: width * 2, height: height * 2), width: width, height: height)
    }

    // MARK: - The mark

    @Test("Every Hebrew glyph is followed by a left-to-right mark")
    func hebrewGlyphsAreIsolated() {
        let lines = render(" אבגדהוזחט")
        #expect(!lines.isEmpty)
        for line in lines {
            var previous: Character?
            for character in line {
                if let previous, previous.isStrongRightToLeft {
                    #expect(
                        character == Self.mark,
                        "a mark follows every RTL glyph: \(line.debugDescription)")
                }
                previous = character
            }
            #expect(
                line.last.map { !$0.isStrongRightToLeft } ?? true,
                "including the last one: \(line.debugDescription)")
        }
    }

    /// The whole point of the mark: each letter is its own run, so nothing the
    /// bidirectional algorithm does can put two of them in the other order.
    @Test("No two RTL glyphs are ever adjacent")
    func rtlGlyphsAreNeverAdjacent() {
        for line in render(" אבגדהוזחט") {
            var previous: Character?
            for character in line {
                if let previous, previous.isStrongRightToLeft {
                    #expect(!character.isStrongRightToLeft, "adjacent: \(line.debugDescription)")
                }
                previous = character
            }
        }
    }

    /// A mixed ramp marks only what needs it — the ASCII glyphs are written as
    /// they always were.
    @Test("A left-to-right glyph is left alone")
    func asciiGlyphsAreUntouched() {
        for line in render(" .אב#@") {
            var previous: Character?
            for character in line {
                if let previous, !previous.isStrongRightToLeft {
                    #expect(character != Self.mark, "unasked-for mark: \(line.debugDescription)")
                }
                previous = character
            }
        }
    }

    /// A ramp with no RTL in it pays nothing — not a byte, so no existing
    /// picture changes.
    @Test("An ASCII ramp carries no marks at all")
    func asciiRampIsUnchanged() {
        for line in render(" .:-=+*#%@") {
            #expect(!line.contains(Self.mark), "no mark: \(line.debugDescription)")
        }
    }

    // MARK: - The columns

    /// Zero width, so the picture keeps its shape: the marked rows measure
    /// exactly as many cells as the ASCII ones, and as many as were asked for.
    @Test("The marks cost no columns")
    func markedRowsKeepTheirWidth() {
        let hebrew = render(" אבגדהוזחט")
        let ascii = render(" .:-=+*#%@")
        #expect(hebrew.count == ascii.count)
        for (marked, plain) in zip(hebrew, ascii) {
            #expect(marked.strippedLength == 20, "asked for 20: \(marked.debugDescription)")
            #expect(marked.strippedLength == plain.strippedLength)
        }
    }

    // MARK: - The predicate

    @Test("Which characters count as strong right-to-left")
    func predicateCoversTheBlocks() {
        for character in "אבגתשׁ" { #expect(character.isStrongRightToLeft, "\(character)") }
        for character in "ابتث" { #expect(character.isStrongRightToLeft, "\(character)") }
        for character in "abcZ .:-=+*#%@█▓░▘◢" {
            #expect(!character.isStrongRightToLeft, "\(character)")
        }
        // A cluster of several scalars is never one of these blocks' letters,
        // and an image ramp is one cell per character anyway.
        #expect(!Character("🤙🏽").isStrongRightToLeft)
    }
}
