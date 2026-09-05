//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndeterminateRaster.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - A moving ramp as pictures

/// The indeterminate `.gradient` motion as a cycle of pictures — one per
/// frame, each a window onto the same ramp one step further along.
///
/// The cell renderer draws this motion by sampling the ramp four times a cell
/// and re-colouring every cell every frame: forty SGR runs a frame, thirty
/// frames a second. As pictures the ramp is sampled once a PIXEL, and what
/// changes from frame to frame is which picture a row of unchanged
/// placeholder cells names — the id in their foreground — so the bytes a
/// frame costs are the row's cells, not a colour run per cell, and no pixel
/// is ever sent twice: the whole cycle is transmitted once and replayed by
/// naming.
///
/// ## Why a picture per frame, and not one picture shifted
///
/// The protocol can crop a placement to a source rectangle, which would let
/// ONE picture of the ramp serve every frame by moving the window — but a
/// virtual placement is addressed from its cells by image id alone, and a
/// second placement of the same image would need a placement id in the
/// underline colour, which no host has been measured to honour. A picture per
/// frame needs nothing beyond what every drawing host has already been
/// measured to do: transmit by id, name by id. Forty-eight frames of a
/// forty-cell bar are forty-eight rows of 320 pixels, about a kilobyte each
/// deflated, once.
enum IndeterminateRaster {

    /// The pictures for `count` frames of `configuration`'s ramp across a
    /// `width`-cell, one-row track — or `nil` for a box with no pixels.
    static func frames(
        width: Int, count: Int, configuration: IndeterminateConfiguration,
        cellPixels: TerminalCellPixels
    ) -> [GradientRaster.Picture]? {
        guard count > 0,
            let size = GradientRaster.resolution(columns: width, rows: 1, cellPixels: cellPixels)
        else { return nil }
        // The same cyclic ramp the cells sample, quantised once at the
        // picture's own resolution so every frame reads from one table.
        let ramp = IndeterminateRenderer.cyclic(configuration.gradient)
        let steps = size.width
        let samples = Color.quantisedRamp(ramp, count: steps + 1, depth: .truecolor).map { colour in
            colour.rgbComponents.map { ($0.red, $0.green, $0.blue) } ?? (0, 0, 0)
        }
        guard samples.count == steps + 1 else { return nil }
        return (0..<count).map { frame in
            let phase = Double(frame) / Double(count)
            var row = [UInt8](repeating: 0, count: size.width * 3)
            for x in 0..<size.width {
                // The cells' arithmetic, per pixel: each pixel samples at its
                // own offset in the ramp minus the frame's shift, wrapped, so
                // the pattern scrolls rightward.
                let raw = ((Double(x) + 0.5) / Double(size.width) - phase + 1)
                    .truncatingRemainder(dividingBy: 1)
                let (r, g, b) = samples[min(steps, Int((raw * Double(steps)).rounded()))]
                row[x * 3] = r
                row[x * 3 + 1] = g
                row[x * 3 + 2] = b
            }
            var bytes = [UInt8]()
            bytes.reserveCapacity(row.count * size.height)
            for _ in 0..<size.height { bytes += row }
            return GradientRaster.Picture(bytes: bytes, width: size.width, height: size.height)
        }
    }
}

/// Everything about one frame of a moving ramp that, if it changed, means the
/// terminal is holding the wrong picture.
struct IndeterminateFrameSignature: Equatable {
    var configuration: IndeterminateConfiguration
    var width: Int
    var height: Int
    var frame: Int
    var count: Int
}
