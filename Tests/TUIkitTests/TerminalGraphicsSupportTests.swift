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

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// How "does this terminal draw pictures" is decided.
///
/// `.serialized`, and every test restores what it changed: the override, the
/// environment variable and the simulation are all process-wide.
@Suite("Terminal graphics support", .serialized)
@MainActor
struct TerminalGraphicsSupportTests {

    /// Runs `body` with `TUIKIT_GRAPHICS` set to `value` (or unset), restoring
    /// whatever was there — same shape as `TerminalURLOpeningTests`.
    private func withEnvironment(_ value: String?, _ body: () -> Void) {
        let name = "TUIKIT_GRAPHICS"
        let saved = ProcessInfo.processInfo.environment[name]
        if let value { setenv(name, value, 1) } else { unsetenv(name) }
        defer {
            if let saved { setenv(name, saved, 1) } else { unsetenv(name) }
        }
        body()
    }

    /// Runs `body` with the override set, restoring it afterwards.
    ///
    /// Restoring it to `nil` also republishes `KittyGraphics.isSupported`
    /// through `didSet`, so nothing leaks into a suite rendering in parallel.
    private func withOverride(_ value: Bool?, _ body: () -> Void) {
        let saved = TerminalClient.graphicsSupport
        TerminalClient.graphicsSupport = value
        defer { TerminalClient.graphicsSupport = saved }
        body()
    }

    @Test("The override outranks the environment in both directions")
    func overrideOutranksTheEnvironment() {
        for environment in ["1", "0", nil] {
            withEnvironment(environment) {
                withOverride(true) {
                    #expect(TerminalClient.graphicsSupported, "on, against \(environment ?? "unset")")
                }
                withOverride(false) {
                    #expect(
                        !TerminalClient.graphicsSupported, "off, against \(environment ?? "unset")")
                }
            }
        }
    }

    @Test("TUIKIT_GRAPHICS answers for the user when the app has not")
    func environmentAnswersWhereTheAppHasNot() {
        withOverride(nil) {
            withEnvironment("1") { #expect(TerminalClient.graphicsSupported) }
            withEnvironment("0") { #expect(!TerminalClient.graphicsSupported) }
            // No handshake has run in a test process, so `detectedGraphics` is
            // nil and the ladder's last rung is the safe default.
            withEnvironment(nil) { #expect(!TerminalClient.graphicsSupported) }
        }
    }

    @Test("Only `1` and `0` are answers; anything else falls through to the handshake")
    func otherEnvironmentValuesAreNotAnswers() {
        // The switch has no `default: true` arm by design — a stray
        // `TUIKIT_GRAPHICS=yes` must not turn pictures on for a terminal that
        // was never asked.
        withOverride(nil) {
            for value in ["yes", "true", "", "01"] {
                withEnvironment(value) {
                    #expect(!TerminalClient.graphicsSupported, "\(value.debugDescription)")
                }
            }
        }
    }

    /// The documented divergence from ``TerminalClient/hyperlinksSupported``,
    /// which DOES read through `effective`. Simulating a host is a statement
    /// about which compensations to emit, not a claim that the terminal in
    /// front of the user has stopped being able to draw.
    @Test("Simulating a program does not change whether pictures are drawn")
    func simulationDoesNotChangeTheAnswer() {
        defer { TerminalClient.simulated = nil }
        withOverride(nil) {
            withEnvironment(nil) {
                TerminalClient.simulated = .ghostty
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
    func overrideIsPublished() {
        withEnvironment(nil) {
            withOverride(true) { #expect(KittyGraphics.isSupported) }
            // And back: clearing the override republishes the ladder's answer,
            // which is what keeps the flag from sticking on.
            #expect(!KittyGraphics.isSupported)

            withOverride(false) { #expect(!KittyGraphics.isSupported) }
        }
    }

    @Test("applyGraphicsSupport publishes the current answer on demand")
    func applyPublishesOnDemand() {
        withEnvironment("1") {
            withOverride(nil) {
                // Written behind the accessor's back, as the startup path's
                // publish would find it.
                KittyGraphics.isSupported = false
                TerminalClient.applyGraphicsSupport()
                #expect(KittyGraphics.isSupported)
            }
        }
        TerminalClient.applyGraphicsSupport()
        #expect(!KittyGraphics.isSupported, "and back to the default once nothing forces it")
    }
}
