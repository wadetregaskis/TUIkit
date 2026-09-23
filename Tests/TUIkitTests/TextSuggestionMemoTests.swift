//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextSuggestionMemoTests.swift
//
//  `.searchSuggestions` and `.textInputSuggestions` put their entries in the
//  environment, and the entries cannot be compared (a label is an `AnyView`),
//  so every memo under them was off: a List under `.searchSuggestions` drew
//  every row afresh on every frame. They compare by presence and emptiness now,
//  and the one reader of the entries — a text field, which syncs its handler
//  from them on every render — declares a side effect whenever they are
//  present, so no memo holding one can be served. These pin both halves.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// One frame of the real loop's lifecycle, with the cache counters a test
/// asks about.
@MainActor
private final class SuggestionLoop {
    let tui = TUIContext()
    let focus = FocusManager()
    var cache: RenderCache { tui.renderCache }

    /// Draws `view` and returns the composited lines, styling kept.
    @discardableResult
    func frame(_ view: some View) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        environment.terminalWidth = 60
        environment.terminalHeight = 20
        let context = RenderContext(
            availableWidth: 60, availableHeight: 20, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.compositingOverlays(maxWidth: 60, maxHeight: 20, palette: environment.palette).lines
    }

    /// How many memoized subtrees the next frame of `view` served.
    func served(_ view: some View) -> Int {
        let before = cache.rowWork.served
        frame(view)
        return cache.rowWork.served - before
    }

    /// How many subtree clears the next frame of `view` made.
    func clears(_ view: some View) -> Int {
        let before = cache.stats.subtreeClears
        frame(view)
        return cache.stats.subtreeClears - before
    }
}

/// A text field in a memoized card, compared by title alone.
private struct FieldCard: View, @preconcurrency Equatable {
    let title: String
    let text: Binding<String>

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View { TextField(title, text: text).focusID("combo") }
}

/// Twenty memoized rows.
private struct Rows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { index in Text("row \(index)") }
        }
    }
}

@MainActor
@Suite("Memos under text and search suggestions")
struct TextSuggestionMemoTests {
    @Test("Rows under .searchSuggestions are served")
    func rowsUnderSearchSuggestionsAreServed() {
        let loop = SuggestionLoop()
        var query = ""
        func view() -> some View {
            Rows()
                .searchable(text: Binding(get: { query }, set: { query = $0 }))
                .searchSuggestions { Text("apple") }
        }
        loop.frame(view())
        // The field takes the focus in the first frame, so `isSearching` turns
        // true for the content in the second — rightly clearing it.
        loop.frame(view())
        #expect(loop.served(view()) >= 20, "the rows were drawn afresh under the suggestions")
    }

    @Test("Rows beside a field under .textInputSuggestions are served")
    func rowsUnderTextInputSuggestionsAreServed() {
        let loop = SuggestionLoop()
        var text = ""
        func view() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Rows()
                TextField("Field", text: Binding(get: { text }, set: { text = $0 }))
            }
            .textInputSuggestions { Text("a") }
        }
        loop.frame(view())
        #expect(loop.served(view()) >= 20, "the field's siblings were drawn afresh")
    }

    /// A card holding a field, with another control holding the focus — an
    /// unfocused field is otherwise storable, which the first case shows.
    private func cardServes(offering options: [String]?, disabled: Bool = false) -> Int {
        let loop = SuggestionLoop()
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        @ViewBuilder func view() -> some View {
            let base = VStack {
                Button("Other") {}.focusID("other")
                FieldCard(title: "t", text: binding).equatable().disabled(disabled)
            }
            if let options {
                base.textInputSuggestions(options, id: \.self) { Text($0) }
            } else {
                base
            }
        }
        loop.frame(view())
        loop.focus.focus(id: "other")
        loop.frame(view())
        return loop.served(view())
    }

    @Test("A memo holding a field under suggestions is never served")
    func aFieldUnderSuggestionsIsNeverServed() {
        #expect(cardServes(offering: nil) >= 1, "precondition: an unfocused field is servable")
        #expect(cardServes(offering: ["alpha"]) == 0, "served with suggestions present")
        #expect(cardServes(offering: []) == 0, "served with suggestions present but empty")
        #expect(cardServes(offering: ["alpha"], disabled: true) == 0, "served while disabled")
    }

    /// What serving would cost: the handler's completions are synced by the
    /// render, and an event can use them before the next one.
    @Test("Changed suggestions reach the handler with no render in between")
    func changedSuggestionsReachTheHandler() {
        let loop = SuggestionLoop()
        var text = ""
        var options = ["alpha"]
        let binding = Binding(get: { text }, set: { text = $0 })
        func view() -> some View {
            VStack {
                Button("Other") {}.focusID("other")
                FieldCard(title: "t", text: binding).equatable()
            }
            .textInputSuggestions(options, id: \.self) { Text($0) }
        }
        loop.frame(view())
        loop.focus.focus(id: "other")
        loop.frame(view())
        loop.frame(view())
        options = ["beta"]
        loop.frame(view())

        loop.focus.focus(id: "combo")
        _ = loop.focus.dispatchKeyEvent(KeyEvent(key: .down))
        _ = loop.focus.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(text == "beta", "the field was served with the old completions: \(text)")
    }

    @Test("The ▾ follows whether there are suggestions")
    func theDisclosureFollowsEmptiness() {
        let loop = SuggestionLoop()
        var text = ""
        var options: [String] = []
        let binding = Binding(get: { text }, set: { text = $0 })
        func screen() -> String {
            loop.frame(
                VStack {
                    Button("Other") {}.focusID("other")
                    FieldCard(title: "t", text: binding).equatable()
                }
                .textInputSuggestions(options, id: \.self) { Text($0) }
            ).map(\.stripped).joined(separator: "\n")
        }
        _ = screen()
        loop.focus.focus(id: "other")
        #expect(!screen().contains(DropdownMenu.closedCaret), "no suggestions, no ▾")
        options = ["alpha"]
        #expect(screen().contains(DropdownMenu.closedCaret), "suggestions arrived, the ▾ did not")
        options = []
        #expect(!screen().contains(DropdownMenu.closedCaret), "suggestions went, the ▾ did not")
    }

    /// The price of the comparison: a change of content clears nothing below
    /// the modifier — suggestions are rebuilt as the query is typed — and a
    /// change of emptiness clears once.
    @Test("New suggestions clear nothing; running out of them clears")
    func contentChangesDoNotClear() {
        let loop = SuggestionLoop()
        var text = ""
        var options = ["a"]
        func view() -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Rows()
                TextField("Field", text: Binding(get: { text }, set: { text = $0 }))
            }
            .textInputSuggestions(options, id: \.self) { Text($0) }
        }
        loop.frame(view())
        loop.frame(view())
        options = ["b"]
        #expect(loop.clears(view()) == 0, "a change of content cleared the subtree")
        options = []
        #expect(loop.clears(view()) >= 1, "running out of suggestions cleared nothing")
    }

    /// Every label renders at the field's own identity, so memos inside two
    /// labels share one entry: they must stay off, as they were.
    @Test("Two labels with memos inside draw as themselves")
    func labelsWithMemosDrawAsThemselves() {
        let loop = SuggestionLoop()
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        func view() -> some View {
            TextField("City", text: binding)
                .focusID("combo")
                .textInputSuggestions {
                    HStack { ForEach(["Paris"], id: \.self) { Text($0) } }
                        .foregroundStyle(.red).textInputCompletion("red")
                    HStack { ForEach(["Paris"], id: \.self) { Text($0) } }
                        .foregroundStyle(.blue).textInputCompletion("blue")
                }
                .frame(width: 24)
        }
        loop.frame(view())
        loop.focus.focus(id: "combo")
        loop.frame(view())
        _ = loop.focus.dispatchKeyEvent(KeyEvent(key: .down))
        loop.frame(view())
        let rows = loop.frame(view()).filter { $0.stripped.contains("Paris") }
        #expect(rows.count == 2, "both rows in the open menu: \(rows.map(\.stripped))")
        if rows.count == 2 {
            #expect(rows[0] != rows[1], "one label was served the other's buffer: \(rows)")
        }
    }

    /// Why a memo may store a field's SIZE under suggestions, though never its
    /// buffer: the size does not depend on them.
    @Test("A field measures the same with and without suggestions", arguments: [5, 6, 7, 8, 30])
    func theSizeDoesNotDependOnSuggestions(width: Int) {
        let context = RenderContext(availableWidth: width, availableHeight: 5, tuiContext: TUIContext())
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let proposal = ProposedSize(width: width, height: nil)
        let plain = measureChild(TextField("F", text: binding), proposal: proposal, context: context)
        let offered = measureChild(
            TextField("F", text: binding).textInputSuggestions { Text("x") }, proposal: proposal, context: context)
        let empty = measureChild(
            TextField("F", text: binding).textInputSuggestions([String](), id: \.self) { Text($0) },
            proposal: proposal, context: context)
        #expect(offered == plain)
        #expect(empty == plain)
    }
}
