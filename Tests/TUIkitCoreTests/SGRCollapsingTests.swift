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

    /// The contract is what the ROW LOOKS LIKE, so the check is: feed both the
    /// original and the collapsed form to the same model and compare the
    /// appearance of every cell each paints.
    ///
    /// Appearance rather than state, because the collapsing is allowed to hold
    /// a change across cells that cannot show it — see
    /// ``ReferenceStyle/appearance(of:)``. On a cell with a glyph the two are
    /// the same thing, so nothing is given away for the cases that matter most.
    ///
    /// The model is ``ReferenceStyle``, not ``SGRState``: this test grades
    /// `SGRState`'s netting, and checking it against itself would grade
    /// nothing.
    private func statesAlongTheLine(_ line: String) -> [String] {
        // Walked at the SCALAR level, as a terminal's own parser does: an
        // escape's final byte can fuse with a following combining scalar into
        // one Character, and a Character-level walk would hand the model a
        // "sequence" with the mark inside it — grading the implementation
        // against its own mistake.
        var state = ReferenceStyle()
        var states: [String] = []
        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "[" {
                var end = index + 2
                while end < scalars.count, !scalars[end].properties.isAlphabetic { end += 1 }
                if end < scalars.count {
                    state.apply(String(String.UnicodeScalarView(scalars[index...end])))
                    index = end + 1
                    continue
                }
            }
            // Zero-width scalars have no cell of their own — they modify the
            // previous glyph, whose cell was already graded — so their
            // position relative to invisible styling is not part of the
            // contract. Their PRESENCE is, asserted separately.
            if Character(scalars[index]).terminalWidth > 0 {
                states.append(state.appearance(of: Character(scalars[index])))
            }
            index += 1
        }
        // The state a row ENDS in is load-bearing whatever the last cell shows:
        // it is what the next thing drawn inherits.
        states.append(
            "<end>|\(state.attributes.sorted())|\(state.foreground ?? [])"
                + "|\(state.background ?? [])|\(state.passthrough)")
        return states
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

    @Test("An SGR whose terminator fused with a combining scalar still nets")
    func fusedTerminatorStaysSGR() {
        // Swift fuses `m` + U+0301 into one Character, so a Character-level
        // scan returns a "sequence" that no longer ends in m and takes the
        // barrier branch: emitted verbatim, never applied to the model. The
        // state diverges silently, and a later escape that nets to what the
        // model BELIEVES is on the wire reconciles to nothing — a dropped
        // reset. The mark itself must also survive as content.
        let line = "\(esc)[0m\(esc)[48;5;16ma\(esc)[0m\(esc)[38;5;196m\u{0301}x\(esc)[0mb"
        check(line, expectSaving: false)
        #expect(line.collapsingAdjacentSGR().unicodeScalars.contains("\u{0301}"))
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

    // MARK: - Holding a change across cells that cannot show it

    @Test("A colour that goes off and back on over spaces is never emitted")
    func invisibleChangeIsHeldAcrossBlanks() {
        // The commonest row in the whole render stream: a label, some padding,
        // another label in the same colour. `ESC[39m` was the single most
        // frequent escape TUIkit emitted before this — 4,187 of 17,367 over one
        // divider drag — and it says "stop being green" to cells that are not
        // green either way.
        let line = "\(esc)[0m\(esc)[38;5;22mab\(esc)[0m   \(esc)[38;5;22mcd\(esc)[0m"
        check(line)
        let collapsed = line.collapsingAdjacentSGR()
        #expect(
            collapsed == "\(esc)[0;38;5;22mab   cd\(esc)[0m",
            "expected one statement of the colour, got \(collapsed.debugDescription)")
    }

    @Test("A background change over spaces is emitted — that is what a space shows")
    func backgroundChangeIsNotHeld() {
        let line = "\(esc)[0m\(esc)[41mab\(esc)[0m   \(esc)[41mcd\(esc)[0m"
        check(line, expectSaving: false)
        #expect(
            line.collapsingAdjacentSGR().contains("\(esc)[49m")
                || line.collapsingAdjacentSGR().contains("\(esc)[0m   "),
            "the background went back to default over the spaces and must be said so")
    }

    @Test("Underline, strikethrough, blink and reverse are ink on an empty cell")
    func inkingAttributesAreNotHeld() {
        for attribute in [4, 5, 6, 7, 9] {
            // Turning one ON over the spaces must reach them: each of these
            // paints a blank cell.
            let line = "\(esc)[0mab\(esc)[\(attribute)m   \(esc)[0mcd"
            check(line, expectSaving: false)
            let collapsed = line.collapsingAdjacentSGR()
            #expect(
                collapsed.contains("\(esc)[\(attribute)m"),
                "SGR \(attribute) draws on a space and must not be held: \(collapsed.debugDescription)")
        }
    }

    @Test("With ink in force the foreground colours it, so a change reaches the blanks")
    func foregroundReachesBlanksUnderInk() {
        // Underlined spaces in one colour, then another: the underline is drawn
        // in the foreground, so the change IS visible.
        let line = "\(esc)[0m\(esc)[4;31m   \(esc)[4;32m   \(esc)[0m"
        check(line, expectSaving: false)
        #expect(
            line.collapsingAdjacentSGR().contains("\(esc)[32m"),
            "an underline changing colour is visible on a space")
    }

    @Test("A held change is emitted the moment a glyph can show it")
    func heldChangeLandsOnTheFirstGlyph() {
        let line = "\(esc)[0m\(esc)[31mab\(esc)[32m   cd\(esc)[0m"
        check(line, expectSaving: false)
        let collapsed = line.collapsingAdjacentSGR()
        // The green is owed from the third cell and paid at the sixth.
        #expect(
            collapsed == "\(esc)[0;31mab   \(esc)[32mcd\(esc)[0m",
            "expected the colour to land on `cd`, got \(collapsed.debugDescription)")
    }

    @Test("Randomised rows with blanks stay faithful")
    func randomisedBlankHolding() {
        let palette = [
            "", "\(esc)[0m", "\(esc)[31m", "\(esc)[38;5;22m", "\(esc)[1m", "\(esc)[4m",
            "\(esc)[7m", "\(esc)[9m", "\(esc)[41m", "\(esc)[48;5;16m", "\(esc)[39m",
            "\(esc)[49m", "\(esc)[24m", "\(esc)[27m", "\(esc)[22m",
        ]
        let alphabet = Array("ab  ─ ▓  ")  // deliberately space-heavy
        var seed: UInt64 = 0x5EED_1234
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<400 {
            var line = "\(esc)[0m"
            for _ in 0..<(6 + next(40)) {
                if next(3) == 0 { line += palette[next(palette.count)] }
                line.append(alphabet[next(alphabet.count)])
            }
            check(line + "\(esc)[0m", expectSaving: false)
        }
    }
}
