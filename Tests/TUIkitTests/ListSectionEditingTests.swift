//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSectionEditingTests.swift
//
//  `.onDelete` and `.onMove` on a `ForEach` that is not the List's whole
//  content: inside a `Section`, inside one of several `Section`s, and inside a
//  `Section` a `ForEach` produced. The offsets such a row hands its action are
//  indices into the `ForEach`'s OWN collection — not the list's row numbering,
//  which counts section headers and every earlier section's rows as well — and
//  a reorder cannot leave the section, because the rows on the other side of a
//  header belong to a different collection entirely.
//
//  The arrangements whose action no row owns — and which the `List`
//  therefore refuses — are in `ListUnownedEditActionTests`, a `ForEach` with
//  a `Group` or an `if`/`else` between it and its container is in
//  `ListGroupEditingTests`, and
//  where a delete leaves the cursor is in `ListEditingCursorLandingTests`; the
//  harness all four share is `ListSectionEditingFixture`.
//
//  Every assertion here is on the collection afterwards, never on a count of
//  callbacks: an offset-based oracle passes just as happily when the action
//  deletes the right index of the wrong array.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Editing a ForEach inside a Section", .rendersEnglishUI)
struct ListSectionEditingTests {

    // MARK: - One Section

    @Test("A Section's ForEach deletes from its own collection, not by row number")
    func singleSectionDeletesByDataOffset() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
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

        // header, alpha, beta, gamma — so "beta" is row 2 and data offset 1.
        #expect(fixture.pressDelete(onRow: 2, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    // MARK: - Several Sections

    @Test("The second row of the second Section deletes from the SECOND Section's collection")
    func secondSectionDeletesFromItsOwnCollection() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(twoSections(alpha: alpha, beta: beta, betaEditable: true))

        // header, a1, a2, a3, header, b1, b2, b3 — "b2" is row 6, data offset 1.
        #expect(fixture.pressDelete(onRow: 6, named: "b2") == true)
        #expect(beta.value == ["b1", "b3"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "the other section is untouched: \(alpha.value)")
    }

    @Test("A row whose own ForEach has no delete action leaves Delete alone")
    func nonDeletableSectionFallsThrough() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(twoSections(alpha: alpha, beta: beta, betaEditable: false))

        #expect(
            fixture.pressDelete(onRow: 6, named: "b2") == false,
            "Delete must fall through on a row nothing can delete")
        #expect(beta.value == ["b1", "b2", "b3"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "got \(alpha.value)")
    }

    // MARK: - A ForEach of Sections

    @Test("A Section a ForEach produced deletes from THAT section's own collection")
    func foreachOfSectionsDeletesTheInnerRow() {
        let regions = MainActorBox([
            EditableRegion(id: "North", seas: ["coral", "philippine"]),
            EditableRegion(id: "South", seas: ["sargasso", "weddell"]),
        ])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                ForEach(regions.value) { region in
                    Section(region.id) {
                        ForEach(region.seas, id: \.self) { Text($0) }
                            .onDelete { offsets in
                                guard
                                    let index = regions.value.firstIndex(where: {
                                        $0.id == region.id
                                    })
                                else { return }
                                regions.value[index].seas.remove(atOffsets: offsets)
                            }
                    }
                }
            }
            .frame(height: 12))

        // header, coral, philippine, header, sargasso, weddell.
        #expect(fixture.pressDelete(onRow: 5, named: "weddell") == true)
        #expect(regions.value[1].seas == ["sargasso"], "got \(regions.value[1].seas)")
        #expect(
            regions.value[0].seas == ["coral", "philippine"],
            "the other region is untouched: \(regions.value[0].seas)")
    }

    // MARK: - .deleteDisabled inside a Section

    @Test("deleteDisabled names the row that wrote it, not the row that many places into the list")
    func deleteDisabledIsRelativeToTheSectionsOwnRows() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        func render() {
            fixture.render(
                List(selection: .constant(String?.none)) {
                    Section("Alpha") {
                        ForEach(alpha.value, id: \.self) { Text($0) }
                            .onDelete { alpha.value.remove(atOffsets: $0) }
                    }
                    Section("Beta") {
                        ForEach(beta.value, id: \.self) { item in
                            Text(item).deleteDisabled(item == "b2")
                        }
                        .onDelete { beta.value.remove(atOffsets: $0) }
                    }
                }
                .frame(height: 12))
        }
        render()

        // "b2" refuses, and refusing leaves the key alone.
        #expect(fixture.pressDelete(onRow: 6, named: "b2") == false)
        #expect(beta.value == ["b1", "b2", "b3"], "b2 refused: \(beta.value)")

        // Its neighbours do not — including "a2", which sits at the same data
        // offset (1) inside the OTHER section and must not inherit the refusal.
        #expect(fixture.pressDelete(onRow: 2, named: "a2") == true)
        #expect(alpha.value == ["a1", "a3"], "got \(alpha.value)")
    }

    // MARK: - Reordering

    private func twoReorderableSections(
        alpha: MainActorBox<[String]>, beta: MainActorBox<[String]>, betaMovable: Bool
    ) -> some View {
        let betaRows = ForEach(beta.value, id: \.self) { Text($0) }
        return List(selection: .constant(String?.none)) {
            Section("Alpha") {
                ForEach(alpha.value, id: \.self) { Text($0) }
                    .onMove { alpha.value.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("Beta") {
                betaMovable
                    ? betaRows.onMove { beta.value.move(fromOffsets: $0, toOffset: $1) }
                    : betaRows
            }
        }
        .frame(height: 12)
    }

    @Test("A Section's ForEach reorders its own collection, by data offset not row number")
    func singleSectionReordersByDataOffset() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Items") {
                    ForEach(items.value, id: \.self) { Text($0) }
                        .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .frame(height: 10))

        // header, alpha, beta, gamma — "alpha" is row 1 and data offset 0.
        #expect(fixture.pickUpMoveAndPlace(row: 1, named: "alpha", by: 1))
        #expect(items.value == ["beta", "alpha", "gamma"], "got \(items.value)")
    }

    @Test("The second Section's rows reorder the SECOND Section's collection")
    func secondSectionReordersItsOwnCollection() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(twoReorderableSections(alpha: alpha, beta: beta, betaMovable: true))

        // header, a1, a2, a3, header, b1, b2, b3 — "b1" is row 5, data offset 0.
        #expect(fixture.pickUpMoveAndPlace(row: 5, named: "b1", by: 1))
        #expect(beta.value == ["b2", "b1", "b3"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "the other section is untouched: \(alpha.value)")
    }

    /// Pushed five rows down in an eight-row list, a row of the first section
    /// would land among the second's — where an offset means something else.
    @Test("A held row stops at its own Section's end, however far it is pushed")
    func aHeldRowCannotLeaveItsSection() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(twoReorderableSections(alpha: alpha, beta: beta, betaMovable: true))

        #expect(fixture.pickUpMoveAndPlace(row: 1, named: "a1", by: 5))
        #expect(alpha.value == ["a2", "a3", "a1"], "the end of its OWN section: \(alpha.value)")
        #expect(beta.value == ["b1", "b2", "b3"], "and nothing arrived here: \(beta.value)")
    }

    @Test("A Section a ForEach produced reorders within that section's own collection")
    func foreachOfSectionsReordersTheInnerRows() {
        let regions = MainActorBox([
            EditableRegion(id: "North", seas: ["coral", "philippine"]),
            EditableRegion(id: "South", seas: ["sargasso", "weddell"]),
        ])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                ForEach(regions.value) { region in
                    Section(region.id) {
                        ForEach(region.seas, id: \.self) { Text($0) }
                            .onMove { offsets, destination in
                                guard
                                    let index = regions.value.firstIndex(where: {
                                        $0.id == region.id
                                    })
                                else { return }
                                regions.value[index].seas.move(
                                    fromOffsets: offsets, toOffset: destination)
                            }
                    }
                }
            }
            .frame(height: 12))

        // header, coral, philippine, header, sargasso, weddell.
        #expect(fixture.pickUpMoveAndPlace(row: 4, named: "sargasso", by: 1))
        #expect(regions.value[1].seas == ["weddell", "sargasso"], "got \(regions.value[1].seas)")
        #expect(
            regions.value[0].seas == ["coral", "philippine"],
            "the other region is untouched: \(regions.value[0].seas)")
    }

    @Test("A row whose own ForEach has no move action is not reorderable")
    func nonMovableSectionRefusesThePickUp() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(twoReorderableSections(alpha: alpha, beta: beta, betaMovable: false))

        #expect(
            fixture.pickUpMoveAndPlace(row: 5, named: "b1", by: 1) == false,
            "the pick-up chord must fall through on a row nothing can move")
        #expect(beta.value == ["b1", "b2", "b3"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "got \(alpha.value)")
    }

    /// The mouse half, end to end: a `.live` drag moves the data at every step,
    /// so a pointer that reached another section's rows would have moved a row
    /// into a collection it never belonged to before any drop happened.
    @Test("A live drag cannot carry a row out of its Section")
    func liveDragStaysInsideTheSection() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        func render() {
            fixture.render(twoReorderableSections(alpha: alpha, beta: beta, betaMovable: true))
        }
        render()
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        // Grab "b1" (row 5) and drag it onto "b3" (row 7) — a move inside Beta.
        handler.beginReorder(grabbing: 5)
        render()
        guard let lastBetaRow = fixture.band(row: 7) else {
            Issue.record("no band for row 7: \(handler.visibleRowBands)")
            return
        }
        handler.dragReorder(toContentY: lastBetaRow.yStart)
        #expect(beta.value == ["b2", "b3", "b1"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "got \(alpha.value)")

        // Now drag on up into Alpha. Alpha's rows are not drop targets for this
        // gesture at all, and the pointer resolves to the near edge of Beta —
        // so the row travels to the top of its OWN section and Alpha is never
        // written to.
        render()
        guard let alphaRow = fixture.band(row: 2) else {
            Issue.record("no band for row 2: \(handler.visibleRowBands)")
            return
        }
        #expect(
            handler.dropTarget(atContentY: alphaRow.yStart) == nil,
            "a row of the other section is not a drop target for this drag")
        handler.dragReorder(toContentY: alphaRow.yStart)
        #expect(alpha.value == ["a1", "a2", "a3"], "Alpha is never written to: \(alpha.value)")
        #expect(beta.value == ["b1", "b2", "b3"], "the row went to Beta's top: \(beta.value)")
    }
}
