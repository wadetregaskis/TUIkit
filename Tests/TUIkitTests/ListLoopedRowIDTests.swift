//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListLoopedRowIDTests.swift
//
//  A `ForEach` that shares its container with other rows — `Section {
//  Text("All items").tag("all"); ForEach(items) { … } }`, the same mix straight
//  in a `List`, two loops side by side, or a loop under a modifier — reaches
//  the list FLATTENED (`resolveChildViews`), one child per row, and each looped
//  row carries its element's id only as the string its identity is keyed by.
//  Those rows used to be keyed by the hand-written rule instead: their own
//  `.tag(_:)`, which `_MemoizedRow` hides, else their ordinal, which no
//  `String`, `UUID` or `Set` of either can hold. So under any such selection
//  every looped row was unselectable: the cursor stepped over it and a click
//  on it wrote nothing.
//
//  These pin the id each looped row takes now — the one its OWN `ForEach` gives
//  it when it is the container's whole content — down both routes
//  (`Section`'s child walk and `_ListCore.extractFromChildren`), for both of a
//  loop's row shapes (memoised, and bare for a non-`Equatable` element),
//  through the providers that flatten a loop into its container, beside a
//  second loop or an outline whose rows are spelled the same, and the one
//  thing a hand-written row gives up for it: an ordinal a looped row already
//  answers to.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Looped rows beside other rows", .rendersEnglishUI)
struct ListLoopedRowIDTests {

    /// A live `List`, rendered through the real focus manager and the real
    /// mouse dispatcher so a click travels the path a terminal's does.
    @MainActor
    private final class Fixture<Value: Hashable> {
        let tui = TUIContext()
        var env = EnvironmentValues()
        private(set) var buffer = FrameBuffer()

        init() {
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var handler: ItemListHandler<Value>? {
            env.focusManager?.currentFocused as? ItemListHandler<Value>
        }

        /// Every row's id, `nil` for chrome and for a row the selection cannot
        /// name — through `id(at:)`, the accessor that answers on both of the
        /// handler's id paths.
        var rowIDs: [Value?] {
            guard let handler else { return [] }
            return (0..<handler.itemCount).map { handler.id(at: $0) }
        }

        @discardableResult
        func render(_ view: some View) -> FrameBuffer {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            tui.mouseEventDispatcher.beginRenderPass()
            let context = RenderContext(
                availableWidth: 30, availableHeight: 14, environment: env, tuiContext: tui)
            buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        /// A plain left click on the line showing `text`, pressed and
        /// released where a terminal would report them.
        func click(rowShowing text: String) {
            guard let y = buffer.lines.firstIndex(where: { $0.stripped.contains(text) }) else {
                Issue.record("no row shows \(text): \(buffer.lines.map(\.stripped))")
                return
            }
            let dispatcher = tui.mouseEventDispatcher
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y))
        }
    }

    // MARK: - The two routes

    /// The shape the hole was found in, down `Section`'s child walk.
    @Test("A Section mixing a ForEach with a hand-written row keys each looped row by its element")
    func sectionLoopedRowsTakeTheirElementIDs() {
        let fixture = Fixture<String>()
        var selection: String?
        func list() -> some View {
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                Section("Items") {
                    Text("All items").tag("all")
                    ForEach(["alpha", "beta", "gamma"], id: \.self) { Text($0) }
                }
            }
            .frame(height: 10)
        }
        fixture.render(list())
        #expect(
            fixture.rowIDs == [nil, "all", "alpha", "beta", "gamma"],
            "the header, the tagged row, then each looped row by its element: \(fixture.rowIDs)")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }

        // The cursor lands on the looped rows rather than stepping over them.
        handler.focusedIndex = 1
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(
            handler.id(at: handler.focusedIndex) == "alpha",
            "Down from the hand-written row reaches the first looped one, row \(handler.focusedIndex)")

        // Space names the element…
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == "beta", "Space on beta: \(String(describing: selection))")

        // …and so does a click.
        fixture.render(list())
        fixture.click(rowShowing: "gamma")
        #expect(selection == "gamma", "a click on gamma: \(String(describing: selection))")
    }

    /// The same mix with no `Section`, which reaches the same hole down
    /// `_ListCore`'s own child walk — a shared cause is not a shared rule
    /// until both ends are asserted.
    @Test("A List mixing a ForEach with a hand-written row keys each looped row by its element")
    func flatListLoopedRowsTakeTheirElementIDs() {
        let fixture = Fixture<String>()
        var selection: String?
        func list() -> some View {
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                Text("All items").tag("all")
                ForEach(["alpha", "beta", "gamma"], id: \.self) { Text($0) }
            }
            .frame(height: 10)
        }
        fixture.render(list())
        #expect(
            fixture.rowIDs == ["all", "alpha", "beta", "gamma"],
            "the tagged row, then each looped row by its element: \(fixture.rowIDs)")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }

        handler.focusedIndex = 0
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(
            handler.id(at: handler.focusedIndex) == "alpha",
            "Down from the hand-written row reaches the first looped one, row \(handler.focusedIndex)")
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == "beta", "Space on beta: \(String(describing: selection))")

        fixture.render(list())
        fixture.click(rowShowing: "gamma")
        #expect(selection == "gamma", "a click on gamma: \(String(describing: selection))")
    }

    // MARK: - A loop's other row shape

    /// Deliberately NOT `Equatable`, so `ForEach` hands its rows over bare
    /// rather than inside `_MemoizedRow` — the other of the two row shapes a
    /// flattened loop produces, and the one whose tag was never hidden.
    private struct Planet: Identifiable {
        let id = UUID()
        let name: String
    }

    /// `UUID`s under a multi-selection: neither an ordinal nor a `Set` of one
    /// can be cast into it, so before the fix nothing in this Section was
    /// selectable at all.
    @Test("A non-Equatable loop's rows keep their UUIDs under a Set selection")
    func bareLoopedRowsKeepTheirUUIDs() {
        let planets = [Planet(name: "Mercury"), Planet(name: "Venus"), Planet(name: "Earth")]
        let fixture = Fixture<UUID>()
        var selection: Set<UUID> = []
        fixture.render(
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                Section("Planets") {
                    Text("Every planet")
                    ForEach(planets) { Text($0.name) }
                }
            }
            .frame(height: 10))
        #expect(
            fixture.rowIDs == [nil, nil] + planets.map(\.id),
            "the header and the untagged row name nothing; each planet is its id")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.focusedIndex = 3
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == [planets[1].id], "Space on Venus toggles Venus in")
    }

    // MARK: - The loop's own rule, whole

    /// A looped row's own `.tag(_:)` outranks its element's id when the loop is
    /// the whole content (`ListRowTagTests`), and must still here — where the
    /// row's memo wrapper used to hide the tag from the hand-written rule, so
    /// the row fell to its ordinal even under a selection that could hold it.
    @Test("A looped row's own tag still wins beside a hand-written row")
    func loopedRowTagWinsInAMixedContainer() {
        let fixture = Fixture<String>()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Text("All items").tag("all")
                ForEach(["alpha", "beta"], id: \.self) { Text($0).tag("tag-\($0)") }
            }
            .frame(height: 8))
        #expect(
            fixture.rowIDs == ["all", "tag-alpha", "tag-beta"],
            "each looped row by its own tag: \(fixture.rowIDs)")
    }

    /// An `Int` selection could always reach these rows, by ordinal — so the
    /// loop's rows answered to 1, 2, 3 while the same loop alone in the list
    /// answers to its elements, and adding a hand-written row renumbered it.
    /// The ordinal is a fallback this framework invented for a row with nothing
    /// else to say; a looped row has its element.
    @Test("An Int selection gets a looped row's element, not its position")
    func intSelectionGetsTheElement() {
        let fixture = Fixture<Int>()
        var selection: Int?
        fixture.render(
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                Text("All items")
                ForEach([10, 20, 30], id: \.self) { Text("item \($0)") }
            }
            .frame(height: 8))
        #expect(
            fixture.rowIDs == [0, 10, 20, 30],
            "the untagged row keeps its ordinal, the looped rows are their elements: \(fixture.rowIDs)")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.focusedIndex = 2
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == 20, "the element, not the ordinal 2: \(String(describing: selection))")
    }

    /// A loop that is a container's WHOLE content, under a modifier, reaches
    /// the list flattened too — the modifier has to reach every row, so
    /// neither the list nor a section looks through it (`ListRowsPassThrough`)
    /// — and so answered by ordinal. Under an `Int` selection that was a value
    /// the app never wrote: 0, 1, 2 for elements 10, 20, 30.
    @Test("A loop under a modifier as the whole content answers its elements, not its positions")
    func wholeLoopUnderAModifierAnswersItsElements() {
        let fixture = Fixture<Int>()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach([10, 20, 30], id: \.self) { Text("item \($0)") }
                    .foregroundStyle(.red)
            }
            .frame(height: 8))
        #expect(fixture.rowIDs == [10, 20, 30], "the List's loop: \(fixture.rowIDs)")

        let sectioned = Fixture<Int>()
        sectioned.render(
            List(selection: .constant(Int?.none)) {
                Section("Items") {
                    ForEach([40, 50], id: \.self) { Text("item \($0)") }
                        .padding(0)
                }
            }
            .frame(height: 8))
        #expect(sectioned.rowIDs == [nil, 40, 50], "the Section's loop: \(sectioned.rowIDs)")
    }

    // MARK: - Providers that flatten a loop

    /// Every provider that passes a loop's rows through to its container passes
    /// their ids through too: a `Group`, an `if`/`else`, a `ModifiedView`
    /// (`.padding`) and a content-rewrapping modifier (`.foregroundStyle`).
    @Test("A loop flattened through a Group, an if/else or a modifier keeps its ids")
    func loopsUnderProvidersKeepTheirIDs() {
        let fixture = Fixture<String>()
        let showsSecond = true
        fixture.render(
            List(selection: .constant(String?.none)) {
                Text("All items").tag("all")
                Group {
                    ForEach(["a1", "a2"], id: \.self) { Text($0) }
                }
                if showsSecond {
                    ForEach(["b1"], id: \.self) { Text($0) }
                } else {
                    Text("nothing")
                }
                ForEach(["c1"], id: \.self) { Text($0) }.padding(0)
                ForEach(["d1"], id: \.self) { Text($0) }.foregroundStyle(.red)
            }
            .frame(height: 10))
        #expect(
            fixture.rowIDs == ["all", "a1", "a2", "b1", "c1", "d1"],
            "every looped row by its element: \(fixture.rowIDs)")
    }

    /// An `if` with no `else` is an `Optional`, which flattens its loop when
    /// present and contributes no row when absent — and the rows after it must
    /// still be matched to their own loop either way, with nothing of the
    /// absent loop's left to claim them.
    @Test("A loop under an if without an else keeps its ids, present or not")
    func loopUnderAnOptionalKeepsItsIDs() {
        func list(showsPinned: Bool) -> some View {
            List(selection: .constant(String?.none)) {
                Text("All items").tag("all")
                if showsPinned {
                    ForEach(["p1", "p2"], id: \.self) { Text($0) }
                }
                ForEach(["q1", "q2"], id: \.self) { Text($0) }
            }
            .frame(height: 10)
        }
        let shown = Fixture<String>()
        shown.render(list(showsPinned: true))
        #expect(
            shown.rowIDs == ["all", "p1", "p2", "q1", "q2"],
            "the optional loop present: \(shown.rowIDs)")

        let hidden = Fixture<String>()
        hidden.render(list(showsPinned: false))
        #expect(hidden.rowIDs == ["all", "q1", "q2"], "the optional loop absent: \(hidden.rowIDs)")
    }

    // MARK: - Rows spelled alike

    /// A key names a value only up to its spelling, so each row is matched to
    /// the loop that made it by where it sits, not by what it is called. Two
    /// ways for loops to spell a row alike, one per Section: the same element
    /// under two different tags, and an `Int` 1 that a `String` selection
    /// cannot hold beside a `String` "1" that it can — which is where a
    /// match by key lost BOTH loops' answers, or took the other's.
    @Test("Two loops that spell a row alike each keep their own rows' answers")
    func loopsSpelledAlikeKeepTheirOwnAnswers() {
        let fixture = Fixture<String>()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Tags") {
                    Text("All tags").tag("all-tags")
                    ForEach(["x"], id: \.self) { Text("first \($0)").tag("p") }
                    ForEach(["x"], id: \.self) { Text("second \($0)").tag("q") }
                }
                Section("Spellings") {
                    Text("All spellings").tag("all-spellings")
                    ForEach(["1"], id: \.self) { Text("string \($0)") }
                    ForEach([1], id: \.self) { Text("number \($0)") }
                }
            }
            .frame(height: 12))
        #expect(
            fixture.rowIDs == [nil, "all-tags", "p", "q", nil, "all-spellings", "1", nil],
            "each row by its own loop, the Int row naming nothing a String can hold: \(fixture.rowIDs)")
    }

    private enum Pick: Hashable {
        case all
        case project(Int)
        case person(Int)
    }

    private struct Named: Identifiable, Equatable {
        let id: Int
        let name: String
    }

    /// The sidebar the gap was pictured in: an enum selection, every looped
    /// row tagged, and two loops whose ids overlap — projects 1, 2, 3 and
    /// people 1, 2. Matched by key, projects 1 and 2 and both people could not
    /// be selected while project 3 could.
    @Test("A sidebar of two tagged loops over overlapping ids selects every row")
    func overlappingTaggedLoopsSelectEveryRow() {
        let projects = [Named(id: 1, name: "Atlas"), Named(id: 2, name: "Boreas"), Named(id: 3, name: "Ceto")]
        let people = [Named(id: 1, name: "Dana"), Named(id: 2, name: "Eli")]
        let fixture = Fixture<Pick>()
        var pick: Pick?
        fixture.render(
            List(selection: Binding(get: { pick }, set: { pick = $0 })) {
                Text("All").tag(Pick.all)
                ForEach(projects) { Text($0.name).tag(Pick.project($0.id)) }
                ForEach(people) { Text($0.name).tag(Pick.person($0.id)) }
            }
            .frame(height: 10))
        #expect(
            fixture.rowIDs == [
                .all, .project(1), .project(2), .project(3), .person(1), .person(2),
            ],
            "each row by its own loop's tag: \(fixture.rowIDs)")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        handler.focusedIndex = 4
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(pick == .person(1), "Space on Dana: \(String(describing: pick))")
    }

    private struct Node: Identifiable {
        let id: String
        var kids: [Self]?
    }

    /// An `OutlineGroup`'s rows are keyed by their nodes' ids exactly as a
    /// loop's are by its elements', so a node spelled like a loop's element
    /// took that element's answer when rows were matched by key — and a click
    /// on the node selected the loop's row, both highlighting. The outline's
    /// rows keep the hand-written rule here, as they always have; the loop's
    /// rows, AFTER them, keep their own.
    @Test("An outline row spelled like a looped row never takes its answer")
    func outlineRowsNeverTakeALoopsAnswer() {
        let tree = [Node(id: "1", kids: nil), Node(id: "2", kids: nil)]
        let fixture = Fixture<String>()
        var selection: String?
        func list() -> some View {
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                Text("All").tag("all")
                OutlineGroup(tree, children: \Node.kids) { Text(verbatim: "node \($0.id)") }
                ForEach(["1", "2"], id: \.self) { Text("pinned \($0)") }
            }
            .frame(height: 10)
        }
        fixture.render(list())
        #expect(
            fixture.rowIDs == ["all", nil, nil, "1", "2"],
            "the nodes name nothing, the loop's rows their elements: \(fixture.rowIDs)")

        fixture.click(rowShowing: "node 1")
        #expect(selection == nil, "a click on node 1: \(String(describing: selection))")
    }

    // MARK: - An ordinal a looped row already answers to

    /// The one collision the element ids make possible: an untagged
    /// hand-written row falls back to its ordinal, and beside `ForEach(0..<3)`
    /// its ordinal 0 is a looped row's element. Two rows answering 0 means
    /// selecting one highlights both, Space on "None" writes the loop's 0, and
    /// focus returning to a selection of 0 lands on "None". SwiftUI gives an
    /// untagged row no selection value at all, so the ordinal yields.
    @Test("An untagged row's ordinal yields to a looped row answering the same number")
    func ordinalYieldsToALoopedRow() {
        let fixture = Fixture<Int>()
        var selection: Int?
        fixture.render(
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                Text("None")
                ForEach(0..<3) { Text("item \($0)") }
            }
            .frame(height: 8))
        #expect(
            fixture.rowIDs == [nil, 0, 1, 2],
            "None names nothing, each item its element: \(fixture.rowIDs)")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }

        // Space on "None" writes nothing…
        handler.focusedIndex = 0
        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(selection == nil, "Space on None: \(String(describing: selection))")

        // …Space on item 0 writes 0, and only item 0 is highlighted by it…
        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == 0, "Space on item 0: \(String(describing: selection))")
        #expect(
            (0..<handler.itemCount).map { handler.isSelected(at: $0) } == [false, true, false, false],
            "the rows a selection of 0 highlights")

        // …and focus returning to that selection lands on item 0, not None.
        handler.focusedIndex = 3
        handler.onFocusLost()
        #expect(handler.focusedIndex == 1, "focus-lost landing: row \(handler.focusedIndex)")
    }

    /// A loop of sections makes no rows of its own — the list splices each
    /// section's rows, keyed by the section's items — so the groups' ids are
    /// nobody's selection value, and an untagged row beside them keeps its
    /// ordinal. Counted as looped rows' ids, they took it away.
    @Test("A loop of sections takes no number from the row beside it")
    func sectionLoopTakesNoNumber() {
        let fixture = Fixture<Int>()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                Text("Inbox")
                ForEach(0..<2) { group in
                    Section("G\(group)") {
                        ForEach([100 + 10 * group, 101 + 10 * group], id: \.self) { Text("item \($0)") }
                    }
                }
            }
            .frame(height: 12))
        #expect(
            fixture.rowIDs.first == 0,
            "Inbox keeps its ordinal, which no row answers to: \(fixture.rowIDs)")
        #expect(
            fixture.rowIDs.contains(100) && fixture.rowIDs.contains(111),
            "the sections' items answer to their elements: \(fixture.rowIDs)")

        // Beside a loop of rows as well, whose ids ARE taken: the groups' 0 and
        // 1 still are not.
        let mixed = Fixture<Int>()
        mixed.render(
            List(selection: .constant(Int?.none)) {
                Text("Inbox")
                ForEach([5, 6], id: \.self) { Text("pinned \($0)") }
                ForEach(0..<2) { group in
                    Section("G\(group)") {
                        ForEach([100 + 10 * group], id: \.self) { Text("item \($0)") }
                    }
                }
            }
            .frame(height: 12))
        #expect(
            Array(mixed.rowIDs.prefix(3)) == [0, 5, 6],
            "Inbox keeps 0 beside rows that answer 5 and 6: \(mixed.rowIDs)")
    }
}
