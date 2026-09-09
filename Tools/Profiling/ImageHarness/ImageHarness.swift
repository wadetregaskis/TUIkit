//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageHarness.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitImage
import TUIkitStyling

//  Mode A profiling harness for the IMAGE pipeline (see
//  Tools/Profiling/README.md).
//
//  `RenderHarness` loops `renderToBuffer` over a view tree; this loops an
//  `ASCIIConverter` over a picture, which is a different cost curve entirely:
//  the render path is per CELL, and the image path splits into a per-cell half
//  (`convert`, which emits an SGR per cell) and a per-PIXEL half
//  (`recoloured`, which hands real pixels to a graphics protocol and so
//  quantises about two hundred times as often for the same picture).
//
//  A change to a quantiser has to be measured on BOTH, because a table lookup
//  that is free per pixel can still be the wrong trade per cell, and an exact
//  search that is fine per cell is ruinous per pixel. That is the whole reason
//  this harness reports the two separately, in nanoseconds per cell and per
//  pixel rather than as a total: only the per-unit figure is comparable across
//  sizes.
//
//      swift build -c release --product ImageHarness
//      BIN="$(swift build -c release --product ImageHarness --show-bin-path)/ImageHarness"
//      "$BIN" --path glyph --mode ansi256 --iterations 40
//      "$BIN" --path pixel --mode ansi256 --dither floyd --iterations 10
//
//  It needs no PTY and no Instruments *attach*, so it can also be profiled by
//  having Instruments *launch* it, exactly as `RenderHarness` is.

@main
struct ImageHarness {
    static func main() {
        var path = "glyph"
        var mode = "ansi256"
        var dither = "none"
        var cols = 120
        var rows = 50
        var iterations = 20
        var sourceScale = 3
        var depth = "truecolor"

        var args = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = args.next() {
            switch arg {
            case "--path": path = args.next() ?? path
            case "--mode": mode = args.next() ?? mode
            case "--dither": dither = args.next() ?? dither
            case "--cols": cols = args.next().flatMap(Int.init) ?? cols
            case "--rows": rows = args.next().flatMap(Int.init) ?? rows
            case "--iterations": iterations = args.next().flatMap(Int.init) ?? iterations
            case "--source-scale": sourceScale = args.next().flatMap(Int.init) ?? sourceScale
            case "--depth": depth = args.next() ?? depth
            case "--help", "-h":
                print(usage)
                return
            default:
                FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
                print(usage)
                return
            }
        }

        guard let colorMode = Self.colorMode(named: mode) else {
            FileHandle.standardError.write(Data("unknown mode: \(mode)\n".utf8))
            print(usage)
            return
        }
        let dithering: DitheringMode = dither == "floyd" ? .floydSteinberg : .none

        if path == "colour" {
            measureQuantiser(iterations: iterations, cols: cols, rows: rows)
            return
        }

        if path == "palette" {
            guard let target = Self.colorDepth(named: depth) else {
                FileHandle.standardError.write(Data("unknown depth: \(depth)\n".utf8))
                print(usage)
                return
            }
            measureDerivation(
                colorMode, iterations: iterations, cols: cols, rows: rows, depth: target)
            return
        }

        // The output is the terminal's cell grid for the glyph path and the
        // pixel grid a graphics protocol would carry for the pixel path — the
        // cell being about 8×17 device pixels, which is where the ~200×
        // difference in how often a quantiser is asked comes from.
        let (width, height) = path == "pixel" ? (cols * 8, rows * 17) : (cols, rows)
        let units = width * height
        let source = photograph(width: width * sourceScale / 2, height: height * sourceScale / 2)
        let converter = ASCIIConverter(colorMode: colorMode, dithering: dithering)

        // One untimed pass: it pays for every lazily-built table and warms the
        // allocator, neither of which is what a steady-state figure is about.
        var checksum = 0
        checksum &+= run(converter, source, width, height, path)

        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations { checksum &+= run(converter, source, width, height, path) }
        let elapsed = clock.now - start

        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let perIteration = seconds / Double(iterations)
        let perUnit = perIteration / Double(units) * 1e9
        print("""
            path=\(path) mode=\(mode) dither=\(dither) out=\(width)x\(height) \
            src=\(source.width)x\(source.height) iterations=\(iterations)
            \(String(format: "%.3f ms/iteration   %.2f ns/%@   checksum=%d",
                     perIteration * 1000, perUnit, path == "pixel" ? "pixel" : "cell", checksum))
            """)
    }

    private static func run(
        _ converter: ASCIIConverter, _ source: RGBAImage, _ width: Int, _ height: Int, _ path: String
    ) -> Int {
        // The checksum escapes via the return value so the optimiser cannot
        // delete the conversion as dead code.
        if path == "pixel" {
            let image = converter.recoloured(source, width: width, height: height)
            return image.pixels.count &+ Int(image.pixels[image.pixels.count / 2].r)
        }
        let lines = converter.convert(source, width: width, height: height)
        return lines.count &+ (lines.first?.utf8.count ?? 0)
    }

    /// The palette quantiser on its own, over DISTINCT colours.
    ///
    /// Worth measuring separately because in both other paths it is a small
    /// part of a large total — resampling, sharpening, glyph choice and string
    /// building are most of what a conversion costs — so a quantiser that got
    /// four times dearer can hide inside the noise of `--path glyph` and still
    /// be the wrong trade. Distinct colours, because `Color`'s answer is
    /// memoised and a loop over one colour measures a dictionary.
    private static func measureQuantiser(iterations: Int, cols: Int, rows: Int) {
        let count = cols * rows
        let colours: [(UInt8, UInt8, UInt8)] = (0..<count).map { step in
            var hash = UInt64(step) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            hash ^= hash >> 29
            return (
                UInt8(truncatingIfNeeded: hash >> 8), UInt8(truncatingIfNeeded: hash >> 24),
                UInt8(truncatingIfNeeded: hash >> 40)
            )
        }
        // One untimed pass, for the same reason the other paths take one: it
        // fills whatever the quantiser memoises. Its answers are folded into
        // the checksum too, so the printed number is a function of the code and
        // not of a hash seed — a checksum that moves between identical builds
        // is worse than none.
        var checksum = 0
        for (red, green, blue) in colours {
            guard case .palette256(let index) =
                Color.rgb(red, green, blue).downsampledToPalette256().value
            else { continue }
            checksum &+= Int(index)
        }
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations {
            for (red, green, blue) in colours {
                guard case .palette256(let index) =
                    Color.rgb(red, green, blue).downsampledToPalette256().value
                else { continue }
                checksum &+= Int(index)
            }
        }
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print("""
            path=colour colours=\(count) iterations=\(iterations)
            \(String(format: "%.3f ms/iteration   %.1f ns/colour   checksum=%d",
                     seconds / Double(iterations) * 1000,
                     seconds / Double(iterations) / Double(count) * 1e9, checksum))
            """)
    }

    /// An adaptive palette's DERIVATION on its own — the histogram, and then
    /// the ranking, or the median cut and Lloyd's iteration over it.
    ///
    /// Separated for the same reason ``measureQuantiser`` is: in `--path glyph`
    /// and `--path pixel` it is a small part of a large total (resampling,
    /// glyph choice, the per-pixel quantisation and its table are most of what
    /// a conversion costs), so a derivation that got four times dearer can hide
    /// inside the noise of either. It is also the part whose cost depends on
    /// two things at once — every pixel goes into the histogram, and everything
    /// after walks the populated cells once per colour asked for — so `--cols`
    /// and `--rows` here are the PICTURE the palette is derived from rather
    /// than an output grid, and the figure is per pixel of it.
    ///
    /// A palette that was never a question — `shades8`, say — derives to
    /// itself, so it measures what this loop's own scaffolding costs and
    /// nothing else, which is the baseline the adaptive numbers stand against.
    /// A mode carrying no palette at all has nothing to derive and says so.
    /// - Parameter depth: What the output can draw, which is half of what a
    ///   derivation costs: an adaptive palette targeting a depth chooses from
    ///   that depth's own colours, which adds a projection of every centre onto
    ///   them to every Lloyd pass. `truecolor` constrains nothing and is the
    ///   figure the constrained ones stand against.
    private static func measureDerivation(
        _ mode: ASCIIColorMode, iterations: Int, cols: Int, rows: Int, depth: ColorDepth
    ) {
        guard case .palette(let palette) = mode else {
            FileHandle.standardError.write(Data("mode has no palette to derive\n".utf8))
            return
        }
        let source = photograph(width: cols, height: rows)
        // One untimed pass, as the other paths take: it pays for the
        // process-wide tables the histogram's cell arithmetic reads.
        var checksum = colourSum(palette.derived(from: source, depth: depth))
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations {
            checksum &+= colourSum(palette.derived(from: source, depth: depth))
        }
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let perIteration = seconds / Double(iterations)
        print("""
            path=palette depth=\(depth) src=\(source.width)x\(source.height) iterations=\(iterations)
            \(String(format: "%.3f ms/derivation   %.2f ns/pixel   checksum=%d",
                     perIteration * 1000, perIteration / Double(cols * rows) * 1e9, checksum))
            """)
    }

    /// The derived colours as one number, so a change that moved one of them
    /// cannot pass as a speed-up.
    private static func colourSum(_ palette: ASCIIPalette) -> Int {
        palette.colors.reduce(0) { sum, colour in
            guard let rgb = colour.rgbComponents else { return sum }
            return sum &+ (Int(rgb.red) << 16 | Int(rgb.green) << 8 | Int(rgb.blue))
        }
    }

    private static func colorDepth(named name: String) -> ColorDepth? {
        switch name {
        case "truecolor": .truecolor
        case "ansi256", "palette256": .palette256
        case "ansi16", "basic16": .basic16
        case "mono", "nocolor": .noColor
        default: nil
        }
    }

    private static func colorMode(named name: String) -> ASCIIColorMode? {
        switch name {
        case "truecolor": .trueColor
        case "ansi256": .ansi256
        case "ansi16": .ansi16
        case "grayscale": .grayscale
        case "mono": .mono
        case "shades8": .palette(.shades(8))
        case "shades256": .palette(.shades(256))
        // The adaptive palettes, which are the only modes whose cost depends on
        // the picture's own colour statistics rather than only on its size: the
        // derivation is a histogram plus (for `leastError`) median cut and
        // Lloyd's iteration over the populated cells. Named with their counts
        // because the cost grows with them.
        case "popular8": .palette(.adaptive(8, by: .popularity))
        case "popular256": .palette(.adaptive(256, by: .popularity))
        case "optimal8": .palette(.adaptive(8, by: .leastError))
        case "optimal64": .palette(.adaptive(64, by: .leastError))
        case "optimal256": .palette(.adaptive(256, by: .leastError))
        default: nil
        }
    }

    /// A picture with a photograph's colour STATISTICS, which is what a
    /// quantiser's cost depends on: smooth gradients (so neighbouring pixels
    /// differ by a unit or two, as a lens's output does) plus enough
    /// hash-driven grain that the colours are nearly all distinct — a
    /// synthetic image of flat bands would be answered by any memo and would
    /// measure the memo instead of the quantiser.
    private static func photograph(width: Int, height: Int) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                var hash = UInt64(truncatingIfNeeded: y &* 73_856_093 &+ x &* 19_349_663)
                hash = hash &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let grain = { (shift: UInt64) in Int(truncatingIfNeeded: hash >> shift) % 12 }
                let across = x * 255 / max(1, width - 1)
                let down = y * 255 / max(1, height - 1)
                pixels.append(
                    RGBA(
                        r: UInt8(clamping: across + grain(16)),
                        g: UInt8(clamping: (across + down) / 2 + grain(28)),
                        b: UInt8(clamping: 255 - down + grain(40))))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    static let usage = """
        ImageHarness — image-pipeline profiling harness (no PTY, xctrace --launch safe).
        Usage: ImageHarness [--path glyph|pixel|colour|palette] [--mode truecolor|ansi256|ansi16|grayscale|mono|shades8]
                            [--dither none|floyd] [--cols C] [--rows R] [--iterations N]
                            [--source-scale S] [--depth truecolor|ansi256|ansi16|mono]
        """
}
