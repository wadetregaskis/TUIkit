//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MonoThresholdTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage

@Suite("Adaptive mono threshold")
struct MonoThresholdTests {

    /// An image of `levels`, laid out left to right, one column per pixel run.
    private func image(levels: [UInt8], repeatEach: Int = 1) -> RGBAImage {
        var pixels: [RGBA] = []
        for level in levels {
            for _ in 0..<repeatEach { pixels.append(RGBA(r: level, g: level, b: level)) }
        }
        return RGBAImage(width: pixels.count, height: 1, pixels: pixels)
    }

    // MARK: - Where it lands

    @Test("The split falls between two clusters, not at mid-grey")
    func bimodalDarkImage() {
        // The shape of a photograph: a large dark field and a small bright
        // subject, all of it well below mid-luminance. A fixed 128 split calls
        // every one of these pixels background and draws nothing.
        let dark = [UInt8](repeating: 20, count: 870)
        let subject = [UInt8](repeating: 90, count: 130)
        let threshold = ASCIIConverter.monoInkThreshold(for: image(levels: dark + subject))
        #expect(
            threshold > 20 && threshold < 90,
            "the split should sit between the two clusters, not at \(threshold)")
    }

    @Test("Both clusters land on the side they belong to")
    func clustersSeparate() {
        let dark = [UInt8](repeating: 30, count: 600)
        let bright = [UInt8](repeating: 200, count: 400)
        let threshold = ASCIIConverter.monoInkThreshold(for: image(levels: dark + bright))
        #expect(!ASCIIConverter.isMonoInk(RGBA(r: 30, g: 30, b: 30), threshold: threshold))
        #expect(ASCIIConverter.isMonoInk(RGBA(r: 200, g: 200, b: 200), threshold: threshold))
    }

    @Test("A bright-field image splits too, in the other direction")
    func bimodalBrightImage() {
        // Dark text on white paper — the case that motivated the old inverted
        // polarity. The threshold has to sit high, not at mid-grey.
        let paper = [UInt8](repeating: 240, count: 900)
        let ink = [UInt8](repeating: 160, count: 100)
        let threshold = ASCIIConverter.monoInkThreshold(for: image(levels: paper + ink))
        #expect(threshold > 160 && threshold < 240, "split landed at \(threshold)")
    }

    // MARK: - Where it declines

    @Test("A flat image keeps the fixed split rather than splitting noise")
    func uniformImage() {
        let flat = ASCIIConverter.monoInkThreshold(for: image(levels: [UInt8](repeating: 64, count: 500)))
        #expect(flat == ASCIIConverter.midLuminance)
    }

    @Test("A nearly-flat image keeps it too")
    func narrowSpread() {
        // Fifteen levels of spread — below `minimumSeparableSpread`. There is no
        // subject here, only noise, and Otsu would split the noise down the
        // middle and render it as speckle.
        let noisy = (0..<500).map { UInt8(100 + $0 % 15) }
        #expect(ASCIIConverter.monoInkThreshold(for: image(levels: noisy)) == ASCIIConverter.midLuminance)
    }

    @Test("An empty image keeps it")
    func emptyImage() {
        let empty = RGBAImage(width: 0, height: 0, pixels: [])
        #expect(ASCIIConverter.monoInkThreshold(for: empty) == ASCIIConverter.midLuminance)
    }

    // MARK: - What it does to a render

    /// The fraction of a mono render's cells that carry ink.
    ///
    /// A braille cell with no dots is U+2800, not a space — it is the blank of
    /// that repertoire, and counting it as ink reports every braille render as
    /// 100% covered whatever it drew.
    private func inkFraction(_ lines: [String]) -> Double {
        var ink = 0
        var total = 0
        for line in lines {
            for character in line {
                total += 1
                if character != " " && character != "\u{2800}" { ink += 1 }
            }
        }
        return total > 0 ? Double(ink) / Double(total) : 0
    }

    /// A dark photograph's shape: a gradient field almost entirely below
    /// mid-luminance, with a brighter subject in the middle.
    private func darkSubjectImage(width: Int, height: Int) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let insideSubject =
                    x > width / 3 && x < 2 * width / 3 && y > height / 3 && y < 2 * height / 3
                let level = insideSubject ? 95 : 15 + (x * 10) / max(1, width)
                pixels.append(RGBA(r: UInt8(level), g: UInt8(level), b: UInt8(level)))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    @Test("A dark image renders its subject instead of nothing", arguments: [
        ASCIICharacterSet.blocks(.solid), .blocks(.fine), .blocks(.braille),
    ])
    func darkImageRendersSomething(characterSet: ASCIICharacterSet) {
        let source = darkSubjectImage(width: 240, height: 120)
        let converter = ASCIIConverter(characterSet: characterSet, colorMode: .mono)
        let lines = converter.convert(source, width: 60, height: 24)
        let inked = inkFraction(lines)
        // The subject is a ninth of the frame. Anything near zero means the
        // threshold sat outside the image's tones — which is what a fixed
        // mid-luminance split did — and anything near one means everything
        // crossed it.
        #expect(inked > 0.02, "\(characterSet): rendered \(inked) ink — effectively blank")
        #expect(inked < 0.9, "\(characterSet): rendered \(inked) ink — effectively solid")
    }

    @Test("The same image at the fixed split renders nothing, which is the point")
    func fixedSplitWouldRenderNothing() {
        // Guards the premise rather than the code: if this ever stops being
        // true, the adaptive threshold is solving a problem that went away.
        let source = darkSubjectImage(width: 240, height: 120)
        let above = source.pixels.filter { $0.luminance >= ASCIIConverter.midLuminance }
        #expect(above.isEmpty, "\(above.count) pixels reach mid-luminance; the premise has changed")
    }
}
