//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleCascadeCoverageTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Additional coverage filling gaps left by StyleCascadeTests: SecureField,
//  Section footer chrome, Table rows, disabled-cascade beyond Button, Theme
//  within-bundle specificity ordering, TintedPalette delegation, and a few
//  StyleAttributes / modifier edge cases.

import Testing

@testable import TUIkit

private struct CoverageRow: Identifiable, Sendable {
    let id: Int
    let name: String
}

@MainActor
@Suite("Style cascade — additional coverage")
struct StyleCascadeCoverageTests {

    private func context(width: Int = 40, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    // MARK: - StyleAttributes

    @Test("StyleAttributes.isEmpty reflects whether any field is set")
    func isEmpty() {
        #expect(StyleAttributes().isEmpty)
        #expect(!StyleAttributes(bold: true).isEmpty)
        #expect(!StyleAttributes(foreground: .red).isEmpty)
        #expect(!StyleAttributes(background: .red).isEmpty)
        #expect(!StyleAttributes(textCase: .uppercase).isEmpty)
    }

    @Test("merged carries foreground/background per property")
    func mergedColours() {
        let result = StyleAttributes(background: .red)
            .merged(over: StyleAttributes(foreground: .blue, background: .green))
        #expect(result.background == .red)   // self wins
        #expect(result.foreground == .blue)  // base fills
    }

    // MARK: - Broad modifiers

    @Test(".all scope applies to text")
    func allScopeAppliesToText() {
        let view = Text("Hi").style(.all, StyleAttributes(bold: true))
        let line = renderToBuffer(view, context: context()).lines.joined()
        #expect(line.contains("\u{1B}[1;") || line.contains("\u{1B}[1m"))
    }

    @Test("fontWeight(.regular) clears an inherited bold")
    func fontWeightRegularClears() {
        let view = VStack { Text("Hi").fontWeight(.regular) }.bold()
        let line = renderToBuffer(view, context: context()).lines.joined()
        #expect(!line.contains("\u{1B}[1;") && !line.contains("\u{1B}[1m"), "regular should clear bold")
    }

    // MARK: - Section footer chrome

    @Test("A section footer is dim (not bold) by default")
    func footerDefault() {
        let section = Section { Text("Body") } footer: { Text("Foot") }
        let footer = renderToBuffer(section, context: context()).lines.last ?? ""
        #expect(footer.contains("\u{1B}[2;") || footer.contains("\u{1B}[2m"), "footer should be dim")
        #expect(!footer.contains("\u{1B}[1;2"), "footer should not be bold")
    }

    @Test("A .chrome(.sectionFooter) override can bold the footer")
    func footerOverride() {
        let section = Section { Text("Body") } footer: { Text("Foot") }
            .style(.chrome(.sectionFooter)) { $0.bold = true }
        let footer = renderToBuffer(section, context: context()).lines.last ?? ""
        #expect(footer.contains("\u{1B}[1;2"), "footer should now be bold + dim")
    }

    // MARK: - TintedPalette delegation

    @Test("TintedPalette overrides only accent; other roles delegate to base")
    func tintedPaletteDelegates() {
        let base = SystemPalette(.green)
        let tinted = TintedPalette(base: base, tint: .rgb(1, 2, 3))
        #expect(tinted.accent == .rgb(1, 2, 3))
        #expect(tinted.background == base.background)
        #expect(tinted.foreground == base.foreground)
        #expect(tinted.success == base.success)
        #expect(tinted.id == base.id)
    }

    @Test("TintedPalette resolves a semantic tint against its base")
    func tintedPaletteResolvesSemantic() {
        let base = SystemPalette(.green)
        let tinted = TintedPalette(base: base, tint: .palette.success)
        #expect(tinted.accent == base.success.resolve(with: base))
        #expect(tinted.accent.rgbComponents != nil, "accent must be concrete (renderable)")
    }
}

// MARK: - SecureField

@MainActor
@Suite("SecureField style cascade")
struct SecureFieldStyleCascadeTests {

    @Test(".secureFieldTextStyle colours the masked text")
    func secureFieldForeground() {
        let view = SecureField("Password", text: .constant("hunter2"))
            .secureFieldTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }
}

// MARK: - Table rows

@MainActor
@Suite("Table row style cascade")
struct TableRowStyleCascadeTests {

    @Test("Broad .foregroundStyle reaches Table cell text")
    func tableCellForeground() {
        let view = Table([CoverageRow(id: 1, name: "Alpha")], selection: .constant(nil as Int?)) {
            TableColumn("Name", value: \CoverageRow.name)
        }
        .foregroundStyle(.rgb(7, 8, 9))
        let line = renderToBuffer(view, context: makeRenderContext(width: 30, height: 8)).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }
}

// MARK: - Cascading disabled beyond Button

@MainActor
@Suite("Cascading disabled — other controls")
struct CascadingDisabledOtherControlsTests {

    @Test("A container .disabled() disables a Toggle like its own .disabled()")
    func toggleContainerDisable() {
        let viaContainer = VStack { Toggle("Wrap", isOn: .constant(true)) }.disabled()
        let viaInstance = VStack { Toggle("Wrap", isOn: .constant(true)).disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("A container .disabled() disables a Slider like its own .disabled()")
    func sliderContainerDisable() {
        let viaContainer = VStack { Slider(value: .constant(0.5)) }.disabled()
        let viaInstance = VStack { Slider(value: .constant(0.5)).disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("A container .disabled() disables a Stepper like its own .disabled()")
    func stepperContainerDisable() {
        let viaContainer = VStack { Stepper("Qty", value: .constant(5)) }.disabled()
        let viaInstance = VStack { Stepper("Qty", value: .constant(5)).disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("A container .disabled() disables a RadioButtonGroup like its own .disabled()")
    func radioGroupContainerDisable() {
        func group() -> RadioButtonGroup<String> {
            RadioButtonGroup(selection: .constant("a")) {
                RadioButtonItem("a", "Alpha")
                RadioButtonItem("b", "Beta")
            }
        }
        let viaContainer = VStack { group() }.disabled()
        let viaInstance = VStack { group().disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("A container .disabled() disables a (menu) Picker like its own .disabled()")
    func pickerContainerDisable() {
        func picker() -> Picker<Text, Int, some View> {
            Picker("Theme", selection: .constant(1)) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
        }
        let viaContainer = VStack { picker() }.disabled()
        let viaInstance = VStack { picker().disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("A container .disabled() disables a TextField like its own .disabled()")
    func textFieldContainerDisable() {
        let viaContainer = VStack { TextField("Name", text: .constant("Ada")) }.disabled()
        let viaInstance = VStack { TextField("Name", text: .constant("Ada")).disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("A container .disabled() disables a SecureField like its own .disabled()")
    func secureFieldContainerDisable() {
        let viaContainer = VStack { SecureField("Pass", text: .constant("hunter2")) }.disabled()
        let viaInstance = VStack { SecureField("Pass", text: .constant("hunter2")).disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }
}

// MARK: - Theme within-bundle specificity

@MainActor
@Suite("Theme bundle specificity")
struct ThemeBundleSpecificityTests {

    @Test("Within a theme bundle, a more specific entry beats a broader one")
    func specificBeatsBroadInBundle() {
        // Both entries match a default Text (role .foreground). Within the bundle
        // they're ordered broad-first, so the .semanticColor entry wins.
        let theme = Theme(
            palette: SystemPalette(.green),
            styles: [
                StyleCascade.Entry(scope: .text, attributes: StyleAttributes(foreground: .rgb(1, 2, 3))),
                StyleCascade.Entry(
                    scope: .semanticColor(.foreground),
                    attributes: StyleAttributes(foreground: .rgb(7, 8, 9))),
            ])
        let line = renderToBuffer(Text("Hi").theme(theme), context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"), "the more specific .semanticColor entry should win")
        #expect(!line.contains("38;2;1;2;3"), "the broader .text entry should be overridden")
    }
}
