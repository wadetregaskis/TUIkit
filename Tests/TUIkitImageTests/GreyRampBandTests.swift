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

    @Test("A near-white highlight reaches the top grey")
    func highlightReachesTheTop() {
        let converter = ASCIIConverter(colorMode: .grayscale)
        #expect(converter.foregroundColorCode(for: RGBA(r: 250, g: 250, b: 250), mode: .grayscale).contains("38;5;255"))
        #expect(converter.foregroundColorCode(for: RGBA(r: 255, g: 255, b: 255), mode: .grayscale).contains("38;5;255"))
        #expect(converter.foregroundColorCode(for: RGBA(r: 0, g: 0, b: 0), mode: .grayscale).contains("38;5;232"))
    }
}
