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

    /// The `Color` front door — which is what the blend actually calls, and
    /// which neither test above touches: both pin `setForeground(parameters:)`,
    /// the SINK. `settingForeground(_:depth:)` no longer builds a parameter
    /// list at all, so the parity that has to hold now is between the two
    /// routes, at every depth and for `nil` as well as for a colour.
    ///
    /// `.noColor` is in the loop deliberately, and `nil` is in `colours`
    /// deliberately: at that depth the two answers differ IN KIND. `nil`
    /// clears the colour (SGR 39/49) at every depth, while a colour has no SGR
    /// form and must leave the state untouched. A front door that checks the
    /// depth before the nil silently stops clearing, and
    /// ``noColorLeavesTheStateAlone`` cannot see it — that test iterates
    /// `colours.compactMap { $0 }`, so it never passes `nil`.
    @Test("The Color setters equal the parameter-list route, every depth and nil included")
    func colourSettersMatchTheParameterRoute() {
        var decorated = SGRState()
        decorated.apply("\u{1B}[1;4;7;31;44m")  // bold, underline, inverse, red on blue
        for depth in [ColorDepth.truecolor, .palette256, .basic16, .noColor] {
            for base in [SGRState(), decorated] {
                for colour in Self.colours {
                    var expectedForeground = base
                    expectedForeground.setForeground(
                        parameters: colour.map { $0.foregroundCodes(depth: depth) })
                    #expect(
                        base.settingForeground(colour, depth: depth) == expectedForeground,
                        "fg \(String(describing: colour)) @\(depth)")

                    var expectedBackground = base
                    expectedBackground.setBackground(
                        parameters: colour.map { $0.backgroundCodes(depth: depth) })
                    #expect(
                        base.settingBackground(colour, depth: depth) == expectedBackground,
                        "bg \(String(describing: colour)) @\(depth)")
                }
            }
        }
    }

    /// `.terminalForeground` and `.terminalBackground` through the blend's front
    /// door. Not in `colours`: `settersMatchApply` compares against `apply`, which
    /// reads 39 as a CLEARED slot where a stated colour is `.named(39)`, the same
    /// split `Color.default` already has. So the oracle here is `Color.default`
    /// itself in the carried colour's own slot. In the other slot it is the
    /// `.rgb` of the reported components once the terminal has reported them, and
    /// `Color.default` while it has not. Both sit beside the parameter-list route
    /// at every depth.
    @Test("A carried terminal colour states the default in its own slot, and its reported RGB or the default in the other")
    func carriedColoursStateTheDefaultOrTheirRGB() {
        let ink = Color(value: .terminalForeground)
        let paper = Color(value: .terminalBackground)
        let reported = TerminalColors(
            foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
            background: TerminalColors.RGB(red: 40, green: 44, blue: 52))
        let terminals: [(colours: TerminalColors, inkAsBackground: Color, paperAsForeground: Color)] = [
            (.unknown, .default, .default),
            (reported, .rgb(171, 178, 191), .rgb(40, 44, 52)),
        ]
        var decorated = SGRState()
        decorated.apply("\u{1B}[1;4;7;31;44m")  // bold, underline, inverse, red on blue
        for terminal in terminals {
            TerminalColors.withCurrent(terminal.colours) {
                for depth in [ColorDepth.truecolor, .palette256, .basic16, .noColor] {
                    for base in [SGRState(), decorated] {
                        #expect(
                            base.settingForeground(ink, depth: depth)
                                == base.settingForeground(.default, depth: depth))
                        #expect(
                            base.settingBackground(paper, depth: depth)
                                == base.settingBackground(.default, depth: depth))
                        #expect(
                            base.settingBackground(ink, depth: depth)
                                == base.settingBackground(terminal.inkAsBackground, depth: depth),
                            "ink as bg @\(depth), \(terminal.colours)")
                        #expect(
                            base.settingForeground(paper, depth: depth)
                                == base.settingForeground(terminal.paperAsForeground, depth: depth),
                            "paper as fg @\(depth), \(terminal.colours)")
                        for colour in [ink, paper] {
                            var expectedForeground = base
                            expectedForeground.setForeground(parameters: colour.foregroundCodes(depth: depth))
                            #expect(
                                base.settingForeground(colour, depth: depth) == expectedForeground,
                                "fg \(colour) @\(depth)")
                            var expectedBackground = base
                            expectedBackground.setBackground(parameters: colour.backgroundCodes(depth: depth))
                            #expect(
                                base.settingBackground(colour, depth: depth) == expectedBackground,
                                "bg \(colour) @\(depth)")
                        }
                    }
                }
            }
        }
    }
}
