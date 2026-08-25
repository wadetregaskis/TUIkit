//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRStateExtendedColourTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// `SGRState.apply` on the extended-colour introducers (38/48/58) and their
/// malformed forms — the cases where mis-parsing corrupts OTHER codes rather
/// than merely losing one.
@Suite("SGRState extended colours")
struct SGRStateExtendedColourTests {

    @Test("SGR 58's arguments belong to it, not to the attribute table")
    func underlineColourIsAtomic() {
        // ESC[58;5;4m sets the underline colour to palette 4. Re-parsing its
        // arguments as top-level codes read the 5 as blink and the 4 as
        // underline — inventing two attributes and emitting them separately.
        var state = SGRState()
        state.apply("\u{1B}[58;5;4m")
        #expect(state.rendered == "\u{1B}[58;5;4m")

        var truecolor = SGRState()
        truecolor.apply("\u{1B}[58;2;10;20;30m")
        #expect(truecolor.rendered == "\u{1B}[58;2;10;20;30m")
    }

    @Test("A truncated introducer cannot swallow its neighbour")
    func truncatedExtendedColourIsDropped() {
        // Parameter lists are joined back to back on re-emission, so a stored
        // "38;5" fragment would consume whatever code came next — a following
        // 41 becoming the "missing" palette index and the background
        // vanishing. The fragment is dropped instead: what the terminal did
        // with the malformed original is undefined; eating a neighbour is not.
        var state = SGRState()
        state.apply("\u{1B}[38;5m")
        state.apply("\u{1B}[41m")
        #expect(state.rendered == "\u{1B}[41m")

        var short = SGRState()
        short.apply("\u{1B}[38;2;10;20m")  // three channels expected, two given
        short.apply("\u{1B}[32m")
        #expect(short.rendered == "\u{1B}[32m")
    }

    @Test("Complete extended colours still net as colours")
    func completeExtendedColoursSurvive() {
        var state = SGRState()
        state.apply("\u{1B}[38;5;104m")
        state.apply("\u{1B}[48;2;1;2;3m")
        #expect(state.rendered == "\u{1B}[38;5;104;48;2;1;2;3m")
    }
}
