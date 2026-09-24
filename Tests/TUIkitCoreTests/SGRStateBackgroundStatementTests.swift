//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRStateBackgroundStatementTests.swift
//
//  `SGRState.applyReportingBackground(_:)`: the state `apply(_:)` leaves, and
//  what the sequence last said about the background. The replay's splice
//  (`String.paintedOver(fields:)`) keeps the field its output has in force from
//  that answer instead of parsing every sequence of a frame a second time, so a
//  wrong answer is a field restated where it is not needed or missing where it
//  is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("SGRState reports what a sequence said about the background")
struct SGRStateBackgroundStatementTests {

    /// Each sequence, and what it last said about the background.
    static let cases: [(sequence: String, statement: SGRState.BackgroundStatement?)] = [
        ("\u{1B}[0m", .reset),
        ("\u{1B}[m", .reset),
        ("\u{1B}[;31m", .reset),
        ("\u{1B}[49m", .terminalDefault),
        ("\u{1B}[44m", .colour),
        ("\u{1B}[104m", .colour),
        ("\u{1B}[48;5;21m", .colour),
        ("\u{1B}[48;2;1;2;3m", .colour),
        // Nothing about the background.
        ("\u{1B}[31m", nil),
        ("\u{1B}[1;4;7m", nil),
        ("\u{1B}[38;2;1;2;3m", nil),
        ("\u{1B}[58;5;4m", nil),
        // An incomplete extended background is consumed and ignored.
        ("\u{1B}[48;5m", nil),
        // Not SGR at all.
        ("\u{1B}[2K", nil),
        // The last statement wins, as it does in the state.
        ("\u{1B}[0;48;5;21m", .colour),
        ("\u{1B}[44;0m", .reset),
        ("\u{1B}[0;49m", .terminalDefault),
        ("\u{1B}[49;44m", .colour),
        ("\u{1B}[0;38;2;1;2;3m", .reset),
    ]

    @Test("The last statement about the background, and the same state apply(_:) leaves", arguments: cases)
    func reportsTheLastStatement(sequence: String, statement: SGRState.BackgroundStatement?) {
        // From a state with a field of its own, so a sequence that clears it and
        // one that leaves it are told apart by the state as well.
        var reported = SGRState()
        reported.apply("\u{1B}[1;48;5;196m")
        var applied = reported
        #expect(reported.applyReportingBackground(sequence) == statement, "\(sequence.debugDescription)")
        applied.apply(sequence)
        #expect(reported == applied, "\(sequence.debugDescription)")
    }
}
