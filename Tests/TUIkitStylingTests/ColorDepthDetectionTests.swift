//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorDepthDetectionTests.swift
//
//  `ColorDepth.detect()` had one call site — the lazy initializer of
//  `processCurrent` — and no test. Every colour test pins the depth through
//  `withCurrent`/`withCap` instead, so the whole TERM decision table was
//  unasserted whichever way the ambient environment happened to branch, and
//  under CI (where TERM is usually unset) detection returned at the second
//  rung and never reached the table at all.
//
//  The order is load-bearing: "xterm-256color" also contains "color", so
//  putting the basic16 rule first silently downgrades the most common
//  termtype — and the depth gates the WCAG contrast floor, the SGR encoding
//  and the pulse ramp.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

/// The documented detection order, one test per rung.
///
/// `.serialized`, and every test restores what it changed: `TERM` and
/// `COLORTERM` are process-wide.
@Suite("Colour depth detection", .serialized)
struct ColorDepthDetectionTests {

    /// Runs `body` with `TERM` and `COLORTERM` set as given (or unset),
    /// restoring both afterwards.
    private func withTerminalEnvironment(
        term: String?, colorterm: String? = nil, _ body: () -> Void
    ) {
        // `processCurrent` is a LAZY static whose initializer is `detect()`.
        // Reading it first means a parallel suite cannot be the one to trigger
        // that initializer inside the window below and freeze the process-wide
        // depth at one of these fake values for the rest of the run.
        _ = ColorDepth.current

        let saved = (
            term: ProcessInfo.processInfo.environment["TERM"],
            colorterm: ProcessInfo.processInfo.environment["COLORTERM"]
        )
        defer {
            if let value = saved.term { setenv("TERM", value, 1) } else { unsetenv("TERM") }
            if let value = saved.colorterm {
                setenv("COLORTERM", value, 1)
            } else {
                unsetenv("COLORTERM")
            }
        }

        if let term { setenv("TERM", term, 1) } else { unsetenv("TERM") }
        if let colorterm { setenv("COLORTERM", colorterm, 1) } else { unsetenv("COLORTERM") }
        body()
    }

    @Test(
        "Every documented TERM rung answers as documented",
        arguments: [
            // Rung 3: the one terminal that gets no escape codes at all.
            ("dumb", ColorDepth.noColor),
            // Rung 4: direct colour.
            ("xterm-direct", .truecolor),
            ("iterm2-direct", .truecolor),
            // Rung 5: the common case. These also contain "color", which is
            // why this rung has to be tested before rung 6 is trusted.
            ("xterm-256color", .palette256),
            ("screen-256color", .palette256),
            ("tmux-256color", .palette256),
            // Rung 6: some colour, but not 256.
            ("xterm-16color", .basic16),
            ("xterm-color", .basic16),
            // Rung 7: set but unrecognised.
            ("vt100", .basic16),
            ("xterm", .basic16),
        ])
    func termTable(term: String, expected: ColorDepth) {
        withTerminalEnvironment(term: term) {
            #expect(ColorDepth.detect() == expected, "TERM=\(term)")
        }
    }

    @Test("TERM is matched case-insensitively")
    func termIsLowercased() {
        withTerminalEnvironment(term: "XTERM-256COLOR") {
            #expect(ColorDepth.detect() == .palette256)
        }
        withTerminalEnvironment(term: "DUMB") {
            #expect(ColorDepth.detect() == .noColor)
        }
    }

    @Test("An unset TERM means truecolor, not no colour")
    func unsetTermIsTruecolor() {
        // The deliberate asymmetry: an absent TERM is an IDE, a redirect or an
        // environment that was not propagated — no positive evidence of a
        // limited terminal — and the rule is to downgrade only on evidence.
        withTerminalEnvironment(term: nil) {
            #expect(ColorDepth.detect() == .truecolor)
        }
    }

    @Test(
        "COLORTERM outranks the whole TERM table",
        arguments: ["truecolor", "24bit", "TrueColor", "24BIT"])
    func colortermWins(colorterm: String) {
        // Rung 1, and it must beat rung 3: a terminal that sets COLORTERM and
        // an unhelpful TERM is common, and `dumb` is the strongest thing the
        // table can say.
        withTerminalEnvironment(term: "dumb", colorterm: colorterm) {
            #expect(ColorDepth.detect() == .truecolor)
        }
        withTerminalEnvironment(term: "vt100", colorterm: colorterm) {
            #expect(ColorDepth.detect() == .truecolor)
        }
    }

    @Test("A COLORTERM that claims nothing falls through to TERM")
    func unhelpfulColortermIsIgnored() {
        // Only "truecolor" and "24bit" are claims. Anything else — and some
        // terminals set COLORTERM to their own name — must not upgrade.
        withTerminalEnvironment(term: "xterm-16color", colorterm: "gnome-terminal") {
            #expect(ColorDepth.detect() == .basic16)
        }
        withTerminalEnvironment(term: "dumb", colorterm: "") {
            #expect(ColorDepth.detect() == .noColor)
        }
    }

    @Test("Detection re-reads the environment on every call")
    func detectionIsNotCached() {
        // What makes `detect()` usable after a terminal change, and what the
        // cached `current` deliberately is not.
        withTerminalEnvironment(term: "xterm-256color") {
            #expect(ColorDepth.detect() == .palette256)
        }
        withTerminalEnvironment(term: "dumb") {
            #expect(ColorDepth.detect() == .noColor)
        }
    }
}
