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
//  The table is posed on a DICTIONARY, never on the real environment. The
//  first version of this file set `TERM` process-wide and restored it, which
//  left a window in which a parallel test could be the one to trigger the
//  lazy `processCurrent` initializer and latch the process at a fake value;
//  the guard against that was a single hand-written `_ = ColorDepth.current`
//  nobody was obliged to remember. `detect(environment:)` removes the window
//  rather than guarding it, and `.swiftlint.yml`'s
//  `process_terminal_environment_mutation` rule keeps it removed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitStyling

/// The documented detection order, one test per rung.
///
/// Every case is a dictionary handed to ``ColorDepth/detect(environment:)``,
/// so nothing here touches the process environment, nothing has to be
/// restored, and the suite needs no serialization.
@Suite("Colour depth detection")
struct ColorDepthDetectionTests {

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
        #expect(ColorDepth.detect(environment: ["TERM": term]) == expected, "TERM=\(term)")
    }

    @Test("TERM is matched case-insensitively")
    func termIsLowercased() {
        #expect(ColorDepth.detect(environment: ["TERM": "XTERM-256COLOR"]) == .palette256)
        #expect(ColorDepth.detect(environment: ["TERM": "DUMB"]) == .noColor)
    }

    @Test("An unset TERM means truecolor, not no colour")
    func unsetTermIsTruecolor() {
        // The deliberate asymmetry: an absent TERM is an IDE, a redirect or an
        // environment that was not propagated — no positive evidence of a
        // limited terminal — and the rule is to downgrade only on evidence.
        #expect(ColorDepth.detect(environment: [:]) == .truecolor)
    }

    @Test(
        "COLORTERM outranks the whole TERM table",
        arguments: ["truecolor", "24bit", "TrueColor", "24BIT"])
    func colortermWins(colorterm: String) {
        // Rung 1, and it must beat rung 3: a terminal that sets COLORTERM and
        // an unhelpful TERM is common, and `dumb` is the strongest thing the
        // table can say.
        #expect(
            ColorDepth.detect(environment: ["TERM": "dumb", "COLORTERM": colorterm])
                == .truecolor)
        #expect(
            ColorDepth.detect(environment: ["TERM": "vt100", "COLORTERM": colorterm])
                == .truecolor)
    }

    @Test("A COLORTERM that claims nothing falls through to TERM")
    func unhelpfulColortermIsIgnored() {
        // Only "truecolor" and "24bit" are claims. Anything else — and some
        // terminals set COLORTERM to their own name — must not upgrade.
        #expect(
            ColorDepth.detect(environment: ["TERM": "xterm-16color", "COLORTERM": "gnome-terminal"])
                == .basic16)
        #expect(ColorDepth.detect(environment: ["TERM": "dumb", "COLORTERM": ""]) == .noColor)
    }

    @Test("Detection memoizes nothing")
    func detectionIsNotCached() {
        // What makes `detect(environment:)` usable after a terminal change, and
        // what the latched `current` deliberately is not: two calls, two
        // environments, two answers — no first answer is kept.
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-256color"]) == .palette256)
        #expect(ColorDepth.detect(environment: ["TERM": "dumb"]) == .noColor)
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-256color"]) == .palette256)
    }

    @Test("The default environment is the live one, read per call")
    func defaultArgumentIsTheProcessEnvironment() {
        // `detect()` must keep answering for the process that calls it, since
        // that is the call the lazy `processCurrent` initializer makes. A
        // default argument is evaluated at each call site, so this reads the
        // environment now rather than a snapshot taken at type-initialization.
        #expect(
            ColorDepth.detect()
                == ColorDepth.detect(environment: ProcessInfo.processInfo.environment))
    }

    @Test("The process-wide depth still says what this process's environment says")
    func processDepthIsNotLatchedToAFakeValue() {
        // The runtime backstop to the lint rule, and the only check that also
        // covers the OTHER route to the same defect: `ColorDepth.current` has a
        // setter, and a test assigning it process-wide would poison every
        // concurrently-rendering test exactly as a fake `TERM` would. Both pins
        // (`withCurrent`/`withCap`) are task-local and invisible here, and
        // `cap` defaults to `.truecolor`, so `current` should be precisely what
        // detection says about this process.
        //
        // It is a BACKSTOP, not the mechanism: it can only fire if the
        // poisoning happened earlier in this same process, which under the
        // parallel runner means the same shard. What makes forgetting
        // impossible is the lint rule; this catches the case the regex cannot
        // see (`let name = "TERM"; setenv(name, …)`) when luck cooperates.
        #expect(ColorDepth.current == ColorDepth.detect())
    }
}
