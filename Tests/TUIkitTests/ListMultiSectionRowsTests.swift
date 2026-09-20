//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListMultiSectionRowsTests.swift
//
//  Two or more `Section`s in one `List`. A lone Section is recognised by
//  `extractRows` and its header/content/footer become rows of the list; two
//  Sections make a `TupleView`, which used to fall through to the static-child
//  path and turn each WHOLE Section into one row keyed by its ordinal. So the
//  header was selectable, Down jumped a whole section — and where the ordinal
//  happened to cast into the selection type, the binding received a number
//  that named nothing in the data.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("List with several Sections", .rendersEnglishUI)
struct ListMultiSectionRowsTests {

    /// Two row types whose ids are BOTH `UUID` — the shape Apple's own
    /// multidimensional-list example has (`OceanRegion.ID` / `Sea.ID`) and the
    /// reason a mis-keyed selection compiles. The ids are hand-built so the
    /// two are told apart at runtime: a region's is all-zero but for its last
    /// digit, a sea's all-ones.
    private struct Region: Identifiable, Hashable {
        let id: UUID
        let name: String
        init(_ n: Int, _ name: String) {
            id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!
            self.name = name
        }
    }

    private struct Sea: Identifiable, Hashable {
        let id: UUID
        let name: String
        init(_ n: Int, _ name: String) {
            id = UUID(uuidString: "11111111-1111-1111-1111-11111111111\(n)")!
            self.name = name
        }
    }

    /// Apple's own shape: a region owns its seas, and the `ForEach` iterates
    /// the regions while the rows are the seas.
    private struct OceanRegion: Identifiable, Hashable {
        let id: UUID
        let name: String
        let seas: [Sea]
        init(_ n: Int, _ name: String, _ seas: [Sea]) {
            id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!
            self.name = name
            self.seas = seas
        }
    }

    private static let regions = [Region(1, "Pacific"), Region(2, "Atlantic")]
    private static let seas = [Sea(1, "Coral"), Sea(2, "Sargasso")]
    private static let oceanRegions = [
        OceanRegion(1, "Pacific", [Sea(1, "Coral"), Sea(2, "Philippine")]),
        OceanRegion(2, "Atlantic", [Sea(3, "Sargasso")]),
    ]

    private static func isRegionID(_ id: UUID) -> Bool {
        Self.regions.contains { $0.id == id }
    }

    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var env = EnvironmentValues()

        init() {
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
        }

        var handler: ItemListHandler<UUID>? {
            env.focusManager?.currentFocused as? ItemListHandler<UUID>
        }

        @discardableResult
        func render(_ view: some View) -> FrameBuffer {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            let context = RenderContext(
                availableWidth: 30, availableHeight: 14, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }
    }

    private func twoSections(selection: Binding<UUID?>) -> some View {
        List(selection: selection) {
            Section("Regions") {
                ForEach(Self.regions) { Text($0.name) }
            }
            Section("Seas") {
                ForEach(Self.seas) { Text($0.name) }
            }
        }
        .frame(height: 12)
    }

    @Test("Every section's items are rows of the list")
    func itemsAreRows() {
        let fixture = Fixture()
        var selection: UUID?
        fixture.render(
            twoSections(selection: Binding(get: { selection }, set: { selection = $0 })))

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        // header, Pacific, Atlantic, header, Coral, Sargasso
        #expect(handler.itemCount == 6, "got \(handler.itemCount) rows")
        #expect(
            handler.selectableIndices == [1, 2, 4, 5],
            "the two headers are chrome, the four items are rows: \(handler.selectableIndices.sorted())")
    }

    @Test("Selecting a row in the second section writes THAT row's id")
    func selectionCarriesTheRowsOwnID() {
        let fixture = Fixture()
        var selection: UUID?
        fixture.render(
            twoSections(selection: Binding(get: { selection }, set: { selection = $0 })))

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        // The ids the list publishes per row — `nil` where a row is chrome.
        #expect(
            handler.itemIDs == [
                nil, Self.regions[0].id, Self.regions[1].id, nil, Self.seas[0].id,
                Self.seas[1].id,
            ],
            "each row carries its own element's id: \(handler.itemIDs)")

        guard let sargasso = handler.itemIDs.firstIndex(of: Self.seas[1].id) else {
            Issue.record("no row carries Sargasso's id: \(handler.itemIDs)")
            return
        }
        handler.focusedIndex = sargasso
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)

        guard let chosen = selection else {
            Issue.record("the row selected nothing")
            return
        }
        #expect(
            !Self.isRegionID(chosen),
            "a Sea row must not write a Region id: \(chosen)")
        #expect(chosen == Self.seas[1].id, "expected Sargasso's id, got \(chosen)")
    }

    /// The second half is what makes the first falsifiable, and is the reason
    /// this test names the row BELOW the header at all. "Enter on row 0 writes
    /// nothing" is true of the broken tree too, for a reason that has nothing
    /// to do with headers: there row 0 was not a header but the whole first
    /// `Section` rendered as one ordinal-keyed row, and an ordinal cannot cast
    /// into this suite's `UUID` selection, so it was unselectable by accident.
    /// Pinning that row 1 is that section's first ITEM, and selects as itself,
    /// is what says row 0 is a header rather than a section.
    @Test("A section header is chrome, and the row below it is the section's first item")
    func headersAreChrome() {
        let fixture = Fixture()
        var selection: UUID?
        fixture.render(
            twoSections(selection: Binding(get: { selection }, set: { selection = $0 })))

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(
            handler.id(at: 0) == nil,
            "the 'Regions' header carries no id: \(String(describing: handler.id(at: 0)))")
        handler.focusedIndex = 0
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(
            selection == nil,
            "the 'Regions' header is chrome, not a row: \(String(describing: selection))")

        handler.focusedIndex = 1
        _ = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(
            selection == Self.regions[0].id,
            "the row under the header is that section's first item: \(String(describing: selection))")
    }

    /// Apple's worked example for a multidimensional list. This is the case
    /// that COMPILED and wrote the wrong id: the `ForEach` iterates regions, so
    /// the windowed path keyed every row by an `OceanRegion.ID` while the app
    /// looks the answer up among seas — both being `UUID`, nothing complained.
    @Test("A ForEach of Sections selects a SEA, not the region holding it")
    func foreachOfSectionsKeysByTheInnerRow() {
        let fixture = Fixture()
        var selection: UUID?
        let list = List(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            ForEach(Self.oceanRegions) { region in
                Section(region.name) {
                    ForEach(region.seas) { Text($0.name) }
                }
            }
        }
        .frame(height: 12)
        fixture.render(list)

        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        // header, Coral, Philippine, header, Sargasso
        #expect(handler.itemCount == 5, "got \(handler.itemCount) rows")
        #expect(
            handler.selectableIndices == [1, 2, 4],
            "the seas are the rows: \(handler.selectableIndices.sorted())")

        let sargassoID = Self.oceanRegions[1].seas[0].id
        #expect(
            handler.itemIDs == [
                nil, Self.oceanRegions[0].seas[0].id, Self.oceanRegions[0].seas[1].id, nil,
                sargassoID,
            ],
            "the rows carry SEA ids, not the regions': \(handler.itemIDs)")

        guard let sargasso = handler.itemIDs.firstIndex(of: sargassoID) else {
            Issue.record("no row carries Sargasso's id: \(handler.itemIDs)")
            return
        }
        handler.focusedIndex = sargasso
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == true)

        let regionIDs = Set(Self.oceanRegions.map(\.id))
        guard let chosen = selection else {
            Issue.record("the row selected nothing")
            return
        }
        #expect(!regionIDs.contains(chosen), "a region's id reached the binding: \(chosen)")
        #expect(chosen == sargassoID, "expected Sargasso's id, got \(chosen)")
    }
}
