//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedTitleOverloadShapeTests.swift
//
//  The second half of `LocalizedTitleTests`: the overload SHAPES its cases do
//  not reach.
//
//  Split out because the two halves answer different questions, and because one
//  file carrying both crossed SwiftLint's 600-line ceiling. Same suite, so the
//  registration in `LocalizedTitleTests.init()` still runs for every case here
//  — these are an extension of that type, not a copy of it.
//
//  Each control here already had a case in the sibling file for its SIMPLEST
//  spelling; its ranged / formatted / footered / content-taking siblings are
//  separate declarations that nothing exercised. Which overload a literal binds
//  to is decided per CALL SITE, so a shape no test writes is a shape that can
//  go wrong without anything going red — which is how `Button` shipped
//  resolving its titles to the key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

extension LocalizedTitleTests {

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
}
