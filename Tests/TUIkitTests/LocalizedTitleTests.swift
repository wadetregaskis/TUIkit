//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// The `systemImage:` convenience initializers add a THIRD overload to each
    /// of these controls, so the literal now has one more candidate to lose to.
    /// Same rule, and it has to be re-pinned per control rather than inferred
    /// from the plain overloads passing above.
    @Test("systemImage overloads")
    func systemImageOverloads() {
        let toggleBox = Box(false)
        let pickerBox = Box(1)
        expectLocalized(
            Button("test.title.control", systemImage: "star") {},
            Button(Self.computedKey, systemImage: "star") {}, "Button(systemImage:)")
        expectLocalized(
            Button("test.title.control", systemImage: "star", role: .destructive) {},
            Button(Self.computedKey, systemImage: "star", role: .destructive) {},
            "Button(systemImage:role:)")
        expectLocalized(
            Toggle("test.title.control", systemImage: "star", isOn: toggleBox.binding),
            Toggle(Self.computedKey, systemImage: "star", isOn: toggleBox.binding),
            "Toggle(systemImage:)")
        expectLocalized(
            Picker("test.title.control", systemImage: "star", selection: pickerBox.binding) {
                Text("a").tag(1)
            },
            Picker(Self.computedKey, systemImage: "star", selection: pickerBox.binding) {
                Text("a").tag(1)
            }, "Picker(systemImage:)")
        expectLocalized(
            ContentUnavailableView("test.title.control", systemImage: "star"),
            ContentUnavailableView(Self.computedKey, systemImage: "star"),
            "ContentUnavailableView(systemImage:)")
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

    // MARK: - The overload shapes the cases above do not reach

    // Each control below already had a case here for its SIMPLEST spelling, and
    // its ranged / formatted / footered / content-taking siblings are separate
    // declarations that nothing exercised. That gap is not academic: which
    // overload a literal binds to is decided per CALL SITE, so a shape no test
    // writes is a shape that can go wrong without anything going red — which is
    // exactly how `Button` shipped resolving its titles to the key.

    @Test("Ranged and formatted overloads")
    func rangedAndFormattedOverloads() {
        let date = Box(Date(timeIntervalSince1970: 0))
        let lower = Date(timeIntervalSince1970: -86400)
        let upper = Date(timeIntervalSince1970: 86400)
        expectLocalized(
            DatePicker("test.title.control", selection: date.binding, in: lower...upper),
            DatePicker(Self.computedKey, selection: date.binding, in: lower...upper),
            "DatePicker(in: ClosedRange)")
        expectLocalized(
            DatePicker("test.title.control", selection: date.binding, in: lower...),
            DatePicker(Self.computedKey, selection: date.binding, in: lower...),
            "DatePicker(in: PartialRangeFrom)")
        expectLocalized(
            DatePicker("test.title.control", selection: date.binding, in: ...upper),
            DatePicker(Self.computedKey, selection: date.binding, in: ...upper),
            "DatePicker(in: PartialRangeThrough)")

        let slider = Box(0.5)
        expectLocalized(
            Slider("test.title.control", value: slider.binding, in: 0...1),
            Slider(Self.computedKey, value: slider.binding, in: 0...1),
            "Slider")

        expectLocalized(
            LabeledContent("test.title.control", value: 0.5, format: .percent),
            LabeledContent(Self.computedKey, value: 0.5, format: .percent),
            "LabeledContent(value:format:)")

        // A field's title is stored rather than drawn — same exception the
        // plain `TextField` case makes.
        let number = Box(1.5)
        #expect(
            TextField(
                "test.title.control", value: number.binding, format: .number, prompt: nil
            ).label.content == Self.translation)
        #expect(
            TextField(Self.computedKey, value: number.binding, format: .number, prompt: nil)
                .label.content == Self.key)
    }

    @Test("Content-taking and footered overloads")
    func compositeOverloads() {
        let expanded = Box(true)
        expectLocalized(
            DisclosureGroup("test.title.control") { Text("body") },
            DisclosureGroup(Self.computedKey) { Text("body") },
            "DisclosureGroup")
        expectLocalized(
            DisclosureGroup("test.title.control", isExpanded: expanded.binding) { Text("body") },
            DisclosureGroup(Self.computedKey, isExpanded: expanded.binding) { Text("body") },
            "DisclosureGroup(isExpanded:)")

        let radio = Box(1)
        expectLocalized(
            RadioButtonGroup(selection: radio.binding) {
                RadioButtonItem(1, "test.title.control") { Text("c") }
            },
            RadioButtonGroup(selection: radio.binding) {
                RadioButtonItem(1, Self.computedKey) { Text("c") }
            }, "RadioButtonItem(content:)")

        expectLocalized(
            Panel("test.title.control") { Text("body") } footer: { Text("f") },
            Panel(Self.computedKey) { Text("body") } footer: { Text("f") },
            "Panel(footer:)")

        // Spelled out because this overload lives on the UNCONSTRAINED
        // `extension List`, so nothing in the call infers `SelectionValue`.
        expectLocalized(
            List<Int, Text, Text>("test.title.control") { Text("row") } footer: { Text("f") },
            List<Int, Text, Text>(Self.computedKey) { Text("row") } footer: { Text("f") },
            "List(footer:)")
        let single = Box<Int?>(nil)
        expectLocalized(
            List("test.title.control", selection: single.binding) { Text("row") } footer: {
                Text("f")
            },
            List(Self.computedKey, selection: single.binding) { Text("row") } footer: { Text("f") },
            "List(selection:footer:)")
        let multi = Box(Set<Int>())
        expectLocalized(
            List("test.title.control", selection: multi.binding) { Text("row") },
            List(Self.computedKey, selection: multi.binding) { Text("row") },
            "List(selection: Set)")
    }

    @Test("TableColumn value and content overloads")
    func tableColumnOverloads() {
        let box = Box<Row.ID?>(nil)
        expectLocalized(
            Table([Row(name: "a")], selection: box.binding) {
                TableColumn("test.title.control", value: \.name) { $0.name }
            },
            Table([Row(name: "a")], selection: box.binding) {
                TableColumn(Self.computedKey, value: \.name) { $0.name }
            }, "TableColumn(value:content:)")
        expectLocalized(
            Table([Row(name: "a")], selection: box.binding) {
                TableColumn("test.title.control") { $0.name }
            },
            Table([Row(name: "a")], selection: box.binding) {
                TableColumn(Self.computedKey) { $0.name }
            }, "TableColumn(value: closure)")
    }

    @Test("Presentation overloads with a message and a value")
    func presentationOverloads() {
        let box = Box(true)
        expectPresented(
            Text("body").alert("test.title.control", isPresented: box.binding) {
                Button("ok") {}
            } message: { Text("m") },
            Text("body").alert(Self.computedKey, isPresented: box.binding) {
                Button("ok") {}
            } message: { Text("m") },
            "alert(message:)")
        expectPresented(
            Text("body").confirmationDialog(
                "test.title.control", isPresented: box.binding, titleVisibility: .visible
            ) { Button("ok") {} } message: { Text("m") },
            Text("body").confirmationDialog(
                Self.computedKey, isPresented: box.binding, titleVisibility: .visible
            ) { Button("ok") {} } message: { Text("m") },
            "confirmationDialog(message:)")

        let item = Box<Int?>(1)
        expectPresented(
            Text("body").alert(
                "test.title.control", isPresented: box.binding, presenting: item.value
            ) { _ in Button("ok") {} },
            Text("body").alert(
                Self.computedKey, isPresented: box.binding, presenting: item.value
            ) { _ in Button("ok") {} },
            "alert(presenting:)")
    }

    /// The call shape that actually breaks, which none of the cases above is.
    ///
    /// Worth stating plainly, because it is the difference between coverage and
    /// the appearance of it: most of the shapes tested above pass whether their
    /// twin is spelled `String` or `<S: StringProtocol>`, so they pin nothing on
    /// this toolchain — they are guards against a future ranking change, not
    /// evidence about today's. Mutation-tested: reverting `DisclosureGroup`'s
    /// and `DatePicker`'s twins to a concrete `String` leaves every one of them
    /// green, because a `@ViewBuilder` returning a generic, and a `Binding`
    /// neighbour, both keep the key overload ranked first.
    ///
    /// `.constant(…)` is the spelling that does not. It was demonstrated on
    /// `ColorPickerPanel` by demangling the initializer SIL actually applied:
    /// with a real `Binding` the literal reached `LocalizedStringKey`, and with
    /// `.constant(…)` the identical declaration reached `String`. So this case
    /// is the one that fails if any of these twins loses its generic spelling,
    /// and it is why the sweep was worth doing at all.
    @Test("A .constant binding must not change which overload wins")
    func constantBindingsKeepTheKey() {
        // EVERY binding constant, not just one: a single `.constant` beside a
        // real `Binding` still ranks the key overload first, so a half-measure
        // here would be a test that cannot fail. Mutation-tested both ways.
        expectLocalized(
            ColorPickerPanel(
                "test.title.control", selection: .constant(.red), isPresented: .constant(true)),
            ColorPickerPanel(
                Self.computedKey, selection: .constant(.red), isPresented: .constant(true)),
            "ColorPickerPanel(.constant)")
        expectLocalized(
            Toggle("test.title.control", isOn: .constant(true)),
            Toggle(Self.computedKey, isOn: .constant(true)), "Toggle(.constant)")
        expectLocalized(
            Picker("test.title.control", selection: .constant(1)) { Text("a").tag(1) },
            Picker(Self.computedKey, selection: .constant(1)) { Text("a").tag(1) },
            "Picker(.constant)")
        expectLocalized(
            Stepper("test.title.control", value: .constant(0), in: 0...10),
            Stepper(Self.computedKey, value: .constant(0), in: 0...10), "Stepper(.constant)")
        #expect(
            TextField("test.title.control", text: .constant("")).label.content == Self.translation)
        #expect(TextField(Self.computedKey, text: .constant("")).label.content == Self.key)
    }

    @Test("Alert presets with an explicit title and actions")
    func alertPresetTitledOverloads() {
        #expect(
            Alert.warning(title: "test.title.control", message: "m") { Button("ok") {} }.title
                == Self.translation)
        #expect(
            Alert.error(title: "test.title.control", message: "m") { Button("ok") {} }.title
                == Self.translation)
        #expect(
            Alert.success(title: "test.title.control", message: "m") { Button("ok") {} }.title
                == Self.translation)
        // …and a computed title is still shown as written rather than looked up.
        #expect(
            Alert.warning(title: Self.computedKey, message: "m") { Button("ok") {} }.title
                == Self.key)
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

    // MARK: - TUI-specific chrome

    // Everything below has no SwiftUI counterpart — a terminal app's dialogs,
    // cards and status bar. The rule is the same one: text a reader has to
    // understand is a key, and a glyph is not.

    @Test("Dialog")
    func dialog() {
        expectLocalized(
            Dialog(title: "test.title.control") { Text("body") },
            Dialog(title: Self.computedKey) { Text("body") }, "Dialog")
        expectLocalized(
            Dialog(title: "test.title.control") { Text("body") } footer: { Text("f") },
            Dialog(title: Self.computedKey) { Text("body") } footer: { Text("f") },
            "Dialog(footer:)")
        expectLocalized(
            Dialog.doubleLine(title: "test.title.control") { Text("body") },
            Dialog.doubleLine(title: Self.computedKey) { Text("body") },
            "Dialog.doubleLine")
        expectLocalized(
            Dialog.heavy(title: "test.title.control") { Text("body") },
            Dialog.heavy(title: Self.computedKey) { Text("body") },
            "Dialog.heavy")
    }

    @Test("Alert title and message")
    func alert() {
        expectLocalized(
            Alert(title: "test.title.control", message: "m"),
            Alert(title: Self.computedKey, message: "m"), "Alert title")
        // The message is prose the reader has to understand, so it is a key too
        // — unlike a `LabeledContent` value, which is the thing being labelled.
        #expect(
            rendered(Alert(title: "t", message: "test.title.control"))
                .contains(Self.translation), "Alert message")
        expectLocalized(
            Alert(title: "test.title.control", message: "m") { Button("ok") {} },
            Alert(title: Self.computedKey, message: "m") { Button("ok") {} },
            "Alert(actions:)")
    }

    @Test("Alert presets")
    func alertPresets() {
        // The four styled presets used to default their titles to hardcoded
        // English. They now come from the framework's own table, so they follow
        // the selected language like everything else.
        #expect(
            Alert<EmptyView>.warning(message: "m").title
                == LocalizationService.shared.string(for: LocalizationKey.Label.warning))
        #expect(
            Alert<EmptyView>.error(message: "m").title
                == LocalizationService.shared.string(for: LocalizationKey.Label.error))
        #expect(
            Alert<EmptyView>.info(message: "m").title
                == LocalizationService.shared.string(for: LocalizationKey.Label.info))
        #expect(
            Alert<EmptyView>.success(message: "m").title
                == LocalizationService.shared.string(for: LocalizationKey.Label.success))

        // …and that default is worth having: an isolated service in another
        // language returns a different word for each. (Isolated, so the shared
        // service — which every other test reads — is never re-pointed.)
        let german = LocalizationService(
            configDirectoryPath: NSTemporaryDirectory() + "tuikit-alert-\(UUID().uuidString)")
        german.setLanguage(.german)
        #expect(german.string(for: LocalizationKey.Label.warning) == "Warnung")
        #expect(german.string(for: LocalizationKey.Label.success) == "Erfolg")

        // A literal message is a key; a computed `String` is not, and still
        // reaches the overload that keeps the localized default title.
        #expect(Alert<EmptyView>.warning(message: "test.title.control").message == Self.translation)
        #expect(Alert<EmptyView>.warning(message: Self.computedKey).message == Self.key)
        #expect(
            Alert<EmptyView>.warning(message: Self.computedKey).title
                == LocalizationService.shared.string(for: LocalizationKey.Label.warning))
        // An explicit literal title wins over the default and is looked up.
        #expect(Alert<EmptyView>.error(title: "test.title.control", message: "m").title == Self.translation)
        // The with-actions forms resolve identically.
        #expect(
            Alert.info(message: "test.title.control") { Button("ok") {} }.message
                == Self.translation)
    }

    @Test("Card")
    func card() {
        expectLocalized(
            Card(title: "test.title.control") { Text("body") },
            Card(title: Self.computedKey) { Text("body") }, "Card")
        expectLocalized(
            Card(title: "test.title.control") { Text("body") } footer: { Text("f") },
            Card(title: Self.computedKey) { Text("body") } footer: { Text("f") },
            "Card(footer:)")
        // The key overload is non-optional, so neither untitled form becomes
        // ambiguous with it — but they do not reach the same place, which this
        // comment used to claim they did. `Card { … }` reaches the dedicated
        // no-title initializer (not disfavoured, and one fewer defaulted
        // argument); only `Card(title: nil)` reaches the `String?` one, since
        // `nil` cannot infer a generic `S` and so cannot go anywhere else.
        // Both spellings must keep compiling, which is what is asserted here.
        #expect(Card { Text("body") }.title == nil)
        #expect(Card(title: nil) { Text("body") }.title == nil)
    }

    @Test("Colour and gradient editor panels")
    func editorPanels() {
        let color = Box(Color.red)
        let stops = Box(Gradient(colors: [Color.red, Color.blue]))
        let presented = Box(true)
        expectLocalized(
            ColorPickerPanel(
                "test.title.control", selection: color.binding,
                isPresented: presented.binding),
            ColorPickerPanel(
                Self.computedKey, selection: color.binding,
                isPresented: presented.binding),
            "ColorPickerPanel")
        expectLocalized(
            GradientEditorPanel(
                "test.title.control", gradient: stops.binding,
                isPresented: presented.binding),
            GradientEditorPanel(
                Self.computedKey, gradient: stops.binding,
                isPresented: presented.binding),
            "GradientEditorPanel")
    }

    @Test("StatusBarItem and QuitShortcut labels")
    func statusBar() {
        // Not views — the label is stored, so it is read directly. `shortcut` /
        // `shortcutSymbol` stay plain strings: they are the key glyph, which is
        // the same in every language.
        #expect(StatusBarItem(shortcut: "q", label: "test.title.control").label
            == Self.translation)
        #expect(StatusBarItem(shortcut: "q", label: Self.computedKey).label == Self.key)
        #expect(StatusBarItem(shortcut: "q", label: "test.title.control") {}.label
            == Self.translation)
        #expect(StatusBarItem(shortcut: "q", label: Self.computedKey) {}.label == Self.key)

        #expect(
            QuitShortcut(key: .character("q"), shortcutSymbol: "q", label: "test.title.control")
                .label == Self.translation)
        #expect(
            QuitShortcut(key: .character("q"), shortcutSymbol: "q", label: Self.computedKey)
                .label == Self.key)
        // Omitting the label still reaches the `String` overload's default.
        #expect(QuitShortcut(key: .character("q"), shortcutSymbol: "q").label == "quit")
    }

    @Test("imagePlaceholder")
    func imagePlaceholder() {
        // A path that cannot load leaves the image in its placeholder state,
        // which is where the text is drawn.
        expectLocalized(
            Image(.file("/nope.png")).imagePlaceholder("test.title.control")
                .imagePlaceholderSpinner(false),
            Image(.file("/nope.png")).imagePlaceholder(Self.computedKey)
                .imagePlaceholderSpinner(false),
            "imagePlaceholder")
        // Non-optional key overload, so `nil` still reaches the `String?` one.
        _ = Image(.file("/nope.png")).imagePlaceholder(nil)
    }

    @Test("Notification message")
    func notification() {
        let service = NotificationService()
        service.post("test.title.control")
        service.post(Self.computedKey)
        let entries = service.activeEntries()
        #expect(entries.count == 2)
        #expect(entries[0].message == Self.translation)
        #expect(entries[1].message == Self.key)
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
