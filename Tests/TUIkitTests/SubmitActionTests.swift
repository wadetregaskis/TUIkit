//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SubmitActionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("onSubmit / submitLabel")
struct SubmitActionTests {

    // MARK: - combinedSubmitAction (the composition core)

    @Test("Per-field runs first, then cascading actions inner-first")
    func compositionOrder() {
        var log: [String] = []
        // Env append order is outer-first, so [outer, inner]; inner must fire
        // before outer, and both after the per-field closure.
        let actions = [
            SubmitActionEntry(triggers: .text, action: { log.append("outer") }),
            SubmitActionEntry(triggers: .text, action: { log.append("inner") }),
        ]
        let combined = combinedSubmitAction(
            perField: { log.append("field") }, cascading: actions, role: .text)
        combined?()
        #expect(log == ["field", "inner", "outer"])
    }

    @Test("Nil when there is neither a per-field closure nor a matching entry")
    func nilWhenEmpty() {
        // The load-bearing invariant: a field with no submit action must leave
        // handler.onSubmit nil so Return falls through to a dialog default button.
        #expect(combinedSubmitAction(perField: nil, cascading: [], role: .text) == nil)
        // A cascading entry that doesn't match the field's role also yields nil.
        let searchOnly = [SubmitActionEntry(triggers: .search, action: {})]
        #expect(combinedSubmitAction(perField: nil, cascading: searchOnly, role: .text) == nil)
    }

    @Test("Role filtering routes .text and .search independently")
    func roleFiltering() {
        var textFired = false
        var searchFired = false
        let actions = [
            SubmitActionEntry(triggers: .text, action: { textFired = true }),
            SubmitActionEntry(triggers: .search, action: { searchFired = true }),
        ]
        // A .text-role field runs only the .text entry.
        combinedSubmitAction(perField: nil, cascading: actions, role: .text)?()
        #expect(textFired == true)
        #expect(searchFired == false)

        // A .search-role field runs only the .search entry.
        textFired = false
        combinedSubmitAction(perField: nil, cascading: actions, role: .search)?()
        #expect(textFired == false)
        #expect(searchFired == true)
    }

    @Test("A combined [.text, .search] entry fires for either role")
    func combinedTriggers() {
        var count = 0
        let actions = [SubmitActionEntry(triggers: [.text, .search], action: { count += 1 })]
        combinedSubmitAction(perField: nil, cascading: actions, role: .text)?()
        combinedSubmitAction(perField: nil, cascading: actions, role: .search)?()
        #expect(count == 2)
    }

    // MARK: - Rendered wiring (env cascade → handler)

    private func makeContext(_ focusManager: FocusManager) -> RenderContext {
        makeRenderContext { environment, _ in environment.focusManager = focusManager }
    }

    @Test("A cascading .onSubmit fires when Return is pressed in a descendant field")
    func cascadeFiresOnEnter() {
        let focusManager = FocusManager()
        let context = makeContext(focusManager)
        var submitted = 0

        let view = VStack {
            TextField("Name", text: .constant("Ada"))
        }
        .onSubmit { submitted += 1 }

        _ = renderToBuffer(view, context: context)  // auto-focuses the lone field
        #expect(focusManager.currentFocusedID != nil, "the field is focused after render")
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(submitted == 1, "Return in the field ran the cascading .onSubmit")
    }

    @Test("Per-field and cascading .onSubmit both fire, per-field first")
    func perFieldAndCascadeBothFire() {
        let focusManager = FocusManager()
        let context = makeContext(focusManager)
        var log: [String] = []

        let view = VStack {
            TextField("Name", text: .constant("Ada"))
                .onSubmit { log.append("field") }
        }
        .onSubmit { log.append("cascade") }

        _ = renderToBuffer(view, context: context)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(log == ["field", "cascade"], "both ran, most-specific first")
    }

    @Test("Rendering (or measuring) never fires the submit action — only Return does")
    func renderDoesNotFire() {
        let focusManager = FocusManager()
        let context = makeContext(focusManager)
        var fired = 0

        let view = TextField("Name", text: .constant("x")).onSubmit { fired += 1 }
        // Multiple renders + a measure pass: the action is assembled, never run.
        _ = renderToBuffer(view, context: context)
        _ = renderToBuffer(view, context: context)
        _ = measureChild(view, proposal: ProposedSize(width: 40, height: 1), context: context)
        #expect(fired == 0, "no submit action fires during layout")
    }

    @Test("SecureField submits just like TextField")
    func secureFieldParity() {
        let focusManager = FocusManager()
        let context = makeContext(focusManager)
        var submitted = 0

        let view = SecureField("Password", text: .constant("hunter2"))
            .onSubmit { submitted += 1 }
        _ = renderToBuffer(view, context: context)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(submitted == 1)
    }

    // MARK: - .search routing (via .searchable's query field)

    @Test("Return in a .searchable field fires .onSubmit(of: .search), not .text")
    func searchRoleRouting() {
        let focusManager = FocusManager()
        let context = makeContext(focusManager)
        var textFired = false
        var searchFired = false

        // The searchable query field carries the .search role; the .onSubmit(of:
        // .search) must fire, and a .text-scoped one must not.
        let view = Text("results")
            .searchable(text: .constant("q"))
            .onSubmit(of: .search) { searchFired = true }
            .onSubmit(of: .text) { textFired = true }

        _ = renderToBuffer(view, context: context)
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        #expect(searchFired == true, "the search field ran the .search action")
        #expect(textFired == false, "and NOT the .text action")
    }

    // MARK: - submitLabel (stored for parity)

    @Test("submitLabel is stored in the environment; titles resolve")
    func submitLabelStored() {
        var env = EnvironmentValues()
        #expect(env.submitLabel == nil)
        env.submitLabel = .send
        #expect(env.submitLabel == .send)
        #expect(SubmitLabel.send.title == "Send")
        #expect(SubmitLabel.return.title == "Return")
        #expect(SubmitLabel.continue.title == "Continue")
        // The modifier compiles and renders without crashing.
        _ = renderToBuffer(
            TextField("x", text: .constant("y")).submitLabel(.go),
            context: makeBareRenderContext())
    }
}
