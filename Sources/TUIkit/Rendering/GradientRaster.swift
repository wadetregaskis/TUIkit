//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientRaster.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - A ramp as pixels

/// A gradient rendered as a picture, for the terminals that draw pictures.
///
/// The cell renderer paints a ramp one colour per cell — forty steps across a
/// forty-cell bar, and a diagonal or a circle as a staircase of them. Where the
/// terminal will place an image in its cell grid (``KittyGraphics``), the same
/// ramp can be a picture instead: one colour per PIXEL, sixteen or more of
/// them a cell, with no palette quantisation and no contrast floor, drawn by
/// exactly the cells the ramp would have painted. This is the picture.
///
/// ## What it asks of the terminal, and what the terminal does with it
///
/// A virtual placement is fit to its cell box **with the aspect ratio
/// preserved and the picture centred** (`Documentation/Compressed image
/// transfer.md` §1.1) — the terminal never stretches. So a horizontal ramp
/// cannot be sent one pixel tall and stretched to the row, however tempting:
/// it would be drawn as a hairline across the middle of the cells. The
/// picture has to carry the box's own proportions, and the smallest picture
/// that does is the box's pixel size divided by a common factor of its width
/// and height. ``resolution(columns:rows:cellPixels:)`` picks that factor, and
/// keeps at least ``minimumPixelsPerCell`` a cell in each direction so the
/// reduction never flattens the ramp — a 17×8-cell box divides by 272 to a
/// single pixel, which is a flat colour, not a gradient.
///
/// The rows a horizontal ramp then carries are identical, and that is what
/// ``SystemZlib`` is for: seventeen copies of one row deflate to little more
/// than the row (`Documentation/Terminal graphics protocols.md` §10 has the
/// measurements), so the picture costs on the wire about what the one-pixel
/// strip would have.
///
/// ## The same ramp as the cells would have painted
///
/// The colours come from ``RampSampler`` — the sampler the cell renderer
/// uses, built at PIXEL resolution over the same frame, so the picture and
/// the cells agree about where every colour falls. A `.gradientExtent(.subtree)`
/// window into a larger ramp is honoured the same way: the frame's origin and
/// extent scale with the cell, and the sampler does the rest. The one thing
/// that changes is the aspect handed to the geometries with a centre: a cell
/// is twice as tall as it is wide, a pixel is square, so the sampler is told
/// `1` and a circle comes out round in pixels for the same reason it came
/// out round in cells.
enum GradientRaster {

    /// A picture ready to transmit.
    struct Picture: Equatable {
        var bytes: [UInt8]
        var width: Int
        var height: Int
        /// Always opaque: a ramp has no alpha to send.
        var format: KittyGraphics.PixelFormat { .rgb }
    }

    /// The fewest pixels a cell keeps in either direction after the reduction.
    /// Eight across a cell is 320 steps along a forty-cell bar — smoother than
    /// any terminal's font will show — and at a 16×34 cell the reduction that
    /// keeps it is exactly 2, so the common picture is 8×17 pixels a cell.
    static let minimumPixelsPerCell = 8

    /// The size to transmit a `columns` × `rows` box at: the box's pixel size
    /// divided by the largest common factor that leaves
    /// ``minimumPixelsPerCell`` in each direction, so the picture keeps the
    /// box's exact proportions and the terminal's fit is exact.
    ///
    /// - Returns: the picture's size and the factor, or `nil` for a box with
    ///   no pixels.
    static func resolution(
        columns: Int, rows: Int, cellPixels: TerminalCellPixels
    ) -> (width: Int, height: Int, factor: Int)? {
        let fullWidth = columns * cellPixels.width
        let fullHeight = rows * cellPixels.height
        guard columns > 0, rows > 0, fullWidth > 0, fullHeight > 0 else { return nil }
        let common = greatestCommonDivisor(fullWidth, fullHeight)
        // The largest divisor of the gcd that keeps the minimum — walking
        // down from the gcd itself, which is what makes 2 the answer at a
        // 16×34 cell: 34 shares only the 2 with any multiple of 16.
        var factor = 1
        var candidate = common
        while candidate > 1 {
            if common.isMultiple(of: candidate),
                fullWidth / candidate >= columns * minimumPixelsPerCell,
                fullHeight / candidate >= rows * minimumPixelsPerCell
            {
                factor = candidate
                break
            }
            candidate -= 1
        }
        return (fullWidth / factor, fullHeight / factor, factor)
    }

    /// The pixels for `paint` over a `columns` × `rows` box that sits at
    /// `frame` within the ramp's extent — or `nil` when the paint is not a
    /// ramp, or is a degenerate one, which is the cell renderer's answer too:
    /// paint flat, and a flat colour is cells. Also `nil` when a colour of the
    /// ramp has no RGB: a stop the terminal decides and has not reported, and the
    /// stretch of the ramp that snaps to it. A pixel cannot hold that colour, so
    /// the cells draw it, and they can spell it.
    ///
    /// - Parameters:
    ///   - paint: The paint, already resolved against the palette.
    ///   - frame: Where the box sits in the ramp's extent, in cells — the
    ///     view's own box unless a `.gradientExtent(.subtree)` named a larger
    ///     one — with `width`/`height` the extent's size.
    ///   - columns: The box's width, in cells.
    ///   - rows: The box's height, in cells.
    ///   - cellPixels: The size of one cell, in pixels.
    static func picture(
        paint: Paint, frame: GradientFrame, columns: Int, rows: Int, cellPixels: TerminalCellPixels
    ) -> Picture? {
        guard let size = resolution(columns: columns, rows: rows, cellPixels: cellPixels) else {
            return nil
        }
        // The extent in pixels — every cell coordinate times the cell — and
        // the sampler over it at that resolution. The factor is applied by
        // SAMPLING every `factor`-th pixel rather than by shrinking the frame,
        // because the frame's origin need not divide by it.
        let pixelFrame = GradientFrame(
            originX: frame.originX * cellPixels.width,
            originY: frame.originY * cellPixels.height,
            width: max(1, frame.width) * cellPixels.width,
            height: max(1, frame.height) * cellPixels.height)
        guard
            let sampler = RampSampler(
                paint: paint, extent: pixelFrame, depth: .truecolor, cellAspect: 1)
        else { return nil }
        let factor = size.factor
        let centre = (factor - 1) / 2
        // The sampler's colours are `.rgb` between two measurable stops — a
        // resolved ramp interpolates in RGB or OKLab and lands in RGB — but a ramp
        // of palette entries lands where the palette says, so read them once. A
        // colour with no RGB declines the picture. It used to be sent as black.
        var colours: [(UInt8, UInt8, UInt8)] = []
        colours.reserveCapacity(sampler.ramp.count)
        for colour in sampler.ramp {
            guard let rgb = colour.rgbComponents else { return nil }
            colours.append((rgb.red, rgb.green, rgb.blue))
        }
        var bytes = [UInt8](repeating: 0, count: size.width * size.height * 3)
        var offset = 0
        for y in 0..<size.height {
            let term = sampler.rowTerm(y * factor + centre)
            if !sampler.variesAcrossRow {
                // One colour along the row: fill it without asking per pixel.
                let (r, g, b) = colours[sampler.entry(column: centre, rowTerm: term)]
                for _ in 0..<size.width {
                    bytes[offset] = r
                    bytes[offset + 1] = g
                    bytes[offset + 2] = b
                    offset += 3
                }
                continue
            }
            for x in 0..<size.width {
                let (r, g, b) = colours[sampler.entry(column: x * factor + centre, rowTerm: term)]
                bytes[offset] = r
                bytes[offset + 1] = g
                bytes[offset + 2] = b
                offset += 3
            }
        }
        return Picture(bytes: bytes, width: size.width, height: size.height)
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (a, b)
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }
}

// MARK: - What decides whether a ramp picture has changed

/// Everything about a ramp picture that, if it changed, means the terminal is
/// holding the wrong one — the counterpart of ``TerminalImageSignature`` for
/// a gradient, and like it a typed value rather than a description, so a new
/// knob cannot be forgotten by being left out of a format string.
struct GradientImageSignature: Equatable {
    /// The paint, resolved — every stop, the geometry, the colour space.
    var paint: Paint
    /// Where the box sits in the ramp's extent, and how big the extent is: a
    /// window into a `.gradientExtent(.subtree)` ramp is a different picture
    /// at every scroll position.
    var frame: GradientFrame
    /// The picture's resolution, which follows the box and the cell.
    var width: Int
    var height: Int
}

extension GradientImageSignature: ImageStoreSignature {
    /// Where the box sits in its extent, and the picture's size: each row of a
    /// list under one `.gradientExtent(.subtree)` ramp is a bucket of its own.
    var storeBucket: [Int] {
        [frame.originX, frame.originY, frame.width, frame.height, width, height]
    }
}
