//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AsciiDetailedRenderTests.swift
//
//  `.asciiDetailed` uses a longer, ink-ordered ramp with 2× supersampling for
//  finer tonal gradation than `.ascii`, while staying pure ASCII.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

@MainActor
@Suite("asciiDetailed rendering")
struct AsciiDetailedRenderTests {
    /// A left→right greyscale ramp (luminance 0…255 across the width).
    private func horizontalGradient(_ width: Int, _ height: Int) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)
        for _ in 0..<height {
            for x in 0..<width {
                let v = UInt8(clamping: x * 255 / max(1, width - 1))
                pixels.append(RGBA(r: v, g: v, b: v))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func distinctGlyphs(_ charSet: ASCIICharacterSet, width: Int) -> Set<Character> {
        let converter = ASCIIConverter(characterSet: charSet, colorMode: .mono, dithering: .none)
        let line = converter.convert(horizontalGradient(width, 2), width: width, height: 2)
            .first?.stripped ?? ""
        return Set(line)
    }

    @Test("asciiDetailed resolves more tonal levels than ascii across a gradient")
    func finerGradation() {
        let plain = distinctGlyphs(.ascii, width: 60)
        let detailed = distinctGlyphs(.asciiDetailed, width: 60)
        #expect(
            detailed.count > plain.count,
            "detailed (\(detailed.count) glyphs) should out-resolve ascii (\(plain.count))")
        // ascii tops out at its 10-glyph ramp; detailed reaches well past that.
        #expect(plain.count <= 10)
        #expect(detailed.count >= 14, "the long ramp uses many levels: \(detailed.sorted())")
    }

    @Test("asciiDetailed stays pure ASCII (renders on any terminal)")
    func pureAscii() {
        let glyphs = distinctGlyphs(.asciiDetailed, width: 80)
        #expect(
            glyphs.allSatisfy { $0.isASCII },
            "no non-ASCII glyphs leaked in: \(glyphs.filter { !$0.isASCII })")
    }

    @Test("asciiDetailed renders the requested cell grid (supersampling is internal)")
    func cellGridUnchanged() {
        let converter = ASCIIConverter(characterSet: .asciiDetailed, colorMode: .mono, dithering: .none)
        let lines = converter.convert(horizontalGradient(24, 6), width: 24, height: 6)
        #expect(lines.count == 6, "one line per requested cell row")
        #expect(lines.allSatisfy { $0.stripped.count == 24 }, "one glyph per requested cell column")
    }
}
