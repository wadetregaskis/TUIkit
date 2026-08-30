//  🖥️ TUIkit — Terminal UI Kit for Swift
//  QuantisedRampTests.swift
//
//  Banding is a property of a SEQUENCE, so these assert on the sequence: the
//  run-length-encoded palette indices a ramp quantises to.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Quantised ramps")
struct QuantisedRampTests {

    /// The run-length encoding of a ramp's palette indices — the shape the
    /// defect is visible in, and the shape a headless test can see.
    private func runs(_ stops: [Color], count: Int = 40) -> [(index: Int, length: Int)] {
        let ramp = Color.quantisedRamp(stops: stops, count: count, depth: .palette256)
        var result: [(index: Int, length: Int)] = []
        for colour in ramp {
            guard case .palette256(let index) = colour.value else { continue }
            if var last = result.last, last.index == Int(index) {
                last.length += 1
                result[result.count - 1] = last
            } else {
                result.append((index: Int(index), length: 1))
            }
        }
        return result
    }

    /// Whether every channel moves the way the source ramp moves it — the
    /// property "no out-of-place colours" actually means.
    private func violations(_ stops: [Color], count: Int = 40) -> Int {
        let ramp = Color.quantisedRamp(stops: stops, count: count, depth: .palette256)
        let source = (0..<count).map {
            Color.interpolate(stops: stops, phase: Double($0) / Double(count - 1))
        }
        var breaks = 0
        for index in 1..<ramp.count {
            guard let a = ramp[index - 1].rgbComponents, let b = ramp[index].rgbComponents,
                let sa = source[index - 1].rgbComponents, let sb = source[index].rgbComponents
            else { continue }
            let entry = [Int(b.red) - Int(a.red), Int(b.green) - Int(a.green), Int(b.blue) - Int(a.blue)]
            let want = [Int(sb.red) - Int(sa.red), Int(sb.green) - Int(sa.green), Int(sb.blue) - Int(sa.blue)]
            let against = zip(entry, want).contains { step, wanted in
                step != 0 && (wanted == 0 || (step > 0) != (wanted > 0))
            }
            if against {
                breaks += 1
            }
        }
        return breaks
    }

    /// The reported case, by name: the Example's default track gradient.
    private let trackDefault: [Color] = [.rgb(0xFF, 0x50, 0x50), .rgb(0xFF, 0xC8, 0x50), .rgb(0x50, 0xDC, 0x78)]
    /// The unfilled-track ramp the track editor ships.
    private let cool: [Color] = [.rgb(32, 48, 80), .rgb(60, 110, 165), .rgb(120, 200, 220)]

    @Test("The reported ramp has no out-of-place entries left")
    func trackDefaultIsMonotone() {
        #expect(violations(trackDefault) == 0, "runs: \(runs(trackDefault))")
    }

    @Test("Nor does the cool ramp")
    func coolIsMonotone() {
        #expect(violations(cool) == 0, "runs: \(runs(cool))")
    }

    @Test("The blue-zero corner is gone from the reported ramp")
    func saturatedCornerIsGone() {
        // 202, 208, 214 are the cube's blue=0 entries that used to appear as
        // one- and two-cell speckles between their blue=95 neighbours.
        let indices = Set(runs(trackDefault).map(\.index))
        #expect(indices.isDisjoint(with: [202, 208, 214]), "runs: \(runs(trackDefault))")
    }

    @Test("A ramp that was already monotone is left exactly as it was")
    func alreadyGoodRampIsUntouched() {
        // Pure red to pure blue crosses the cube diagonally with no lateral
        // excursions; the repair must be a no-op, entry for entry.
        let stops: [Color] = [.rgb(255, 0, 0), .rgb(0, 0, 255)]
        let repaired = Color.quantisedRamp(stops: stops, count: 40, depth: .palette256)
        let perCell = (0..<40).map {
            Color.interpolate(stops: stops, phase: Double($0) / 39).downsampledToPalette256()
        }
        #expect(repaired == perCell, "a clean ramp was rewritten")
    }

    @Test("Truecolor is handed the interpolation, untouched")
    func truecolorIsNotQuantised() {
        let ramp = Color.quantisedRamp(stops: trackDefault, count: 8, depth: .truecolor)
        #expect(ramp.allSatisfy { if case .rgb = $0.value { return true } else { return false } })
    }

    @Test("Every ramp still spans its stops")
    func endpointsSurvive() {
        // The repair retires entries; it must never retire so many that the
        // ramp stops going anywhere.
        for stops in [trackDefault, cool] {
            let indices = Set(runs(stops).map(\.index))
            #expect(indices.count >= 4, "collapsed to \(runs(stops))")
        }
    }

    // MARK: - The cache

    /// The cache must not be able to change the answer — which is the whole
    /// risk of consulting it before the ramp is sampled, and of retiring a
    /// generation instead of the whole table.
    @Test("A cached ramp is the ramp")
    func cacheReturnsTheSameRamp() {
        let stops: [Color] = [.rgb(255, 80, 80), .rgb(80, 160, 255)]
        let first = Color.quantisedRamp(stops: stops, count: 40, depth: .palette256)
        for _ in 0..<3 {
            #expect(Color.quantisedRamp(stops: stops, count: 40, depth: .palette256) == first)
        }
        // A different width is a different ramp, not the cached one resized.
        let narrow = Color.quantisedRamp(stops: stops, count: 12, depth: .palette256)
        #expect(narrow.count == 12)
        #expect(narrow != Array(first.prefix(12)))
    }

    /// Past the generation size, so the turnover actually happens — the answers
    /// must survive it. A `removeAll` cliff passed this too; what it would not
    /// survive is being wrong about which entry belongs to which key, which is
    /// what promoting a stale entry could get wrong.
    @Test("Answers survive a cache turnover")
    func answersSurviveTurnover() {
        let stops: [Color] = [.rgb(20, 200, 120), .rgb(240, 80, 20)]
        let before = Color.quantisedRamp(stops: stops, count: 33, depth: .palette256)
        // Distinct keys by width; 600 crosses the 512-entry generation.
        for width in 3..<603 {
            _ = Color.quantisedRamp(stops: stops, count: width, depth: .palette256)
        }
        #expect(Color.quantisedRamp(stops: stops, count: 33, depth: .palette256) == before)
    }

    /// The guards the early lookup skips past have to keep holding: below three
    /// cells there is no sequence to repair, and the answer is the plain
    /// interpolation whatever the cache has seen.
    @Test("Short ramps and non-256 depths are never served from the cache")
    func shortRampsBypassTheCache() {
        let stops: [Color] = [.rgb(0, 0, 0), .rgb(255, 255, 255)]
        for count in 0...2 {
            let ramp = Color.quantisedRamp(stops: stops, count: count, depth: .palette256)
            #expect(ramp.count == count)
            #expect(ramp.allSatisfy { $0.rgbComponents != nil }, "quantised a ramp too short to repair")
        }
        let plain = Color.quantisedRamp(stops: stops, count: 40, depth: .truecolor)
        #expect(plain.allSatisfy { if case .rgb = $0.value { return true } else { return false } })
    }
}
