//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks for color quantization and manipulation.
///
/// Distinct from the image pipeline's `image/Color:*`
/// benchmarks (which exercise `ASCIIConverter`'s per-pixel
/// color mode): these target the standalone `Color` value
/// type's public arithmetic — the nearest-neighbour
/// downsampling used whenever a true-color value has to be
/// emitted on a 256- or 16-color terminal, plus the
/// lighten/darken/opacity/lerp helpers used by styling and
/// animation. All are pure value-type math, so they run off
/// the main actor.
///
/// Each benchmark sweeps a fixed 1024-color gradient so a
/// single sample reflects a realistic spread of inputs rather
/// than one lucky/unlucky color.
enum ColorBenchmarks {

    static func register() {
        registerDownsampling()
        registerManipulation()
    }

    // MARK: - Test inputs

    /// 1024 RGB colors spread across the cube, so nearest-
    /// neighbour search hits a representative variety of
    /// cube / grayscale / ANSI-16 outcomes.
    private static let colors: [Color] = (0..<1024).map { index in
        let red = UInt8(index & 0xFF)
        let green = UInt8((index &* 5) & 0xFF)
        let blue = UInt8((index &* 11) & 0xFF)
        return Color.rgb(red, green, blue)
    }

    // MARK: - Downsampling

    private static func registerDownsampling() {
        Benchmark("color/downsampledToPalette256 ×1024") { benchmark in
            for _ in benchmark.scaledIterations {
                for color in colors { blackHole(color.downsampledToPalette256()) }
            }
        }

        Benchmark("color/downsampledToANSI16 ×1024") { benchmark in
            for _ in benchmark.scaledIterations {
                for color in colors { blackHole(color.downsampledToANSI16()) }
            }
        }
    }

    // MARK: - Manipulation

    private static func registerManipulation() {
        Benchmark("color/lighter+darker ×1024") { benchmark in
            for _ in benchmark.scaledIterations {
                for color in colors {
                    blackHole(color.lighter(by: 0.2))
                    blackHole(color.darker(by: 0.2))
                }
            }
        }

        Benchmark("color/opacity ×1024") { benchmark in
            for _ in benchmark.scaledIterations {
                for color in colors { blackHole(color.opacity(0.5)) }
            }
        }

        Benchmark("color/lerp ×1024") { benchmark in
            for _ in benchmark.scaledIterations {
                for index in 0..<colors.count - 1 {
                    blackHole(Color.lerp(colors[index], colors[index + 1], phase: 0.5))
                }
            }
        }
    }
}
