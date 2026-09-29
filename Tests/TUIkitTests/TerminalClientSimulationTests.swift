//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClientSimulationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Rendering as a terminal other than the one detected — the mechanism the
/// `TerminalClientQuirks` app is built on.
///
/// The two knobs are process-wide by design: they have to reach a writer
/// nothing hands them to. Setting either also republishes the width traits
/// (and `simulated`, link support) to the whole process, which every width
/// measurement on every thread reads. So each test that sets one runs in an
/// exit test, whose child process no other test shares — see
/// `ProcessWideState`. They used to set and restore them here, `.serialized`
/// and on the main actor, which kept other main-actor tests out and nothing
/// else: a nonisolated suite measuring a ZWJ or skin-tone cluster on another
/// thread meanwhile measured it as Apple Terminal claims it.
@Suite("Terminal client simulation")
@MainActor
struct TerminalClientSimulationTests {

    private static func row(_ text: String, on writer: FrameDiffWriter) -> String {
        writer.buildOutputLines(
            buffer: FrameBuffer(text: text), terminalWidth: 10, terminalHeight: 1,
            bgCode: "", reset: "")[0]
    }

    /// A writer that has detected nothing — the state an unknown terminal
    /// leaves things in, and the one a simulation has to be able to override.
    private static var unidentified: FrameDiffWriter {
        FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
    }

    @Test("A simulated program applies its workarounds to a writer that detected nothing")
    func simulatedProgramApplies() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let writer = Self.unidentified
                #expect(!Self.row("🖥️X", on: writer).contains("\u{1B}[1C"))

                ProcessWideState.simulated = .appleTerminal
                #expect(Self.row("🖥️X", on: writer).contains("\u{1B}[1C"))

                ProcessWideState.simulated = nil
                #expect(!Self.row("🖥️X", on: writer).contains("\u{1B}[1C"))
            }
        }
    }

    @Test("Changing the model repaints, rather than leaving rows built under the old one")
    func changingTheModelInvalidates() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let writer = FrameDiffWriter(
                    isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false,
                    isTmux: false)
                // Build once so the reuse cache is populated, then change the
                // model. A row whose BYTES did not change would otherwise be
                // served from cache still carrying the previous model's
                // compensation — the half-repainted screen a simulation would be
                // useless for.
                let before = writer.buildOutputLines(
                    buffer: FrameBuffer(text: "🖥️X"), terminalWidth: 10, terminalHeight: 1,
                    bgCode: "", reset: "", reusingFor: .content)[0]
                #expect(!before.contains("\u{1B}[1C"))

                ProcessWideState.simulated = .appleTerminal
                let after = writer.buildOutputLines(
                    buffer: FrameBuffer(text: "🖥️X"), terminalWidth: 10, terminalHeight: 1,
                    bgCode: "", reset: "", reusingFor: .content)[0]
                #expect(after.contains("\u{1B}[1C"), "the cached row survived a change of terminal model")
            }
        }
    }

    /// Whether `line` still carries a Fitzpatrick modifier.
    private static func keepsTheTone(_ line: String) -> Bool {
        line.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }

    /// tmux, not Apple Terminal, as the program: Apple Terminal has separated
    /// tones (base, ZWNJ, modifier) rather than stripped them since
    /// 2026-08-28, so under it the modifier survived whichever model won and
    /// this test could not fail. tmux still strips 🤙's tone, which the first
    /// expectation checks, so that it cannot go vacuous the same way again.
    @Test("Hand-built quirks outrank a simulated program")
    func quirksOutrankProgram() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let writer = Self.unidentified
                ProcessWideState.simulated = .tmux
                #expect(
                    !Self.keepsTheTone(Self.row("🤙🏽X", on: writer)),
                    "the fixture: the simulated program strips this tone")
                // A hand-built set that keeps tones must win, or the
                // exploration is arguing with a model it is trying to replace.
                ProcessWideState.simulatedQuirks = TerminalQuirks(skinTones: .keep)
                #expect(Self.keepsTheTone(Self.row("🤙🏽X", on: writer)))
            }
        }
    }

    @Test("A detected host is unaffected when nothing is simulated")
    func detectionStillWins() {
        #expect(TerminalClient.simulated == nil)
        #expect(TerminalClient.simulatedQuirks == nil)
        let apple = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        #expect(Self.row("🖥️X", on: apple).contains("\u{1B}[1C"))
    }
}
