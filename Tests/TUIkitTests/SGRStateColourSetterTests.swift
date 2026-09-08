//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRStateColourSetterTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// `settingForeground`/`settingBackground` used to build the SGR sequence a
/// colour would emit and parse it back in — one code path for "what colour
/// is in force", at a parse per cell. They now state the parameters
/// directly, and this is the pin that the two are the same state, for every
/// kind of colour and depth, on a plain state and on a busy one.
@Suite("Stating a colour on an SGR state equals applying its sequence")
struct SGRStateColourSetterTests {

    private static let colours: [Color?] = [
        nil, .red, .brightBlue, .white, .rgb(10, 200, 30), .rgb(255, 255, 255), .rgb(0, 0, 0),
    ]

    private static func applied(_ codes: [String], to state: SGRState) -> SGRState {
        var result = state
        result.apply("\u{1B}[" + codes.joined(separator: ";") + "m")
        return result
    }

    @Test("Foreground and background, at every depth, from a plain and a decorated state")
    func settersMatchApply() {
        for depth in [ColorDepth.truecolor, .palette256, .basic16] {
            var decorated = SGRState()
            decorated.apply("\u{1B}[1;4;31;44m")
            for base in [SGRState(), decorated] {
                for colour in Self.colours {
                    let fg = colour.map { $0.foregroundCodes(depth: depth) }
                    let bg = colour.map { $0.backgroundCodes(depth: depth) }
                    var stated = base
                    stated.setForeground(parameters: fg)
                    #expect(stated == Self.applied(fg ?? ["39"], to: base), "fg \(String(describing: colour)) @\(depth)")
                    var statedBackground = base
                    statedBackground.setBackground(parameters: bg)
                    #expect(statedBackground == Self.applied(bg ?? ["49"], to: base), "bg \(String(describing: colour)) @\(depth)")
                    // And what they render — the bytes a terminal sees.
                    #expect(stated.rendered(changingFrom: SGRState()) == Self.applied(fg ?? ["39"], to: base).rendered(changingFrom: SGRState()))
                }
            }
        }
    }

    /// `.noColor`, which the loop above deliberately does not cover — and
    /// could not usefully cover, because its oracle is `apply(codes)` and that
    /// is precisely the thing that was wrong. Adding the depth there would
    /// compare the bug against itself and pass.
    ///
    /// At this depth a colour has NO parameters: `foregroundCodes()` returns
    /// `[]`. An empty list is not a colour, so it fell through to `apply`,
    /// where it spells `ESC[m` — a bare SGR 0, which resets the WHOLE state.
    /// So at the one depth whose entire contract is "emit no colour", asking
    /// for a colour stripped every attribute off the cell. `.opacity()`
    /// composites through these setters, so a faded bold heading came back
    /// unemphasised on a monochrome terminal.
    ///
    /// The assertion is that the state is UNCHANGED — stated against the
    /// decorated base itself, not against what applying something would give.
    @Test("At noColor, stating a colour changes nothing at all")
    func noColorLeavesTheStateAlone() {
        var decorated = SGRState()
        decorated.apply("\u{1B}[1;4;7;31;44m")  // bold, underline, inverse, red on blue
        for base in [SGRState(), decorated] {
            for colour in Self.colours.compactMap({ $0 }) {
                var foreground = base
                foreground.setForeground(parameters: colour.foregroundCodes(depth: .noColor))
                #expect(foreground == base, "fg \(colour) reset the state at .noColor")

                var background = base
                background.setBackground(parameters: colour.backgroundCodes(depth: .noColor))
                #expect(background == base, "bg \(colour) reset the state at .noColor")
            }
        }
        // The premise the case rests on: there really are no parameters here.
        #expect(Color.red.foregroundCodes(depth: .noColor).isEmpty)
    }
}
