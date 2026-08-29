//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompensationGateTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// Pins the compensation walks' narrow byte gate (`utf8MayNeedCompensation`)
/// to what the walks actually DO.
///
/// The gate exists to keep the framework's own box-drawing chrome off the
/// per-`Character` walk, and it works by knowing which scalars the advance
/// models read. That is exactly the kind of knowledge that rots: a model grows
/// an arm for some new scalar, the gate does not hear about it, and the walk
/// stops running on a row that needed it — silently, because a skipped row
/// looks identical to a row with nothing to repair.
///
/// So the assertion is not "the gate matches this list of scalars". It is the
/// implication that matters: **if the gate says skip, no walk changes the
/// string.** Anything else is a real bug, and it fails here rather than on
/// somebody's screen.
@Suite("Compensation gate")
struct CompensationGateTests {

    /// Every walk gated by `utf8MayNeedCompensation`, by name.
    private static let walks: [(String, @Sendable (String) -> String)] = [
        ("apple", { $0.withTerminalAppCursorCompensation() }),
        ("iterm2", { $0.withITerm2CursorCompensation() }),
        ("ghostty", { $0.withGhosttyCursorCompensation() }),
        ("warp", { $0.withWarpCursorCompensation() }),
        ("tmux", { $0.withTmuxCursorCompensation() }),
        ("skin-tone fallback", { $0.withSkinToneFallback() }),
    ]

    private func check(_ text: String, _ label: @autoclosure () -> String) {
        guard !text.utf8MayNeedCompensation else { return }
        for (host, walk) in Self.walks {
            #expect(
                walk(text) == text,
                "\(label()): the gate skipped a string the \(host) walk rewrites")
        }
        #expect(
            !text.containsTerminalAppCursorAdvanceQuirk,
            "\(label()): the gate skipped a string Terminal.app reports a quirk in")
    }

    @Test("No corpus cluster the walks rewrite is skipped by the gate")
    func corpusIsCovered() {
        for entry in TerminalWidthCorpus.all {
            check(entry.text, "corpus \(entry.id)")
            // In a bordered row, which is the shape the gate was added for.
            check("│ \(entry.text) │", "bordered corpus \(entry.id)")
        }
    }

    /// A generated sweep, because the corpus only contains what somebody
    /// already thought to doubt. Covers the BMP blocks the chrome lives in
    /// (box drawing, blocks, geometric shapes, arrows), the BMP emoji blocks,
    /// the selectors and joiners, and a stride through the astral planes.
    @Test("No scalar in a broad sweep is skipped by a walk that would change it")
    func sweepIsCovered() {
        var scalars: [Unicode.Scalar] = []
        for value in 0x2000...0x2FFF { append(value, to: &scalars) }
        for value in stride(from: 0x3000, through: 0xFFFF, by: 7) {
            append(value, to: &scalars)
        }
        for value in stride(from: 0x1F000, through: 0x1FBFF, by: 3) {
            append(value, to: &scalars)
        }
        for value in stride(from: 0x10000, through: 0x10FFFD, by: 293) {
            append(value, to: &scalars)
        }
        for scalar in scalars {
            check(String(scalar), "U+\(String(scalar.value, radix: 16, uppercase: true))")
        }
    }

    private func append(_ value: Int, to scalars: inout [Unicode.Scalar]) {
        guard let scalar = Unicode.Scalar(UInt32(value)) else { return }
        scalars.append(scalar)
    }

    @Test("A plain bordered ASCII row is skipped — the point of the gate")
    func borderedRowIsSkipped() {
        #expect(!"┌────────────┐".utf8MayNeedCompensation)
        #expect(!"│ Hello, world │".utf8MayNeedCompensation)
        #expect(!"╰──── ▲ ▼ ◀ ▶ ────╯".utf8MayNeedCompensation)
        #expect(!"│ 日本語のテキスト │".utf8MayNeedCompensation)
        #expect(!"█▓▒░ progress ░▒▓█".utf8MayNeedCompensation)
        // …and one that must NOT be.
        #expect("│ 👍🏽 │".utf8MayNeedCompensation)
        #expect("│ ❤️ │".utf8MayNeedCompensation)
        #expect("│ 1️⃣ │".utf8MayNeedCompensation)
    }
}
