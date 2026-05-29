//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit
import TUIkitImage

/// Benchmarks for the image-rendering pipeline. Image
/// rendering has historically been the most CPU-intensive
/// path in TUIkit — converting RGBA pixels into terminal
/// glyphs involves per-cell shape matching, palette
/// quantization, optional dithering, and ANSI emission.
/// Each rendering style has its own hot path; benchmarks
/// below isolate them so a regression in one doesn't hide
/// behind another's noise.
enum ImageBenchmarks {

    static func register() {
        registerStyleBenchmarks()
        registerColorBenchmarks()
        registerDitheringBenchmarks()
    }

    // MARK: - Test inputs

    /// 80×40 synthetic RGBA — wide enough for the shape
    /// matcher to actually exercise its full character table,
    /// small enough that the suite runs in a couple of
    /// seconds.
    private static let smallImage: RGBAImage = makeSynthetic(width: 80, height: 40)

    /// 200×100 — exercises the windowed-resampling path that
    /// kicks in when the source is wider than the terminal.
    private static let largeImage: RGBAImage = makeSynthetic(width: 200, height: 100)

    private static func makeSynthetic(width: Int, height: Int) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let intensity = UInt8((x * 255) / max(1, width - 1))
                let band = (y / 8) % 3
                let red: UInt8 = band == 0 ? intensity : intensity / 4
                let green: UInt8 = band == 1 ? intensity : intensity / 4
                let blue: UInt8 = band == 2 ? intensity : intensity / 4
                // RGBA uses short field names (r/g/b/a)
                // matching the upstream API; `a` defaults to
                // .max so an opaque pixel doesn't need to
                // pass it explicitly.
                pixels.append(RGBA(r: red, g: green, b: blue))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    // MARK: - Style benchmarks

    /// Each rendering style maps RGBA pixels to terminal
    /// glyphs differently; each has its own per-cell cost
    /// profile.
    private static func registerStyleBenchmarks() {
        Benchmark("image/Style: fine-blocks (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .ansi256,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }

        Benchmark("image/Style: braille (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .braille,
                colorMode: .ansi256,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }

        Benchmark("image/Style: shape-based (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .shapeBased,
                colorMode: .ansi256,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }
    }

    // MARK: - Color benchmarks

    /// Color-mode translation is a per-pixel operation; each
    /// mode has its own quantization cost.
    private static func registerColorBenchmarks() {
        Benchmark("image/Color: mono (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .mono,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }

        Benchmark("image/Color: grayscale (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .grayscale,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }

        Benchmark("image/Color: ANSI 256 (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .ansi256,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }

        Benchmark("image/Color: true-color (small)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .trueColor,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(smallImage, width: 80, height: 40))
            }
        }
    }

    // MARK: - Dithering benchmarks

    /// Dithering adds per-pixel cost; isolating it lets us see
    /// whether the dithering algorithm itself regresses (or
    /// whether the without-dithering hot path got slower).
    private static func registerDitheringBenchmarks() {
        Benchmark("image/Dithering: off (large)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .ansi256,
                dithering: .none
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(largeImage, width: 100, height: 50))
            }
        }

        Benchmark("image/Dithering: floyd-steinberg (large)") { benchmark in
            let converter = ASCIIConverter(
                characterSet: .fineBlocks,
                colorMode: .ansi256,
                dithering: .floydSteinberg
            )
            for _ in benchmark.scaledIterations {
                blackHole(converter.convert(largeImage, width: 100, height: 50))
            }
        }
    }
}
