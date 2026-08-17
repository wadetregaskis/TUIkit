//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SearchableTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("searchable")
struct SearchableTests {
    private final class QueryBox { var query = "" }
    private func binding(_ box: QueryBox) -> Binding<String> {
        Binding(get: { box.query }, set: { box.query = $0 })
    }
    private func render(_ view: some View) -> [String] {
        let context = makeBareRenderContext(width: 40, height: 8)
        return renderToBuffer(view, context: context).lines
    }

    @Test("Presents a search field above the searchable content")
    func presentsFieldAboveContent() {
        let out = render(Text("CONTENT").searchable(text: binding(QueryBox())))
        let joined = out.joined(separator: "\n")
        // No emoji chrome in a bare context, so the icon is omitted (a tiny
        // ⌕ / mis-drawn magnifier would read as noise) — the "Search" prompt
        // carries the affordance instead. Both magnifiers are checked: the
        // placement decides WHICH one is drawn, so asserting only one would
        // silently stop testing anything if the default side ever changed.
        #expect(joined.contains("Search"), "the default prompt renders when the field is empty")
        #expect(!joined.contains("\u{1F50D}"), "no magnifier at all without emoji chrome")
        #expect(!joined.contains("\u{1F50E}"), "no magnifier at all without emoji chrome")
        #expect(joined.contains("CONTENT"), "the searchable content renders too")

        let promptLine = out.firstIndex { $0.contains("Search") } ?? Int.max
        let contentLine = out.firstIndex { $0.contains("CONTENT") } ?? Int.min
        #expect(promptLine < contentLine, "the field sits above the content")
    }

    @Test("Draws a magnifier where the terminal renders emoji chrome")
    func magnifierWithEmojiChrome() {
        let out = render(
            Text("CONTENT")
                .searchable(text: binding(QueryBox()))
                .environment(\.supportsEmojiChrome, true))
        let joined = out.joined(separator: "\n")
        #expect(joined.contains("\u{1F50E}"), "the leading 🔎 magnifier renders under emoji chrome")

        let glyphLine = out.firstIndex { $0.contains("\u{1F50E}") } ?? Int.max
        let contentLine = out.firstIndex { $0.contains("CONTENT") } ?? Int.min
        #expect(glyphLine < contentLine, "the field sits above the content")
    }

    /// The glyph follows the SIDE so the lens always faces the field: 🔎
    /// (right-pointing) leads, 🔍 (left-pointing) trails.
    ///
    /// Both the glyph AND its column are asserted. Checking only the glyph
    /// would pass for a regression that swapped the characters but left the
    /// icon on the same side — which is exactly the half-fix this is guarding.
    @Test("The magnifier's glyph and column follow its placement")
    func magnifierFollowsPlacement() {
        func iconColumn(_ placement: SearchFieldIconPlacement, glyph: String) -> Int? {
            let out = render(
                Text("CONTENT")
                    .searchable(text: binding(QueryBox()))
                    .searchFieldIconPlacement(placement)
                    .environment(\.supportsEmojiChrome, true))
            return out.compactMap { line -> Int? in
                guard let r = line.range(of: glyph) else { return nil }
                return line.distance(from: line.startIndex, to: r.lowerBound)
            }.first
        }

        guard let leading = iconColumn(.leading, glyph: "\u{1F50E}") else {
            Issue.record("leading placement drew no 🔎")
            return
        }
        guard let trailing = iconColumn(.trailing, glyph: "\u{1F50D}") else {
            Issue.record("trailing placement drew no 🔍")
            return
        }
        #expect(leading < trailing, "the trailing icon sits to the right of the leading one")

        // …and each side draws only its own glyph.
        #expect(iconColumn(.leading, glyph: "\u{1F50D}") == nil, "leading must not draw 🔍")
        #expect(iconColumn(.trailing, glyph: "\u{1F50E}") == nil, "trailing must not draw 🔎")
    }

    @Test("The field reflects the bound query text")
    func reflectsBoundText() {
        let box = QueryBox()
        box.query = "apple"
        let out = render(Text("body").searchable(text: binding(box))).joined(separator: "\n")
        #expect(out.contains("apple"), "the current query renders in the field")
    }

    @Test("A custom prompt is displayed")
    func customPrompt() {
        let out = render(Text("body").searchable(text: binding(QueryBox()), prompt: "Find fruit"))
            .joined(separator: "\n")
        #expect(out.contains("Find fruit"))
    }

    // MARK: - isSearching / dismissSearch

    /// A content view that reports what it reads out of the environment.
    ///
    /// Reading through a rendered view rather than poking the context is the
    /// point: these two values are only worth anything if they reach the
    /// caller's own subtree, which is the half a direct environment assertion
    /// would not test.
    private struct Probe: View {
        let captured: ActionBox

        @Environment(\.isSearching) private var isSearching
        @Environment(\.dismissSearch) private var dismissSearch

        var body: some View {
            captured.dismiss = dismissSearch
            return Text(isSearching ? "SEARCHING" : "IDLE")
        }
    }

    private final class ActionBox { var dismiss: DismissSearchAction? }

    /// Drives one full frame the way `RenderLoop` does, so focus is assigned
    /// and `@State` survives to the next one.
    @discardableResult
    private func frame(
        _ view: some View, tuiContext: TUIContext, focusManager: FocusManager
    ) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 8,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("The content learns that the field has focus")
    func contentSeesIsSearching() {
        let box = QueryBox()
        let captured = ActionBox()
        let view = Probe(captured: captured).searchable(text: binding(box))
        let tui = TUIContext()
        let focus = FocusManager()

        // Frame 1 registers the field and hands it focus; the content of that
        // same frame was already built, so it still reads the old value. Frame
        // 2 is the one that carries it — the ordinary one-cycle propagation a
        // state change has, and the reason this is not a one-render test.
        frame(view, tuiContext: tui, focusManager: focus)
        #expect(frame(view, tuiContext: tui, focusManager: focus).contains("SEARCHING"))
    }

    @Test("With focus elsewhere, nothing is searching")
    func idleWhenTheFieldIsUnfocused() {
        let captured = ActionBox()
        // A button ahead of the search field takes the auto-focus, so the field
        // never gets it — the same shape as a user who has tabbed away.
        let view = VStack {
            Button("Elsewhere") {}
            Probe(captured: captured).searchable(text: binding(QueryBox()))
        }
        let tui = TUIContext()
        let focus = FocusManager()

        frame(view, tuiContext: tui, focusManager: focus)
        #expect(frame(view, tuiContext: tui, focusManager: focus).contains("IDLE"))
    }

    @Test("Dismissing empties the query and lets go of the keyboard")
    func dismissSearchClearsAndUnfocuses() {
        let box = QueryBox()
        box.query = "apple"
        let captured = ActionBox()
        let view = VStack {
            Probe(captured: captured).searchable(text: binding(box))
            Button("After") {}
        }
        let tui = TUIContext()
        let focus = FocusManager()

        frame(view, tuiContext: tui, focusManager: focus)
        frame(view, tuiContext: tui, focusManager: focus)
        let fieldID = focus.currentFocusedID
        #expect(fieldID != nil, "the search field should hold focus to begin with")

        captured.dismiss?()
        #expect(box.query.isEmpty, "the query is emptied")
        #expect(
            focus.currentFocusedID != fieldID,
            "focus moved off the field — it was \(focus.currentFocusedID ?? "nil")")
    }

    @Test("Dismissing from outside a search leaves focus alone")
    func dismissOutsideASearchOnlyClears() {
        let box = QueryBox()
        box.query = "apple"
        let captured = ActionBox()
        // The field never takes focus (the button ahead of it does), so
        // dismissing must not shunt the keyboard off whatever the user IS
        // using. Only the query goes.
        let view = VStack {
            Button("Elsewhere") {}
            Probe(captured: captured).searchable(text: binding(box))
        }
        let tui = TUIContext()
        let focus = FocusManager()

        frame(view, tuiContext: tui, focusManager: focus)
        frame(view, tuiContext: tui, focusManager: focus)
        let before = focus.currentFocusedID

        captured.dismiss?()
        #expect(box.query.isEmpty)
        #expect(focus.currentFocusedID == before, "focus must not move")
    }

    // MARK: - searchSuggestions / searchCompletion

    /// A full frame at a known terminal size, with the pop-up overlay
    /// composited in — a suggestions menu is an overlay, so it is not in
    /// `buffer.lines` until that happens.
    private func screen(
        _ view: some View, tui: TUIContext, focus: FocusManager
    ) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 60
        environment.terminalHeight = 20
        let context = RenderContext(
            availableWidth: 60, availableHeight: 20,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.compositingOverlays(
            maxWidth: 60, maxHeight: 20, palette: environment.palette
        ).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("The search field offers what searchSuggestions built")
    func searchFieldOffersSuggestions() {
        let tui = TUIContext()
        let focus = FocusManager()
        let view = Text("CONTENT")
            .searchable(text: binding(QueryBox()))
            .searchSuggestions {
                Text("apple")
                Divider()
                Text("apricot")
            }

        _ = screen(view, tui: tui, focus: focus)  // register + auto-focus the field
        _ = screen(view, tui: tui, focus: focus)  // sync the completions
        // The menu opens on demand, never on focus — so the Down is the test's
        // subject as much as the suggestions are.
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        let out = screen(view, tui: tui, focus: focus)
        #expect(out.contains("apple") && out.contains("apricot"), "\(out)")
    }

    @Test("A text field in the CONTENT is not armed by searchSuggestions")
    func contentFieldsAreNotArmed() {
        // The reason `\.searchSuggestions` is a key of its own. A modifier that
        // named the search field must not reach into the caller's own fields —
        // and sharing `\.textInputSuggestions` would do exactly that, silently.
        let tui = TUIContext()
        let focus = FocusManager()
        let box = QueryBox()
        let view = TextField("Other", text: binding(box))
            .focusID("other")
            .searchable(text: binding(QueryBox()))
            .searchSuggestions { Text("apple") }

        _ = screen(view, tui: tui, focus: focus)
        focus.focus(id: "other")
        _ = screen(view, tui: tui, focus: focus)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        let out = screen(view, tui: tui, focus: focus)
        #expect(!out.contains("apple"), "the content's field opened a menu it was never given: \(out)")
    }

    @Test("An outer textInputSuggestions still reaches the search field")
    func inheritedSuggestionsSurvive() {
        // The other half of that decision: with no `.searchSuggestions` of its
        // own, the field inherits like any text field rather than being
        // singled out and cleared.
        let tui = TUIContext()
        let focus = FocusManager()
        let view = Text("CONTENT")
            .searchable(text: binding(QueryBox()))
            .textInputSuggestions { Text("inherited") }

        _ = screen(view, tui: tui, focus: focus)
        _ = screen(view, tui: tui, focus: focus)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))
        #expect(screen(view, tui: tui, focus: focus).contains("inherited"))
    }

    @Test("searchCompletion decides what choosing a suggestion types")
    func searchCompletionFillsTheField() {
        // The label and the completion deliberately share no text, so the
        // query can only be right by way of the completion.
        let tui = TUIContext()
        let focus = FocusManager()
        let box = QueryBox()
        let view = Text("CONTENT")
            .searchable(text: binding(box))
            .searchSuggestions {
                Text("Everything").searchCompletion("*")
            }

        _ = screen(view, tui: tui, focus: focus)
        _ = screen(view, tui: tui, focus: focus)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))  // open
        _ = screen(view, tui: tui, focus: focus)
        _ = focus.dispatchKeyEvent(KeyEvent(key: .down))  // highlight the row
        _ = focus.dispatchKeyEvent(KeyEvent(key: .enter))  // choose it
        #expect(box.query == "*", "chose the completion, not the label: \(box.query)")
    }

    @Test("Outside any searchable, the two values are inert")
    func defaultsOutsideASearchable() {
        let captured = ActionBox()
        let out = render(Probe(captured: captured))
        #expect(out.joined().contains("IDLE"))
        // Nothing to clear and nothing to unfocus: the call must simply do
        // nothing rather than, say, reach for the focus manager.
        captured.dismiss?()
    }
}
