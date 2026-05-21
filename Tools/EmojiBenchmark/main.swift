//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EmojiBenchmark / main.swift
//
//  Measures how long it takes to classify the scalars/clusters in a
//  representative buffer line using four alternative implementations:
//
//    A) Current heuristic — `Character.terminalAppCursorAdvance` with
//       hand-curated range checks.
//    B) Direct Unicode.Scalar.Properties query (ICU lookup per char).
//    C) Pre-computed Set<UInt32> of "interesting" codepoints.
//    D) Pre-computed sorted [ClosedRange<UInt32>] with binary search.
//
//  The point of the benchmark is to find out whether a build-time
//  pre-computation buys us anything material over the on-demand
//  property query.

import Foundation
import TUIkitCore

// MARK: - Workload

/// Typical FeatureBox row from `TUIkitExample`'s main menu — mostly
/// ASCII / box-drawing, with some CJK and a couple of emoji.  This is
/// roughly what every render-loop iteration is asking the function
/// about, every cell, every frame.
let representativeRow = " │   Pure Swift   │   │   Declarative    │   │    Composable     │   │   Unicode compatible   │ "
let emojiHeavyRow     = "🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽 🥳 🤙🏽"
let cjkRow            = "所有语言 中文 日本語 한국어 中文 日本語 한국어 中文 日本語 한국어 中文 日本語 한국어 中文 日本語 한국어"
let mixedFullRow      = " ╭────────────────╮ │ 🤙🏽 World 你好 🥳 ╰──╯ 🖥️ TUIkit "

let testRows: [(String, String)] = [
    ("representative (boxes + emoji)", representativeRow),
    ("emoji-heavy",                    emojiHeavyRow),
    ("CJK-heavy",                      cjkRow),
    ("mixed",                          mixedFullRow),
]

// MARK: - Implementation A: current heuristic

@inline(never)
func variantCurrentHeuristic(_ chars: [Character]) -> Int {
    var sum = 0
    for c in chars {
        sum &+= c.terminalAppCursorAdvance
    }
    return sum
}

// MARK: - Implementation B: direct Unicode.Scalar.Properties

@inline(never)
func variantICUProperties(_ chars: [Character]) -> Int {
    var sum = 0
    for c in chars {
        let scalars = c.unicodeScalars
        guard let first = scalars.first else { continue }
        let p = first.properties
        // Reproduce the same advance decisions the current code makes,
        // but use ICU properties instead of range checks.
        var advance = c.terminalWidth   // baseline
        if scalars.count > 1 {
            let hasVS16     = scalars.contains { $0.value == 0xFE0F }
            let hasFitz     = scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
            if hasVS16 && p.isEmoji && !p.isEmojiPresentation {
                advance = 1
            } else if hasFitz && p.isEmojiModifierBase {
                advance = 4
            }
        }
        sum &+= advance
    }
    return sum
}

// MARK: - Implementation C: Set<UInt32> lookup

let underAdvancingBases: Set<UInt32> = {
    // Populated empirically from the scanner: every codepoint that is
    // emoji-with-VS16 and Terminal.app under-advances.  For benchmark
    // purposes, a small representative set; the production version
    // would be the full ~95-entry table.
    var s: Set<UInt32> = []
    // Misc symbols & pictographs (selected)
    for cp in [0x1F321, 0x1F324, 0x1F32C, 0x1F32D, 0x1F32E, 0x1F32F,
               0x1F336, 0x1F37D, 0x1F396, 0x1F397, 0x1F399, 0x1F39A,
               0x1F39B, 0x1F39E, 0x1F39F, 0x1F3CD, 0x1F3CE, 0x1F3D4,
               0x1F3D5, 0x1F3D6, 0x1F3D7, 0x1F3D8, 0x1F3D9, 0x1F3DA] {
        s.insert(UInt32(cp))
    }
    return s
}()

let overAdvancingBases: Set<UInt32> = {
    // Same shape — codepoints where `<base>+<Fitzpatrick>` advances 4.
    var s: Set<UInt32> = []
    for cp in 0x1F000...0x1FBFF {
        // We'd populate from the scanner output; for benchmark purposes,
        // approximate with the entire pictographic block as candidates.
        s.insert(UInt32(cp))
    }
    return s
}()

@inline(never)
func variantSetLookup(_ chars: [Character]) -> Int {
    var sum = 0
    for c in chars {
        let scalars = c.unicodeScalars
        guard let first = scalars.first else { continue }
        var advance = c.terminalWidth
        if scalars.count > 1 {
            let hasVS16     = scalars.contains { $0.value == 0xFE0F }
            let hasFitz     = scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
            if hasVS16 && underAdvancingBases.contains(first.value) {
                advance = 1
            } else if hasFitz && overAdvancingBases.contains(first.value) {
                advance = 4
            }
        }
        sum &+= advance
    }
    return sum
}

// MARK: - Implementation D: [ClosedRange<UInt32>] binary search

let overAdvancingRanges: [ClosedRange<UInt32>] = [
    // Coarse range matching the current heuristic; production would
    // use specific ranges derived from the scanner output.
    0x1F000...0x1FBFF,
]

@inline(__always)
func contains(_ ranges: [ClosedRange<UInt32>], _ value: UInt32) -> Bool {
    // Binary search.  Ranges must be sorted and non-overlapping.
    var lo = 0
    var hi = ranges.count - 1
    while lo <= hi {
        let mid = (lo + hi) / 2
        let r = ranges[mid]
        if r.contains(value)         { return true }
        else if value < r.lowerBound { hi = mid - 1 }
        else                         { lo = mid + 1 }
    }
    return false
}

@inline(never)
func variantRangeBinarySearch(_ chars: [Character]) -> Int {
    var sum = 0
    for c in chars {
        let scalars = c.unicodeScalars
        guard let first = scalars.first else { continue }
        var advance = c.terminalWidth
        if scalars.count > 1 {
            let hasVS16     = scalars.contains { $0.value == 0xFE0F }
            let hasFitz     = scalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
            if hasVS16 && contains(overAdvancingRanges, first.value) {
                advance = 1
            } else if hasFitz && contains(overAdvancingRanges, first.value) {
                advance = 4
            }
        }
        sum &+= advance
    }
    return sum
}

// MARK: - Driver

let iterations = 100_000

func measure(_ name: String, body: () -> Int) -> Double {
    // Warmup
    for _ in 0..<5 { _ = body() }
    let start = ContinuousClock.now
    var acc = 0
    for _ in 0..<iterations { acc &+= body() }
    let elapsed = ContinuousClock.now - start
    // Use acc so the optimizer can't eliminate the loop.
    if acc == Int.min { print("never") }
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
}

func pad(_ s: String, to width: Int, leftAlign: Bool = true) -> String {
    if s.count >= width { return s }
    let pad = String(repeating: " ", count: width - s.count)
    return leftAlign ? s + pad : pad + s
}
func ns(_ s: Double) -> String {
    return pad(String(format: "%.1f", s) + "ns", to: 11, leftAlign: false)
}

func run() {
    print("Per-iteration cost classifying every character in the row.")
    print("\(iterations) iterations × N chars per row.  Release build.")
    print()
    let sep = String(repeating: "─", count: 92)
    print(sep)
    print(pad("row", to: 34)
        + pad("chars", to: 8, leftAlign: false)
        + "  "
        + pad("current", to: 11, leftAlign: false)
        + "  "
        + pad("ICU props", to: 11, leftAlign: false)
        + "  "
        + pad("Set", to: 11, leftAlign: false)
        + "  "
        + pad("ranges", to: 11, leftAlign: false))
    print(sep)

    for (label, row) in testRows {
        let chars = Array(row)
        let tA = measure("A") { variantCurrentHeuristic(chars) }
        let tB = measure("B") { variantICUProperties(chars) }
        let tC = measure("C") { variantSetLookup(chars) }
        let tD = measure("D") { variantRangeBinarySearch(chars) }
        let nA = tA / Double(iterations) * 1e9
        let nB = tB / Double(iterations) * 1e9
        let nC = tC / Double(iterations) * 1e9
        let nD = tD / Double(iterations) * 1e9
        print(pad(label, to: 34)
            + pad(String(chars.count), to: 8, leftAlign: false)
            + "  " + ns(nA) + "  " + ns(nB) + "  " + ns(nC) + "  " + ns(nD))
        let pcA = nA / Double(chars.count)
        let pcB = nB / Double(chars.count)
        let pcC = nC / Double(chars.count)
        let pcD = nD / Double(chars.count)
        print(pad("  per char", to: 34)
            + pad("", to: 8)
            + "  " + ns(pcA) + "  " + ns(pcB) + "  " + ns(pcC) + "  " + ns(pcD))
    }

    print()
    print("legend:  current   = Character.terminalAppCursorAdvance (range checks)")
    print("         ICU props = Unicode.Scalar.Properties access per char")
    print("         Set       = Set<UInt32> hash lookup")
    print("         ranges    = sorted [ClosedRange<UInt32>] binary search")
}

run()
