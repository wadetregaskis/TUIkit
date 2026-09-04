//  🖥️ TUIkit — Terminal UI Kit for Swift
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

/// A palette that STATES every ``Palette`` role, each a distinct colour.
///
/// Every role, because the defaults in `Palette`'s extension are *collapsing*
/// — `foregroundSecondary` falls back to `foreground`, `cursorColor` to
/// `accent`, `fieldBackground` to a step off `background` — so a palette that
/// leaves a role unstated cannot tell "delegated to the base" apart from
/// "recomputed from the base's other roles", which is exactly the bug this
/// palette exists to catch.
///
/// Distinct, for the same reason at a smaller scale: two roles sharing a
/// colour make a forwarding mistake *between those two* invisible. The suite
/// asserts the distinctness rather than trusting this list.
private struct EveryRolePalette: Palette {
    let id = "every-role"
    let name = "Every role"

    let background = Color.rgb(1, 1, 1)
    let statusBarBackground = Color.rgb(2, 2, 2)
    let appHeaderBackground = Color.rgb(3, 3, 3)
    let overlayBackground = Color.rgb(4, 4, 4)
    let foreground = Color.rgb(5, 5, 5)
    let foregroundSecondary = Color.rgb(6, 6, 6)
    let foregroundTertiary = Color.rgb(7, 7, 7)
    let foregroundQuaternary = Color.rgb(8, 8, 8)
    let accent = Color.rgb(9, 9, 9)
    let success = Color.rgb(10, 10, 10)
    let warning = Color.rgb(11, 11, 11)
    let error = Color.rgb(12, 12, 12)
    let info = Color.rgb(13, 13, 13)
    let border = Color.rgb(14, 14, 14)
    let focusBackground = Color.rgb(15, 15, 15)
    let cursorColor = Color.rgb(16, 16, 16)
    let fieldBackground = Color.rgb(17, 17, 17)
}

/// Every colour role, read through the existential so the same entry can be
/// applied to a base palette and to the `TintedPalette` wrapping it.
///
/// Closures rather than key paths because `\(any Palette).background` is not a
/// key path Swift will form — the roles live on a protocol, and the two sides
/// of every comparison below are different concrete types.
private let paletteRoles: [(name: String, read: @Sendable (any Palette) -> Color)] = [
    ("background", { $0.background }),
    ("statusBarBackground", { $0.statusBarBackground }),
    ("appHeaderBackground", { $0.appHeaderBackground }),
    ("overlayBackground", { $0.overlayBackground }),
    ("foreground", { $0.foreground }),
    ("foregroundSecondary", { $0.foregroundSecondary }),
    ("foregroundTertiary", { $0.foregroundTertiary }),
    ("foregroundQuaternary", { $0.foregroundQuaternary }),
    ("accent", { $0.accent }),
    ("success", { $0.success }),
    ("warning", { $0.warning }),
    ("error", { $0.error }),
    ("info", { $0.info }),
    ("border", { $0.border }),
    ("focusBackground", { $0.focusBackground }),
    ("cursorColor", { $0.cursorColor }),
    ("fieldBackground", { $0.fieldBackground }),
]

@MainActor
@Suite("Style cascade — additional coverage")
struct StyleCascadeCoverageTests {

    private func context(width: Int = 40, height: Int = 8) -> RenderContext {
        makeBareRenderContext(width: width, height: height)
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

    @Test("The role table lists exactly the roles a palette states")
    func roleTableIsComplete() {
        // The forcing function under the test below, which can only check the
        // roles it is given: a new `Palette` requirement is stated on
        // `EveryRolePalette` (that is what the type is FOR), Mirror sees the
        // new stored property, and this fails until the table grows to match.
        // Without it, adding a role silently leaves it untested — which is how
        // `fieldBackground` went unforwarded.
        let stated = Set(
            Mirror(reflecting: EveryRolePalette()).children
                .compactMap(\.label)
                .filter { $0 != "id" && $0 != "name" })
        #expect(Set(paletteRoles.map(\.name)) == stated)
    }

    @Test("TintedPalette overrides only accent; EVERY other role delegates to base")
    func tintedPaletteDelegates() {
        let base = EveryRolePalette()
        let tint = Color.rgb(200, 100, 50)
        let tinted = TintedPalette(base: base, tint: tint)

        // Or a forwarding mistake BETWEEN two roles reads as a pass.
        #expect(
            Set(paletteRoles.map { $0.read(base) }).count == paletteRoles.count,
            "the base palette's roles must all differ")
        #expect(tint != base.accent, "the tint must differ from the base's accent")

        for role in paletteRoles where role.name != "accent" {
            #expect(
                role.read(tinted) == role.read(base),
                "\(role.name) did not delegate: \(role.read(tinted)) vs \(role.read(base))")
        }
        #expect(tinted.accent == tint.resolve(with: base))
        #expect(tinted.id == base.id)
        #expect(tinted.name == base.name)
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

    @Test("A semantic .secureFieldTextStyle foreground resolves instead of trapping")
    func secureFieldSemanticForegroundResolves() {
        // SecureField shares TextFieldContentRenderer, so the same semantic-
        // colour trap applied (see the TextField regression test).
        let view = SecureField("Password", text: .constant("hunter2"))
            .secureFieldTextStyle { $0.foreground = .palette.accent }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;"))
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
