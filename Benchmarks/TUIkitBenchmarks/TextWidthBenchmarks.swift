//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextWidthBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Benchmarks for terminal display-width measurement and
/// ANSI-aware string clipping.
///
/// These are the hottest per-character paths in the whole
/// library: every glyph that reaches the terminal has its
/// width measured at least once, and every rendered line is
/// width-measured (`strippedLength`) and frequently clipped
/// (`ansiAwarePrefix`) to the viewport. The grapheme-cluster
/// logic (emoji presentation selectors, Fitzpatrick skin-tone
/// modifiers, ZWJ sequences, CJK wide ranges) is materially
/// more expensive than the ASCII fast path, so the cases are
/// split by content shape to keep a regression in one from
/// hiding behind another's noise.
///
/// All entry points here are `nonisolated` value-type
/// computation, so they run under the default benchmark
/// configuration (no `@MainActor` deadlock — see
/// `Benchmarks.swift`).
enum TextWidthBenchmarks {

    static func register() {
        registerCharacterWidth()
        registerStringWidth()
        registerClipping()
        registerTerminalAppQuirks()
    }

    // MARK: - Test inputs

    /// ~126-column plain ASCII line — the common case: a full
    /// terminal row of unstyled text.
    private static let plainLine = String(repeating: "The quick brown fox. ", count: 6)

    /// A line peppered with ANSI SGR sequences, as styled
    /// output produces. `strippedLength` has to skip every
    /// escape sequence to count only the visible cells.
    private static let ansiLine: String = {
        let esc = "\u{1B}"
        var result = ""
        for index in 0..<20 {
            result += "\(esc)[38;5;\(index % 256)m\(esc)[1mword\(esc)[0m "
        }
        return result
    }()

    /// Emoji-rich line exercising the expensive cluster paths:
    /// a Fitzpatrick-modified hand, a four-person ZWJ family,
    /// a VS-16 pictograph, a regional-indicator flag, and a
    /// profession ZWJ sequence with a skin tone.
    private static let emojiLine = String(
        repeating: "👋🏽 hi 👨‍👩‍👧‍👦 fam ❤️ love 🇺🇸 flag 🧑🏿‍🚀 crew ",
        count: 4
    )

    /// Full-width CJK / Hiragana line — every character is a
    /// 2-cell wide glyph that hits the CJK range checks.
    private static let cjkLine = String(repeating: "你好世界こんにちは", count: 10)

    private static let asciiChars = Array(plainLine)
    private static let emojiChars = Array(emojiLine)
    private static let cjkChars = Array(cjkLine)

    // MARK: - Per-character width

    private static func registerCharacterWidth() {
        Benchmark("text/Character.terminalWidth — ASCII") { benchmark in
            for _ in benchmark.scaledIterations {
                var width = 0
                for character in asciiChars { width += character.terminalWidth }
                blackHole(width)
            }
        }

        Benchmark("text/Character.terminalWidth — emoji clusters") { benchmark in
            for _ in benchmark.scaledIterations {
                var width = 0
                for character in emojiChars { width += character.terminalWidth }
                blackHole(width)
            }
        }

        Benchmark("text/Character.terminalWidth — CJK wide") { benchmark in
            for _ in benchmark.scaledIterations {
                var width = 0
                for character in cjkChars { width += character.terminalWidth }
                blackHole(width)
            }
        }
    }

    // MARK: - Whole-line visible width

    private static func registerStringWidth() {
        Benchmark("text/String.strippedLength — plain") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(plainLine.strippedLength)
            }
        }

        Benchmark("text/String.strippedLength — ANSI-heavy") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(ansiLine.strippedLength)
            }
        }

        Benchmark("text/String.strippedLength — emoji") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(emojiLine.strippedLength)
            }
        }
    }

    // MARK: - ANSI-aware clipping / padding

    private static func registerClipping() {
        Benchmark("text/ansiAwarePrefix — clip ANSI line to 40") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(ansiLine.ansiAwarePrefix(visibleCount: 40))
            }
        }

        Benchmark("text/ansiAwareSuffix — drop 20 visible from ANSI line") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(ansiLine.ansiAwareSuffix(droppingVisible: 20))
            }
        }

        Benchmark("text/padToVisibleWidth — pad plain to 160") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(plainLine.padToVisibleWidth(160))
            }
        }
    }

    // MARK: - Terminal.app cursor-advance quirk workarounds

    private static func registerTerminalAppQuirks() {
        Benchmark("text/Character.terminalAppCursorAdvance — emoji clusters") { benchmark in
            for _ in benchmark.scaledIterations {
                var advance = 0
                for character in emojiChars { advance += character.terminalAppCursorAdvance }
                blackHole(advance)
            }
        }

        Benchmark("text/containsTerminalAppCursorAdvanceQuirk — emoji line") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(emojiLine.containsTerminalAppCursorAdvanceQuirk)
            }
        }

        Benchmark("text/withTerminalAppCursorCompensation — emoji line") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(emojiLine.withTerminalAppCursorCompensation())
            }
        }
    }
}
