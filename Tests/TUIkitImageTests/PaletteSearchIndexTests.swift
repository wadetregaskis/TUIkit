//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteSearchIndexTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// The candidate index against the walk it replaces.
///
/// The index is an optimisation of an exact search, so it is held to the
/// exact search's answers — including its tie-break — everywhere a cell's
/// bound could be wrong: at every cell corner, where a colour is farthest from
/// its cell's centre, and across a strided sample of the whole gamut.
@Suite("Palette search index")
struct PaletteSearchIndexTests {

    /// The walk, transcribed from `nearestIndex(to:)` before the index existed.
    private static func walked(_ palette: ASCIIPalette, _ pixel: RGBA) -> Int {
        let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
        var best = 0
        var bestDistance = Double.infinity
        for (index, entry) in palette.entries.enumerated() {
            let dl = target.l - entry.lightness, da = target.a - entry.a, db = target.b - entry.b
            let distance = dl * dl + da * da + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func corners() -> [RGBA] {
        var first = [Int](repeating: -1, count: 32)
        var last = [Int](repeating: 0, count: 32)
        for value in 0...255 {
            let bucket = Int(ASCIIPalette.quantisationBucket[value])
            if first[bucket] < 0 { first[bucket] = value }
            last[bucket] = value
        }
        // The perceptual spacing leaves a few buckets with no byte in them;
        // those cells have no corners, and no pixel ever reaches them.
        let filled = (0..<32).filter { first[$0] >= 0 }
        var out: [RGBA] = []
        for r in filled {
            for g in filled {
                for b in filled {
                    out.append(RGBA(r: UInt8(first[r]), g: UInt8(first[g]), b: UInt8(first[b])))
                    out.append(RGBA(r: UInt8(last[r]), g: UInt8(last[g]), b: UInt8(last[b])))
                }
            }
        }
        return out
    }

    private static func strided(_ step: Int) -> [RGBA] {
        var out: [RGBA] = []
        var value = 0
        while value < 1 << 24 {
            out.append(RGBA(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF)))
            value += step
        }
        return out
    }

    /// A graded field with a red patch — the shape of a photograph, so the
    /// adaptive palette derives something other than a ramp.
    private static func photograph() -> RGBAImage {
        var pixels: [RGBA] = []
        for y in 0..<64 {
            for x in 0..<64 {
                if y > 54 && x > 54 {
                    pixels.append(RGBA(r: 230, g: 30, b: 30))
                } else {
                    let shade = UInt8(clamping: 40 + (x * 180) / 64)
                    pixels.append(RGBA(r: shade, g: shade, b: UInt8(clamping: Int(shade) + 6 + y / 3)))
                }
            }
        }
        return RGBAImage(width: 64, height: 64, pixels: pixels)
    }

    private static let subjects: [String: ASCIIPalette] = [
        "ansi256": .ansi256,
        "shades256": .shades(256),
        "spread64": .spread(64),
        "optimal32": ASCIIPalette.adaptive(32, by: .leastError).derived(from: photograph()),
    ]

    @Test("Every cell corner agrees with the walk, tie-break included", arguments: subjects.keys.sorted())
    func cornersAgree(_ name: String) throws {
        let palette = try #require(Self.subjects[name])
        var disagreements = 0
        for pixel in Self.corners() where palette.nearestIndex(to: pixel) != Self.walked(palette, pixel) {
            disagreements += 1
        }
        #expect(disagreements == 0, "\(name): \(disagreements) corner colours differ from the walk")
    }

    @Test("A stride across the gamut agrees with the walk", arguments: subjects.keys.sorted())
    func gamutSampleAgrees(_ name: String) throws {
        let palette = try #require(Self.subjects[name])
        var disagreements = 0
        for pixel in Self.strided(97) where palette.nearestIndex(to: pixel) != Self.walked(palette, pixel) {
            disagreements += 1
        }
        #expect(disagreements == 0, "\(name): \(disagreements) sampled colours differ from the walk")
    }

    @Test("The lists are short: a few candidates a cell, not the palette")
    func listsAreShort() {
        let index = ASCIIPalette.ansi256.searchIndex
        let perCell = Double(index.candidateCount) / Double(ASCIIPalette.quantisationCells)
        #expect(perCell < 12, "\(perCell) candidates a cell against 240 entries")
    }

    @Test("Palettes below the threshold still walk; every copy of a large one shares an index")
    func thresholdAndSharing() {
        #expect(ASCIIPalette.ansi16.entries.count == ASCIIPalette.indexedEntryThreshold)
        let one = ASCIIPalette.shades(256)
        let copy = one
        #expect(one.searchIndex === copy.searchIndex, "a copy shares its original's index")
        let another = ASCIIPalette.shades(256)
        #expect(one.searchIndex === another.searchIndex, "the same colours share one index across instances")
        #expect(one.searchIndex !== ASCIIPalette.ansi256.searchIndex)
    }
}
