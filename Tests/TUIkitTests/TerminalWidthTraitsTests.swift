//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalWidthTraitsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The claim follows the host now, so that a cluster the host draws wide is
/// ALLOCATED wide rather than cut down to fit — see ``TerminalWidthTraits``.
///
/// Every expectation here is a measurement taken on the alternate screen on
/// 2026-08-26, recorded in `Documentation/Terminal-compatibility.md`.
@Suite("Terminal width traits")
struct TerminalWidthTraitsTests {

    private static let warp = TerminalWidthTraits(
        decomposesZWJSequences: true, skinTone: .detached)
    private static let apple = TerminalWidthTraits(
        decomposesZWJSequences: true, skinTone: .detached)
    private static let iTerm = TerminalWidthTraits(
        decomposesZWJSequences: false, skinTone: .detachedOnBMPBases)

    // MARK: - The measured widths

    @Test(
        "Warp's decomposed ZWJ widths are the sum of the segments plus a cell per joiner",
        arguments: [
            ("👩‍🚀", 5), ("🧑‍🌾", 5), ("👩‍🦰", 5), ("❤️‍🔥", 5),
            ("⛓️‍💥", 5), ("🏳️‍🌈", 5), ("🏴‍☠️", 5),
            ("👨‍👩‍👧", 8), ("👨‍❤️‍👨", 8), ("👨‍👩‍👧‍👦", 11),
            // The case that proves the two rules compose rather than duplicate:
            // 4 for the skin-toned segment, 1 for the joiner, 2 for the rocket.
            ("👩🏽‍🚀", 7),
        ] as [(String, Int)])
    func warpZWJWidths(text: String, expected: Int) {
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character(text).terminalWidth == expected)
        }
    }

    @Test(
        "A detached skin-tone cluster is the base's width plus two",
        arguments: [
            ("👍🏽", 4), ("🤙🏽", 4), ("✊🏻", 4),
            // A 1-cell text-presentation base gives 3 …
            ("☝🏽", 3),
            // … and 4 once its selector promotes it to 2, which is why the base
            // width is taken from the cluster-minus-modifier and not from the
            // first scalar alone.
            ("☝️🏽", 4),
        ] as [(String, Int)])
    func detachedSkinToneWidths(text: String, expected: Int) {
        TerminalWidthTraits.withTraits(Self.apple) {
            #expect(Character(text).terminalWidth == expected)
        }
    }

    @Test("iTerm2 and tmux merge an SMP base and detach only a BMP one")
    func detachedOnBMPBasesOnly() {
        TerminalWidthTraits.withTraits(Self.iTerm) {
            #expect(Character("👍🏽").terminalWidth == 2, "SMP base merges")
            #expect(Character("✊🏻").terminalWidth == 4, "BMP base detaches")
            #expect(Character("☝🏽").terminalWidth == 3, "1-cell BMP base")
        }
    }

    /// Apple Terminal PAINTS a ZWJ cluster composed into about two cells but
    /// RESERVES the decomposed width — a row budgeted at 2 wraps, measured by
    /// the row number changing. So the claim is the reserved width and the
    /// glyph sits at the left of the space it owns.
    @Test(
        "Apple Terminal reserves the decomposed width even though it composes the glyph",
        arguments: [
            ("👩‍🚀", 5), ("🧑‍🌾", 5), ("👨‍👩‍👧", 8), ("👨‍👩‍👧‍👦", 11), ("👩🏽‍🚀", 7),
        ] as [(String, Int)])
    func appleReservesDecomposedWidth(text: String, expected: Int) {
        #expect(TerminalClient.widthTraits(of: .appleTerminal).decomposesZWJSequences)
        TerminalWidthTraits.withTraits(Self.apple) {
            #expect(Character(text).terminalWidth == expected)
        }
    }

    /// Where the claim and the host's own advance differ, the EXISTING
    /// compensation closes the gap — the same trade already accepted for a
    /// Ghostty SF Symbol that paints narrower than the layout allocated.
    ///
    /// ❤️‍🔥 and 🏳️‍🌈 lead with a VS-16 segment, which Apple Terminal
    /// under-advances, so they advance 4 against a claim of 5.
    @Test(
        "A VS-16-leading ZWJ over-claims by one and the CUF closes it",
        arguments: ["❤️‍🔥", "🏳️‍🌈"])
    func vs16LeadingZWJIsCompensated(text: String) {
        TerminalWidthTraits.withTraits(Self.apple) {
            let character = Character(text)
            #expect(character.terminalWidth == 5, "claim")
            #expect(character.terminalAppCursorAdvance == 4, "measured advance")
            let out = TerminalClient.compensating(
                text, for: .appleTerminal, followedByContent: true)
            #expect(out.contains("\u{1B}[1C"), "one CUF to reach the claimed end")
        }
    }

    /// Every advance the models report is a measurement from a real terminal.
    @Test(
        "The per-host advance models match what the terminals actually do",
        arguments: [
            ("👩‍🚀", 5, 5), ("👨‍👩‍👧‍👦", 11, 11), ("👩🏽‍🚀", 7, 7),
            ("❤️‍🔥", 4, 5), ("🏳️‍🌈", 4, 5),
            ("👍🏽", 4, 4), ("👍", 2, 2), ("中", 2, 2),
        ] as [(String, Int, Int)])
    func advanceModelsMatchMeasurement(text: String, apple: Int, warp: Int) {
        let character = Character(text)
        TerminalWidthTraits.withTraits(Self.apple) {
            #expect(character.terminalAppCursorAdvance == apple, "Apple Terminal")
        }
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(character.warpCursorAdvance == warp, "Warp")
        }
    }

    @Test("A composing host is unchanged, and is the default")
    func composingIsTheDefault() {
        #expect(TerminalWidthTraits.current == .composing)
        for text in ["👩‍🚀", "👨‍👩‍👧‍👦", "👍🏽", "☝🏽", "🏳️‍🌈"] {
            #expect(Character(text).terminalWidth == 2, "\(text) claims 2 when composed")
        }
    }

    @Test("Ghostty is the composing host")
    func ghosttyComposes() {
        #expect(TerminalClient.widthTraits(of: .ghostty) == .composing)
        #expect(TerminalClient.widthTraits(of: .unidentified) == .composing)
    }

    // MARK: - What the claim buys

    /// The point of the whole change: the modifier survives.
    @Test(
        "A claim that fits the cluster stops the modifier being stripped",
        arguments: [
            TerminalClient.Program.appleTerminal, .iTerm2, .warp, .tmux,
        ])
    func skinToneSurvivesWhenClaimed(program: TerminalClient.Program) {
        let row = "│ ✊🏻 │"          // a BMP base: detached on every one of these
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let out = TerminalClient.compensating(row, for: program, followedByContent: true)
            #expect(
                out.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) },
                "\(program) must keep the Fitzpatrick modifier once the claim holds it")
        }
    }

    /// And without the claim, the old behaviour stands — a caller who has not
    /// published the host's traits must not be handed an over-advancing row.
    @Test(
        "Without the claim the modifier is still stripped",
        arguments: [TerminalClient.Program.iTerm2, .warp, .tmux])
    func skinToneStrippedWhenUnclaimed(program: TerminalClient.Program) {
        let row = "│ ✊🏻 │"
        TerminalWidthTraits.withTraits(.composing) {
            let out = TerminalClient.compensating(row, for: program, followedByContent: true)
            #expect(!out.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) })
        }
    }

    /// Claim equals advance for these classes, so the compensation machinery
    /// has nothing to do — no CUF, no ECH, no rewrite. That is the test that
    /// says the two models agree rather than fighting.
    @Test(
        "A claimed cluster needs no compensation at all",
        arguments: [
            (TerminalClient.Program.warp, "👩‍🚀"),
            (.warp, "👨‍👩‍👧‍👦"),
            (.warp, "✊🏻"),
            (.appleTerminal, "👍🏽"),
            (.appleTerminal, "☝🏽"),
            (.iTerm2, "✊🏻"),
        ] as [(TerminalClient.Program, String)])
    func claimedClustersAreEmittedVerbatim(program: TerminalClient.Program, text: String) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let out = TerminalClient.compensating(text, for: program, followedByContent: true)
            #expect(out == text, "expected verbatim, got \(out.debugDescription)")
        }
    }

    /// A pin must not leak: `TerminalWidthTraits` is read from the render path
    /// by every layout pass, and Swift Testing runs suites in parallel.
    @Test("A scoped pin does not outlive its scope")
    func pinIsScoped() {
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character("👩‍🚀").terminalWidth == 5)
        }
        #expect(Character("👩‍🚀").terminalWidth == 2, "the pin must not have escaped")
    }
}

/// These mutate the PROCESS-wide traits, which every other suite's width
/// reads would see, so they are serialized — the same treatment
/// `TerminalClientSimulationTests` gets for mutating `TerminalClient.simulated`.
@Suite("Terminal width traits — process-wide", .serialized)
struct TerminalWidthTraitsProcessTests {

    private static let warp = TerminalWidthTraits(
        decomposesZWJSequences: true, skinTone: .detached)

    @Test("Changing the process traits bumps the generation; a no-op change does not")
    @MainActor
    func generationTracksRealChanges() {
        let before = TerminalWidthTraits.generation
        let saved = TerminalWidthTraits.current
        defer { TerminalWidthTraits.current = saved }

        TerminalWidthTraits.current = Self.warp
        let afterChange = TerminalWidthTraits.generation
        #expect(afterChange > before, "a real change must bump the generation")

        TerminalWidthTraits.current = Self.warp
        #expect(
            TerminalWidthTraits.generation == afterChange,
            "assigning the same value must not invalidate every cache in the process")
    }

    @Test("A scoped pin does NOT bump the generation")
    func pinDoesNotBumpGeneration() {
        // A pin is scoped to the work that opted into it; the render path did
        // not, so bumping here would drop every cache for a test's benefit.
        let before = TerminalWidthTraits.generation
        TerminalWidthTraits.withTraits(Self.warp) {
            #expect(Character("👩‍🚀").terminalWidth == 5)
        }
        #expect(TerminalWidthTraits.generation == before)
    }

    @Test("Simulating another client republishes its traits")
    @MainActor
    func simulatingRepublishesTraits() {
        let savedSimulated = TerminalClient.simulated
        let savedTraits = TerminalWidthTraits.current
        defer {
            TerminalClient.simulated = savedSimulated
            TerminalWidthTraits.current = savedTraits
        }
        TerminalClient.simulated = .warp
        #expect(TerminalWidthTraits.current.decomposesZWJSequences,
                "the picker must move the claim, not just the compensation")
        TerminalClient.simulated = .ghostty
        #expect(TerminalWidthTraits.current == .composing)
    }
}
