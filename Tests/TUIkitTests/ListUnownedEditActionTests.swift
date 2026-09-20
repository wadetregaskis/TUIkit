//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListUnownedEditActionTests.swift
//
//  `.onDelete` / `.onMove` written on a `ForEach` that no list row can be
//  attributed to, which the `List` therefore refuses rather than guesses at:
//  a `ForEach` that is not its container's whole content — beside a
//  hand-written row, or beside a second `ForEach` — where the children arrive
//  flattened and no longer say which of them produced any row; and a
//  `ForEach` whose elements are whole `Section`s, where the action addresses
//  the SECTIONS and the gesture is on a row inside one.
//
//  Every refusal here is pinned so it reads as a decision rather than as an
//  ordinary no-op somebody "fixes": the repair each arrangement invites is an
//  offset into the wrong collection — measured from a header, or into the
//  outer array — so the assertions are on the collection afterwards, and the
//  key is pressed on EVERY row, which needs no claim about which row is which.
//
//  The arrangements that ARE wired are in `ListSectionEditingTests`; the
//  harness is `ListSectionEditingFixture`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("An edit action no row owns", .rendersEnglishUI)
struct ListUnownedEditActionTests {

    // MARK: - A ForEach whose elements are Sections

    /// The gap, pinned so nobody closes it by accident. `.onDelete` on the
    /// OUTER `ForEach` addresses the regions, and a `List` shows no affordance
    /// for deleting a whole section — SwiftUI shows none either. Delete on a
    /// row belongs to the row's own `ForEach`; if it ever reached the outer one
    /// it would delete a REGION while the user was pointing at a sea.
    @Test("Delete on a row never reaches the outer ForEach that made the Sections")
    func outerForEachOfSectionsIsNotTheRowsDeleter() {
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
                    }
                }
                .onDelete { regions.value.remove(atOffsets: $0) }
            }
            .frame(height: 12))

        #expect(
            fixture.pressDelete(onRow: 5, named: "weddell") == false,
            "no row of a section is the section itself")
        #expect(regions.value.count == 2, "no region was deleted: \(regions.value.map(\.id))")
        #expect(regions.value[1].seas == ["sargasso", "weddell"], "got \(regions.value[1].seas)")
    }

    /// `.onMove`'s twin of the same gap, and the more dangerous half: a
    /// delete that reached the outer `ForEach` would take a whole region, but
    /// a MOVE that reached it would renumber the regions under a cursor that
    /// was pointing at a sea, and the keyboard reorder writes at the drop
    /// rather than at the pick-up, so nothing would look wrong until then.
    ///
    /// The chord is pressed on EVERY row — headers included — so this says no
    /// row of such a list is a grabbable region, which needs no claim about
    /// which row is which.
    @Test("The pick-up chord never reaches the outer ForEach that made the Sections")
    func outerForEachOfSectionsIsNotTheRowsMover() {
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
                    }
                }
                .onMove { regions.value.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 12))
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == 6, "two headers and four seas, got \(handler.itemCount)")

        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) == false,
                "row \(row) claimed the pick-up chord")
            // The chord is followed through anyway — Down to shift the landing
            // slot, Return to place — so that if a pick-up were ever accepted
            // the row would land somewhere and the collection below would say
            // so. A refused pick-up leaves both keys to their ordinary jobs.
            _ = handler.handleKeyEvent(KeyEvent(key: .down))
            _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        }
        #expect(
            regions.value.map(\.id) == ["North", "South"],
            "the regions kept their order: \(regions.value.map(\.id))")
        #expect(
            regions.value.map(\.seas) == [["coral", "philippine"], ["sargasso", "weddell"]],
            "and no sea moved either: \(regions.value.map(\.seas))")
    }

    // MARK: - A ForEach that shares its container with hand-written rows

    /// The one arrangement that still refuses, pinned so the refusal is a
    /// decision somebody can read rather than a silent no-op somebody
    /// "fixes".
    ///
    /// `resolveChildViews` flattens the `ForEach` in among the hand-written
    /// rows beside it, and a row arrives with nothing left on it to say which
    /// of the two produced it. Wiring the section's actions anyway — the
    /// obvious repair — hands `onDelete` an offset measured from the HEADER,
    /// so a press on the second looped row deletes the third element; the
    /// assertions below are on the collection for exactly that reason.
    ///
    /// Every row is tried, not one: this says no row of such a section is
    /// deletable, which needs no claim about which row is which.
    @Test("A Section mixing a ForEach with a hand-written row refuses Delete on every row")
    func mixedSectionRefusesEveryDelete() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        let buffer = fixture.render(
            List(selection: .constant(Int?.none)) {
                Section("Items") {
                    Text("All items")
                    ForEach(items.value, id: \.self) { Text($0) }
                        .onDelete { items.value.remove(atOffsets: $0) }
                }
            }
            .frame(height: 10))
        guard let handler = fixture.handler(Int.self) else {
            Issue.record("the list took focus")
            return
        }
        // The arrangement really is the mixed one — the hand-written row and
        // all three looped rows drew, under one header.
        let drawn = buffer.lines.joined(separator: "\n")
        for line in ["Items", "All items", "alpha", "beta", "gamma"] {
            #expect(drawn.contains(line), "\(line) drew:\n\(drawn)")
        }
        #expect(handler.itemCount == 5, "header + four rows, got \(handler.itemCount)")

        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .delete)) == false,
                "row \(row) claimed Delete")
        }
        #expect(items.value == ["alpha", "beta", "gamma"], "nothing was deleted: \(items.value)")
    }

    /// `.onMove` refuses the same arrangement for the same reason, and refuses
    /// it at the pick-up — before a drag can start and before `.live` feedback
    /// can write anything.
    @Test("A Section mixing a ForEach with a hand-written row refuses the pick-up on every row")
    func mixedSectionRefusesEveryPickUp() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                Section("Items") {
                    Text("All items")
                    ForEach(items.value, id: \.self) { Text($0) }
                        .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .frame(height: 10))
        guard let handler = fixture.handler(Int.self) else {
            Issue.record("the list took focus")
            return
        }
        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) == false,
                "row \(row) claimed the pick-up chord")
            // The chord is followed through anyway — Down to shift the landing
            // slot, Return to place — so that if a pick-up were ever accepted
            // the row would land somewhere and the collection below would say
            // so. A refused pick-up leaves both keys to their ordinary jobs.
            _ = handler.handleKeyEvent(KeyEvent(key: .down))
            _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        }
        #expect(items.value == ["alpha", "beta", "gamma"], "nothing moved: \(items.value)")
    }

    /// The same refusal without a `Section` in sight: it is the FLATTENING
    /// that loses the attribution, and a `List` mixing a `ForEach` with a
    /// hand-written row flattens through the same call. Pinned beside its
    /// twin because a shared cause is not a shared rule until both are
    /// asserted — the flat list reaches it through `_ListCore`'s own child
    /// walk, not through `Section.sectionRowActions`.
    @Test("A List mixing a ForEach with a hand-written row refuses Delete on every row")
    func mixedFlatListRefusesEveryDelete() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                Text("All items")
                ForEach(items.value, id: \.self) { Text($0) }
                    .onDelete { items.value.remove(atOffsets: $0) }
            }
            .frame(height: 10))
        guard let handler = fixture.handler(Int.self) else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == 4, "four rows, got \(handler.itemCount)")
        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .delete)) == false,
                "row \(row) claimed Delete")
        }
        #expect(items.value == ["alpha", "beta", "gamma"], "nothing was deleted: \(items.value)")
    }

    /// The fourth corner of that pair of twins: the flat `List`'s pick-up.
    /// `Section` / flat and Delete / pick-up are two independent choices, and
    /// three of the four squares being pinned says nothing about the fourth —
    /// the flat list's move refusal is decided by `_ListCore`'s own child
    /// walk producing no ``ListRowEditOwner``, which is a different line of
    /// code from the one `Section.sectionRowActions` returns `nil` on.
    @Test("A List mixing a ForEach with a hand-written row refuses the pick-up on every row")
    func mixedFlatListRefusesEveryPickUp() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                Text("All items")
                ForEach(items.value, id: \.self) { Text($0) }
                    .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 10))
        guard let handler = fixture.handler(Int.self) else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == 4, "four rows, got \(handler.itemCount)")
        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) == false,
                "row \(row) claimed the pick-up chord")
            // The chord is followed through anyway — Down to shift the landing
            // slot, Return to place — so that if a pick-up were ever accepted
            // the row would land somewhere and the collection below would say
            // so. A refused pick-up leaves both keys to their ordinary jobs.
            _ = handler.handleKeyEvent(KeyEvent(key: .down))
            _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        }
        #expect(items.value == ["alpha", "beta", "gamma"], "nothing moved: \(items.value)")
    }

    // MARK: - Two ForEaches in one container

    /// No hand-written row in sight and the attribution is lost just the same:
    /// two `ForEach`es are a `TupleView`, a `TupleView` is flattened by the
    /// same call, and what comes back is six rows that no longer say which
    /// loop made them. The obvious repair — `Section.sectionRowActions`
    /// answering with the content's actions — cannot even be written here,
    /// because there are two sets of actions and nothing to choose between
    /// them; a guess at the first would delete from `starts` while the cursor
    /// was on a row of `ends`.
    ///
    /// Both keys are pressed on every row, and both collections are asserted:
    /// a refusal that only held for one of the two loops would leave the other
    /// silently editable.
    @Test("A Section holding two ForEaches refuses both editing gestures on every row")
    func sectionOfTwoForEachesRefusesEveryGesture() {
        let starts = MainActorBox(["alpha", "beta"])
        let ends = MainActorBox(["chi", "psi"])
        let fixture = ListSectionEditingFixture()
        let buffer = fixture.render(
            List(selection: .constant(Int?.none)) {
                Section("Letters") {
                    ForEach(starts.value, id: \.self) { Text($0) }
                        .onDelete { starts.value.remove(atOffsets: $0) }
                        .onMove { starts.value.move(fromOffsets: $0, toOffset: $1) }
                    ForEach(ends.value, id: \.self) { Text($0) }
                        .onDelete { ends.value.remove(atOffsets: $0) }
                        .onMove { ends.value.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .frame(height: 10))
        guard let handler = fixture.handler(Int.self) else {
            Issue.record("the list took focus")
            return
        }
        // The arrangement really is the two-loop one: both loops' rows drew,
        // under one header, and each is a row of its own.
        let drawn = buffer.lines.joined(separator: "\n")
        for line in ["Letters", "alpha", "beta", "chi", "psi"] {
            #expect(drawn.contains(line), "\(line) drew:\n\(drawn)")
        }
        #expect(handler.itemCount == 5, "header + four rows, got \(handler.itemCount)")

        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .delete)) == false,
                "row \(row) claimed Delete")
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) == false,
                "row \(row) claimed the pick-up chord")
            // The chord is followed through anyway — Down to shift the landing
            // slot, Return to place — so that if a pick-up were ever accepted
            // the row would land somewhere and the collection below would say
            // so. A refused pick-up leaves both keys to their ordinary jobs.
            _ = handler.handleKeyEvent(KeyEvent(key: .down))
            _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        }
        #expect(starts.value == ["alpha", "beta"], "the first loop is untouched: \(starts.value)")
        #expect(ends.value == ["chi", "psi"], "the second loop is untouched: \(ends.value)")
    }

    /// And the same two loops without a `Section` around them, which is a
    /// different route to the same place — `_ListCore`'s own child walk rather
    /// than `Section.sectionRowActions` — for the same reason its hand-written
    /// twin is pinned separately.
    @Test("A List holding two ForEaches refuses both editing gestures on every row")
    func flatListOfTwoForEachesRefusesEveryGesture() {
        let starts = MainActorBox(["alpha", "beta"])
        let ends = MainActorBox(["chi", "psi"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(starts.value, id: \.self) { Text($0) }
                    .onDelete { starts.value.remove(atOffsets: $0) }
                    .onMove { starts.value.move(fromOffsets: $0, toOffset: $1) }
                ForEach(ends.value, id: \.self) { Text($0) }
                    .onDelete { ends.value.remove(atOffsets: $0) }
                    .onMove { ends.value.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 10))
        guard let handler = fixture.handler(Int.self) else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == 4, "four rows, got \(handler.itemCount)")
        for row in 0..<handler.itemCount {
            handler.focusedIndex = row
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .delete)) == false,
                "row \(row) claimed Delete")
            #expect(
                handler.handleKeyEvent(KeyEvent(key: .character("r"), ctrl: true)) == false,
                "row \(row) claimed the pick-up chord")
            // The chord is followed through anyway — Down to shift the landing
            // slot, Return to place — so that if a pick-up were ever accepted
            // the row would land somewhere and the collection below would say
            // so. A refused pick-up leaves both keys to their ordinary jobs.
            _ = handler.handleKeyEvent(KeyEvent(key: .down))
            _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        }
        #expect(starts.value == ["alpha", "beta"], "the first loop is untouched: \(starts.value)")
        #expect(ends.value == ["chi", "psi"], "the second loop is untouched: \(ends.value)")
    }
}
