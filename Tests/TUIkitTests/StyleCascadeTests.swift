//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleCascadeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Style cascade")
struct StyleCascadeTests {

    private func context(width: Int = 40, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    /// All SGR parameter codes present across a rendered buffer (e.g. "1" = bold,
    /// "2" = dim, "3" = italic, "4" = underline, "9" = strikethrough).
    private func sgrCodes(_ buffer: FrameBuffer) -> Set<String> {
        var codes: Set<String> = []
        for line in buffer.lines {
            var rest = Substring(line)
            while let start = rest.range(of: "\u{1B}[") {
                rest = rest[start.upperBound...]
                guard let m = rest.firstIndex(of: "m") else { break }
                for code in rest[..<m].split(separator: ";") { codes.insert(String(code)) }
                rest = rest[rest.index(after: m)...]
            }
        }
        return codes
    }

    // MARK: - StyleAttributes.merged

    @Test("merged: self wins per property, base fills the rest")
    func mergedPerProperty() {
        let base = StyleAttributes(bold: true, dim: true)
        let over = StyleAttributes(bold: false, italic: true)
        let result = over.merged(over: base)
        #expect(result.bold == false)     // over wins
        #expect(result.italic == true)    // only over sets it
        #expect(result.dim == true)       // only base sets it
    }

    // MARK: - StyleCascade.resolve

    @Test("resolve: innermost matching entry wins, per property")
    func resolveProximityPerProperty() {
        let cascade = StyleCascade()
            .appending(.text, StyleAttributes(bold: true, dim: true))      // outer
            .appending(.text, StyleAttributes(bold: false))                // inner
        let resolved = cascade.resolve(for: [.all, .text])
        #expect(resolved.bold == false)   // inner overrides
        #expect(resolved.dim == true)     // outer persists (inner didn't set it)
    }

    @Test("resolve: only entries whose scope matches apply")
    func resolveScopeMatching() {
        let cascade = StyleCascade()
            .appending(.control(.button), StyleAttributes(bold: true))
            .appending(.semanticColor(.foregroundSecondary), StyleAttributes(dim: true))
        // A plain text view matches .all/.text but neither of the above.
        #expect(cascade.resolve(for: [.all, .text]).bold == nil)
        #expect(cascade.resolve(for: [.all, .text]).dim == nil)
        // Add the secondary role to the scope path → the dim entry now applies.
        #expect(cascade.resolve(for: [.all, .text, .semanticColor(.foregroundSecondary)]).dim == true)
    }

    @Test("appending empty attributes is a no-op")
    func appendingEmptyIsNoop() {
        #expect(StyleCascade().appending(.text, StyleAttributes()).isEmpty)
    }

    // MARK: - Text integration

    @Test("Container .bold() makes descendant text bold")
    func containerBold() {
        let view = VStack { Text("Hi") }.bold()
        #expect(sgrCodes(renderToBuffer(view, context: context())).contains("1"))
    }

    @Test("italic / underline / strikethrough cascade to text")
    func otherAttributesCascade() {
        #expect(sgrCodes(renderToBuffer(Text("Hi").style(.text, StyleAttributes(italic: true)), context: context())).contains("3"))
        #expect(sgrCodes(renderToBuffer(Text("Hi").underline(), context: context())).contains("4"))
        #expect(sgrCodes(renderToBuffer(Text("Hi").strikethrough(), context: context())).contains("9"))
    }

    @Test("The broad .italic() modifier italicises text, and an inner .italic(false) wins")
    func broadItalicModifier() {
        // The bare modifier emits SGR 3 (its siblings .underline()/.strikethrough()
        // are covered above; .italic() was previously only reached via .style()).
        #expect(sgrCodes(renderToBuffer(Text("Hi").italic(), context: context())).contains("3"))
        // Proximity override, mirroring .bold(): an inner .italic(false) beats an
        // outer .italic().
        let nested = VStack { Text("Hi").italic(false) }.italic()
        #expect(!sgrCodes(renderToBuffer(nested, context: context())).contains("3"))
    }

    @Test("Proximity: an inner .bold(false) overrides an outer .bold()")
    func innerOverridesOuter() {
        let view = VStack { Text("Hi").bold(false) }.bold()
        #expect(!sgrCodes(renderToBuffer(view, context: context())).contains("1"))
    }

    @Test("Per-Text .bold() wins over a container .bold(false)")
    func perTextWins() {
        let view = VStack { Text("Hi").bold() }.bold(false)
        #expect(sgrCodes(renderToBuffer(view, context: context())).contains("1"))
    }

    @Test("Role-scoped dim applies only to text drawn with that palette role")
    func semanticRoleScoped() {
        let view = VStack {
            Text("plain")
            Text("secondary").foregroundStyle(.palette.foregroundSecondary)
        }
        .style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
        // The secondary-coloured text must render dim ("2"); the plain text alone
        // would not, so the presence of "2" proves the role-scoped entry matched.
        #expect(sgrCodes(renderToBuffer(view, context: context())).contains("2"))
    }

    @Test("textCase transforms the rendered text")
    func textCaseTransforms() {
        let upper = renderToBuffer(VStack { Text("Hello") }.textCase(.uppercase), context: context())
        #expect(upper.lines.contains { $0.contains("HELLO") })
        let lower = renderToBuffer(VStack { Text("Hello") }.textCase(.lowercase), context: context())
        #expect(lower.lines.contains { $0.contains("hello") })
    }

    @Test("fontWeight maps to bold / faint")
    func fontWeightMapping() {
        #expect(sgrCodes(renderToBuffer(Text("Hi").fontWeight(.bold), context: context())).contains("1"))
        #expect(sgrCodes(renderToBuffer(Text("Hi").fontWeight(.light), context: context())).contains("2"))
    }

    // MARK: - Scoped colour

    @Test("A scoped foreground colours text via the cascade")
    func cascadeForeground() {
        let view = VStack { Text("Hi") }.style(.text, StyleAttributes(foreground: .rgb(10, 20, 30)))
        let line = renderToBuffer(view, context: context()).lines.joined()
        #expect(line.contains("38;2;10;20;30"))
    }

    @Test("A role-scoped foreground recolours only text with that palette role")
    func cascadeSemanticForeground() {
        let view = VStack {
            Text("primary")
            Text("secondary").foregroundStyle(.palette.foregroundSecondary)
        }
        .style(.semanticColor(.foregroundSecondary), StyleAttributes(foreground: .rgb(1, 2, 3)))
        let line = renderToBuffer(view, context: context()).lines.joined()
        #expect(line.contains("38;2;1;2;3"), "secondary text should be recoloured")
    }

    // MARK: - Chrome roles (Section header/footer)

    @Test("A section header is bold + dim by default")
    func chromeHeaderDefault() {
        let section = Section("Header") { Text("Body") }
        let header = renderToBuffer(section, context: context()).lines.first ?? ""
        // bold (1) then dim (2) as the leading style codes.
        #expect(header.contains("\u{1B}[1;2"))
    }

    @Test("A .chrome(.sectionHeader) override turns off the default bold, keeping dim")
    func chromeHeaderBoldOff() {
        let section = Section("Header") { Text("Body") }
            .style(.chrome(.sectionHeader)) { $0.bold = false }
        let header = renderToBuffer(section, context: context()).lines.first ?? ""
        #expect(!header.contains("\u{1B}[1;2"), "bold should be off")
        #expect(header.contains("\u{1B}[2;") || header.contains("\u{1B}[2m"), "dim should remain")
    }

    @Test("A .chrome(.sectionHeader) override can uppercase the header")
    func chromeHeaderUppercase() {
        let section = Section("Header") { Text("Body") }
            .style(.chrome(.sectionHeader)) { $0.textCase = .uppercase }
        let lines = renderToBuffer(section, context: context()).lines
        #expect(lines.contains { $0.contains("HEADER") }, "header should be uppercased")
        #expect(lines.contains { $0.contains("Body") }, "body should be unaffected")
    }
}

@MainActor
@Suite("Button style cascade")
struct ButtonStyleCascadeTests {

    @Test(".buttonTextStyle colours the button label")
    func buttonTextForeground() {
        let view = Button("Save") {}.buttonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A destructive role keeps its colour despite a broad button override")
    func destructiveStaysLoadBearing() {
        let view = Button("Delete", role: .destructive) {}
            .buttonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(!line.contains("38;2;7;8;9"), "destructive label must not take the broad override")
    }

    @Test("Variant scoping targets only the matching button variant")
    func variantScoping() {
        // .automatic targets the default style → applies.
        let matched = Button("A") {}.buttonTextStyle(.automatic) { $0.foreground = .rgb(7, 8, 9) }
        #expect(renderToBuffer(matched, context: makeRenderContext()).lines.joined().contains("38;2;7;8;9"))
        // .primary targets the primary style → does not apply to a default button.
        let unmatched = Button("A") {}.buttonTextStyle(.primary) { $0.foreground = .rgb(7, 8, 9) }
        #expect(!renderToBuffer(unmatched, context: makeRenderContext()).lines.joined().contains("38;2;7;8;9"))
    }
}

@MainActor
@Suite("Toggle style cascade")
struct ToggleStyleCascadeTests {

    @Test(".toggleTextStyle colours the toggle label")
    func toggleTextForeground() {
        let view = Toggle("Wi-Fi", isOn: .constant(true))
            .toggleTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A broad .control(.button) entry does not touch a toggle label")
    func toggleIgnoresButtonScope() {
        let view = Toggle("Wi-Fi", isOn: .constant(true))
            .buttonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(!line.contains("38;2;7;8;9"))
    }
}

@MainActor
@Suite("Theme bundle")
struct ThemeBundleTests {

    @Test(".theme applies palette + tint + scoped styles together")
    func themeBundle() {
        let theme = Theme(
            palette: TerminalProfilePalette(.ocean),
            tint: .rgb(7, 8, 9),
            styles: [
                StyleCascade.Entry(
                    scope: .chrome(.sectionHeader),
                    attributes: StyleAttributes(textCase: .uppercase))
            ])
        let view = VStack {
            Button("Save") {}.buttonStyle(.primary)
            Section("settings") { Text("body") }
        }
        .theme(theme)
        let buffer = renderToBuffer(view, context: makeRenderContext(width: 40, height: 12))
        let joined = buffer.lines.joined()
        #expect(joined.contains("38;2;7;8;9"), "theme tint reaches the button accent")
        #expect(
            buffer.lines.contains { $0.contains("SETTINGS") },
            "theme's chrome style uppercases the section header")
    }

    @Test(".theme installs a control style for the subtree")
    func themeControlStyle() {
        let theme = Theme(palette: SystemPalette(.green), buttonStyle: PlainButtonStyle())
        // Plain buttons have no bracket caps; the default style does. Applying the
        // theme should make the button render plain (no caps).
        let themed = renderToBuffer(
            VStack { Button("X") {} }.theme(theme), context: makeRenderContext()
        ).lines.joined().stripped
        #expect(!themed.contains("▐") && !themed.contains("▌"), "theme buttonStyle should make it plain")
    }
}

@MainActor
@Suite("Tint")
struct TintTests {

    @Test("tint recolours a control's accent affordance")
    func tintButtonAccent() {
        let view = Button("Save") {}.buttonStyle(.primary).tint(.rgb(7, 8, 9))
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("tint cascades from a container to a toggle's ON mark")
    func tintCascadesToToggle() {
        let view = VStack { Toggle("Wi-Fi", isOn: .constant(true)) }.tint(.rgb(7, 8, 9))
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A semantic tint (.palette.success) resolves and doesn't trap the renderer")
    func semanticTintResolves() {
        // Regression: a `.semantic` tint reached the ANSI renderer unresolved and
        // trapped (fatalError). TintedPalette now resolves the tint against its base.
        let context = makeRenderContext()
        let view = Button("Save") {}.buttonStyle(.primary).tint(.palette.success)
        let buffer = renderToBuffer(view, context: context)
        #expect(!buffer.isEmpty)
        // It resolves to the palette's concrete success colour.
        if let (r, g, b) = Color.palette.success.resolve(with: context.environment.palette).rgbComponents {
            #expect(buffer.lines.joined().contains("38;2;\(r);\(g);\(b)"))
        }
    }

    @Test("A nested tint overrides an outer one")
    func nestedTintWins() {
        let view = VStack {
            VStack { Toggle("Inner", isOn: .constant(true)) }.tint(.rgb(7, 8, 9))
        }
        .tint(.rgb(1, 2, 3))
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))      // inner tint
    }
}

@MainActor
@Suite("Cascading disabled")
struct CascadingDisabledTests {

    @Test("A container .disabled() disables a control like its own .disabled()")
    func containerDisablesControl() {
        let viaContainer = VStack { Button("Save") {} }.disabled()
        let viaInstance = VStack { Button("Save") {}.disabled() }
        let a = renderToBuffer(viaContainer, context: makeRenderContext()).lines
        let b = renderToBuffer(viaInstance, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("Disabled is additive — a descendant cannot re-enable")
    func disabledIsAdditive() {
        // Inner .disabled(false) must NOT re-enable inside a disabled container.
        let reEnabled = VStack { Button("Save") {}.disabled(false) }.disabled(true)
        let plainDisabled = VStack { Button("Save") {} }.disabled(true)
        let a = renderToBuffer(reEnabled, context: makeRenderContext()).lines
        let b = renderToBuffer(plainDisabled, context: makeRenderContext()).lines
        #expect(a == b)
    }

    @Test("An enabled control renders differently from a disabled one")
    func enabledDiffersFromDisabled() {
        let enabled = renderToBuffer(VStack { Button("Save") {} }, context: makeRenderContext()).lines
        let disabled = renderToBuffer(VStack { Button("Save") {} }.disabled(), context: makeRenderContext()).lines
        #expect(enabled != disabled)
    }
}

@MainActor
@Suite("Slider style cascade")
struct SliderStyleCascadeTests {

    @Test(".sliderTextStyle colours the value read-out")
    func sliderValueForeground() {
        let view = Slider(value: .constant(0.5)).sliderTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }
}

@MainActor
@Suite("Picker style cascade")
struct PickerStyleCascadeTests {

    @Test(".pickerTextStyle colours the picker's option text")
    func pickerOptionForeground() {
        let view = Picker("Theme", selection: .constant(1)) {
            Text("One").tag(1)
            Text("Two").tag(2)
        }
        .pickerStyle(.radioGroup)
        .pickerTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }
}

@MainActor
@Suite("Stepper style cascade")
struct StepperStyleCascadeTests {

    @Test(".stepperTextStyle colours the value read-out")
    func stepperValueForeground() {
        let view = Stepper("Quantity", value: .constant(5))
            .stepperTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }
}

@MainActor
@Suite("TextField style cascade")
struct TextFieldStyleCascadeTests {

    @Test(".textFieldTextStyle colours the entered text")
    func textFieldForeground() {
        let view = TextField("Name", text: .constant("hello"))
            .textFieldTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A semantic .textFieldTextStyle foreground resolves instead of trapping")
    func textFieldSemanticForegroundResolves() {
        // Regression: `.textFieldTextStyle { $0.foreground = .palette.accent }`
        // put a *semantic* colour in the cascade, which the field handed to
        // ANSIRenderer unresolved — and ANSIRenderer traps on `.semantic`. (This
        // is what crashed TUIkitExample's Text Fields page.) The semantic accent
        // must resolve to a concrete RGB. Non-empty text guarantees the entered-
        // text path runs rather than the dim-prompt branch.
        let view = TextField("Name", text: .constant("Ada"))
            .textFieldTextStyle { $0.foreground = .palette.accent }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        // Reaching this line at all proves it didn't trap; a concrete foreground
        // SGR (38;2;r;g;b) proves the semantic accent was resolved, not raw.
        #expect(line.contains("38;2;"))
    }
}

@MainActor
@Suite("List/Table row style cascade")
struct ListRowStyleCascadeTests {

    // List/Table row content is ordinary Text. Its colour is styleable both
    // per-row (on the row's own Text) and broadly (`.foregroundStyle` reaches
    // rows). NOTE: container-level *attribute* cascade (e.g. `.bold()` on the
    // List itself) does not yet reach row text — the lazy row-buffer path does
    // not re-key on the style cascade. Tracked as a follow-up in
    // Documentation/Styling-and-theming-design.md. Per-row attributes and broad
    // foreground (below) are the supported styling for rows today.

    @Test("Broad .foregroundStyle reaches List row text")
    func listRowForeground() {
        let view = List {
            ForEach(["Alpha"], id: \.self) { Text($0) }
        }
        .foregroundStyle(.rgb(7, 8, 9))
        let line = renderToBuffer(view, context: makeRenderContext(width: 30, height: 8)).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A row's own Text styling renders in the List")
    func perRowStyling() {
        let view = List {
            ForEach(["Alpha"], id: \.self) { Text($0).foregroundStyle(.rgb(7, 8, 9)) }
        }
        let line = renderToBuffer(view, context: makeRenderContext(width: 30, height: 8)).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }
}

@MainActor
@Suite("RadioButton style cascade")
struct RadioButtonStyleCascadeTests {

    @Test(".radioButtonTextStyle colours the radio labels")
    func radioForeground() {
        let view = RadioButtonGroup(selection: .constant("a")) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Beta")
        }
        .radioButtonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A picker's radio options keep the .picker identity, not .radioButton")
    func pickerRadioKeepsPickerIdentity() {
        // .radioButtonTextStyle must NOT reach a picker's radio-group options —
        // RadioButton claims `.radioButton` only when not already inside a control.
        let view = Picker("X", selection: .constant(1)) {
            Text("One").tag(1)
            Text("Two").tag(2)
        }
        .pickerStyle(.radioGroup)
        .radioButtonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(!line.contains("38;2;7;8;9"))
    }
}
