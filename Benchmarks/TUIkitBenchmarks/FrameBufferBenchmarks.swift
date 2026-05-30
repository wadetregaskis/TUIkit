//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBufferBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks for `FrameBuffer` composition.
///
/// `FrameBuffer` is the value type every view renders into and
/// that the render loop stacks, overlays, and clips on every
/// frame. Its width is recomputed (an O(lines) scan of
/// `strippedLength`) on construction and on every `lines`
/// mutation, so construction cost scales with both line count
/// and per-line width complexity (ANSI sequences cost more to
/// measure). These operations are pure `Sendable` value-type
/// work and run off the main actor.
enum FrameBufferBenchmarks {

    static func register() {
        registerConstruction()
        registerStacking()
        registerCompositing()
    }

    // MARK: - Test inputs

    /// 50 plain rows of 120 cells — a typical full-screen frame.
    private static let plainLines: [String] = (0..<50).map { _ in
        String(repeating: "x", count: 120)
    }

    /// 50 styled rows — each wrapped in SGR codes so width
    /// measurement must skip escape sequences.
    private static let ansiLines: [String] = (0..<50).map { index in
        "\u{1B}[3\(index % 8)m" + String(repeating: "y", count: 110) + "\u{1B}[0m"
    }

    private static let baseBuffer = FrameBuffer(lines: plainLines)

    /// A small overlay (a dialog / tooltip shape) to composite
    /// onto the base frame.
    private static let smallOverlay = FrameBuffer(
        lines: (0..<5).map { _ in String(repeating: "O", count: 20) }
    )

    /// 50 single-row buffers to stack — models assembling a
    /// frame row-by-row from child views.
    private static let manyBuffers: [FrameBuffer] = (0..<50).map { _ in
        FrameBuffer(lines: [String(repeating: "z", count: 80)])
    }

    // MARK: - Construction (width recompute)

    private static func registerConstruction() {
        Benchmark("buffer/init(lines:) width — plain 50×120") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(FrameBuffer(lines: plainLines))
            }
        }

        Benchmark("buffer/init(lines:) width — ANSI 50×110") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(FrameBuffer(lines: ansiLines))
            }
        }
    }

    // MARK: - Vertical / horizontal stacking

    private static func registerStacking() {
        Benchmark("buffer/init(verticallyStacking:) — 50 buffers") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(FrameBuffer(verticallyStacking: manyBuffers))
            }
        }

        Benchmark("buffer/appendVertically — stack 50 one at a time") { benchmark in
            for _ in benchmark.scaledIterations {
                var buffer = FrameBuffer()
                for other in manyBuffers { buffer.appendVertically(other) }
                blackHole(buffer)
            }
        }

        Benchmark("buffer/appendHorizontally — two 50×120 columns") { benchmark in
            for _ in benchmark.scaledIterations {
                var buffer = baseBuffer
                buffer.appendHorizontally(baseBuffer, spacing: 1)
                blackHole(buffer)
            }
        }
    }

    // MARK: - Compositing / clipping

    private static func registerCompositing() {
        Benchmark("buffer/composited overlay at (5,10)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(baseBuffer.composited(with: smallOverlay, at: (x: 5, y: 10)))
            }
        }

        Benchmark("buffer/clamped to 80×24") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(baseBuffer.clamped(toWidth: 80, height: 24))
            }
        }
    }
}
