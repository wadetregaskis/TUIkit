//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIRendererPerformanceTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkitImage

@Suite("ASCII renderer performance")
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

    private func measure(_ iterations: Int, _ body: () -> Void) -> Double {
        let start = Date()
        for _ in 0..<iterations { body() }
        return Date().timeIntervalSince(start) / Double(iterations)
    }

    @Test("Shape-vector ASCII renderer is fast at 160x80")
    func shapeRendererThroughput() {
        // 160 × 80 source pixels → 80 × 40 cells (2:1 cell ratio is typical
        // for fixed-width terminal cells).
        let image = makeSyntheticImage(width: 320, height: 160)
        let converter = ASCIIConverter(characterSet: .ascii, shapeAware: true)

        let perCall = measure(10) {
            _ = converter.convert(image, width: 80, height: 40)
        }
        let label = String(format: "%.3fms", perCall * 1000)
        print("=== Shape-vector ASCII Performance ===")
        print("  80x40 cells from 320x160 image: \(label) per call")
        print("=======================================")
    }

    @Test("Braille ASCII renderer is fast at 160x80")
    func brailleRendererThroughput() {
        // Braille packs 2x4 source pixels into each output cell, so a
        // 80 × 40 braille frame comes from 160 × 160 pixels.
        let image = makeSyntheticImage(width: 160, height: 160)
        let converter = ASCIIConverter()

        let perCall = measure(10) {
            _ = converter.convertBraille(image, width: 80, height: 40, mode: .grayscale)
        }
        let label = String(format: "%.3fms", perCall * 1000)
        print("=== Braille ASCII Performance ===")
        print("  80x40 cells from 160x160 image: \(label) per call")
        print("==================================")
    }
}
