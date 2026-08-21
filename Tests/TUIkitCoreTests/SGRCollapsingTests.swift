//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRCollapsingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("SGR collapsing")
struct SGRCollapsingTests {

    private let esc = "\u{1B}"

    /// The contract is TERMINAL-STATE equivalence, so the check is: feed both
    /// the original and the collapsed form to the same model and compare the
    /// state each leaves, at every point a character is printed.
    private func statesAlongTheLine(_ line: String) -> [String] {
        var state = SGRState()
        var states: [String] = []
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "\u{1B}", let end = escapeEnd(line, from: index) {
                state.apply(String(line[index..<end]))
                index = end
                continue
            }
            states.append("\(line[index]):\(state.rendered)")
            index = line.index(after: index)
        }
        states.append("<end>:\(state.rendered)")
        return states
    }

    private func escapeEnd(_ line: String, from start: String.Index) -> String.Index? {
        var index = line.index(after: start)
        guard index < line.endIndex, line[index] == "[" else { return nil }
        index = line.index(after: index)
        while index < line.endIndex {
            let character = line[index]
            index = line.index(after: index)
            if character.isLetter { return index }
        }
        return nil
    }

    private func check(_ line: String, expectSaving: Bool = true) {
        let collapsed = line.collapsingAdjacentSGR()
        #expect(
            statesAlongTheLine(collapsed) == statesAlongTheLine(line),
            "collapsed \(collapsed.debugDescription) is not equivalent to \(line.debugDescription)")
        if expectSaving {
            #expect(
                collapsed.count < line.count,
                "no saving: \(collapsed.count) vs \(line.count) — \(collapsed.debugDescription)")
        }
    }

    @Test("The shape the diff writer actually emits: reset, then re-establish")
    func resetThenBackground() {
        check("\(esc)[0m\(esc)[48;5;16mhello\(esc)[0m\(esc)[48;5;16m world")
    }

    @Test("A colour overwritten before anything is printed costs nothing")
    func supersededColourIsDropped() {
        let line = "\(esc)[0m\(esc)[48;5;16m\(esc)[38;5;22m\(esc)[48;5;22mX"
        check(line)
        #expect(!line.collapsingAdjacentSGR().contains("48;5;16"), "the dead background is gone")
    }

    @Test("Styling already in force is not re-emitted")
    func redundantRestatementIsDropped() {
        // The shape that dominates a real frame: every styled fragment ends by
        // resetting, and the row's background is re-established after each one.
        // Between two identically-styled characters that is pure noise.
        let line = "\(esc)[0m\(esc)[48;5;16m\(esc)[38;5;22mA"
            + "\(esc)[0m\(esc)[48;5;16m\(esc)[38;5;22mB"
            + "\(esc)[0m\(esc)[48;5;16m\(esc)[38;5;22mC"
        check(line)
        let collapsed = line.collapsingAdjacentSGR()
        #expect(
            collapsed.components(separatedBy: "38;5;22").count - 1 == 1,
            "the style is stated once, not three times: \(collapsed.debugDescription)")
    }

    @Test("A run with no reset still lands the right state")
    func runWithoutReset() {
        check("A\(esc)[1m\(esc)[31mB", expectSaving: false)
    }

    @Test("A cursor move ends a run — styling must not cross it")
    func nonSGREscapeEndsARun() {
        let line = "\(esc)[0m\(esc)[31m\(esc)[5C\(esc)[0m\(esc)[32mX"
        let collapsed = line.collapsingAdjacentSGR()
        #expect(statesAlongTheLine(collapsed) == statesAlongTheLine(line))
        #expect(collapsed.contains("\(esc)[5C"), "the cursor move survives")
        #expect(
            collapsed.range(of: "\(esc)[5C")!.lowerBound
                > collapsed.range(of: "31")!.lowerBound,
            "and stays on the far side of the styling that preceded it")
    }

    @Test("A line with nothing to merge is returned untouched")
    func nothingToDo() {
        for line in ["plain text", "\(esc)[31mred\(esc)[0m", "", "\(esc)[0m"] {
            #expect(line.collapsingAdjacentSGR() == line, "\(line.debugDescription) was rewritten")
        }
    }

    @Test("An unknown code is carried through rather than dropped")
    func unknownCodeSurvives() {
        // 53 (overline) is not modelled; it must still reach the terminal.
        let line = "\(esc)[0m\(esc)[53m\(esc)[31mX"
        let collapsed = line.collapsingAdjacentSGR()
        #expect(collapsed.contains("53"), "unknown means not safe to drop")
        #expect(statesAlongTheLine(collapsed) == statesAlongTheLine(line))
    }

    @Test("Attributes turned off inside a run are not re-emitted")
    func attributeOffIsNetted() {
        check("\(esc)[0m\(esc)[1m\(esc)[22m\(esc)[31mX")
    }
}
