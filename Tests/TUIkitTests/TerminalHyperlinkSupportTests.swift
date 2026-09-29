//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHyperlinkSupportTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Which hosts get OSC 8, and how the answer is reached.
///
/// The ladder is asked on its inputs, and only the test that is about
/// `simulated` reaching it sets anything: both knobs republish link support —
/// and `simulated` the width traits — to the whole process, so that one runs
/// in an exit test. See `ProcessWideState`. These used to set and restore the
/// knobs in the shared process, `.serialized`, which kept out only this suite's
/// own tests and other main-actor ones.
@Suite("Terminal hyperlink support")
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

    /// An exit test, because `simulated` reaching the live answer is the
    /// subject. `TUIKIT_HYPERLINKS` is cleared first, in the child, so a
    /// developer who exported it cannot answer in the table's place.
    ///
    /// The ladder's own tests below pose it on arguments, so they cannot see
    /// what the live answer passes it. The last three checks here can: the
    /// process's environment and the real override outranking the simulated
    /// table, and the override published to the path that reads it.
    @Test("Simulating a program answers as that program")
    func simulationChangesTheAnswer() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("TUIKIT_HYPERLINKS", to: nil)
                ProcessWideState.simulated = .ghostty
                #expect(TerminalClient.hyperlinksSupported)
                ProcessWideState.simulated = .appleTerminal
                #expect(!TerminalClient.hyperlinksSupported)

                ProcessWideState.setEnvironment("TUIKIT_HYPERLINKS", to: "1")
                #expect(TerminalClient.hyperlinksSupported, "the process's TUIKIT_HYPERLINKS=1 reaches the ladder")
                ProcessWideState.setEnvironment("TUIKIT_HYPERLINKS", to: nil)
                ProcessWideState.hyperlinkSupport = true
                #expect(TerminalClient.hyperlinksSupported, "the real override reaches the ladder")
                #expect(TerminalHyperlink.isSupported, "and is published to the path that reads it")
            }
        }
    }

    /// An app sets the override in its `init`, which `App.main()` runs before
    /// `AppRunner` asks the terminal who it is. The name the terminal answers
    /// is seeded into the environment, where `TerminalHost`'s detectors find
    /// it, and those are `static let`s that keep their first answer. So
    /// setting the override must not read the host: the override answers the
    /// ladder by itself, and reading the program anyway would freeze every
    /// detector before the seed. An Apple Terminal reached over ssh, the case
    /// identification exists for, would then keep none of its compensation,
    /// and be sent the graphics probe it prints.
    ///
    /// An exit test, because the detectors freeze for the whole process. The
    /// variables that name a host are cleared first, as ssh leaves them.
    @Test("Setting the override before the host is identified leaves the detectors unread")
    func overrideLeavesTheHostUnread() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                for name in ["TUIKIT_TERM_PROGRAM", "TERM_PROGRAM", "LC_TERMINAL", "TERM", "TMUX"] {
                    ProcessWideState.setEnvironment(name, to: nil)
                }
                ProcessWideState.hyperlinkSupport = false  // the app's init
                ProcessWideState.seedDiscoveredHost("Apple_Terminal")  // what identification does
                #expect(TerminalHost.isAppleTerminal, "the detector read the seed, not the empty environment")
            }
        }
    }

    /// The override is what a user reaches for on a terminal TUIkit has never
    /// measured — most of which do support OSC 8 — and what an app reaches for
    /// when it must keep every URL for its own `OpenURLAction`, because a
    /// terminal-owned ⌘-click bypasses that entirely.
    @Test("The override outranks the table in both directions")
    func overrideOutranksTheTable() {
        #expect(
            TerminalClient.hyperlinksSupported(override: true, environment: [:], program: .appleTerminal),
            "on, for a host measured not to honour them")
        #expect(
            !TerminalClient.hyperlinksSupported(override: false, environment: [:], program: .ghostty),
            "off, for one measured to")
    }

    /// How a user turns links on for their own terminal without the app knowing
    /// anything about it — and off again. Only `1` and `0` are answers.
    @Test("TUIKIT_HYPERLINKS answers where the app has not, and the override outranks it")
    func environmentAnswersWhereTheAppHasNot() {
        func answer(_ override: Bool?, _ value: String?, _ program: TerminalClient.Program) -> Bool {
            let environment = value.map { ["TUIKIT_HYPERLINKS": $0] } ?? [:]
            return TerminalClient.hyperlinksSupported(
                override: override, environment: environment, program: program)
        }
        #expect(answer(nil, "1", .appleTerminal), "on, for a host measured not to honour them")
        #expect(!answer(nil, "0", .ghostty), "off, for one measured to")
        for value in ["yes", "true", "", "01"] {
            #expect(!answer(nil, value, .appleTerminal), "\(value.debugDescription) is not an answer")
            #expect(answer(nil, value, .ghostty), "\(value.debugDescription) is not an answer")
        }
        #expect(!answer(false, "1", .ghostty), "the app's off outranks the user's on")
        #expect(answer(true, "0", .appleTerminal), "the app's on outranks the user's off")
    }
}
