//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListEdgeAnchorTests.swift
//
//  `Documentation/Scroll-anchoring.md` §1.1 Bottom — follow-the-log — for
//  `List` and `Table`. The ScrollView had this from the start;
//  `ItemListHandler` had no edge behaviour at all, so `.defaultScrollAnchor(
//  .bottom)` on a List was accepted and did nothing. Measured before the fix,
//  40 rows appending five: `before=[0…4] after=[0…4]` for the declared anchor,
//  the bound anchor, and no anchor alike — all three identical, which is what
//  "the anchor is not consulted" looks like.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct Entry: Identifiable, Sendable {
    let id: Int
    var name: String { "row \(id)" }
}

@MainActor
@Suite("List / Table edge anchors")
struct ListEdgeAnchorTests {

    private static let height = 8

    // MARK: - Harnesses

    private func renderList(
        ids: [Int], declared: UnitPoint?, bound: ErasedScrollAnchor?,
        tui: TUIContext, fm: FocusManager
    ) -> [String] {
        let view = List(selection: .constant(Int?.none)) {
            ForEach(ids, id: \.self) { Text("row \($0)") }
        }
        .frame(height: Self.height)
        return render(view, declared: declared, bound: bound, tui: tui, fm: fm)
    }

    private func renderTable(
        ids: [Int], declared: UnitPoint?, bound: ErasedScrollAnchor?,
        tui: TUIContext, fm: FocusManager
    ) -> [String] {
        let view = Table(ids.map(Entry.init(id:)), selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Entry.name)
        }
        .frame(height: Self.height + 3)  // top border + header + bottom border
        return render(view, declared: declared, bound: bound, tui: tui, fm: fm)
    }

    private func render<V: View>(
        _ view: V, declared: UnitPoint?, bound: ErasedScrollAnchor?,
        tui: TUIContext, fm: FocusManager
    ) -> [String] {
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        env.defaultScrollAnchor = declared
        if let bound { env.anchorPosition = .constant(bound) }
        let context = RenderContext(
            availableWidth: 28, availableHeight: Self.height + 3, environment: env, tuiContext: tui)

        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private func shownIDs(_ lines: [String]) -> [Int] {
        lines.compactMap { line in
            guard let marker = line.range(of: "row ") else { return nil }
            return Int(line[marker.upperBound...].prefix { $0.isNumber })
        }
    }

    /// Settles the view, appends five rows, and reports what was visible before
    /// and after.
    private func appendUnder(
        declared: UnitPoint?, bound: ErasedScrollAnchor?,
        render: ([Int], UnitPoint?, ErasedScrollAnchor?, TUIContext, FocusManager) -> [String]
    ) -> (before: [Int], after: [Int]) {
        let tui = TUIContext()
        let fm = FocusManager()
        var ids = Array(0..<40)

        for _ in 0..<3 { _ = render(ids, declared, bound, tui, fm) }
        let before = shownIDs(render(ids, declared, bound, tui, fm))
        ids.append(contentsOf: 100..<105)
        let after = shownIDs(render(ids, declared, bound, tui, fm))
        return (before, after)
    }

    // MARK: - List

    @Test("A List with a declared .bottom opens at the tail and follows appends")
    func listDeclaredBottomFollows() {
        let (before, after) = appendUnder(declared: .bottom, bound: nil, render: renderList)
        #expect(before.last == 39, "opens at the tail: \(before)")
        #expect(after.last == 104, "follows the new tail: \(after)")
    }

    @Test("A List with a bound .bottom follows with no declaration")
    func listBoundBottomFollows() {
        let (before, after) = appendUnder(declared: nil, bound: .bottom, render: renderList)
        #expect(before.last == 39, "the bound anchor put it at the tail: \(before)")
        #expect(after.last == 104, "and it follows: \(after)")
    }

    /// The contrast that makes the two above meaningful: Window (the default)
    /// keeps its line coordinates, so it neither opens at the tail nor follows.
    @Test("An unanchored List stays where it is")
    func unanchoredListDoesNotFollow() {
        let (before, after) = appendUnder(declared: nil, bound: nil, render: renderList)
        #expect(before.first == 0, "opens at the top: \(before)")
        #expect(after == before, "an append moves nothing: \(after)")
    }

    /// A bound `.window` is an explicit release, and must beat the declaration
    /// here exactly as it does in a ScrollView.
    @Test("A bound .window releases a List's declared .bottom")
    func listReleasedDoesNotFollow() {
        let (before, after) = appendUnder(declared: .bottom, bound: .window, render: renderList)
        #expect(before.first == 0, "released: not glued to the tail: \(before)")
        #expect(after == before, "and appends do not move it: \(after)")
    }

    // MARK: - Table (the sibling)

    @Test("A Table with a declared .bottom follows appends too")
    func tableDeclaredBottomFollows() {
        let (before, after) = appendUnder(declared: .bottom, bound: nil, render: renderTable)
        #expect(before.last == 39, "opens at the tail: \(before)")
        #expect(after.last == 104, "follows the new tail: \(after)")
    }

    @Test("An unanchored Table stays where it is")
    func unanchoredTableDoesNotFollow() {
        let (before, after) = appendUnder(declared: nil, bound: nil, render: renderTable)
        #expect(before.first == 0, "opens at the top: \(before)")
        #expect(after == before, "an append moves nothing: \(after)")
    }

    // MARK: - The engagement rule, at the handler

    /// Engagement is POSITIONAL: at the tail ⇒ following; scrolled away ⇒ not.
    /// No stored "am I following" flag, so nothing can get out of step with
    /// where the view actually is — the same rule the ScrollView's glue uses.
    /// This is what stops the follow from fighting a user who scrolled up.
    @Test("Scrolling away from the tail releases the follow; returning re-engages")
    func followIsPositional() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8,
            selectionMode: .single, canBeFocused: true)
        handler.declaredAnchorMode = .bottom

        handler.applyAnchorHold()
        #expect(handler.scrollOffset == handler.maxOffset, "opens glued to the tail")

        // The user scrolls up three rows.
        handler.scroll(by: -3)
        let scrolledTo = handler.scrollOffset
        #expect(scrolledTo < handler.maxOffset, "really moved off the tail")

        // More rows arrive: the follow must NOT drag the view back down.
        handler.itemCount = 45
        handler.applyAnchorHold()
        #expect(
            handler.scrollOffset == scrolledTo,
            "a released follow leaves the reader where they are")

        // Scrolling back to the bottom re-engages it.
        handler.scrollOffset = handler.maxOffset
        handler.applyAnchorHold()
        handler.itemCount = 50
        handler.applyAnchorHold()
        #expect(handler.scrollOffset == handler.maxOffset, "back at the tail, following again")
    }

    /// The cursor-carry is scoped to frames where the tail ADVANCES (opening
    /// placement, appends, re-engagement). Carrying it on every glued frame
    /// made the arrow keys dead on a focused `.bottom` list: Up moved the
    /// cursor to a row that was already visible, so no offset moved, so the
    /// next render was still glued and snapped the cursor straight back — the
    /// documented release path ("arrowing up moves the offset off the tail")
    /// could never engage because the cursor was reset before it could reach
    /// the viewport's top edge.
    @Test("Arrow-up walks off the tail; appends still carry the cursor")
    func arrowUpEscapesTheGlue() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 40, viewportHeight: 8,
            selectionMode: .single, canBeFocused: true)
        handler.declaredAnchorMode = .bottom

        handler.applyAnchorHold()
        #expect(handler.scrollOffset == handler.maxOffset, "opens glued to the tail")
        #expect(handler.focusedIndex == 39, "the opening placement carries the cursor")

        // Up moves the cursor to a row that is already visible — no offset
        // moves — and the following steady glued render must leave it there.
        handler.moveFocus(by: -1, wrap: false)
        #expect(handler.focusedIndex == 38)
        handler.applyAnchorHold()
        #expect(handler.focusedIndex == 38, "a steady glued frame must not snap the cursor back")
        #expect(handler.scrollOffset == handler.maxOffset, "the follow itself stays engaged")

        // Rows arrive: the tail advances, and the cursor comes along — that is
        // what follow-the-log means; the newest row is the interesting one.
        handler.itemCount = 45
        handler.applyAnchorHold()
        #expect(handler.scrollOffset == handler.maxOffset, "followed the new tail")
        #expect(handler.focusedIndex == 44, "and carried the cursor to it")
    }

    /// A list shorter than its viewport appends at offset 0 forever, so an
    /// offset comparison alone can't see the tail advance — the carry must
    /// key on the item count.
    @Test("A short list's appends still carry the cursor (offset never moves)")
    func shortListStillCarriesTheCursor() {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: 5, viewportHeight: 8,
            selectionMode: .single, canBeFocused: true)
        handler.declaredAnchorMode = .bottom

        handler.applyAnchorHold()
        #expect(handler.focusedIndex == 4, "opens on the tail row")

        handler.moveFocus(by: -1, wrap: false)
        handler.applyAnchorHold()
        #expect(handler.focusedIndex == 3, "arrows walk freely between appends")

        handler.itemCount = 7
        handler.applyAnchorHold()
        #expect(handler.focusedIndex == 6, "an append carries the cursor, offset or no offset")
    }

    /// Top and Window ask for nothing beyond "leave the offset alone", so the
    /// hold must not touch it. Guards against a naive `.top` implementation
    /// that snaps to row 0 every frame and makes the list unscrollable.
    @Test("Top and Window never move the offset")
    func topAndWindowLeaveTheOffsetAlone() {
        for mode in [ScrollAnchorMode.top, .window] {
            let handler = ItemListHandler<Int>(
                focusID: "list", itemCount: 40, viewportHeight: 8,
                selectionMode: .single, canBeFocused: true)
            handler.declaredAnchorMode = mode
            handler.scrollOffset = 12

            handler.applyAnchorHold()
            #expect(handler.scrollOffset == 12, "\(mode) must not move a scrolled view")
        }
    }
}
