//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GreyRampBandTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

/// `.grayscale` is documented as 24 shades. Scaling luminance by 23 and
/// truncating gave 23 of them an 11-value band and the top one — #eeeeee —
/// exactly one input, pure white: every highlight clipped a step dark.
@Suite("Grey ramp bands")
struct GreyRampBandTests {

    @Test("Each of the 24 greys owns an equal slice of the luminance range")
    func bandsAreEqual() {
        let converter = ASCIIConverter(colorMode: .grayscale)
        var counts: [String: Int] = [:]
        for value in 0...255 {
            let pixel = RGBA(r: UInt8(value), g: UInt8(value), b: UInt8(value))
            counts[converter.foregroundColorCode(for: pixel, mode: .grayscale), default: 0] += 1
            #expect(
                converter.backgroundColorCode(for: pixel, mode: .grayscale).contains(
                    converter.foregroundColorCode(for: pixel, mode: .grayscale).dropFirst(5)),
                "the background copy agrees with the foreground: \(value)")
        }
        #expect(counts.count == 24)
        #expect(counts.values.max()! - counts.values.min()! <= 1, "\(counts.values.sorted())")
    }

    /// The `.ansi256` grey ramp: every level lands on its NEAREST entry. The
    /// old arithmetic floored, so a level in the upper half of a ten-wide step
    /// came out an entry too dark — the exact palette entries included — and
    /// sent 5…7 to pure black with (8,8,8) three levels away.
    @Test("The ansi256 grey ramp rounds to the nearest entry")
    func ansi256GreysRound() {
        let converter = ASCIIConverter(colorMode: .ansi256)
        func index(_ level: UInt8) -> String {
            converter.foregroundColorCode(for: RGBA(r: level, g: level, b: level), mode: .ansi256)
        }
        for step in 0..<24 {
            let entry = UInt8(8 + 10 * step)
            #expect(index(entry).contains("38;5;\(232 + step)m"), "the exact entry \(entry) is itself")
            // Four above the entry is nearer to it than to the next.
            #expect(index(entry + 4).contains("38;5;\(232 + step)m"), "\(entry + 4) rounds down")
        }
        #expect(index(15).contains("38;5;233m"), "15 is nearer 18 than 8")
        #expect(index(6).contains("38;5;232m"), "6 is nearer (8,8,8) than black")
        #expect(index(2).contains("38;5;16m"), "2 is nearer black")
        #expect(index(250).contains("38;5;231m"), "250 is nearer white than 238")
        #expect(index(242).contains("38;5;255m"), "242 is nearer 238 than white")
    }

    @Test("A near-white highlight reaches the top grey")
    func highlightReachesTheTop() {
        let converter = ASCIIConverter(colorMode: .grayscale)
        #expect(converter.foregroundColorCode(for: RGBA(r: 250, g: 250, b: 250), mode: .grayscale).contains("38;5;255"))
        #expect(converter.foregroundColorCode(for: RGBA(r: 255, g: 255, b: 255), mode: .grayscale).contains("38;5;255"))
        #expect(converter.foregroundColorCode(for: RGBA(r: 0, g: 0, b: 0), mode: .grayscale).contains("38;5;232"))
    }
}
