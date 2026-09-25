//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowSelectionValueCostTests.swift
//
//  What a `List` pays, per frame, to learn its rows' selection values — counted
//  in the work that dominates it, deterministically: row views BUILT by the
//  `ForEach` content closure (a `.tag(_:)` can only be read off a built row)
//  and reads of an element's `id`. A windowed loop — a `ForEach` that is the
//  list's whole content — resolves them for the rows the frame draws and the
//  handler asks about, and that is the reference every shape here is held to.
//
//  The mixed shapes are the Stress scenarios `app-shapes/sidebar` (a
//  hand-written row above looped rows, every looped row tagged with the app's
//  enum) and `app-shapes/sidebar-untagged` (the same list answering by the
//  elements' ids), shrunk to a test and counted instead of timed.
//
//  Every count is a DIFFERENCE between two lists that share everything but the
//  one thing being priced — tagged against untagged, hugging against filling —
//  so the rows' own renders, measures and identity keys cancel, and what is
//  left is the selection-value work alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A list resolves the selection values it is asked for", .rendersEnglishUI)
struct ListRowSelectionValueCostTests {

    /// Counts across frames. A class, not `@State`, so counting does not
    /// invalidate the rows being counted.
    final class Counter {
        var builds = 0
        var idReads = 0
    }

    /// A project whose `id` counts its reads — the key-path read an untagged
    /// looped row answers by. `Equatable` on the number alone, so the row memo
    /// serves it as it would an app's value type.
    struct Project: Identifiable, Equatable {
        let number: Int
        let counter: Counter
        var id: Int {
            counter.idReads += 1
            return number
        }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.number == rhs.number }
    }

    /// What the tagged sidebar selects: everything, or one project.
    enum Pick: Hashable {
        case all
        case project(Int)
    }

    /// The looped row, counted as it is built. Named types rather than
    /// `some View`, so the row's static type is exactly what the list sees.
    static func taggedRow(_ project: Project) -> _TaggedView<Text> {
        project.counter.builds += 1
        return _TaggedView(
            tagValue: AnyHashable(Pick.project(project.number)), includeOptional: true,
            content: Text("project \(project.number)"))
    }

    /// The looped row tagged with its own number — `Row($0).tag($0.id)` under
    /// an `Int` selection.
    static func numberTaggedRow(_ project: Project) -> _TaggedView<Text> {
        project.counter.builds += 1
        return _TaggedView(
            tagValue: AnyHashable(project.number), includeOptional: true,
            content: Text("project \(project.number)"))
    }

    static func untaggedRow(_ project: Project) -> Text {
        project.counter.builds += 1
        return Text("project \(project.number)")
    }

    /// Frames through one state store and one render cache, each bracketed in
    /// the pass lifecycle the run loop brackets it in, so the row memo serves
    /// a steady frame as it would in the app.
    @MainActor
    final class Frames {
        let tui = TUIContext()
        var env = EnvironmentValues()
        let counter: Counter
        /// The last frame's lines, stripped.
        var lastScreen: [String] = []

        init(counter: Counter) {
            self.counter = counter
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
        }

        /// Renders one frame and returns what it cost and how many project
        /// rows it drew.
        func frame(_ view: some View) -> (builds: Int, idReads: Int, drawn: Int) {
            let before = (counter.builds, counter.idReads)
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            let context = RenderContext(
                availableWidth: 60, availableHeight: 24, environment: env, tuiContext: tui)
            context.renderCache?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            context.renderCache?.removeInactive()
            lastScreen = buffer.lines.map(\.stripped)
            let drawn = lastScreen.filter { $0.contains("project ") }.count
            return (counter.builds - before.0, counter.idReads - before.1, drawn)
        }

        /// The third frame: the first two fill the caches and settle focus.
        func steadyFrame(_ view: some View) -> (builds: Int, idReads: Int, drawn: Int) {
            _ = frame(view)
            _ = frame(view)
            return frame(view)
        }
    }

    private static let rowCount = 300

    /// `rowCount` projects, numbered from `first`.
    private static func projects(_ counter: Counter, numberedFrom first: Int = 0) -> [Project] {
        (first..<first + rowCount).map { Project(number: $0, counter: counter) }
    }

    // MARK: - The hug walk

    /// A hugging list — `.fixedSize(horizontal:)`, or a `NavigationSplitView`'s
    /// sidebar — walks EVERY row for its width on each frame the size memo
    /// cannot answer: the first, and every one after the data changes. The
    /// walk asked each row for its selection value too, and a tagged row can
    /// only answer that by being built: 300 builds for nothing the width looks
    /// at.
    @Test("A hugging list's width walk builds no row to read its tag")
    func hugWalkReadsNoTags() {
        func coldBuilds(tagged: Bool) -> (builds: Int, drawn: Int) {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            let cost =
                tagged
                ? frames.frame(
                    List(selection: .constant(Pick?.none)) {
                        ForEach(projects) { Self.taggedRow($0) }
                    }
                    .fixedSize(horizontal: true))
                : frames.frame(
                    List(selection: .constant(Int?.none)) {
                        ForEach(projects) { Self.untaggedRow($0) }
                    }
                    .fixedSize(horizontal: true))
            return (cost.builds, cost.drawn)
        }
        let tagged = coldBuilds(tagged: true)
        let untagged = coldBuilds(tagged: false)
        let tagBuilds = tagged.builds - untagged.builds
        #expect(tagged.drawn > 0 && tagged.drawn == untagged.drawn, "both lists drew their rows")
        // A windowed loop reads the tag of each row it draws and of each row
        // the handler asks about — the O(visible) price of a tagged row.
        #expect(
            tagBuilds <= 2 * tagged.drawn + 2,
            "\(tagBuilds) tag builds for \(tagged.drawn) drawn rows of \(Self.rowCount)")
    }

    /// The mixed container's own hug: the list walks its flattened children
    /// eagerly, once for the width and once to draw, and the width's walk
    /// resolved every looped row's selection value — a build per tagged row —
    /// that nothing in a measure reads.
    @Test("A mixed list's hug measure resolves no looped row's tag")
    func mixedHugMeasureReadsNoTags() {
        func steadyBuilds(tagged: Bool, hugging: Bool) -> Int {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            func list() -> AnyView {
                let list: AnyView =
                    tagged
                    ? AnyView(
                        List(selection: .constant(Pick?.some(.all))) {
                            Text("All projects").tag(Pick.all)
                            ForEach(projects) { Self.taggedRow($0) }
                        })
                    : AnyView(
                        List(selection: .constant(Int?.some(-1))) {
                            Text("All projects").tag(-1)
                            ForEach(projects) { Self.untaggedRow($0) }
                        })
                // In a stack, which MEASURES its child before drawing it —
                // what a `NavigationSplitView` does to its sidebar. A filling
                // list answers that measure without building a row.
                return hugging
                    ? AnyView(HStack(spacing: 0) { list.fixedSize(horizontal: true) })
                    : AnyView(HStack(spacing: 0) { list })
            }
            return frames.steadyFrame(list()).builds
        }
        // What hugging adds to a tagged list, less what it adds to the same
        // list untagged: the tags the hug read, and nothing else.
        let hugTagBuilds =
            (steadyBuilds(tagged: true, hugging: true) - steadyBuilds(tagged: true, hugging: false))
            - (steadyBuilds(tagged: false, hugging: true) - steadyBuilds(tagged: false, hugging: false))
        #expect(hugTagBuilds == 0, "the hug built \(hugTagBuilds) rows to read tags it never uses")
    }

    // MARK: - The frame

    /// The tagged sidebar, filling its space: the handler asks about the rows
    /// it draws and the row it focuses, and every other looped row's tag was
    /// built anyway — 300 builds a frame where the same loop alone builds a
    /// screenful.
    @Test("A mixed list builds the tags of the rows it draws, not of every row")
    func mixedListReadsTheTagsItDraws() {
        func steady(tagged: Bool) -> (builds: Int, drawn: Int) {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            let cost =
                tagged
                ? frames.steadyFrame(
                    List(selection: .constant(Pick?.some(.all))) {
                        Text("All projects").tag(Pick.all)
                        ForEach(projects) { Self.taggedRow($0) }
                    })
                : frames.steadyFrame(
                    List(selection: .constant(Int?.some(-1))) {
                        Text("All projects").tag(-1)
                        ForEach(projects) { Self.untaggedRow($0) }
                    })
            return (cost.builds, cost.drawn)
        }
        let tagged = steady(tagged: true)
        let untagged = steady(tagged: false)
        let tagBuilds = tagged.builds - untagged.builds
        #expect(tagged.drawn > 0 && tagged.drawn == untagged.drawn, "both lists drew their rows")
        #expect(
            tagBuilds <= tagged.drawn + 2,
            "\(tagBuilds) tag builds for \(tagged.drawn) drawn rows of \(Self.rowCount)")
    }

    /// The untagged sidebar: each looped row answers by its project's `id`, a
    /// key-path read, and each was read on every frame whether or not the row
    /// was drawn or asked about.
    @Test("A mixed list reads the ids of the rows it draws, not of every row")
    func mixedListReadsTheIDsItDraws() {
        func steady(mixed: Bool) -> (idReads: Int, drawn: Int) {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            let cost =
                mixed
                ? frames.steadyFrame(
                    List(selection: .constant(Int?.some(-1))) {
                        Text("All projects").tag(-1)
                        ForEach(projects) { Self.untaggedRow($0) }
                    })
                : frames.steadyFrame(
                    List(selection: .constant(Int?.some(-1))) {
                        ForEach(projects) { Self.untaggedRow($0) }
                    })
            return (cost.idReads, cost.drawn)
        }
        let mixed = steady(mixed: true)
        let windowed = steady(mixed: false)
        // The mixed list keys every row's identity by its id — the splice
        // flattens all of them, a read each — and the windowed one keys only
        // the rows it builds. What the mixed list reads beyond its identity
        // keys is what it paid for selection values.
        let selectionReads = mixed.idReads - Self.rowCount
        #expect(mixed.drawn > 0, "the mixed list drew its rows")
        #expect(
            selectionReads <= windowed.idReads + 4,
            "\(selectionReads) id reads for selection values where the windowed loop reads \(windowed.idReads) in all")
    }

    /// An untagged hand-written row beside a tagged loop, under a selection its
    /// ordinal casts into — `List(selection: $number) { Text("None");
    /// ForEach(items) { Row($0).tag($0.id) } }` over projects numbered from
    /// `first` — at a steady frame: the tag builds (tagged less untagged) and
    /// the looped rows drawn. "None" answers to its ordinal, 0, unless a looped
    /// row here already does (`FlattenedRowIDs.ordinalID`), and a looped row's
    /// answer is its tag, read off the BUILT row.
    private static func ordinalBesideATaggedLoop(numberedFrom first: Int) -> (tagBuilds: Int, drawn: Int) {
        func steady(tagged: Bool) -> (builds: Int, drawn: Int) {
            let counter = Counter()
            let projects = Self.projects(counter, numberedFrom: first)
            let frames = Frames(counter: counter)
            let cost =
                tagged
                ? frames.steadyFrame(
                    List(selection: .constant(Int?.none)) {
                        Text("None")
                        ForEach(projects) { Self.numberTaggedRow($0) }
                    })
                : frames.steadyFrame(
                    List(selection: .constant(Int?.none)) {
                        Text("None")
                        ForEach(projects) { Self.untaggedRow($0) }
                    })
            return (cost.builds, cost.drawn)
        }
        let tagged = steady(tagged: true)
        let untagged = steady(tagged: false)
        #expect(tagged.drawn > 0 && tagged.drawn == untagged.drawn, "both lists drew their rows")
        return (tagged.builds - untagged.builds, tagged.drawn)
    }

    /// A loop counted from 0 — `ForEach(0..<n)`, or tags numbered from 0, the
    /// collision the ordinal's yield exists for — answers 0 at its first row.
    /// The looped rows are asked in order and the question stops at the first
    /// that answers the ordinal, so it builds that one row and no other; asked
    /// of every looped row before any was checked, it built all 300.
    @Test("An untagged row beside an Int-tagged loop that answers its ordinal builds the rows it draws")
    func ordinalBesideACollidingLoopBuildsTheRowsItDraws() {
        let cost = Self.ordinalBesideATaggedLoop(numberedFrom: 0)
        #expect(
            cost.tagBuilds <= cost.drawn + 2,
            "\(cost.tagBuilds) tag builds for \(cost.drawn) drawn rows of \(Self.rowCount)")
    }

    /// What a mixed list still pays, pinned: the same list over projects
    /// 1...300, so no looped row answers 0. A tag is any value at all, read off
    /// the built row, so nothing short of building every looped row says that
    /// none of them is 0. Every frame that asks about the hand-written row —
    /// every frame it is drawn — builds them all. Counted so that the day it
    /// moves is seen.
    @Test("An untagged row beside an Int-tagged loop that never answers its ordinal builds every looped row on each frame it is drawn")
    func ordinalBesideATaggedLoopBuildsEveryRow() {
        let cost = Self.ordinalBesideATaggedLoop(numberedFrom: 1)
        #expect(
            cost.tagBuilds == Self.rowCount,
            "\(cost.tagBuilds) tag builds for \(cost.drawn) drawn rows of \(Self.rowCount)")
    }

    /// The same mix inside a `Section`, which walks its own flattened
    /// children (`Section.listRows(of:context:)`) and hands the list rows whose
    /// ids it had already resolved — every one of them, every frame.
    @Test("A Section mixing a loop with a hand-written row builds the tags of the rows it draws")
    func mixedSectionReadsTheTagsItDraws() {
        func steady(tagged: Bool) -> (builds: Int, drawn: Int) {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            let cost =
                tagged
                ? frames.steadyFrame(
                    List(selection: .constant(Pick?.some(.all))) {
                        Section("Projects") {
                            Text("All projects").tag(Pick.all)
                            ForEach(projects) { Self.taggedRow($0) }
                        }
                    })
                : frames.steadyFrame(
                    List(selection: .constant(Int?.some(-1))) {
                        Section("Projects") {
                            Text("All projects").tag(-1)
                            ForEach(projects) { Self.untaggedRow($0) }
                        }
                    })
            return (cost.builds, cost.drawn)
        }
        let tagged = steady(tagged: true)
        let untagged = steady(tagged: false)
        let tagBuilds = tagged.builds - untagged.builds
        #expect(tagged.drawn > 0 && tagged.drawn == untagged.drawn, "both lists drew their rows")
        #expect(
            tagBuilds <= tagged.drawn + 2,
            "\(tagBuilds) tag builds for \(tagged.drawn) drawn rows of \(Self.rowCount)")
    }

    /// The keys that move the cursor ask where it may land — the rows the
    /// selection can name. Asked of the whole list at once, that is every
    /// looped row's loop rule again: a build per tagged row on the first key
    /// after each frame, for a cursor that moves one row.
    @Test("A key that moves a mixed list's cursor asks only the rows it may land on")
    func cursorKeysAskOnlyWhereTheyLand() {
        let counter = Counter()
        let projects = Self.projects(counter)
        let frames = Frames(counter: counter)
        var selection: Pick? = .all
        let list = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Text("All projects").tag(Pick.all)
            ForEach(projects) { Self.taggedRow($0) }
        }
        _ = frames.steadyFrame(list)
        guard let handler = frames.env.focusManager?.currentFocused as? ItemListHandler<Pick> else {
            Issue.record("the list took focus")
            return
        }
        let keys: [Key] = [.down, .down, .end, .home, .up, .pageDown, .pageUp, .down]
        let before = counter.builds
        for key in keys { _ = handler.handleKeyEvent(KeyEvent(key: key)) }
        let keyBuilds = counter.builds - before
        // The rows the frame drew were asked as they were drawn; a key asks at
        // most the one row it lands on beyond them.
        #expect(
            keyBuilds <= keys.count,
            "\(keys.count) keys built \(keyBuilds) rows of \(Self.rowCount) to decide where to land")
    }

    /// A bottom-anchored list follows its tail on every frame, and the follow
    /// asks for the last row a cursor can sit on. Read off the whole landing
    /// set, that settled the maps on every frame — every looped row's tag
    /// built, for the one row at the end.
    @Test("A bottom-anchored mixed list follows its tail without asking every row")
    func bottomAnchoredFollowAsksOnlyTheTail() {
        func steady(tagged: Bool) -> (builds: Int, drawn: Int, followed: Bool, unsettled: Bool) {
            let counter = Counter()
            let projects = Self.projects(counter)
            let frames = Frames(counter: counter)
            let cost =
                tagged
                ? frames.steadyFrame(
                    List(selection: .constant(Pick?.some(.all))) {
                        Text("All projects").tag(Pick.all)
                        ForEach(projects) { Self.taggedRow($0) }
                    }
                    .defaultScrollAnchor(.bottom))
                : frames.steadyFrame(
                    List(selection: .constant(Int?.some(-1))) {
                        Text("All projects").tag(-1)
                        ForEach(projects) { Self.untaggedRow($0) }
                    }
                    .defaultScrollAnchor(.bottom))
            // Each twin's handler under its own selection type: the tagged
            // list selects a `Pick`, the untagged one an `Int`.
            let focused = frames.env.focusManager?.currentFocused
            let unsettled =
                tagged
                ? (focused as? ItemListHandler<Pick>)?.rowAnswersAreUnsettled
                : (focused as? ItemListHandler<Int>)?.rowAnswersAreUnsettled
            return (
                cost.builds, cost.drawn,
                frames.lastScreen.contains { $0.contains("project \(Self.rowCount - 1)") },
                unsettled ?? false
            )
        }
        let tagged = steady(tagged: true)
        let untagged = steady(tagged: false)
        let tagBuilds = tagged.builds - untagged.builds
        #expect(tagged.followed && untagged.followed, "precondition: both lists show their last row")
        #expect(tagged.drawn > 0 && tagged.drawn == untagged.drawn, "both lists drew their rows")
        #expect(
            tagBuilds <= tagged.drawn + 2,
            "\(tagBuilds) tag builds for \(tagged.drawn) drawn rows of \(Self.rowCount)")
        #expect(tagged.unsettled, "the follow settled the tagged list's maps")
        #expect(untagged.unsettled, "the follow settled the untagged list's maps")
    }

    // MARK: - The answers are the same answers

    /// The handler's row answers — the ids row by row, where each key lands,
    /// and then the maps whole — for a mixed list with a row the selection
    /// cannot name. These are the answers the list gave when it resolved
    /// every row up front; asked for one row at a time, and the rest only when
    /// something reads them, they must not move. The rows and the keys are
    /// asked first, while the maps are still to be settled: read whole first,
    /// they would answer every key from the settled set.
    @Test("A mixed list's handler answers every row as it did when every row was resolved up front")
    func mixedListAnswersAreUnchanged() {
        let counter = Counter()
        let frames = Frames(counter: counter)
        var selection: String?
        let list = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Text("Every planet")
            ForEach(["mercury", "venus", "earth"], id: \.self) { Text($0) }
            Text("Pluto").tag("pluto")
        }
        _ = frames.steadyFrame(list)
        guard let handler = frames.env.focusManager?.currentFocused as? ItemListHandler<String> else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.rowAnswersAreUnsettled, "precondition: nothing has read the maps yet")
        #expect(
            (0..<handler.itemCount).map { handler.id(at: $0) }
                == [nil, "mercury", "venus", "earth", "pluto"])
        #expect(handler.index(of: "earth") == 3)

        // The keys land where the landing set says.
        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        #expect(handler.focusedIndex == 1, "Home lands on the first selectable row")
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.focusedIndex == 4, "Up from the first selectable row wraps past the one above it")
        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.focusedIndex == 2, "Down steps onto the next looped row")
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        #expect(handler.focusedIndex == 4, "End lands on the last row")
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == "pluto")
        #expect(handler.rowAnswersAreUnsettled, "the keys asked row by row, and settled nothing")

        // And the maps, read whole, which settles them.
        #expect(handler.itemIDs == [nil, "mercury", "venus", "earth", "pluto"])
        #expect(handler.selectableIndices == [1, 2, 3, 4], "\(handler.selectableIndices.sorted())")
    }

    /// The sidebar: every row selectable, so the handler is told so — an
    /// empty landing set and no id array, the windowed loop's shape — once
    /// anything asks.
    @Test("A mixed list whose every row is selectable hands its handler the all-content answers")
    func allContentMixedListAnswersAreUnchanged() {
        let counter = Counter()
        let frames = Frames(counter: counter)
        let projects = Self.projects(counter)
        var selection: Pick? = .all
        let list = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Text("All projects").tag(Pick.all)
            ForEach(projects) { Self.taggedRow($0) }
        }
        _ = frames.steadyFrame(list)
        guard let handler = frames.env.focusManager?.currentFocused as? ItemListHandler<Pick> else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == Self.rowCount + 1)
        #expect(handler.id(at: 0) == .all)
        #expect(handler.id(at: Self.rowCount) == .project(Self.rowCount - 1))
        #expect(handler.itemIDs.isEmpty && handler.selectableIndices.isEmpty, "all content")
        #expect(handler.index(of: .project(250)) == 251)
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        #expect(handler.focusedIndex == Self.rowCount)
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == .project(Self.rowCount - 1))
    }

    /// The mix inside a `Section`: a header, a row the selection cannot name,
    /// the looped rows and a tagged one — the answers its handler gave when
    /// every row was resolved up front, asked in the same order as the flat
    /// list's: rows and keys first, the maps whole after.
    @Test("A mixed Section's handler answers every row as it did when every row was resolved up front")
    func mixedSectionAnswersAreUnchanged() {
        let counter = Counter()
        let frames = Frames(counter: counter)
        var selection: String?
        let list = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Section("Planets") {
                Text("Every planet")
                ForEach(["mercury", "venus", "earth"], id: \.self) { Text($0) }
                Text("Pluto").tag("pluto")
            }
        }
        _ = frames.steadyFrame(list)
        guard let handler = frames.env.focusManager?.currentFocused as? ItemListHandler<String> else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.rowAnswersAreUnsettled, "precondition: nothing has read the maps yet")
        #expect(
            (0..<handler.itemCount).map { handler.id(at: $0) }
                == [nil, nil, "mercury", "venus", "earth", "pluto"])
        #expect(handler.index(of: "venus") == 3)
        _ = handler.handleKeyEvent(KeyEvent(key: .home))
        #expect(handler.focusedIndex == 2, "Home lands on the first selectable row")
        _ = handler.handleKeyEvent(KeyEvent(key: .up))
        #expect(handler.focusedIndex == 5, "Up wraps past the header and the unselectable row")
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.focusedIndex == 2, "Down wraps back past them")
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == "mercury")
        #expect(handler.rowAnswersAreUnsettled, "the keys asked row by row, and settled nothing")

        #expect(handler.itemIDs == [nil, nil, "mercury", "venus", "earth", "pluto"])
        #expect(handler.selectableIndices == [2, 3, 4, 5], "\(handler.selectableIndices.sorted())")
    }

    /// Where each key leaves the cursor, from row `start`: asked before
    /// anything has read the handler's whole maps (`settleFirst == false`), or
    /// after (`true`), when the keys consult the settled landing set as they
    /// always have.
    private func cursorTrajectory<Value: Hashable>(
        _ list: some View, as _: Value.Type, from start: Int, keys: [Key], settleFirst: Bool
    ) -> [Int] {
        let frames = Frames(counter: Counter())
        _ = frames.steadyFrame(list)
        guard let handler = frames.env.focusManager?.currentFocused as? ItemListHandler<Value> else {
            Issue.record("the list took focus")
            return []
        }
        if settleFirst { _ = handler.selectableIndices }
        handler.focusedIndex = start
        return keys.map { key in
            _ = handler.handleKeyEvent(KeyEvent(key: key))
            return handler.focusedIndex
        }
    }

    /// Every key that moves the cursor, several times over, from both ends.
    private static let cursorKeys: [Key] = [
        .down, .down, .up, .home, .up, .down, .end, .pageUp, .pageDown, .down, .up, .up, .end,
        .pageDown, .home, .pageUp,
    ]

    /// The landing questions are answered a row at a time until something
    /// reads the maps whole; the cursor must land exactly where the maps would
    /// have put it — past rows the selection cannot name, onto the first and
    /// last rows that it can, wrapping and clamping alike.
    @Test("The cursor steps past the rows a mixed list cannot name, as it did")
    func cursorLandsWhereItDid() {
        func list() -> some View {
            List(selection: .constant(String?.none)) {
                Text("Every planet")
                ForEach(["mercury", "venus"], id: \.self) { Text($0) }
                Text("Asteroids")
                ForEach(["earth", "mars"], id: \.self) { Text($0) }
                Text("Pluto").tag("pluto")
                Text("Beyond")
            }
            .frame(height: 6)
        }
        let asked = cursorTrajectory(list(), as: String.self, from: 1, keys: Self.cursorKeys, settleFirst: false)
        let settled = cursorTrajectory(list(), as: String.self, from: 1, keys: Self.cursorKeys, settleFirst: true)
        #expect(asked.count == Self.cursorKeys.count)
        #expect(!asked.contains(0) && !asked.contains(3) && !asked.contains(7), "never on an unnamed row: \(asked)")
        #expect(asked == settled, "asked a row at a time: \(asked); from the settled maps: \(settled)")
    }

    /// The same, inside a `Section`, whose header is one more row the cursor
    /// steps past.
    @Test("The cursor steps past a mixed Section's header and unnamed rows, as it did")
    func cursorLandsWhereItDidInASection() {
        func list() -> some View {
            List(selection: .constant(String?.none)) {
                Section("Planets") {
                    Text("Every planet")
                    ForEach(["mercury", "venus"], id: \.self) { Text($0) }
                    Text("Asteroids")
                    ForEach(["earth", "mars"], id: \.self) { Text($0) }
                    Text("Pluto").tag("pluto")
                }
            }
            .frame(height: 6)
        }
        let asked = cursorTrajectory(list(), as: String.self, from: 2, keys: Self.cursorKeys, settleFirst: false)
        let settled = cursorTrajectory(list(), as: String.self, from: 2, keys: Self.cursorKeys, settleFirst: true)
        #expect(asked.count == Self.cursorKeys.count)
        #expect(!asked.contains(0) && !asked.contains(1) && !asked.contains(4), "never on an unnamed row: \(asked)")
        #expect(asked == settled, "asked a row at a time: \(asked); from the settled maps: \(settled)")
    }

    /// Where NO row can be named, every row is landable — the landing set is
    /// empty, which the handler reads as "no restriction" — and must stay so.
    @Test("The cursor walks every row of a list that can name none of them, as it did")
    func cursorLandsWhereItDidWhenNoRowIsNamed() {
        func list() -> some View {
            List(selection: .constant(String?.none)) {
                Text("Every planet")
                Text("Asteroids")
                Text("Comets")
                Text("Beyond")
            }
            .frame(height: 5)
        }
        let asked = cursorTrajectory(list(), as: String.self, from: 0, keys: Self.cursorKeys, settleFirst: false)
        let settled = cursorTrajectory(list(), as: String.self, from: 0, keys: Self.cursorKeys, settleFirst: true)
        #expect(asked.count == Self.cursorKeys.count)
        #expect(Set(asked).count > 2, "the cursor moved: \(asked)")
        #expect(asked == settled, "asked a row at a time: \(asked); from the settled maps: \(settled)")
    }

    /// The all-content sidebar: every row is named, and the keys clamp and wrap
    /// over all of them.
    @Test("The cursor walks every row of a list that names all of them, as it did")
    func cursorLandsWhereItDidWhenEveryRowIsNamed() {
        let projects = Self.projects(Counter())
        let list = List(selection: .constant(Pick?.none)) {
            Text("All projects").tag(Pick.all)
            ForEach(projects) { Self.taggedRow($0) }
        }
        let asked = cursorTrajectory(list, as: Pick.self, from: 0, keys: Self.cursorKeys, settleFirst: false)
        let settled = cursorTrajectory(list, as: Pick.self, from: 0, keys: Self.cursorKeys, settleFirst: true)
        #expect(asked.count == Self.cursorKeys.count)
        #expect(asked == settled, "asked a row at a time: \(asked); from the settled maps: \(settled)")
    }
}
