//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalGraphicsSupportTests.swift
//
//  The twin of `TerminalHyperlinkSupportTests`, which the graphics side's own
//  doc comments repeatedly point at — and which was 100% covered while this
//  file was 0%. Two documented rules had nothing holding them: the precedence
//  ladder (override, then `TUIKIT_GRAPHICS`, then the handshake), and the
//  deliberate asymmetry that `simulated` does NOT change the answer here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// How "does this terminal draw pictures" is decided.
///
/// The ladder is asked on its inputs — an override, an environment and a
/// handshake answer — so those tests set nothing. The tests that are about the
/// live answer or its publication set the override, `KittyGraphics.isSupported`
/// (which every render reads to decide whether to place a picture), the
/// environment, or `simulated`, all process-wide; each runs in an exit test,
/// whose child process no other test shares. See `ProcessWideState`. They used
/// to set and restore all of it in the shared process, `.serialized`, which
/// kept out only this suite's own tests and other main-actor ones — and
/// `setenv` from one thread while others read the environment.
@Suite("Terminal graphics support")
@MainActor
struct TerminalGraphicsSupportTests {

    /// The ladder with no handshake answer: none has run in a test process.
    private static func answer(_ override: Bool?, _ environment: String?) -> Bool {
        TerminalClient.graphicsSupported(
            override: override,
            environment: environment.map { ["TUIKIT_GRAPHICS": $0] } ?? [:],
            detected: nil)
    }

    @Test("The override outranks the environment in both directions")
    func overrideOutranksTheEnvironment() {
        for environment in ["1", "0", nil] {
            #expect(Self.answer(true, environment), "on, against \(environment ?? "unset")")
            #expect(!Self.answer(false, environment), "off, against \(environment ?? "unset")")
        }
    }

    @Test("TUIKIT_GRAPHICS answers for the user when the app has not")
    func environmentAnswersWhereTheAppHasNot() {
        #expect(Self.answer(nil, "1"))
        #expect(!Self.answer(nil, "0"))
        // No handshake answer, so the ladder's last rung is the safe default.
        #expect(!Self.answer(nil, nil))
    }

    @Test("Only `1` and `0` are answers; anything else falls through to the handshake")
    func otherEnvironmentValuesAreNotAnswers() {
        // The switch has no `default: true` arm by design — a stray
        // `TUIKIT_GRAPHICS=yes` must not turn pictures on for a terminal that
        // was never asked. Asked both ways, so falling through is seen to
        // reach the handshake's answer rather than a constant.
        for value in ["yes", "true", "", "01"] {
            for detected in [false, true] {
                let answer = TerminalClient.graphicsSupported(
                    override: nil, environment: ["TUIKIT_GRAPHICS": value], detected: detected)
                #expect(answer == detected, "\(value.debugDescription), handshake \(detected)")
            }
        }
    }

    /// The documented divergence from ``TerminalClient/hyperlinksSupported``,
    /// which DOES read through `effective`. Simulating a host is a statement
    /// about which compensations to emit, not a claim that the terminal in
    /// front of the user has stopped being able to draw.
    ///
    /// An exit test, because it is about the live answers, which read the
    /// process's own knobs and environment.
    @Test("Simulating a program does not change whether pictures are drawn")
    func simulationDoesNotChangeTheAnswer() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("TUIKIT_GRAPHICS", to: nil)
                ProcessWideState.setEnvironment("TUIKIT_HYPERLINKS", to: nil)
                ProcessWideState.simulated = .ghostty
                // Ghostty draws pictures and honours links, so if the graphics
                // answer read through `simulated` this would be true.
                #expect(TerminalClient.hyperlinksSupported, "the twin does read through it")
                #expect(!TerminalClient.graphicsSupported, "this one must not")
            }
        }
    }

    /// The published flag is what the render path actually reads — it is
    /// `nonisolated`, because that path cannot ask a terminal anything — so an
    /// override that is not published changes nothing where it counts.
    @Test("Setting the override publishes it to the path that reads it")
    func overrideIsPublished() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("TUIKIT_GRAPHICS", to: nil)
                ProcessWideState.graphicsSupport = true
                #expect(KittyGraphics.isSupported)
                // And back: clearing the override republishes the ladder's
                // answer, which is what keeps the flag from sticking on.
                ProcessWideState.graphicsSupport = nil
                #expect(!KittyGraphics.isSupported)

                ProcessWideState.graphicsSupport = false
                #expect(!KittyGraphics.isSupported)
            }
        }
    }

    @Test("applyGraphicsSupport publishes the current answer on demand")
    func applyPublishesOnDemand() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                ProcessWideState.setEnvironment("TUIKIT_GRAPHICS", to: "1")
                // Written behind the accessor's back, as the startup path's
                // publish would find it.
                ProcessWideState.picturesSupported = false
                ProcessWideState.applyGraphicsSupport()
                #expect(KittyGraphics.isSupported)

                ProcessWideState.setEnvironment("TUIKIT_GRAPHICS", to: nil)
                ProcessWideState.applyGraphicsSupport()
                #expect(!KittyGraphics.isSupported, "and back to the default once nothing forces it")
            }
        }
    }
}
