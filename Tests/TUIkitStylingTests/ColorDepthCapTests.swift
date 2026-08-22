//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorDepthCapTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Colour-depth cap")
struct ColorDepthCapTests {

    @Test("A cap only ever removes colour")
    func capIsACeiling() {
        ColorDepth.withCurrent(.truecolor) {
            #expect(ColorDepth.current == .truecolor)
            ColorDepth.withCap(.palette256) { #expect(ColorDepth.current == .palette256) }
            ColorDepth.withCap(.basic16) { #expect(ColorDepth.current == .basic16) }
        }
        // The direction that matters: a cap ABOVE what the terminal can do
        // changes nothing, because it is a ceiling and not an override. This is
        // the whole reason it is a second knob — assigning `current` would
        // upgrade a terminal that cannot honour it.
        ColorDepth.withCurrent(.basic16) {
            ColorDepth.withCap(.truecolor) { #expect(ColorDepth.current == .basic16) }
            ColorDepth.withCap(.palette256) { #expect(ColorDepth.current == .basic16) }
        }
    }

    @Test("The default cap is no cap")
    func defaultIsUncapped() {
        #expect(ColorDepth.cap == .truecolor)
        ColorDepth.withCurrent(.truecolor) { #expect(ColorDepth.current == .truecolor) }
    }

    @Test("A cap composes with detection rather than replacing it")
    func capComposes() {
        // Two terminals, one cap: each renders at its own ceiling. Expressing
        // this by assigning `current` would need the cap re-derived every time
        // detection changed.
        ColorDepth.withCap(.palette256) {
            ColorDepth.withCurrent(.truecolor) { #expect(ColorDepth.current == .palette256) }
            ColorDepth.withCurrent(.basic16) { #expect(ColorDepth.current == .basic16) }
            ColorDepth.withCurrent(.noColor) { #expect(ColorDepth.current == .noColor) }
        }
    }

    @Test("The pin is task-local, so it leaves the process alone")
    func pinIsScoped() {
        let before = ColorDepth.cap
        ColorDepth.withCap(.basic16) { #expect(ColorDepth.cap == .basic16) }
        #expect(ColorDepth.cap == before)
    }
}
