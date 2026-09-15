//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateGradientShiftTests.swift
//
//  The indeterminate `.gradient` motion slides one ramp across the track, so
//  every frame of its pass is that ramp shifted by a whole number of samples:
//  in glyphs, four samples a cell; as pictures, one a pixel.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("An indeterminate gradient's frames are whole-sample shifts")
struct IndeterminateGradientShiftTests {

    /// The ramp `.gradient()` slides, sampled `count` times in truecolor as the
    /// renderer and the raster sample it, as RGB triples.
    private func samples(count: Int) -> [[UInt8]] {
        Color.quantisedRamp(IndeterminateRenderer.cyclic(nil), count: count, depth: .truecolor).map { colour in
            colour.rgbComponents.map { [$0.red, $0.green, $0.blue] } ?? []
        }
    }

    /// The truecolor foreground under each cell of a row whose glyphs are one cell
    /// wide: a run's colour for each character in it.
    private func cellColours(_ row: String) -> [[UInt8]] {
        var cells: [[UInt8]] = []
        var current: [UInt8] = []
        for chunk in row.split(separator: "\u{1B}", omittingEmptySubsequences: true) {
            guard chunk.hasPrefix("["), let end = chunk.firstIndex(of: "m") else { continue }
            let parameters = chunk[chunk.index(after: chunk.startIndex)..<end].split(separator: ";")
            if parameters.count >= 5, parameters[0] == "38", parameters[1] == "2" {
                current = parameters[2...4].compactMap { UInt8($0) }
            }
            cells += Array(repeating: current, count: chunk[chunk.index(after: end)...].count)
        }
        return cells
    }

    /// Frame i of a pass of F frames is the ramp shifted by s = ⌊i·4W/F⌋ samples:
    /// cell c shows sample (4c − s) mod 4W. Every cell of a frame is shifted by the
    /// same whole number of samples, so the ramp slides rather than shimmering. The
    /// frames used to round each cell's own float position in the ramp, and where
    /// that position was a tie the cells of one frame rounded different ways: at
    /// 3 cells, frame 3 of 72 was no whole shift of the ramp at all.
    @Test("Every glyph frame at widths 1-40 is the ramp shifted by ⌊i·4W/F⌋ samples")
    func glyphFramesAreWholeShifts() {
        ColorDepth.withCurrent(.truecolor) {
            for width in 1...40 {
                let states = IndeterminateRenderer.samplesPerCell * width
                let ramp = samples(count: states + 1)
                let cycle = IndeterminateRenderer.cycle(
                    width: width, style: .gradient(), fillColor: .white, backgroundColor: .black,
                    accentColor: .white, palette: SystemPalette.green, speed: .standard)
                let count = cycle.frames.count
                var notShifts: [Int] = []
                var misplaced: [Int] = []
                for (index, frame) in cycle.frames.enumerated() {
                    let cells = cellColours(frame)
                    func isShift(_ shift: Int) -> Bool {
                        cells.count == width
                            && cells.indices.allSatisfy { column in
                                cells[column] == ramp[((4 * column - shift) % states + states) % states]
                            }
                    }
                    if !(0..<states).contains(where: isShift) { notShifts.append(index) }
                    if !isShift(index * states / count) { misplaced.append(index) }
                }
                #expect(notShifts.isEmpty, "\(width) cells: frames \(notShifts) of \(count) are no whole shift")
                #expect(misplaced.isEmpty, "\(width) cells: frames \(misplaced) of \(count) are not shifted ⌊i·4W/F⌋")
            }
        }
    }

    /// A 20-cell picture at a 16×34-pixel cell is 160 pixels wide, so its ramp has
    /// 160 samples, and pixel x of frame i shows sample (x + 1 − ⌊i·160/F⌋) mod 160.
    /// Frame 0 therefore shows each of the 160 samples once. Each pixel used to round
    /// its own float position, (x + 0.5)/160 × 160, which came out a hair under the
    /// half at many pixels, so frame 0 drew 122 distinct samples and repeated others.
    @Test("Frame i of a 20-cell picture is the ramp shifted by ⌊i·160/F⌋ pixels, and frame 0 uses all 160 samples")
    func pictureFramesAreWholeShifts() throws {
        let count = 72
        let pictures = try #require(
            IndeterminateRaster.frames(
                width: 20, shifts: IndeterminateRaster.shifts(count: count, pixels: 160).distinct,
                configuration: IndeterminateStyle.gradient().configuration,
                cellPixels: TerminalCellPixels(width: 16, height: 34)))
        let ramp = samples(count: 161)
        #expect(pictures.count == count)
        for (index, picture) in pictures.enumerated() {
            #expect(picture.width == 160)
            let row = stride(from: 0, to: 160 * 3, by: 3).map { Array(picture.bytes[$0..<($0 + 3)]) }
            let shift: Int = index * 160 / count
            let misdrawn = (0..<160).filter { (x: Int) -> Bool in
                let sample: Int = ((x + 1 - shift) % 160 + 160) % 160
                return row[x] != ramp[sample]
            }
            // At frame 0, x + 1 mod 160 over the 160 pixels is every sample once.
            #expect(misdrawn.isEmpty, "frame \(index), shift \(shift): pixels \(misdrawn)")
        }
    }
}
