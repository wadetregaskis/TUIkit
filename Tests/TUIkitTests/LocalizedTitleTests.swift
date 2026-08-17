//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocalizedTitleTests.swift
//
//  "A string literal is a lookup key" applied to every control that takes a
//  title, not just ``Text``.
//
//  These are overload-resolution tests, and that is the whole point: the
//  capability was always reachable — `Button(someLocalizedString)` works — but
//  the spelling SwiftUI source actually uses, `Button("button.save")`, showed
//  the key. Nothing looks wrong in such an app until somebody translates it.
//
//  Each control is checked BOTH ways round. A literal must be looked up, and a
//  computed `String` must not: without the second half the fix would localize
//  file paths and people's names.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Localized titles")
struct LocalizedTitleTests {

    /// The one key every case here looks up, and the text it resolves to.
    ///
    /// Dot-separated and namespaced to this suite, so it cannot collide with an
    /// app's prose or another suite's registration — the same property that
    /// makes the whole rule safe to adopt (see `SwiftUI-compatibility.md` §4a).
    private static let key = "test.title.control"
    private static let translation = "Localized!"

    /// A `String` *equal* to the key but computed rather than written, so it
    /// must NOT be looked up. Built by concatenation so no amount of constant
    /// folding can turn it back into a literal.
    private static var computedKey: String { "test.title" + ".control" }

    init() {
        LocalizationService.shared.register(translations: [
            "en": [Self.key: Self.translation]
        ])
    }

    /// The rendered text of a view, stripped of styling — what the user reads.
    private func rendered(_ view: some View, width: Int = 44, height: Int = 8) -> String {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tui)
        return renderToBuffer(view, context: context).lines
            .map(\.stripped).joined(separator: "\n")
    }

    /// Asserts that `literal` — the view built from the literal key — shows the
    /// translation, and `computed` — the same view built from a `String` — does
    /// not.
    ///
    /// Both halves matter. Only the first would pass if every string were
    /// looked up, which is the bug in the other direction.
    private func expectLocalized(
        _ literal: some View, _ computed: some View,
        _ label: Comment, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            rendered(literal).contains(Self.translation), label,
            sourceLocation: sourceLocation)
        #expect(
            rendered(computed).contains(Self.key), label,
            sourceLocation: sourceLocation)
    }

    // MARK: - The mechanism it generalises

    @Test("Text is unchanged")
    func text() {
        expectLocalized(Text("test.title.control"), Text(Self.computedKey), "Text")
    }

    // MARK: - Buttons, menus and links

    @Test("Button")
    func button() {
        expectLocalized(
            Button("test.title.control") {}, Button(Self.computedKey) {}, "Button")
        expectLocalized(
            Button("test.title.control", role: .destructive) {},
            Button(Self.computedKey, role: .destructive) {}, "Button(role:)")
    }

    @Test("Menu")
    func menu() {
        expectLocalized(
            Menu("test.title.control") { Button("x") {} },
            Menu(Self.computedKey) { Button("x") {} }, "Menu")
    }

    @Test("Link")
    func link() {
        let url = URL(string: "https://example.com")!
        expectLocalized(
            Link("test.title.control", destination: url),
            Link(Self.computedKey, destination: url), "Link")
    }

    @Test("NavigationLink")
    func navigationLink() {
        expectLocalized(
            NavigationLink("test.title.control", value: 1),
            NavigationLink(Self.computedKey, value: 1), "NavigationLink(value:)")
        expectLocalized(
            NavigationLink("test.title.control") { Text("dest") },
            NavigationLink(Self.computedKey) { Text("dest") },
            "NavigationLink(destination:)")
    }

    // MARK: - Value controls

    @Test("Toggle")
    func toggle() {
        let box = Box(false)
        expectLocalized(
            Toggle("test.title.control", isOn: box.binding),
            Toggle(Self.computedKey, isOn: box.binding), "Toggle")
    }

    @Test("TextField and SecureField")
    func textFields() {
        // These two are the exception to the render-and-read rule: as in
        // SwiftUI, a field's title describes it without being drawn on it (the
        // prompt is what appears inside), so there is nothing in the buffer to
        // look for. The stored label is the observable.
        let box = Box("")
        #expect(TextField("test.title.control", text: box.binding).label.content
            == Self.translation)
        #expect(TextField(Self.computedKey, text: box.binding).label.content == Self.key)
        #expect(SecureField("test.title.control", text: box.binding).label.content
            == Self.translation)
        #expect(SecureField(Self.computedKey, text: box.binding).label.content == Self.key)

        // The prompt-taking overloads resolve their title the same way.
        #expect(
            TextField("test.title.control", text: box.binding, prompt: nil).label.content
                == Self.translation)
        #expect(
            SecureField("test.title.control", text: box.binding, prompt: nil).label.content
                == Self.translation)
    }

    @Test("Picker")
    func picker() {
        let box = Box(1)
        expectLocalized(
            Picker("test.title.control", selection: box.binding) { Text("a").tag(1) },
            Picker(Self.computedKey, selection: box.binding) { Text("a").tag(1) },
            "Picker")
    }

    @Test("Stepper")
    func stepper() {
        let box = Box(0)
        expectLocalized(
            Stepper("test.title.control", value: box.binding),
            Stepper(Self.computedKey, value: box.binding), "Stepper(value:)")
        expectLocalized(
            Stepper("test.title.control", value: box.binding, in: 0...10),
            Stepper(Self.computedKey, value: box.binding, in: 0...10), "Stepper(in:)")
        expectLocalized(
            Stepper("test.title.control", onIncrement: {}, onDecrement: {}),
            Stepper(Self.computedKey, onIncrement: {}, onDecrement: {}),
            "Stepper(onIncrement:)")
    }

    @Test("DatePicker")
    func datePicker() {
        let box = Box(Date(timeIntervalSince1970: 0))
        expectLocalized(
            DatePicker("test.title.control", selection: box.binding),
            DatePicker(Self.computedKey, selection: box.binding), "DatePicker")
    }

    @Test("ColorPicker")
    func colorPicker() {
        let box = Box(Color.red)
        expectLocalized(
            ColorPicker("test.title.control", selection: box.binding),
            ColorPicker(Self.computedKey, selection: box.binding), "ColorPicker")
    }

    @Test("RadioButton item")
    func radioButton() {
        let box = Box(1)
        expectLocalized(
            RadioButtonGroup(selection: box.binding) {
                RadioButtonItem(1, "test.title.control")
            },
            RadioButtonGroup(selection: box.binding) {
                RadioButtonItem(1, Self.computedKey)
            }, "RadioButtonItem")
    }

    // MARK: - Read-outs

    @Test("ProgressView")
    func progressView() {
        expectLocalized(
            ProgressView("test.title.control"), ProgressView(Self.computedKey),
            "ProgressView")
        expectLocalized(
            ProgressView("test.title.control", value: 0.5),
            ProgressView(Self.computedKey, value: 0.5), "ProgressView(value:)")
    }

    @Test("Gauge")
    func gauge() {
        expectLocalized(
            Gauge("test.title.control", value: 0.5),
            Gauge(Self.computedKey, value: 0.5), "Gauge")
    }

    @Test("Spinner")
    func spinner() {
        expectLocalized(
            Spinner("test.title.control"), Spinner(Self.computedKey), "Spinner")
    }

    @Test("Label")
    func label() {
        // The symbol resolves to a glyph only on some hosts, so the assertion is
        // about the TITLE either way — which is the half under test.
        expectLocalized(
            Label("test.title.control", systemImage: "star"),
            Label(Self.computedKey, systemImage: "star"), "Label")
    }

    @Test("LabeledContent")
    func labeledContent() {
        expectLocalized(
            LabeledContent("test.title.control") { Text("v") },
            LabeledContent(Self.computedKey) { Text("v") }, "LabeledContent")
        expectLocalized(
            LabeledContent("test.title.control", value: "v"),
            LabeledContent(Self.computedKey, value: "v"), "LabeledContent(value:)")
    }

    @Test("ContentUnavailableView")
    func contentUnavailable() {
        expectLocalized(
            ContentUnavailableView("test.title.control"),
            ContentUnavailableView(Self.computedKey), "ContentUnavailableView")
        // Both halves are prose here, so both are keys.
        #expect(
            rendered(ContentUnavailableView("nope", description: "test.title.control"))
                .contains(Self.translation), "the description is a key too")
    }

    // MARK: - Containers

    @Test("Section")
    func section() {
        expectLocalized(
            List { Section("test.title.control") { Text("row") } },
            List { Section(Self.computedKey) { Text("row") } }, "Section")
    }

    @Test("List title")
    func listTitle() {
        expectLocalized(
            List("test.title.control") { Text("row") },
            List(Self.computedKey) { Text("row") }, "List")
        let box = Box<Int?>(nil)
        expectLocalized(
            List("test.title.control", selection: box.binding) { Text("row") },
            List(Self.computedKey, selection: box.binding) { Text("row") },
            "List(selection:)")
    }

    @Test("List empty placeholder")
    func listPlaceholder() {
        let box = Box<String?>(nil)
        expectLocalized(
            List(selection: box.binding) { EmptyView() }
                .listEmptyPlaceholder("test.title.control"),
            List(selection: box.binding) { EmptyView() }
                .listEmptyPlaceholder(Self.computedKey),
            "listEmptyPlaceholder")
    }

    @Test("Panel")
    func panel() {
        expectLocalized(
            Panel("test.title.control") { Text("body") },
            Panel(Self.computedKey) { Text("body") }, "Panel")
    }

    @Test("Tab")
    func tab() {
        let box = Box(1)
        expectLocalized(
            TabView(selection: box.binding) {
                Tab("test.title.control", value: 1) { Text("body") }
            },
            TabView(selection: box.binding) {
                Tab(Self.computedKey, value: 1) { Text("body") }
            }, "Tab")
    }

    @Test("TableColumn header")
    func tableColumn() {
        let box = Box<Row.ID?>(nil)
        expectLocalized(
            Table([Row(name: "a")], selection: box.binding) {
                TableColumn("test.title.control", value: \.name)
            },
            Table([Row(name: "a")], selection: box.binding) {
                TableColumn(Self.computedKey, value: \.name)
            }, "TableColumn")
    }

    // MARK: - Modifiers

    @Test("navigationTitle")
    func navigationTitle() {
        // A preference rather than drawn text, so this one is read from the
        // preference store instead of the buffer.
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 4,
            environment: environment, tuiContext: tui)

        tui.preferences.beginRenderPass()
        _ = renderToBuffer(
            Text("x").navigationTitle("test.title.control"), context: context)
        #expect(tui.preferences.current[NavigationTitleKey.self] == Self.translation)

        tui.preferences.beginRenderPass()
        _ = renderToBuffer(Text("x").navigationTitle(Self.computedKey), context: context)
        #expect(tui.preferences.current[NavigationTitleKey.self] == Self.key)
    }

    @Test("alert and confirmationDialog")
    func presentations() {
        // A presentation renders into an overlay, so the plain buffer shows only
        // the content behind it — these have to be composited before the title
        // is on screen at all.
        let box = Box(true)
        expectPresented(
            Text("body").alert("test.title.control", isPresented: box.binding) {
                Button("ok") {}
            },
            Text("body").alert(Self.computedKey, isPresented: box.binding) {
                Button("ok") {}
            }, "alert")
        expectPresented(
            Text("body").confirmationDialog(
                "test.title.control", isPresented: box.binding
            ) { Button("ok") {} },
            Text("body").confirmationDialog(
                Self.computedKey, isPresented: box.binding
            ) { Button("ok") {} }, "confirmationDialog")
    }

    /// ``expectLocalized(_:_:_:)`` for a view whose text is in an overlay.
    private func expectPresented(
        _ literal: some View, _ computed: some View,
        _ label: Comment, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            composited(literal).contains(Self.translation), label,
            sourceLocation: sourceLocation)
        #expect(
            composited(computed).contains(Self.key), label,
            sourceLocation: sourceLocation)
    }

    /// The rendered text *including* overlays — what the compositor puts on
    /// screen, which is where a presented dialog's title lives.
    private func composited(_ view: some View, width: Int = 50, height: Int = 16) -> String {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tui)

        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.compositingOverlays(
            maxWidth: width, maxHeight: height, palette: environment.palette
        ).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("searchable prompt")
    func searchablePrompt() {
        let box = Box("")
        expectLocalized(
            Text("body").searchable(text: box.binding, prompt: "test.title.control"),
            Text("body").searchable(text: box.binding, prompt: Self.computedKey),
            "searchable(prompt:)")
    }

    @Test("badge")
    func badge() {
        expectLocalized(
            List { Text("row").badge("test.title.control") },
            List { Text("row").badge(Self.computedKey) }, "badge")
    }

    // MARK: - Fixtures

    /// A row type for the `Table` case.
    private struct Row: Identifiable, Sendable {
        let id = UUID()
        let name: String
    }

    /// Somewhere for a `Binding` to point. A class, because a `Binding` needs
    /// storage that outlives the expression that builds it.
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
        var binding: Binding<T> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }
}
