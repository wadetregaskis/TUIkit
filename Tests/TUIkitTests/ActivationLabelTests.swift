//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ActivationLabelTests.swift
//
//  What the status bar's Return entry says, which is whatever the focused
//  control says Return does to it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Return verb")
struct ActivationLabelTests {
    /// Renders `view` with the focus on whatever registers first, and reports
    /// the verb it published.
    private func verb(for view: some View, focusID: String? = nil) -> String? {
        let tui = TUIContext()
        let state = StatusBarState()
        let focus = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = state
        environment.terminalWidth = 40
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)

        // Two passes: the first registers the control so the focus can land on
        // it, the second renders with it focused — which is when it publishes.
        for pass in 0..<2 {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            if pass == 1 {
                state.activationLabelOverride = nil
                if let focusID { focus.focus(id: focusID) }
            }
            _ = renderToBuffer(view, context: context)
            tui.stateStorage.endRenderPass()
            focus.endRenderPass()
        }
        return state.activationLabelOverride
    }

    @Test("A button on the page activates")
    func button() {
        #expect(verb(for: Button("Go") {}) == "activate")
    }

    @Test("A button in a menu chooses")
    func buttonInAMenu() {
        #expect(
            verb(for: Menu("Pick") { Button("One") {} }.menuStyle(.inline)) == "choose")
    }

    @Test("A toggle toggles")
    func toggle() {
        #expect(verb(for: Toggle("On", isOn: .constant(false))) == "toggle")
    }

    @Test("A closed pop-up opens its menu")
    func closedPicker() {
        #expect(
            verb(for: Picker("Pick", selection: .constant(0)) { Text("One").tag(0) })
                == "open menu")
    }

    @Test("A text field with somewhere to submit says so, and one without says nothing")
    func textField() {
        #expect(verb(for: TextField("Name", text: .constant(""))) == nil)
        #expect(verb(for: TextField("Name", text: .constant("")).onSubmit {}) == "submit")
    }

    @Test("A list selects, and a list with a row action opens")
    func list() {
        let plain = List(selection: .constant(String?.none)) {
            ForEach(["a", "b"], id: \.self) { Text($0) }
        }
        #expect(verb(for: plain) == "select")
        #expect(verb(for: plain.onRowActivate { _ in }) == "open")
    }

    @Test("An unfocused control says nothing")
    func unfocused() {
        // Nothing is focused: the render still runs, and the bar stays silent.
        let tui = TUIContext()
        let state = StatusBarState()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = state
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(Button("Go") {}.disabled(), context: context)
        tui.stateStorage.endRenderPass()
        #expect(state.activationLabelOverride == nil)
    }

    // MARK: - The bar

    private func bar(items: [any StatusBarItemProtocol], verb: String?) -> String {
        let tui = TUIContext()
        let state = StatusBarState()
        state.activationLabelOverride = verb
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = state
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, environment: environment, tuiContext: tui
        ).isolatingRenderCache()
        return renderToBuffer(StatusBar(items: items, style: .compact), context: context)
            .lines.joined()
    }

    @Test("The Return entry takes the focused control's verb, and nothing else does")
    func barRenamesOnlyReturn() {
        let rendered = bar(
            items: [
                StatusBarItem(shortcut: Shortcut.enter, label: "show"),
                StatusBarItem(shortcut: "q", label: "quit"),
            ],
            verb: "toggle")
        #expect(rendered.contains("toggle"))
        #expect(!rendered.contains("show"))
        #expect(rendered.contains("quit"))
    }

    @Test("With nothing published the page's own label stands")
    func barKeepsTheDeclaredLabel() {
        let rendered = bar(
            items: [StatusBarItem(shortcut: Shortcut.enter, label: "show")], verb: nil)
        #expect(rendered.contains("show"))
    }
}
