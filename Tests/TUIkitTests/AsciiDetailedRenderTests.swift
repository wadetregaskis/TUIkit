//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AsciiDetailedRenderTests.swift
//
//  The ASCII charset's configurable size: the full repertoire uses a long,
//  ink-ordered ramp with 2× supersampling for fine tonal gradation, while a
//  small glyph count reproduces the classic coarse ASCII-art look — both
//  pure ASCII.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

@MainActor
@Suite("ASCII charset sizing")
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

    @Test("the full ASCII repertoire resolves more tonal levels than a 10-glyph ramp")
    func finerGradation() {
        let plain = distinctGlyphs(.ascii(glyphs: 10), width: 60)
        let detailed = distinctGlyphs(.ascii, width: 60)
        #expect(
            detailed.count > plain.count,
            "full (\(detailed.count) glyphs) should out-resolve 10-glyph (\(plain.count))")
        #expect(plain.count <= 10)
        #expect(detailed.count >= 14, "the full ramp uses many levels: \(detailed.sorted())")
    }

    @Test("the ASCII charset stays pure ASCII (renders on any terminal)")
    func pureAscii() {
        let glyphs = distinctGlyphs(.ascii, width: 80)
        #expect(
            glyphs.allSatisfy { $0.isASCII },
            "no non-ASCII glyphs leaked in: \(glyphs.filter { !$0.isASCII })")
    }

    @Test("the full ramp renders the requested cell grid (supersampling is internal)")
    func cellGridUnchanged() {
        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .mono, dithering: .none)
        let lines = converter.convert(horizontalGradient(24, 6), width: 24, height: 6)
        #expect(lines.count == 6, "one line per requested cell row")
        #expect(lines.allSatisfy { $0.stripped.count == 24 }, "one glyph per requested cell column")
    }
}
