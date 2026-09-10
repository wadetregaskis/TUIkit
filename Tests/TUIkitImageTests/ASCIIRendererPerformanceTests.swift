//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIRendererPerformanceTests.swift
//
//  A cost guard, not a benchmark. Both converters walk every source pixel, and
//  the failure mode worth catching here is the one that changes the SHAPE of
//  that walk — a per-cell rescan of the character table, a per-pixel allocation
//  — which costs orders of magnitude, not percent. So the ceiling is loose
//  enough that no CI runner's speed can reach it, and each case also asserts
//  what a timing number cannot: that the frame it timed was the whole frame.
//
//  Real numbers come from `Tools/Profiling`, against the app.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkitImage

@Suite("ASCII renderer cost")
struct ASCIIRendererPerformanceTests {

    /// Builds a deterministic synthetic image of the requested size.
    ///
    /// A vertical-bar pattern with a horizontal brightness ramp gives the
    /// renderer realistic variation across cells (so the shape vector
    /// matcher actually exercises its full character table) without
    /// dragging in disk I/O for a real PNG.
    private func makeSyntheticImage(width: Int, height: Int) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let band = (y / 8) % 3
            for x in 0..<width {
                let intensity = UInt8((x * 255) / max(1, width - 1))
                let r: UInt8
                let g: UInt8
                let b: UInt8
                switch band {
                case 0: r = intensity; g = 0;          b = 255 &- intensity
                case 1: r = 0;         g = intensity;  b = 255 &- intensity
                default: r = intensity; g = intensity; b = intensity
                }
                pixels.append(RGBA(r: r, g: g, b: b))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Seconds per call above which the walk has changed shape rather than
    /// merely got slower. The shape-vector pass measures ~130 ms per call in a
    /// debug build on the machine this was written on, and braille an order
    /// less; the ceiling is roughly eight times the slower of the two, which no
    /// runner's slowness reaches and no linear implementation can spend.
    private let costCeiling = 1.0

    /// The cells, with the SGR colour runs taken out. Both converters emit
    /// colour inline, so the raw `String` length counts escape bytes rather
    /// than cells.
    ///
    /// Written out here rather than borrowed: `TUIkitImage` does not depend on
    /// `TUIkitCore`, where `String.stripped` lives, and the test targets hold
    /// the same boundary as the modules they cover.
    private func cells(_ row: String) -> String {
        var out = ""
        var iterator = row.makeIterator()
        while let character = iterator.next() {
            guard character == "\u{1B}" else {
                out.append(character)
                continue
            }
            // ESC, then the '[' that opens the sequence — which is itself in
            // the final-byte range, so it has to be stepped over before the
            // scan for the terminator starts.
            _ = iterator.next()
            while let inside = iterator.next(), !("@"..."~").contains(inside) {}
        }
        return out
    }

    private func measure(_ iterations: Int, _ body: () -> Void) -> Double {
        let start = Date()
        for _ in 0..<iterations { body() }
        return Date().timeIntervalSince(start) / Double(iterations)
    }

    @Test("The shape-vector renderer converts a whole frame, and cheaply")
    func shapeRendererThroughput() {
        // 320 × 160 source pixels → 80 × 40 cells (2:1 cell ratio is typical
        // for fixed-width terminal cells).
        let image = makeSyntheticImage(width: 320, height: 160)
        let converter = ASCIIConverter(characterSet: .ascii, shapeAware: true)

        var frame: [String] = []
        let perCall = measure(10) {
            frame = converter.convert(image, width: 80, height: 40).lines
        }
        #expect(frame.count == 40, "every requested row")
        let widths = Set(frame.map { cells($0).count })
        #expect(widths == [80], "80 cells on every row: \(widths.sorted())")
        // The synthetic image ramps left to right, so a renderer that had
        // stopped discriminating — one character everywhere — would still pass
        // both counts above and every timing bound.
        #expect(
            Set(frame.map(cells).joined()).count > 4,
            "the character table is being used")
        #expect(
            perCall < costCeiling,
            "\(String(format: "%.1f", perCall * 1000))ms per call, ceiling \(Int(costCeiling * 1000))ms")
    }

    @Test("The braille renderer converts a whole frame, and cheaply")
    func brailleRendererThroughput() {
        // Braille packs 2x4 source pixels into each output cell, so a
        // 80 × 40 braille frame comes from 160 × 160 pixels.
        let image = makeSyntheticImage(width: 160, height: 160)
        let converter = ASCIIConverter()

        var frame: [String] = []
        let perCall = measure(10) {
            frame = converter.convertBraille(
                image, width: 80, height: 40, mode: .grayscale,
                monoThreshold: ASCIIConverter.midLuminance
            ).lines
        }
        #expect(frame.count == 40, "every requested row")
        let widths = Set(frame.map { cells($0).count })
        #expect(widths == [80], "80 cells on every row: \(widths.sorted())")
        // Braille and nothing else: every one of the 2×4 blocks becomes a
        // pattern, including the all-dark one.
        let glyphs = Set(frame.map(cells).joined())
        let strays = glyphs.filter { !("\u{2800}"..."\u{28FF}").contains($0) }
        #expect(strays.isEmpty, "braille only, found \(strays.sorted())")
        // Only "more than one": at a mid threshold each dot is on or off, so
        // a left-to-right ramp under vertical bars quantises to a handful of
        // patterns. What is being ruled out is a frame of one glyph, which a
        // packing that dropped its input would produce and every count and
        // timing bound above would accept.
        #expect(glyphs.count > 1, "the dot patterns vary across the ramp")
        #expect(
            perCall < costCeiling,
            "\(String(format: "%.1f", perCall * 1000))ms per call, ceiling \(Int(costCeiling * 1000))ms")
    }
}
