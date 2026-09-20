//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListEditingCursorLandingTests.swift
//
//  Where the cursor stands once a row has been deleted out from under it.
//  The row below slides up into the emptied slot and the cursor keeps THAT
//  row, clamped to its own `Section`'s new end so it never lands on the
//  chrome around it — and when the section had only the one row there is no
//  new end, so the cursor has to go looking for the nearest row it can stand
//  on at all.
//
//  Every assertion is on the id the cursor reports afterwards, never on a row
//  number: a row number passes just as happily when the row that moved into
//  it is a header.
//
//  The row-to-collection mapping these deletes go through is pinned by
//  `ListSectionEditingTests`; the harness is `ListSectionEditingFixture`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Where the cursor stands after a delete", .rendersEnglishUI)
struct ListEditingCursorLandingTests {

    /// The row below slides up into the deleted row's slot and the cursor
    /// keeps it, clamped to the section's own end so it never lands on the
    /// chrome that follows. A section holding ONE row has no row below and no
    /// new end, and the clamp then points one row ABOVE the section's first:
    /// at its HEADER, which carries no selection value, answers nothing to
    /// Return or Space, and would wear the focus ring.
    @Test("Emptying a Section puts the cursor on a row, not on the chrome around it")
    func emptyingASectionLeavesTheCursorOnARow() {
        let alpha = MainActorBox(["only"])
        let beta = MainActorBox(["x", "y"])
        let fixture = ListSectionEditingFixture()
        func render() {
            fixture.render(twoSections(alpha: alpha, beta: beta, betaEditable: true))
        }
        render()

        // header, only, header, x, y — "only" is row 1, data offset 0.
        #expect(fixture.pressDelete(onRow: 1, named: "only") == true)
        #expect(alpha.value.isEmpty, "got \(alpha.value)")
        #expect(beta.value == ["x", "y"], "the other section is untouched: \(beta.value)")

        // header, header, x, y — the next row a cursor can stand on is "x",
        // two rows of chrome below where it was.
        render()
        #expect(
            fixture.focusedRowID == "x",
            "the cursor stands on \(String(describing: fixture.focusedRowID))")
    }

    /// The same emptying with nothing BELOW: the cursor goes back up rather
    /// than sitting on the header of the section it just emptied.
    @Test("Emptying the LAST Section walks the cursor back to the row above it")
    func emptyingTheLastSectionWalksTheCursorBack() {
        let alpha = MainActorBox(["x", "y"])
        let beta = MainActorBox(["only"])
        let fixture = ListSectionEditingFixture()
        func render() {
            fixture.render(twoSections(alpha: alpha, beta: beta, betaEditable: true))
        }
        render()

        // header, x, y, header, only — "only" is row 4, data offset 0.
        #expect(fixture.pressDelete(onRow: 4, named: "only") == true)
        #expect(beta.value.isEmpty, "got \(beta.value)")
        #expect(alpha.value == ["x", "y"], "the other section is untouched: \(alpha.value)")

        render()
        #expect(
            fixture.focusedRowID == "y",
            "the cursor stands on \(String(describing: fixture.focusedRowID))")
    }

    /// The clamp's own job, pinned beside the case it gets wrong: while the
    /// section still HAS a row, deleting its last one leaves the cursor on the
    /// section's new last row rather than on the header that follows it.
    @Test("Deleting a Section's last row leaves the cursor on that section's new last row")
    func deletingASectionsLastRowKeepsTheCursorInTheSection() {
        let alpha = MainActorBox(["a1", "a2"])
        let beta = MainActorBox(["x"])
        let fixture = ListSectionEditingFixture()
        func render() {
            fixture.render(twoSections(alpha: alpha, beta: beta, betaEditable: true))
        }
        render()

        // header, a1, a2, header, x — "a2" is row 2, data offset 1.
        #expect(fixture.pressDelete(onRow: 2, named: "a2") == true)
        #expect(alpha.value == ["a1"], "got \(alpha.value)")

        render()
        #expect(
            fixture.focusedRowID == "a1",
            "the cursor stands on \(String(describing: fixture.focusedRowID))")
    }

    /// The shape the arithmetic is easiest to get wrong on, and the one that
    /// HIDES the error: one Section, one row, so the list is two rows and
    /// `min(span.upperBound, itemCount) - 2` is 0 — the header, which is also
    /// the only row left. Pinned so nobody re-derives it and concludes the
    /// clamp was fine: there is no row to stand on here, and standing on the
    /// chrome is refused the moment Delete is pressed again.
    @Test("A one-row Section that empties leaves nothing to stand on, and refuses Delete there")
    func emptyingTheOnlySectionLeavesNoRowToStandOn() {
        let items = MainActorBox(["only"])
        let fixture = ListSectionEditingFixture()
        func render() {
            fixture.render(
                List(selection: .constant(String?.none)) {
                    Section("Items") {
                        ForEach(items.value, id: \.self) { Text($0) }
                            .onDelete { items.value.remove(atOffsets: $0) }
                    }
                }
                .frame(height: 10))
        }
        render()

        #expect(fixture.pressDelete(onRow: 1, named: "only") == true)
        #expect(items.value.isEmpty, "got \(items.value)")

        render()
        #expect(
            fixture.focusedRowID == nil,
            "no row is left: \(String(describing: fixture.focusedRowID))")
        #expect(
            fixture.handler?.handleKeyEvent(KeyEvent(key: .delete)) == false,
            "Delete on chrome belongs to no collection and must fall through")
        #expect(items.value.isEmpty, "and nothing else was deleted: \(items.value)")
    }
}
