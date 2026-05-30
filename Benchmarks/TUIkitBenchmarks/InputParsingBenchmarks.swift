//  🖥️ TUIKit — Terminal UI Kit for Swift
//  InputParsingBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks for raw-byte input parsing: keyboard escape
/// sequences and mouse reports.
///
/// Every keystroke and mouse movement arrives as a short byte
/// sequence that has to be decoded before dispatch. The work
/// is small per event, but it sits directly on the
/// input-latency path, and a mouse in motion can deliver a
/// dense stream of drag reports. These are pure `static`
/// functions on value types (`KeyEvent` / `MouseEvent`), so
/// they run off the main actor under the default benchmark
/// configuration.
enum InputParsingBenchmarks {

    static func register() {
        registerKeyParsing()
        registerMouseParsing()
    }

    // MARK: - Keyboard byte sequences

    /// A single printable byte — the fast path.
    private static let printable: [UInt8] = [UInt8(ascii: "a")]
    /// `ESC [ A` — cursor up, the most common CSI sequence.
    private static let arrowUp: [UInt8] = [0x1B, 0x5B, UInt8(ascii: "A")]
    /// `ESC [ 15 ; 5 ~` — F5 with Ctrl, the extended-key +
    /// modifier path (the deepest CSI branch).
    private static let functionKeyWithModifier: [UInt8] = Array("\u{1B}[15;5~".utf8)
    /// A 2-byte UTF-8 scalar (é).
    private static let utf8TwoByte: [UInt8] = Array("é".utf8)
    /// A 4-byte UTF-8 scalar (😀).
    private static let utf8FourByte: [UInt8] = Array("😀".utf8)

    /// A realistic mixed keystroke stream parsed end-to-end.
    private static let keyStream: [[UInt8]] = [
        printable, arrowUp, functionKeyWithModifier, utf8TwoByte, utf8FourByte,
        [0x1B, 0x5B, UInt8(ascii: "B")],  // arrow down
        [0x1B, 0x5B, UInt8(ascii: "C")],  // arrow right
        [0x1B, 0x5B, UInt8(ascii: "D")],  // arrow left
        [0x0D],                           // enter
        [0x7F],                           // backspace
    ]

    private static func registerKeyParsing() {
        Benchmark("input/KeyEvent.parse — printable") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(KeyEvent.parse(printable))
            }
        }

        Benchmark("input/KeyEvent.parse — CSI arrow") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(KeyEvent.parse(arrowUp))
            }
        }

        Benchmark("input/KeyEvent.parse — F-key + modifier") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(KeyEvent.parse(functionKeyWithModifier))
            }
        }

        Benchmark("input/KeyEvent.parse — UTF-8 4-byte") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(KeyEvent.parse(utf8FourByte))
            }
        }

        Benchmark("input/KeyEvent.parse — mixed stream (10 events)") { benchmark in
            for _ in benchmark.scaledIterations {
                for bytes in keyStream { blackHole(KeyEvent.parse(bytes)) }
            }
        }
    }

    // MARK: - Mouse reports

    /// SGR left-button press at column 40, row 12.
    private static let sgrPress: [UInt8] = Array("\u{1B}[<0;40;12M".utf8)
    /// SGR drag (button 0 + motion bit 32) — the dense path
    /// during a click-drag.
    private static let sgrDrag: [UInt8] = Array("\u{1B}[<32;41;12M".utf8)
    /// SGR wheel-up (bit 64).
    private static let sgrWheel: [UInt8] = Array("\u{1B}[<64;40;12M".utf8)
    /// Legacy X10 mouse report: `ESC [ M` then three offset
    /// bytes (button/x/y, each +32).
    private static let legacy: [UInt8] = [0x1B, 0x5B, 0x4D, 32 + 0, 32 + 40, 32 + 12]

    private static func registerMouseParsing() {
        Benchmark("input/MouseEvent.parseSGR — press") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(MouseEvent.parseSGR(sgrPress))
            }
        }

        Benchmark("input/MouseEvent.parseSGR — drag") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(MouseEvent.parseSGR(sgrDrag))
            }
        }

        Benchmark("input/MouseEvent.parseSGR — wheel") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(MouseEvent.parseSGR(sgrWheel))
            }
        }

        Benchmark("input/MouseEvent.parseLegacy") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(MouseEvent.parseLegacy(legacy))
            }
        }
    }
}
