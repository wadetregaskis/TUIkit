//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+Dithering.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Color Output

extension ASCIIConverter {

    /// Returns the ANSI foreground color escape code for a pixel.
    ///
    /// Callers must pass the *effective* color mode (the requested mode
    /// downsampled to one the terminal can actually render). See
    /// ``ASCIIColorMode/effective(for:)``.
    func foregroundColorCode(for pixel: RGBA, mode: ASCIIColorMode) -> String {
        Self.escape(for: cellColor(for: pixel, mode: mode), background: false)
    }

    /// Returns the ANSI background color escape code for a pixel.
    func backgroundColorCode(for pixel: RGBA, mode: ASCIIColorMode) -> String {
        Self.escape(for: cellColor(for: pixel, mode: mode), background: true)
    }

    /// The escape for `color` as a string — the spelling ``ANSIRowBuilder``
    /// writes as bytes, for the callers that want a `String`. Not on the
    /// converters' path any more; they write bytes.
    static func escape(for color: Color?, background: Bool) -> String {
        guard let color else { return "" }
        var builder = ANSIRowBuilder(capacity: 24)
        builder.setColors(foreground: background ? nil : color, background: background ? color : nil)
        // The builder closes with a reset; the string form never carried one.
        let closed = builder.finish()
        return String(closed.dropLast(ANSIEscape.reset.count))
    }
}

// MARK: - Floyd-Steinberg Dithering

extension ASCIIConverter {

    /// Applies Floyd-Steinberg error diffusion dithering.
    ///
    /// Distributes quantization error to neighboring pixels:
    /// - Right:       7/16
    /// - Bottom-left: 3/16
    /// - Bottom:      5/16
    /// - Bottom-right: 1/16
    ///
    /// Quantizes against the *effective* color mode so dithering matches
    /// what will actually be emitted. See ``ASCIIColorMode/effective(for:)``.
    func applyFloydSteinbergDithering(
        _ image: RGBAImage, mode: ASCIIColorMode, monoThreshold: Double,
        table: ASCIIPalette.QuantisationTable? = nil
    ) -> RGBAImage {
        var pixels = image.pixels
        PixelQuantiser(mode: mode, monoThreshold: monoThreshold, table: table)
            .dither(&pixels, width: image.width, height: image.height)
        return RGBAImage(width: image.width, height: image.height, pixels: pixels)
    }

    /// Quantizes a pixel to its nearest representative value for the given
    /// color mode, keeping its alpha.
    ///
    /// Alpha is carried rather than defaulted. A glyph has no transparency to
    /// be wrong about, so this was invisible while the only consumer was the
    /// character renderer — and it stops being invisible the moment the same
    /// quantisation is applied to pixels that go to the TERMINAL, which is
    /// what composites them over the page. Same defect as the one
    /// `RGBAImage.scaledBilinear` had, in the same shape: `RGBA(r:g:b:)`
    /// defaults alpha to opaque.
    func quantizePixel(
        _ pixel: RGBA, mode: ASCIIColorMode, monoThreshold: Double,
        table: ASCIIPalette.QuantisationTable? = nil
    ) -> RGBA {
        PixelQuantiser(mode: mode, monoThreshold: monoThreshold, table: table).quantise(pixel)
    }
}

// MARK: - One pixel at a time, a million times

/// A colour mode resolved once per conversion into the form the per-pixel
/// loops want, and the loops themselves.
///
/// `quantizePixel(_:mode:monoThreshold:table:)` used to switch on the mode
/// per pixel, and `case .palette(let palette)` copies the palette out of the
/// enum's payload — every reference it holds retained and released for every
/// pixel of a megapixel picture, before a single distance is computed.
/// Measured on the `.ansi256` pixel path the day the palette gained a fourth
/// reference (its search index): the table lookup that had cost 14.0 ns a
/// pixel cost 18.8, with nothing in the lookup changed.
///
/// The first rewrite put the resolved pieces in an enum of its own and
/// matched THAT per pixel, which bound three arrays and the palette per
/// pixel and measured 2.7× slower still. So the pieces are plain stored
/// properties, the kind is a payload-free enum, and the two loops that
/// matter — a straight quantise and the error-diffusing dither — run over
/// the pixel buffer and the tables through pointers taken once, with the
/// only call left per pixel being the exact search a table does not trust.
struct PixelQuantiser {
    private enum Kind {
        case identity
        case grayscale
        case mono
        case palette
    }

    private let kind: Kind
    private let threshold: Double
    /// The entries' colours, indexed by palette entry.
    private let colours: [RGBA]
    /// The table's two halves, when the caller built one.
    private let answers: [UInt8]?
    private let trusted: [Bool]?
    /// For the exact search: every pixel without a table, and every pixel in
    /// a cell the table does not trust.
    private let palette: ASCIIPalette?
    /// Whether the dither carries its error in OKLab, boxed to what the
    /// palette spans — a chosen palette — or in sRGB, unbounded — the
    /// terminal's own. See `dither`.
    private let carriesInOKLab: Bool
    /// The entries in OKLab, one array per axis, for the OKLab carry.
    private let lightness: [Double]
    private let greenRed: [Double]
    private let blueYellow: [Double]
    /// The least and greatest of each OKLab axis across the entries: the box
    /// a carried colour is kept inside.
    private let labFloor: (l: Double, a: Double, b: Double)
    private let labCeiling: (l: Double, a: Double, b: Double)

    init(mode: ASCIIColorMode, monoThreshold: Double, table: ASCIIPalette.QuantisationTable?) {
        threshold = monoThreshold
        switch mode {
        case .trueColor: kind = .identity
        case .grayscale: kind = .grayscale
        case .mono: kind = .mono
        case .ansi256, .ansi16, .palette: kind = .palette
        }
        // `searchedPalette` is non-nil for exactly the three palette modes.
        let searched = kind == .palette ? mode.searchedPalette : nil
        colours = searched?.entries.map(\.rgba) ?? []
        answers = table?.answers
        trusted = table?.trusted
        palette = searched
        if case .palette = mode {
            carriesInOKLab = true
        } else {
            carriesInOKLab = false
        }
        let entries = searched?.entries ?? []
        lightness = entries.map(\.lightness)
        greenRed = entries.map(\.a)
        blueYellow = entries.map(\.b)
        labFloor = (lightness.min() ?? 0, greenRed.min() ?? 0, blueYellow.min() ?? 0)
        labCeiling = (lightness.max() ?? 1, greenRed.max() ?? 0, blueYellow.max() ?? 0)
    }

    /// `pixel`, as the mode would draw it — the alpha untouched, for the
    /// reason `quantizePixel` gives. The one-at-a-time form; the loops below
    /// do the same work without the per-pixel bookkeeping.
    func quantise(_ pixel: RGBA) -> RGBA {
        switch kind {
        case .identity:
            return pixel
        case .grayscale:
            return Self.grey(pixel)
        case .mono:
            return Self.mono(pixel, threshold: threshold)
        case .palette:
            guard let palette else { return pixel }
            let index: Int
            if let answers, let trusted {
                let cell = ASCIIPalette.quantisationCell(for: pixel)
                index = trusted[cell] ? Int(answers[cell]) : palette.nearestIndex(to: pixel)
            } else {
                index = palette.nearestIndex(to: pixel)
            }
            return Self.entry(colours, index, alpha: pixel.a)
        }
    }

    /// Quantises every pixel in place.
    func apply(to pixels: inout [RGBA]) {
        switch kind {
        case .identity:
            return
        case .grayscale:
            pixels.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices { buffer[index] = Self.grey(buffer[index]) }
            }
        case .mono:
            let threshold = self.threshold
            pixels.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices { buffer[index] = Self.mono(buffer[index], threshold: threshold) }
            }
        case .palette:
            guard let palette else { return }
            withTables { colours, bucket, answers, trusted in
                pixels.withUnsafeMutableBufferPointer { buffer in
                    for index in buffer.indices {
                        let pixel = buffer[index]
                        let entry = Self.index(
                            of: pixel, palette: palette, colours: colours, bucket: bucket,
                            answers: answers, trusted: trusted)
                        buffer[index] = Self.entry(colours, entry, alpha: pixel.a)
                    }
                }
            }
        }
    }

    /// Floyd–Steinberg error diffusion, in place, over a `width` × `height`
    /// buffer: each pixel is quantised and the difference spread to its
    /// neighbours — 7/16 right, 3/16, 5/16 and 1/16 along the row below.
    ///
    /// The neighbours KEEP their alpha. The old `addError` rebuilt each one
    /// with `RGBA(r:g:b:)`, whose alpha defaults to opaque, so a dithered
    /// picture with transparency came out solid everywhere the error reached,
    /// which was everywhere but the first pixel.
    ///
    /// **A chosen palette carries its error in OKLab, boxed to what the
    /// palette spans.** Error diffusion keeps a region's average where it was
    /// by handing each pixel's shortfall to its neighbours — which assumes the
    /// neighbours can make it up. A grey palette cannot make up a blue: a dark
    /// blue mapped to its grey leaves a blue-channel error of +75, the
    /// neighbour takes it and is bluer still, and so on along the row until
    /// the channel pins at 255 and the pixel is a saturated blue whose
    /// *lightness* is far above the original's — so the greys chosen from
    /// there on are too light. Measured on the demo photograph through 134
    /// greys: the dark blue disc came out 4 levels lighter on average and 41
    /// lighter where the drift peaked, a haze that read as a shadow beside
    /// every shape; through the demo's eight-entry "Ice" palette, 33 lighter
    /// on average and 102 at the peak.
    ///
    /// So for a ``ASCIIColorMode/palette(_:)`` the error is carried in OKLab
    /// — the space the nearest search already decides in — and the carried
    /// colour is clamped, per axis, to the least and greatest the palette's
    /// entries reach. Lightness the palette spans is carried in full, which is
    /// what a dither is for; an axis the palette does not reach (any hue, for
    /// greys; red, for a palette of blues) stops at the palette's edge instead
    /// of piling up. With that box the greys read 0.2 lighter and the "Ice"
    /// palette 2, on the same picture.
    ///
    /// The terminal's own palettes (``ASCIIColorMode/ansi256``,
    /// ``ASCIIColorMode/ansi16``) keep the sRGB carry, byte-for-byte: they
    /// span the gamut, so there is no direction the error cannot go, and the
    /// OKLab round trip per pixel is a cost they need not pay.
    func dither(_ pixels: inout [RGBA], width: Int, height: Int) {
        guard width > 0, height > 0, pixels.count >= width * height else { return }
        if carriesInOKLab, kind == .palette {
            ditherInOKLab(&pixels, width: width, height: height)
            return
        }
        withTables { colours, bucket, answers, trusted in
            // Bound ONCE: `guard let` per pixel copies the palette out of the
            // optional, four references retained and released a pixel — the
            // very cost this type exists to remove. The stand-in is never
            // read for a kind that has no palette.
            let palette = self.palette ?? .ansi16
            let kind = self.kind
            let threshold = self.threshold
            pixels.withUnsafeMutableBufferPointer { buffer in
                @inline(__always)
                func spread(_ index: Int, _ r: Int16, _ g: Int16, _ b: Int16) {
                    let pixel = buffer[index]
                    buffer[index] = RGBA(
                        r: UInt8(clamping: Int16(pixel.r) + r),
                        g: UInt8(clamping: Int16(pixel.g) + g),
                        b: UInt8(clamping: Int16(pixel.b) + b),
                        a: pixel.a)
                }
                for y in 0..<height {
                    let row = y * width
                    for x in 0..<width {
                        let index = row + x
                        let oldPixel = buffer[index]
                        let newPixel: RGBA
                        switch kind {
                        case .identity: newPixel = oldPixel
                        case .grayscale: newPixel = Self.grey(oldPixel)
                        case .mono: newPixel = Self.mono(oldPixel, threshold: threshold)
                        case .palette:
                            newPixel = Self.entry(
                                colours,
                                Self.index(
                                    of: oldPixel, palette: palette, colours: colours, bucket: bucket,
                                    answers: answers, trusted: trusted),
                                alpha: oldPixel.a)
                        }
                        buffer[index] = newPixel
                        let rErr = Int16(oldPixel.r) - Int16(newPixel.r)
                        let gErr = Int16(oldPixel.g) - Int16(newPixel.g)
                        let bErr = Int16(oldPixel.b) - Int16(newPixel.b)
                        if x + 1 < width {
                            spread(index + 1, rErr * 7 / 16, gErr * 7 / 16, bErr * 7 / 16)
                        }
                        if y + 1 < height {
                            let below = index + width
                            if x > 0 { spread(below - 1, rErr * 3 / 16, gErr * 3 / 16, bErr * 3 / 16) }
                            spread(below, rErr * 5 / 16, gErr * 5 / 16, bErr * 5 / 16)
                            if x + 1 < width { spread(below + 1, rErr / 16, gErr / 16, bErr / 16) }
                        }
                    }
                }
            }
        }
    }

    /// The OKLab carry — see `dither`. Two rows of (L, a, b) error, the
    /// current row's and the next's, swapped as each row completes.
    private func ditherInOKLab(_ pixels: inout [RGBA], width: Int, height: Int) {
        guard let palette else { return }
        let floor = labFloor
        let ceiling = labCeiling
        // Padded by one on each side so the diagonal spreads at the edges
        // need no bounds checks.
        let carryWidth = width + 2
        var carry = [Double](repeating: 0, count: carryWidth * 3)
        var next = [Double](repeating: 0, count: carryWidth * 3)
        withTables { colours, bucket, answers, trusted in
            lightness.withUnsafeBufferPointer { lightness in
                greenRed.withUnsafeBufferPointer { greenRed in
                    blueYellow.withUnsafeBufferPointer { blueYellow in
                        pixels.withUnsafeMutableBufferPointer { buffer in
                            for y in 0..<height {
                                let row = y * width
                                for index in next.indices { next[index] = 0 }
                                for x in 0..<width {
                                    let pixel = buffer[row + x]
                                    let lab = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
                                    let slot = (x + 1) * 3
                                    let wantedL = min(max(lab.l + carry[slot], floor.l), ceiling.l)
                                    let wantedA = min(max(lab.a + carry[slot + 1], floor.a), ceiling.a)
                                    let wantedB = min(max(lab.b + carry[slot + 2], floor.b), ceiling.b)
                                    let wanted = Color.fromOKLab(l: wantedL, a: wantedA, b: wantedB)
                                    let entry = Self.index(
                                        of: RGBA(r: wanted.red, g: wanted.green, b: wanted.blue),
                                        palette: palette, colours: colours, bucket: bucket,
                                        answers: answers, trusted: trusted)
                                    buffer[row + x] = Self.entry(colours, entry, alpha: pixel.a)
                                    guard entry >= 0, entry < lightness.count else { continue }
                                    let errL = wantedL - lightness[entry]
                                    let errA = wantedA - greenRed[entry]
                                    let errB = wantedB - blueYellow[entry]
                                    carry[slot + 3] += errL * 7 / 16
                                    carry[slot + 4] += errA * 7 / 16
                                    carry[slot + 5] += errB * 7 / 16
                                    next[slot - 3] += errL * 3 / 16
                                    next[slot - 2] += errA * 3 / 16
                                    next[slot - 1] += errB * 3 / 16
                                    next[slot] += errL * 5 / 16
                                    next[slot + 1] += errA * 5 / 16
                                    next[slot + 2] += errB * 5 / 16
                                    next[slot + 3] += errL / 16
                                    next[slot + 4] += errA / 16
                                    next[slot + 5] += errB / 16
                                }
                                swap(&carry, &next)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The pieces

    /// Runs `body` with pointers to every table the palette loops read,
    /// taken once for the whole loop rather than once a pixel. An absent
    /// table is an empty pointer, which the index lookup treats as "search".
    private func withTables(
        _ body: (
            _ colours: UnsafeBufferPointer<RGBA>, _ bucket: UnsafeBufferPointer<UInt8>,
            _ answers: UnsafeBufferPointer<UInt8>, _ trusted: UnsafeBufferPointer<Bool>
        ) -> Void
    ) {
        colours.withUnsafeBufferPointer { colours in
            ASCIIPalette.quantisationBucket.withUnsafeBufferPointer { bucket in
                (answers ?? []).withUnsafeBufferPointer { answers in
                    (trusted ?? []).withUnsafeBufferPointer { trusted in
                        body(colours, bucket, answers, trusted)
                    }
                }
            }
        }
    }

    /// The entry for `pixel`: through the table for a cell it trusts, exactly
    /// otherwise — and exactly for every pixel when there is no table.
    @inline(__always)
    private static func index(
        of pixel: RGBA, palette: ASCIIPalette, colours: UnsafeBufferPointer<RGBA>,
        bucket: UnsafeBufferPointer<UInt8>, answers: UnsafeBufferPointer<UInt8>,
        trusted: UnsafeBufferPointer<Bool>
    ) -> Int {
        guard !answers.isEmpty else { return palette.nearestIndex(to: pixel) }
        let cell =
            (Int(bucket[Int(pixel.r)]) << (2 * ASCIIPalette.quantisationBits))
            | (Int(bucket[Int(pixel.g)]) << ASCIIPalette.quantisationBits)
            | Int(bucket[Int(pixel.b)])
        return trusted[cell] ? Int(answers[cell]) : palette.nearestIndex(to: pixel)
    }

    @inline(__always)
    private static func entry(_ colours: UnsafeBufferPointer<RGBA>, _ index: Int, alpha: UInt8) -> RGBA {
        guard index >= 0, index < colours.count else { return RGBA(r: 0, g: 0, b: 0, a: alpha) }
        var quantized = colours[index]
        quantized.a = alpha
        return quantized
    }

    @inline(__always)
    private static func entry(_ colours: [RGBA], _ index: Int, alpha: UInt8) -> RGBA {
        guard colours.indices.contains(index) else { return RGBA(r: 0, g: 0, b: 0, a: alpha) }
        var quantized = colours[index]
        quantized.a = alpha
        return quantized
    }

    @inline(__always)
    private static func grey(_ pixel: RGBA) -> RGBA {
        let gray = UInt8(clamping: Int(pixel.luminance))
        return RGBA(r: gray, g: gray, b: gray, a: pixel.a)
    }

    /// The same split the mono renderers threshold on, so the error the
    /// dither diffuses is the error they will actually make.
    @inline(__always)
    private static func mono(_ pixel: RGBA, threshold: Double) -> RGBA {
        let value: UInt8 = ASCIIConverter.isMonoInk(pixel, threshold: threshold) ? 255 : 0
        return RGBA(r: value, g: value, b: value, a: pixel.a)
    }
}
