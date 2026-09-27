//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SGRCollapsingSpellingCountTests.swift
//
//  What collapsing a row spells, counted rather than timed. A state spelled
//  from a reset is its whole parameter list built again as a string, and the
//  writer collapses every row it rebuilds, every frame, so a spelling nothing
//  uses is paid per state change per row per frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("Collapsing a row spells a state from a reset only where that is the answer")
struct SGRCollapsingSpellingCountTests {

    private let esc = "\u{1B}"

    /// `line` collapsed, and how many states the collapse spelled from a reset.
    private func collapsed(_ line: String, resetRestoresAField: Bool = false) -> (line: String, spelled: Int) {
        var spelled = 0
        let result = line.collapsingAdjacentSGR(
            resetRestoresAField: resetRestoresAField, absolutesSpelled: &spelled)
        return (result, spelled)
    }

    /// A row as the writer hands it over: opened by a reset, colours that change
    /// from cell to cell, closed by a reset. The first state after the line's
    /// first reset has nothing emitted to be a change from, so it is spelled from
    /// a reset. Every later one is a delta from what was emitted, and the delta
    /// spells its own absolute to compare against, so a second spelling of it
    /// is waste. One was made for every change, and the writer, which never
    /// asks for the unfinished row's reading, threw each of them away: 868
    /// allocations a frame on the `processes` session.
    @Test("A writer's row spells from a reset only its first state")
    func writerRowSpellsOnlyItsFirstState() {
        let line =
            "\(esc)[0m\(esc)[38;2;1;2;3ma\(esc)[38;2;4;5;6mb"
            + "\(esc)[38;2;7;8;9;48;2;1;1;1mc\(esc)[0m"
        let (result, spelled) = collapsed(line)
        #expect(result == line.collapsingAdjacentSGR(), "counting changed what is spelled")
        #expect(spelled == 1)
    }

    /// A reset after the first is netted like any other change, from what was
    /// emitted: it costs no spelling of its own, and neither do the changes
    /// after it.
    @Test("A later reset, and a change after it, costs no spelling")
    func laterResetsCostNone() {
        let fragment = "\(esc)[0m\(esc)[38;2;1;2;3ma\(esc)[38;2;4;5;6mb\(esc)[1mc"
        let (_, spelled) = collapsed(String(repeating: fragment, count: 3) + "\(esc)[0m")
        #expect(spelled == 1)
    }

    /// A row the writer has yet to finish puts the field around it back after a
    /// reset. There a return to that field after a colour must be spelled from
    /// a reset, since the shorter delta `ESC[49m` puts the terminal's own field
    /// under the cell: that spelling is the answer, and is made. The colour
    /// changes after it, on the field around the row, are deltas.
    @Test("An unfinished row spells from a reset where the field around it comes back")
    func unfinishedRowSpellsTheFieldsReturn() {
        let styled = "1;4;38;2;100;100;100"
        let line =
            "\(esc)[0m\(esc)[\(styled);48;2;9;9;9ma\(esc)[0;\(styled)mb"
            + "\(esc)[38;2;1;1;1mc\(esc)[38;2;2;2;2md\(esc)[0m"
        let (result, spelled) = collapsed(line, resetRestoresAField: true)
        #expect(result.contains("\(esc)[0;\(styled)mb"), "the field's return was not spelled from a reset")
        #expect(spelled == 2)
    }
}
