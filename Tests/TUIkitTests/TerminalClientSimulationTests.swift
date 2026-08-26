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
/// `.serialized`, and every test restores what it changed: the two knobs are
/// process-wide by design (they have to reach a writer nothing hands them to),
/// so a suite running in parallel with this one would otherwise see a stray
/// terminal model. Nothing outside this suite ever sets them.
@Suite("Terminal client simulation", .serialized)
@MainActor
struct TerminalClientSimulationTests {

    private func row(_ text: String, on writer: FrameDiffWriter) -> String {
        writer.buildOutputLines(
            buffer: FrameBuffer(text: text), terminalWidth: 10, terminalHeight: 1,
            bgCode: "", reset: "")[0]
    }

    /// A writer that has detected nothing — the state an unknown terminal
    /// leaves things in, and the one a simulation has to be able to override.
    private var unidentified: FrameDiffWriter {
        FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
    }

    @Test("A simulated program applies its workarounds to a writer that detected nothing")
    func simulatedProgramApplies() {
        defer { TerminalClient.simulated = nil }
        let writer = unidentified
        #expect(!row("🖥️X", on: writer).contains("\u{1B}[1C"))

        TerminalClient.simulated = .appleTerminal
        #expect(row("🖥️X", on: writer).contains("\u{1B}[1C"))

        TerminalClient.simulated = nil
        #expect(!row("🖥️X", on: writer).contains("\u{1B}[1C"))
    }

    @Test("Changing the model repaints, rather than leaving rows built under the old one")
    func changingTheModelInvalidates() {
        defer { TerminalClient.simulated = nil }
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        // Build once so the reuse cache is populated, then change the model.
        // A row whose BYTES did not change would otherwise be served from cache
        // still carrying the previous model's compensation — the half-repainted
        // screen a simulation would be useless for.
        let before = writer.buildOutputLines(
            buffer: FrameBuffer(text: "🖥️X"), terminalWidth: 10, terminalHeight: 1,
            bgCode: "", reset: "", reusingFor: .content)[0]
        #expect(!before.contains("\u{1B}[1C"))

        TerminalClient.simulated = .appleTerminal
        let after = writer.buildOutputLines(
            buffer: FrameBuffer(text: "🖥️X"), terminalWidth: 10, terminalHeight: 1,
            bgCode: "", reset: "", reusingFor: .content)[0]
        #expect(after.contains("\u{1B}[1C"), "the cached row survived a change of terminal model")
    }

    @Test("Hand-built quirks outrank a simulated program")
    func quirksOutrankProgram() {
        defer {
            TerminalClient.simulated = nil
            TerminalClient.simulatedQuirks = nil
        }
        let writer = unidentified
        TerminalClient.simulated = .appleTerminal
        // Apple Terminal strips skin tones; a hand-built set that keeps them
        // must win, or the exploration is arguing with a model it is trying to
        // replace.
        TerminalClient.simulatedQuirks = TerminalQuirks(skinTones: .keep)
        let line = row("🤙🏽X", on: writer)
        #expect(line.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) })
    }

    @Test("A detected host is unaffected when nothing is simulated")
    func detectionStillWins() {
        #expect(TerminalClient.simulated == nil)
        #expect(TerminalClient.simulatedQuirks == nil)
        let apple = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        #expect(row("🖥️X", on: apple).contains("\u{1B}[1C"))
    }
}
