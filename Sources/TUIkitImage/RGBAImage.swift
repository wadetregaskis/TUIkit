//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RGBAImage.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - RGBA Pixel

/// A single pixel with red, green, blue, and alpha channels.
///
/// Used as the intermediate representation for image data before
/// ASCII art conversion. Each channel is stored as a `UInt8` (0-255).
public struct RGBA: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    /// Creates an opaque pixel with the given RGB values.
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = .max) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

// MARK: - Luminance

extension RGBA {

    /// The perceived luminance using ITU-R BT.601 coefficients.
    ///
    /// Returns a value in the range 0.0 (black) to 255.0 (white).
    public var luminance: Double {
        // `Double(Int(r))`, not `Double(r)`, and not a typo: Swift has no
        // `Double.init(UInt8)`, so the short spelling binds the generic
        // `init<T: BinaryInteger>` and — unspecialised, in a debug build —
        // calls it through a protocol witness. Three of those, on a property
        // that runs per PIXEL on the graphics path. Going via `Int` picks a
        // concrete initializer; the value is identical, since every byte is
        // exactly representable as an Int and as a Double.
        Double(Int(r)) * 0.299 + Double(Int(g)) * 0.587 + Double(Int(b)) * 0.114
    }
}

// MARK: - RGBAImage

/// A raw image stored as a flat array of RGBA pixels in row-major order.
///
/// This is the platform-independent representation produced by
/// `ImageLoader` implementations and consumed by `ASCIIConverter`.
public struct RGBAImage: Sendable {
    /// Image width in pixels.
    public let width: Int

    /// Image height in pixels.
    public let height: Int

    /// Row-major pixel data (`width * height` elements).
    public private(set) var pixels: [RGBA]

    /// Creates an image from dimensions and pixel data.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - pixels: Pixel data in row-major order. Must contain `width * height` elements.
    public init(width: Int, height: Int, pixels: [RGBA]) {
        precondition(pixels.count == width * height, "Pixel count must match width * height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

// MARK: - Pixel Access

extension RGBAImage {

    /// Returns the pixel at the given coordinates.
    ///
    /// - Parameters:
    ///   - x: Column (0-based, left to right).
    ///   - y: Row (0-based, top to bottom).
    /// - Returns: The RGBA pixel value.
    public func pixel(at x: Int, _ y: Int) -> RGBA {
        pixels[y * width + x]
    }

    /// Sets the pixel at the given coordinates.
    ///
    /// - Parameters:
    ///   - x: Column (0-based).
    ///   - y: Row (0-based).
    ///   - value: The new pixel value.
    public mutating func setPixel(at x: Int, _ y: Int, value: RGBA) {
        pixels[y * width + x] = value
    }

    /// Replaces every pixel with `transform(pixel)`, in place.
    ///
    /// One pass over the buffer rather than a `map` into a second one: this
    /// runs on the scaled image at conversion time, and an extra allocation the
    /// size of the render grid is the kind of thing that shows up in a profile
    /// of an image redrawn on every spinner tick.
    /// Through an unsafe buffer rather than an index loop: this runs once per
    /// non-true-colour conversion and again per mono recolouring, over a
    /// megapixel, and a debug build charges a bounds check and an exclusivity
    /// check for every subscript at both ends.
    public mutating func mapPixels(_ transform: (RGBA) -> RGBA) {
        pixels.withUnsafeMutableBufferPointer { buffer in
            for index in 0..<buffer.count { buffer[index] = transform(buffer[index]) }
        }
    }

    /// Adds an error value to the pixel at the given coordinates (for dithering).
    ///
    /// Clamps each channel to the valid 0-255 range.
    ///
    /// - Parameters:
    ///   - x: Column.
    ///   - y: Row.
    ///   - rError: Red channel error.
    ///   - gError: Green channel error.
    ///   - bError: Blue channel error.
    public mutating func addError(at x: Int, _ y: Int, rError: Int16, gError: Int16, bError: Int16) {
        let index = y * width + x
        let pixel = pixels[index]
        pixels[index] = RGBA(
            r: UInt8(clamping: Int16(pixel.r) + rError),
            g: UInt8(clamping: Int16(pixel.g) + gError),
            b: UInt8(clamping: Int16(pixel.b) + bError)
        )
    }
}

// MARK: - Image Scaling

extension RGBAImage {

    /// Returns a scaled copy using nearest-neighbor interpolation.
    ///
    /// - Parameters:
    ///   - targetWidth: The desired width.
    ///   - targetHeight: The desired height.
    /// - Returns: A new image with the specified dimensions — or an empty
    ///   image when the target is empty, or when this image is: there is no
    ///   pixel to sample. (An empty image is an ordinary value here; a decode
    ///   can succeed with one.)
    public func scaled(to targetWidth: Int, _ targetHeight: Int) -> RGBAImage {
        guard targetWidth > 0, targetHeight > 0, width > 0, height > 0 else {
            return RGBAImage(width: 0, height: 0, pixels: [])
        }

        var result = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: targetWidth * targetHeight)

        for y in 0..<targetHeight {
            let srcY = y * height / targetHeight
            for x in 0..<targetWidth {
                let srcX = x * width / targetWidth
                result[y * targetWidth + x] = pixel(at: srcX, srcY)
            }
        }

        return RGBAImage(width: targetWidth, height: targetHeight, pixels: result)
    }

    /// Returns a scaled copy using bilinear interpolation for smoother results.
    ///
    /// All four channels are interpolated, alpha included — see the note at
    /// the assignment, which is where it was being dropped.
    ///
    /// - Parameters:
    ///   - targetWidth: The desired width.
    ///   - targetHeight: The desired height.
    /// - Returns: A new image with the specified dimensions — or an empty
    ///   image when the target is empty, or when this image is. The source
    ///   guard is load-bearing, not tidy: the edge clamps below are written
    ///   against `sourceWidth - 1`, which for an empty source is `-1`, and an
    ///   index of `-1` into the unsafe buffer is a read off its front.
    public func scaledBilinear(to targetWidth: Int, _ targetHeight: Int) -> RGBAImage {
        guard targetWidth > 0, targetHeight > 0, width > 0, height > 0 else {
            return RGBAImage(width: 0, height: 0, pixels: [])
        }

        let xRatio = Double(width) / Double(targetWidth)
        let yRatio = Double(height) / Double(targetHeight)
        let sourceWidth = width
        let sourceHeight = height

        // Call-free, deliberately, and bit-exact: the same operands in the same
        // order, only without the machinery around them.
        //
        // The arithmetic here was never the cost. Compiled at -Onone the inner
        // loop made 41 non-inlined calls and about 26 atomic retain/release
        // pairs PER OUTPUT PIXEL — four `pixel(at:)` calls each retaining and
        // releasing the array buffer three times, sixteen `Double.init` calls
        // that do NOT resolve to a concrete initializer (there is no
        // `Double.init(UInt8)`, so each goes through a protocol witness), and
        // four calls to a private interpolation helper. A megapixel image is
        // forty million calls to convert some bytes to Doubles.
        //
        // `Double(Int(x))` rather than `Double(x)` is the same value by a
        // concrete initializer; the interpolation is written out; the reads and
        // writes go through unsafe buffers. A debug build optimises none of
        // this away on its own, and a debug build is what the framework is
        // developed and demoed in.
        let count = targetWidth * targetHeight
        let scaled = pixels.withUnsafeBufferPointer { source -> [RGBA] in
            [RGBA](unsafeUninitializedCapacity: count) { destination, initialized in
                for y in 0..<targetHeight {
                    let sourceY = Double(y) * yRatio
                    var y0 = Int(sourceY)
                    if y0 > sourceHeight - 1 { y0 = sourceHeight - 1 }
                    var y1 = y0 + 1
                    if y1 > sourceHeight - 1 { y1 = sourceHeight - 1 }
                    let yFrac = sourceY - Double(y0)
                    let oneMinusY = 1.0 - yFrac
                    let row0 = y0 * sourceWidth
                    let row1 = y1 * sourceWidth
                    let out = y * targetWidth

                    for x in 0..<targetWidth {
                        let sourceX = Double(x) * xRatio
                        var x0 = Int(sourceX)
                        if x0 > sourceWidth - 1 { x0 = sourceWidth - 1 }
                        var x1 = x0 + 1
                        if x1 > sourceWidth - 1 { x1 = sourceWidth - 1 }
                        let xFrac = sourceX - Double(x0)
                        let oneMinusX = 1.0 - xFrac

                        let p00 = source[row0 + x0]
                        let p10 = source[row0 + x1]
                        let p01 = source[row1 + x0]
                        let p11 = source[row1 + x1]
                        // PREMULTIPLIED: each colour is weighted by its own
                        // coverage as well as its distance, and divided back
                        // out at the end. Straight RGBA cannot be filtered
                        // channel-wise — a transparent pixel's colour is
                        // meaningless, yet it got full weight, and the decoder
                        // writes every fully transparent pixel as BLACK, so a
                        // soft edge pulled its opaque neighbours toward black:
                        // a dark fringe one pixel wide around every PNG with a
                        // transparent surround, on a terminal that composites
                        // the pixels itself. Opaque images are unchanged: with
                        // every coverage 255 the weights are the plain ones.
                        let w00 = oneMinusX * oneMinusY
                        let w10 = xFrac * oneMinusY
                        let w01 = oneMinusX * yFrac
                        let w11 = xFrac * yFrac
                        let k00 = w00 * Double(Int(p00.a))
                        let k10 = w10 * Double(Int(p10.a))
                        let k01 = w01 * Double(Int(p01.a))
                        let k11 = w11 * Double(Int(p11.a))
                        let coverage = k00 + k10 + k01 + k11

                        // `Double(Int(byte))`, not `Double(byte)`, and not a
                        // typo: Swift has no `Double.init(UInt8)`, so the short
                        // spelling binds the generic `init<T: BinaryInteger>`
                        // and — unspecialised, in a debug build — calls it
                        // through a protocol witness. Going via `Int` picks a
                        // concrete initializer. Same value, every time: every
                        // byte is exactly representable as a Double, and as an
                        // Int on the way. See the note above the loop.
                        // A fully transparent sample has no colour to keep,
                        // and `0 / 0` would be NaN: it takes zero outright.
                        let red = coverage > 0
                            ? (Double(Int(p00.r)) * k00 + Double(Int(p10.r)) * k10
                                + Double(Int(p01.r)) * k01 + Double(Int(p11.r)) * k11) / coverage
                            : 0
                        let green = coverage > 0
                            ? (Double(Int(p00.g)) * k00 + Double(Int(p10.g)) * k10
                                + Double(Int(p01.g)) * k01 + Double(Int(p11.g)) * k11) / coverage
                            : 0
                        let blue = coverage > 0
                            ? (Double(Int(p00.b)) * k00 + Double(Int(p10.b)) * k10
                                + Double(Int(p01.b)) * k01 + Double(Int(p11.b)) * k11) / coverage
                            : 0
                        // Alpha is interpolated like every other channel. It
                        // used to be dropped — `RGBA(r:g:b:)` defaults it to
                        // opaque — so this function silently flattened every
                        // transparent picture it touched.
                        let alpha = coverage

                        destination[out + x] = RGBA(
                            r: UInt8(clamping: Int(red.rounded())),
                            g: UInt8(clamping: Int(green.rounded())),
                            b: UInt8(clamping: Int(blue.rounded())),
                            a: UInt8(clamping: Int(alpha.rounded())))
                    }
                }
                initialized = count
            }
        }
        return RGBAImage(width: targetWidth, height: targetHeight, pixels: scaled)
    }

    /// The picture composited over black: every colour multiplied by its own
    /// coverage, and every pixel made opaque.
    ///
    /// For the glyph renderers, which read a pixel's colour and never its
    /// alpha. They composited over black by ACCIDENT for as long as the
    /// resampler filtered straight alpha — the decoder writes a transparent
    /// pixel as black, so a soft edge came out of the filter already
    /// darkened — and `scaledBilinear` now filters premultiplied, which hands
    /// them the true colour with the coverage beside it. This is that
    /// accident made deliberate, in one place.
    public func flattenedOverBlack() -> RGBAImage {
        guard pixels.contains(where: { $0.a != 255 }) else { return self }
        var flattened = self
        flattened.mapPixels { pixel in
            let coverage = Int(pixel.a)
            return RGBA(
                r: UInt8(Int(pixel.r) * coverage / 255),
                g: UInt8(Int(pixel.g) * coverage / 255),
                b: UInt8(Int(pixel.b) * coverage / 255))
        }
        return flattened
    }

    /// Returns a copy with each `factor × factor` block averaged into one
    /// pixel — true area sampling.
    ///
    /// ``scaledBilinear(to:_:)`` reads only a 2×2 neighbourhood per output
    /// pixel, so on heavy downscales it effectively point-samples and can
    /// alias fine textures. Scaling to `factor`× the wanted grid and
    /// box-reducing gives every output pixel a proper area average — this
    /// is what backs the image renderers' supersampling. A `factor` of 1
    /// (or an image too small to reduce) returns `self`.
    public func boxReduced(by factor: Int) -> RGBAImage {
        guard factor > 1, width >= factor, height >= factor else { return self }
        let targetWidth = width / factor
        let targetHeight = height / factor
        let count = factor * factor
        var result = [RGBA]()
        result.reserveCapacity(targetWidth * targetHeight)
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                var r = 0, g = 0, b = 0, a = 0
                for dy in 0..<factor {
                    for dx in 0..<factor {
                        let p = pixel(at: x * factor + dx, y * factor + dy)
                        r += Int(p.r)
                        g += Int(p.g)
                        b += Int(p.b)
                        a += Int(p.a)
                    }
                }
                result.append(
                    RGBA(
                        r: UInt8(r / count), g: UInt8(g / count),
                        b: UInt8(b / count), a: UInt8(a / count)))
            }
        }
        return RGBAImage(width: targetWidth, height: targetHeight, pixels: result)
    }

    /// This image with its LOCAL contrast raised — an unsharp mask.
    ///
    /// Every pixel is pushed away from the average of the area around it by
    /// `amount` times the difference: `p + amount × (p − blur(p))`. A flat
    /// region IS its own average and does not move; a pixel on one side of a
    /// boundary moves further from the pixels on the other side. So it sharpens
    /// boundaries and leaves smooth expanses alone, which is the opposite of
    /// what a global contrast curve does — that one moves every pixel of a
    /// given tone, wherever it sits.
    ///
    /// The radii are the caller's because the scale is the point. A picture
    /// scaled to a render's pixel grid is about to be reduced again to one
    /// glyph per CELL, so a lift measured in single pixels of a 5×10 sub-cell
    /// grid averages back out before any character is chosen. Passing the
    /// sub-cell grid makes the neighbourhood about a cell across whatever the
    /// renderer's grid is, so the same `amount` means the same thing for a
    /// luminance ramp, half-blocks, braille and a shape match alike.
    ///
    /// Each channel is sharpened on its own, so a boundary between two
    /// equally-bright colours sharpens too; alpha is left alone, its edges
    /// being the picture's outline rather than anything inside it.
    ///
    /// - Parameters:
    ///   - amount: How far to push. `0` (or less) returns `self`; around `0.6`
    ///     is a visible lift and `2` is heavy-handed.
    ///   - radiusX: Half the neighbourhood's width, in pixels. Clamped to ≥ 1.
    ///   - radiusY: Half its height. Clamped to ≥ 1.
    public func sharpened(amount: Double, radiusX: Int = 1, radiusY: Int = 1) -> RGBAImage {
        guard amount > 0, width > 0, height > 0 else { return self }
        let spanX = max(1, radiusX)
        let spanY = max(1, radiusY)
        let rowBlur = horizontallyAveraged(span: spanX)
        var result = pixels
        // Three scalars, not a three-element array. The arithmetic below is
        // unchanged and the output is byte-identical; what is gone is two heap
        // allocations PER PIXEL — `[here.r, here.g, here.b]` and its copy —
        // which on a megapixel image is two million of them, and which a debug
        // build does not optimise away. This is the difference between an
        // unsharp mask being a knob and being a pause.
        for x in 0..<width {
            var running = (r: 0.0, g: 0.0, b: 0.0)
            for y in 0...min(height - 1, spanY) {
                let slot = (y * width + x) * 3
                running.r += rowBlur[slot]
                running.g += rowBlur[slot + 1]
                running.b += rowBlur[slot + 2]
            }
            for y in 0..<height {
                let low = max(0, y - spanY)
                let high = min(height - 1, y + spanY)
                let count = Double(high - low + 1)
                let index = y * width + x
                let here = pixels[index]
                result[index] = RGBA(
                    r: Self.lifted(here.r, blurred: running.r / count, amount: amount),
                    g: Self.lifted(here.g, blurred: running.g / count, amount: amount),
                    b: Self.lifted(here.b, blurred: running.b / count, amount: amount),
                    a: here.a)
                if y - spanY >= 0 {
                    let slot = ((y - spanY) * width + x) * 3
                    running.r -= rowBlur[slot]
                    running.g -= rowBlur[slot + 1]
                    running.b -= rowBlur[slot + 2]
                }
                if y + spanY + 1 < height {
                    let slot = ((y + spanY + 1) * width + x) * 3
                    running.r += rowBlur[slot]
                    running.g += rowBlur[slot + 1]
                    running.b += rowBlur[slot + 2]
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: result)
    }

    /// One channel pushed away from its neighbourhood's average by `amount`
    /// times the difference — the unsharp mask, per channel.
    private static func lifted(_ value: UInt8, blurred: Double, amount: Double) -> UInt8 {
        let original = Double(value)
        return UInt8(clamping: Int((original + amount * (original - blurred)).rounded()))
    }

    /// Each pixel's three colour channels averaged across `2 × span + 1`
    /// columns, as `[r, g, b]` triples in row-major order — the first half of
    /// ``sharpened(amount:radiusX:radiusY:)``'s separable box blur.
    ///
    /// By a running sum, so the cost is O(pixels) rather than O(pixels × span):
    /// the shape grid's neighbourhood is 11 × 21 taps, which is not something to
    /// walk per pixel per channel. The window SHRINKS at the edges rather than
    /// repeating the border — either is defensible, and averaging only over
    /// pixels that exist keeps the outermost column from being pulled toward a
    /// value counted twice.
    private func horizontallyAveraged(span: Int) -> [Double] {
        var blurred = [Double](repeating: 0, count: pixels.count * 3)
        for y in 0..<height {
            let row = y * width
            var running = (r: 0.0, g: 0.0, b: 0.0)
            func take(_ index: Int, _ sign: Double) {
                let p = pixels[index]
                running.r += sign * Double(p.r)
                running.g += sign * Double(p.g)
                running.b += sign * Double(p.b)
            }
            // Prime the window on the first column, then slide it across.
            for x in 0...min(width - 1, span) { take(row + x, 1) }
            for x in 0..<width {
                let count = Double(min(width - 1, x + span) - max(0, x - span) + 1)
                let slot = (row + x) * 3
                blurred[slot] = running.r / count
                blurred[slot + 1] = running.g / count
                blurred[slot + 2] = running.b / count
                if x - span >= 0 { take(row + x - span, -1) }
                if x + span + 1 < width { take(row + x + span + 1, 1) }
            }
        }
        return blurred
    }
}

// MARK: - Private Helpers

extension RGBAImage {

    private func bilinearInterpolate(
        _ v00: Double,
        _ v10: Double,
        _ v01: Double,
        _ v11: Double,
        _ xFrac: Double,
        _ yFrac: Double
    ) -> Double {
        let top = v00 * (1.0 - xFrac) + v10 * xFrac
        let bottom = v01 * (1.0 - xFrac) + v11 * xFrac
        return top * (1.0 - yFrac) + bottom * yFrac
    }
}
