//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListCustomRowsViewTests.swift
//
//  A view of the app's own whose `body` is list rows — the loop, or a
//  `Section`, a `Group` or an `if`/`else` around one, or another such view —
//  as a `List`'s or a `Section`'s content. SwiftUI draws the rows of the body:
//  one per element, each selectable by its element and deletable (measured in
//  an `NSHostingView` on macOS 15.8, flat, in a `Section`, with `@State` on the
//  view, one view inside another, and an `if`/`else` body). TUIkit drew the
//  whole view as ONE row, unselectable under a `String` selection, and no row
//  took Delete or the pick-up.
//
//  The shared harness is `ListSectionEditingFixture`. Every editing assertion
//  is on the collection afterwards, and every gesture first checks that its
//  row answers to the element it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - The views

/// The shape the gap was reported with: a view whose whole body is the loop.
private struct Rows: View {
    let items: MainActorBox<[String]>

    var body: some View {
        ForEach(items.value, id: \.self) { Text($0) }
            .onDelete { items.value.remove(atOffsets: $0) }
            .onMove { items.value.move(fromOffsets: $0, toOffset: $1) }
    }
}

/// A view of the app's own around another — the look goes through any number.
private struct OuterRows: View {
    let items: MainActorBox<[String]>

    var body: some View { Rows(items: items) }
}

/// An empty state in one arm, the loop in the other.
private struct EmptyStateRows: View {
    let items: MainActorBox<[String]>

    var body: some View {
        if items.value.isEmpty {
            Text("Nothing here")
        } else {
            ForEach(items.value, id: \.self) { Text($0) }
                .onDelete { items.value.remove(atOffsets: $0) }
        }
    }
}

/// A whole `Section` factored out: header, the loop, its actions.
private struct ItemsSection: View {
    let items: MainActorBox<[String]>

    var body: some View {
        Section("Items") {
            ForEach(items.value, id: \.self) { Text($0) }
                .onDelete { items.value.remove(atOffsets: $0) }
        }
    }
}

/// A lone `if` around the loop — an `Optional` body.
private struct LoneIfRows: View {
    let items: MainActorBox<[String]>
    let shown: Bool

    var body: some View {
        if shown {
            ForEach(items.value, id: \.self) { Text($0) }
                .onDelete { items.value.remove(atOffsets: $0) }
        }
    }
}

/// A view whose body can contain itself, the way a recursive tree view's
/// does: its TYPE is a cycle, which the look has to notice and stop at.
private struct Nesting: View {
    let depth: Int

    var body: some View {
        if depth == 0 {
            Text("innermost")
        } else {
            Self(depth: depth - 1)
        }
    }
}

/// Rows that read the view's own `@State`, and hand its binding out through
/// `probe` so a test can write it between frames the way an action would.
private struct SuffixedRows: View {
    let items: MainActorBox<[String]>
    let probe: MainActorBox<Binding<String>?>
    @State private var suffix = ""

    var body: some View {
        probe.value = $suffix
        return ForEach(items.value, id: \.self) { Text($0 + suffix) }
            .onDelete { items.value.remove(atOffsets: $0) }
    }
}

@MainActor
@Observable
private final class SuffixModel {
    var suffix = ""
}

/// Rows whose body reads an `@Observable` model — read while the BODY is
/// evaluated, so it is the body's evaluation that has to be observed.
private struct ModelRows: View {
    let items: [String]
    let model: SuffixModel
    let builds: MainActorBox<Int>

    var body: some View {
        let suffix = model.suffix
        return ForEach(items, id: \.self) { item in
            builds.value += 1
            return Text(item + suffix)
        }
    }
}

/// A view of the app's own that is ONE row: a stack is not rows.
private struct TwoLineCard: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("first line")
            Text("second line")
        }
    }
}

/// A long loop, counting the row views it builds.
private struct CountingRows: View {
    let count: Int
    let builds: MainActorBox<Int>

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            builds.value += 1
            return Text("row \(index)")
        }
    }
}

// MARK: - The suite

@MainActor
@Suite("A view of your own whose body is list rows", .rendersEnglishUI)
struct ListCustomRowsViewTests {

    // MARK: Rows and selection

    @Test("Its loop's elements are the List's rows, each selectable by its element")
    func rowsAreSelectableByElement() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let selection = MainActorBox<String?>(nil)
        let binding = Binding(get: { selection.value }, set: { selection.value = $0 })
        let fixture = ListSectionEditingFixture()
        fixture.render(List(selection: binding) { Rows(items: items) }.frame(height: 10))
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        #expect(handler.itemCount == 3, "rows: \(handler.itemCount)")
        #expect(
            (0..<handler.itemCount).map { handler.id(at: $0) } == ["alpha", "beta", "gamma"],
            "ids: \((0..<handler.itemCount).map { handler.id(at: $0) })")
        handler.focusedIndex = 1
        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(selection.value == "beta", "got \(String(describing: selection.value))")
    }

    // MARK: Editing

    @Test("As the List's content: Delete removes the element the row draws")
    func deleteAsTheListsContent() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) { Rows(items: items) }.frame(height: 10))

        #expect(fixture.pressDelete(onRow: 1, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    @Test("In a Section: Delete removes the element the row draws")
    func deleteInASection() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Items") { Rows(items: items) }
            }
            .frame(height: 10))

        // header, alpha, beta, gamma — "beta" is row 2 and data offset 1.
        #expect(fixture.pressDelete(onRow: 2, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    @Test("As the List's content: the pick-up reorders its collection")
    func pickUpAsTheListsContent() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) { Rows(items: items) }.frame(height: 10))

        #expect(fixture.pickUpMoveAndPlace(row: 0, named: "alpha", by: 2))
        #expect(items.value == ["beta", "gamma", "alpha"], "got \(items.value)")
    }

    /// Two sections, so an offset is measured from the right section's first
    /// item — and the second holds its loop two views of the app's own deep.
    @Test("One such view inside another, in the second Section, deletes from THAT collection")
    func nestedViewsInTheSecondSectionDelete() {
        let alpha = MainActorBox(["a1", "a2", "a3"])
        let beta = MainActorBox(["b1", "b2", "b3"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Alpha") { Rows(items: alpha) }
                Section("Beta") { OuterRows(items: beta) }
            }
            .frame(height: 12))

        // header, a1, a2, a3, header, b1, b2, b3 — "b2" is row 6, data offset 1.
        #expect(fixture.pressDelete(onRow: 6, named: "b2") == true)
        #expect(beta.value == ["b1", "b3"], "got \(beta.value)")
        #expect(alpha.value == ["a1", "a2", "a3"], "the other section is untouched: \(alpha.value)")
    }

    @Test("A body that is an if/else around the loop, in a Section: Delete removes the element")
    func ifElseBodyInASectionDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Section("Items") { EmptyStateRows(items: items) }
            }
            .frame(height: 10))

        #expect(fixture.pressDelete(onRow: 2, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    @Test("A body that is a whole Section: its header and rows, and Delete removes the element")
    func sectionBodyDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) { ItemsSection(items: items) }
                .frame(height: 10))

        // header, alpha, beta, gamma — "beta" is row 2 and data offset 1.
        #expect(fixture.handler?.itemCount == 4, "rows: \(String(describing: fixture.handler?.itemCount))")
        #expect(fixture.pressDelete(onRow: 2, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    @Test("A body that is a lone if around the loop: Delete removes the element")
    func loneIfBodyDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) { LoneIfRows(items: items, shown: true) }
                .frame(height: 10))

        #expect(fixture.pressDelete(onRow: 1, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    /// `if showAll { Rows() }` — the `if` is an `Optional` around the view,
    /// which `as?` alone would look through to a `ForEach` but not to a view
    /// of the app's own.
    @Test("A lone if around such a view, as the List's content: Delete removes the element")
    func loneIfAroundTheViewDeletes() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let shown = true
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                if shown { Rows(items: items) }
            }
            .frame(height: 10))

        #expect(fixture.pressDelete(onRow: 1, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    // MARK: State and memos

    /// The view's `@State` is bound where a render binds it — the view's own
    /// identity — so a write survives into the next frame, and the rows the
    /// body builds from it are still the list's rows.
    ///
    /// The tree is built afresh for each frame, as an app's `body` builds it:
    /// a `@State` nobody bound keeps the box its `init` made, and a view value
    /// reused across frames would carry that box — and the write — along with
    /// it, passing this test with no binding at all.
    @Test("A body reading its own @State keeps that state, and its rows follow it")
    func bodyStateIsKept() {
        let items = MainActorBox(["alpha", "beta", "gamma"])
        let probe = MainActorBox<Binding<String>?>(nil)
        let fixture = ListSectionEditingFixture()
        func tree() -> some View {
            List(selection: .constant(String?.none)) {
                SuffixedRows(items: items, probe: probe)
            }
            .frame(height: 10)
        }
        fixture.render(tree())
        probe.value?.wrappedValue = "!"
        let drawn = fixture.render(tree()).lines.map(\.stripped)

        #expect(fixture.handler?.itemCount == 3, "rows: \(String(describing: fixture.handler?.itemCount))")
        for label in ["alpha!", "beta!", "gamma!"] {
            #expect(drawn.contains { $0.contains(label) }, "\(label) is missing: \(drawn)")
        }
        // And the action its body built on the second frame still edits.
        #expect(fixture.pressDelete(onRow: 1, named: "beta") == true)
        #expect(items.value == ["alpha", "gamma"], "got \(items.value)")
    }

    /// The row memo keys a row by its element, and an element that did not
    /// change is served from the cache without its row being rebuilt — so a
    /// value the body read has to reach the rows another way: the body's
    /// evaluation is observed, and a change drops the view's whole subtree.
    /// The unchanged frame between checks that the memo really is serving.
    @Test("A body reading an @Observable model redraws its rows when the model changes")
    func observedModelRedrawsTheRows() {
        let model = SuffixModel()
        let builds = MainActorBox(0)
        let tui = TUIContext()
        let focusManager = FocusManager()
        let tree = List(selection: .constant(String?.none)) {
            ModelRows(items: ["alpha", "beta", "gamma"], model: model, builds: builds)
        }
        .frame(height: 10)

        func frame() -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 14, environment: environment, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(tree, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }

        // Two frames to settle: the list takes the focus on the first, and a
        // focused list draws its rows differently from an unfocused one.
        _ = frame()
        _ = frame()
        let settledBuilds = builds.value
        let warm = frame()
        let warmBuilds = builds.value - settledBuilds
        let servedRows = warm.filter { line in ["alpha", "beta", "gamma"].contains { line.contains($0) } }.count
        #expect(
            warmBuilds == verifierRenders(hits: servedRows),
            "the memo is not serving, so this test could not see a stale row: \(warmBuilds) builds")

        model.suffix = "?"
        let changed = frame()
        for label in ["alpha?", "beta?", "gamma?"] {
            #expect(changed.contains { $0.contains(label) }, "\(label) is missing: \(changed)")
        }
        let handler = focusManager.currentFocused as? ItemListHandler<String>
        #expect(handler?.itemCount == 3, "rows: \(String(describing: handler?.itemCount))")
    }

    // MARK: What is not looked through

    /// A stack is one view, so a view of the app's own whose body is one is
    /// one row — in SwiftUI too — and draws exactly as it always did.
    @Test("A view of your own whose body is not rows is still one row")
    func nonRowBodyIsStillOneRow() {
        let fixture = ListSectionEditingFixture()
        let drawn = fixture.render(
            List(selection: .constant(Int?.none)) { TwoLineCard() }.frame(height: 10)
        ).lines.map(\.stripped)
        let handler = fixture.handler(Int.self)
        #expect(handler?.itemCount == 1, "rows: \(String(describing: handler?.itemCount))")
        #expect(handler?.id(at: 0) == 0, "the one row keeps its ordinal")
        #expect(drawn.contains { $0.contains("first line") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("second line") }, "\(drawn)")
    }

    /// Its type is a cycle — `Nesting.Body` holds a `Nesting` — so a walk of
    /// the types that did not remember where it had been would never end. It
    /// is not rows either way, so it is still one row.
    @Test("A view whose body can contain itself is still one row")
    func selfContainingViewIsOneRow() {
        let fixture = ListSectionEditingFixture()
        let drawn = fixture.render(
            List(selection: .constant(Int?.none)) { Nesting(depth: 2) }.frame(height: 10)
        ).lines.map(\.stripped)
        #expect(fixture.handler(Int.self)?.itemCount == 1)
        #expect(drawn.contains { $0.contains("innermost") }, "\(drawn)")
    }

    // MARK: Cost

    /// Looked through, the loop is the list's content and takes the windowed
    /// path: a frame builds the rows it shows, not the fifty thousand it has.
    /// Drawn as one row, the loop built every one of them.
    @Test("A 50,000-element loop behind a view of your own builds only the rows it shows")
    func longLoopStaysWindowed() {
        let builds = MainActorBox(0)
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) { CountingRows(count: 50_000, builds: builds) }
                .frame(height: 10))
        #expect(fixture.handler(Int.self)?.itemCount == 50_000)
        #expect(builds.value < 100, "a frame built \(builds.value) row views")
    }
}
