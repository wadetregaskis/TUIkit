//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHyperlinkSupportTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Which hosts get OSC 8, and how the answer is reached.
///
/// `.serialized`, and every test restores what it changed: both knobs here are
/// process-wide, exactly as the simulation ones are.
@Suite("Terminal hyperlink support", .serialized)
@MainActor
struct TerminalHyperlinkSupportTests {

    /// The measured table. Recorded 2026-09-02 — see
    /// `Documentation/Terminal-compatibility.md`, "OSC 8 hyperlinks".
    @Test(
        "The capability table matches what was measured",
        arguments: [
            (TerminalClient.Program.iTerm2, true),
            (.ghostty, true),
            (.tmux, true),
            (.appleTerminal, false),
            (.warp, false),
            (.unidentified, false),
        ])
    func tableMatchesMeasurements(program: TerminalClient.Program, honours: Bool) {
        #expect(TerminalClient.honoursHyperlinks(program) == honours)
    }

    /// A capability defaults the opposite way from a quirk, and the reason is
    /// the cost of being wrong. Applying a cursor-advance workaround to a host
    /// that does not need it breaks output that was fine, so an unmeasured
    /// terminal gets none. Emitting a sequence a host ignores costs a link that
    /// does nothing, so an unmeasured terminal gets none of those either —
    /// same answer, opposite reasoning, and the two must not be confused.
    @Test("An unidentified host gets no links and no quirks")
    func unidentifiedIsConservativeBothWays() {
        #expect(!TerminalClient.honoursHyperlinks(.unidentified))
        #expect(TerminalClient.widthTraits(of: .unidentified) == TerminalWidthTraits())
    }

    @Test("Simulating a program answers as that program")
    func simulationChangesTheAnswer() {
        defer { TerminalClient.simulated = nil }
        TerminalClient.simulated = .ghostty
        #expect(TerminalClient.hyperlinksSupported)
        TerminalClient.simulated = .appleTerminal
        #expect(!TerminalClient.hyperlinksSupported)
    }

    /// The override is what a user reaches for on a terminal TUIkit has never
    /// measured — most of which do support OSC 8 — and what an app reaches for
    /// when it must keep every URL for its own `OpenURLAction`, because a
    /// terminal-owned ⌘-click bypasses that entirely.
    @Test("The override outranks the table in both directions")
    func overrideOutranksTheTable() {
        defer {
            TerminalClient.hyperlinkSupport = nil
            TerminalClient.simulated = nil
        }
        TerminalClient.simulated = .appleTerminal
        TerminalClient.hyperlinkSupport = true
        #expect(TerminalClient.hyperlinksSupported, "on, for a host measured not to honour them")

        TerminalClient.simulated = .ghostty
        TerminalClient.hyperlinkSupport = false
        #expect(!TerminalClient.hyperlinksSupported, "off, for one measured to")
    }
}
