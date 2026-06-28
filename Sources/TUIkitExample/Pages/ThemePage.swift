//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ThemePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Theme demo page — switch presets, change the border appearance, inspect the
/// **full set** of semantic colours, and build a **custom theme** by editing
/// them with the compact inline `ColorPicker` or the full modal
/// `ColorPickerPanel` (RGB / HSL / HSB / CMYK tabs, the palette's semantic
/// roles, and the 256-colour grid).
///
/// Everything here is **global and live**: the page edits `ExampleApp`'s
/// app-wide `palette` (`@Binding`), which drives the scene's `.palette(...)`, so
/// a preset selection or a single channel tweak instantly re-themes every page,
/// the app header, and the status bar. Border appearance is the other app-wide
/// axis, cycled through the shared `appearanceManager`.
struct ThemePage: View {
    @Binding var palette: CustomizablePalette
    @Binding var styling: ExampleStyling
    @Environment(\.appearanceManager) private var appearanceManager

    /// Index into ``editableColors`` currently open in the full modal colour
    /// editor (``ColorPickerPanel``), or `nil` when it is dismissed.
    @State private var editing: Int?

    /// The six editable characters of the custom border (single chars, typeable
    /// in ASCII; box-drawing glyphs come from the preset buttons). Default to an
    /// ASCII set so the fields start usable.
    @State private var borderTL = "+"
    @State private var borderTR = "+"
    @State private var borderBL = "+"
    @State private var borderBR = "+"
    @State private var borderH = "-"
    @State private var borderV = "|"

    /// Tint options offered in the live-styling section (name + colour).
    private static let tintOptions: [(name: String, color: Color?)] = [
        ("None", nil),
        ("Success", .palette.success),
        ("Warning", .palette.warning),
        ("Error", .palette.error),
        ("Info", .palette.info),
    ]

    /// The semantic colours, paired with editable key paths, for display + editing.
    private static let semanticColors: [(name: String, keyPath: WritableKeyPath<CustomizablePalette, Color>)] = [
        ("background", \.background),
        ("statusBarBackground", \.statusBarBackground),
        ("appHeaderBackground", \.appHeaderBackground),
        ("overlayBackground", \.overlayBackground),
        ("foreground", \.foreground),
        ("foregroundSecondary", \.foregroundSecondary),
        ("foregroundTertiary", \.foregroundTertiary),
        ("foregroundQuaternary", \.foregroundQuaternary),
        ("accent", \.accent),
        ("success", \.success),
        ("warning", \.warning),
        ("error", \.error),
        ("info", \.info),
        ("border", \.border),
        ("focusBackground", \.focusBackground),
        ("cursorColor", \.cursorColor),
    ]

    /// The subset offered for editing (the most visually impactful colours).
    private static let editableColors: [(name: String, keyPath: WritableKeyPath<CustomizablePalette, Color>)] = [
        ("Accent", \.accent),
        ("Foreground", \.foreground),
        ("Background", \.background),
        ("Success", \.success),
        ("Warning", \.warning),
        ("Error", \.error),
        ("Info", \.info),
        ("Border", \.border),
    ]

    var body: some View {
        let appearances = AppearanceRegistry.all
        let presetSelection = Binding(
            get: { palette.id },
            set: { id in
                if let preset = PaletteRegistry.all.first(where: { $0.id == id }) {
                    palette = CustomizablePalette(from: preset)
                }
            }
        )
        let appearanceSelection = Binding(
            get: { appearanceManager.current.id },
            set: { id in
                if let appearance = appearances.first(where: { $0.id == id }) {
                    appearanceManager.setCurrent(appearance)
                    // Picking a built-in border deactivates any custom one.
                    styling.customBorder = nil
                }
            }
        )
        let tintSelection = Binding(
            get: { Self.tintOptions.first { $0.color == styling.tint }?.name ?? "None" },
            set: { name in styling.tint = Self.tintOptions.first { $0.name == name }?.color }
        )
        let checkboxSelection = Binding(
            get: { styling.checkboxStyle == .ascii ? "ASCII" : "Squares" },
            set: { name in styling.checkboxStyle = (name == "ASCII") ? .ascii : .squares }
        )
        // Drives the modal colour editor: true while a colour is open for editing.
        let editingBinding = Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 1) {

                DemoSection("Preset Palette") {
                    Picker("Preset", selection: presetSelection) {
                        ForEach(0..<PaletteRegistry.all.count, id: \.self) { index in
                            Text(PaletteRegistry.all[index].name).tag(PaletteRegistry.all[index].id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection("Border Appearance") {
                    Picker("Appearance", selection: appearanceSelection) {
                        ForEach(0..<appearances.count, id: \.self) { index in
                            Text(appearances[index].name).tag(appearances[index].id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection("Custom border characters — applies app-wide") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Build a border from any characters — type ASCII into the "
                            + "fields, or pick a preset for box-drawing glyphs. It overrides "
                            + "the appearance above across the whole app.")
                            .foregroundStyle(.palette.foregroundSecondary)

                        HStack(spacing: 1) {
                            Button("Rounded") { applyBorderPreset("╭", "╮", "╰", "╯", "─", "│") }
                            Button("ASCII") { applyBorderPreset("+", "+", "+", "+", "-", "|") }
                            Button("Stars") { applyBorderPreset("*", "*", "*", "*", "*", "*") }
                            Button("Blocks") { applyBorderPreset("█", "█", "█", "█", "█", "█") }
                            Button("Dots") { applyBorderPreset("·", "·", "·", "·", "·", "·") }
                        }

                        HStack(spacing: 2) {
                            borderCharField("┌", $borderTL)
                            borderCharField("┐", $borderTR)
                            borderCharField("└", $borderBL)
                            borderCharField("┘", $borderBR)
                            borderCharField("─", $borderH)
                            borderCharField("│", $borderV)
                        }

                        Button("Use built-in appearance") { styling.customBorder = nil }

                        Panel("Live preview") {
                            Text("This box uses the app-wide border.")
                        }
                    }
                    .onChange(of: [borderTL, borderTR, borderBL, borderBR, borderH, borderV]) {
                        // Live-update only while a custom border is active, so typing
                        // here doesn't hijack a built-in appearance selection.
                        if styling.customBorder != nil {
                            styling.customBorder = currentBorderStyle()
                        }
                    }
                }

                DemoSection("Live styling — applies to every page") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(
                            "These use the styling cascade: tint overrides the "
                                + "accent app-wide; the toggles add a chrome and a "
                                + "control-scoped text style across all pages."
                        )
                        .foregroundStyle(.palette.foregroundSecondary)

                        Picker("Tint", selection: tintSelection) {
                            ForEach(0..<Self.tintOptions.count, id: \.self) { index in
                                Text(Self.tintOptions[index].name).tag(Self.tintOptions[index].name)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Toggle(
                            "UPPERCASE section headers",
                            isOn: Binding(
                                get: { styling.uppercaseSectionHeaders },
                                set: { styling.uppercaseSectionHeaders = $0 }))
                        Toggle(
                            "Bold button text",
                            isOn: Binding(
                                get: { styling.boldButtons },
                                set: { styling.boldButtons = $0 }))

                        Picker("Checkboxes", selection: checkboxSelection) {
                            Text("Squares ⬛").tag("Squares")
                            Text("ASCII [x]").tag("ASCII")
                        }
                        .pickerStyle(.radioGroup)
                    }
                }

                DemoSection("Semantic Colours — full set") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<Self.semanticColors.count, id: \.self) { index in
                            swatchRow(
                                Self.semanticColors[index].name,
                                palette[keyPath: Self.semanticColors[index].keyPath])
                        }
                    }
                }

                DemoSection("Customise (compact inline editor)") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<Self.editableColors.count, id: \.self) { index in
                            ColorPicker(
                                Self.editableColors[index].name,
                                selection: colorBinding(Self.editableColors[index].keyPath))
                        }
                    }
                }

                DemoSection("Full colour editor (RGB · HSL · HSB · CMYK · semantic · 256)") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Open the modal editor for any colour — tabs for every colour model, the palette's semantic roles, and the 256-colour grid.")
                            .foregroundStyle(.palette.foregroundSecondary)
                        ForEach(0..<Self.editableColors.count, id: \.self) { index in
                            editorRow(index)
                        }
                    }
                }

                DemoSection("Live Preview") {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            Text("Accent").foregroundStyle(.palette.accent)
                            Text("Success").foregroundStyle(.palette.success)
                            Text("Warning").foregroundStyle(.palette.warning)
                            Text("Error").foregroundStyle(.palette.error)
                            Text("Info").foregroundStyle(.palette.info)
                        }
                        Panel("Sample Panel") {
                            Text("Body text in the secondary foreground colour.")
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                    }
                }

                KeyboardHelpSection(
                    "Theme",
                    shortcuts: [
                        "Choose a preset, or edit the colours below to make a custom theme",
                        "[Tab] / [↑↓] move focus; [←→] adjust the focused colour channel",
                        "[F2] / [F3] cycle palette / appearance from any page",
                        "Every change here re-themes the whole app instantly",
                    ]
                )
            }
        }
        .modal(isPresented: editingBinding) {
            if let index = editing {
                ColorPickerPanel(
                    Self.editableColors[index].name,
                    selection: colorBinding(Self.editableColors[index].keyPath),
                    isPresented: editingBinding)
            }
        }
        .appHeader {
            DemoAppHeader("Theme Demo")
        }
    }

    /// A row in the full-editor section: a live swatch, the colour's name, and a
    /// button that opens the modal ``ColorPickerPanel`` for that colour.
    @ViewBuilder
    private func editorRow(_ index: Int) -> some View {
        let entry = Self.editableColors[index]
        HStack(spacing: 1) {
            Text("███").foregroundStyle(palette[keyPath: entry.keyPath])
            Button("Edit \(entry.name)…") { editing = index }
        }
    }

    /// A read-only swatch row: a colour block, the semantic name, and its RGB
    /// (so dark colours that blend into the background are still identifiable).
    @ViewBuilder
    private func swatchRow(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 1) {
            Text("███").foregroundStyle(color)
            Text(name).frame(width: 22, alignment: .leading)
                .foregroundStyle(.palette.foreground)
            Text(rgbText(color)).foregroundStyle(.palette.foregroundTertiary)
        }
    }

    private func rgbText(_ color: Color) -> String {
        guard let c = color.rgbComponents else { return "—" }
        return "rgb(\(c.red), \(c.green), \(c.blue))"
    }

    /// A `Color` binding onto one stored colour of the app palette. Writing
    /// through it mutates `ExampleApp`'s `@State`, re-theming the whole app.
    private func colorBinding(_ keyPath: WritableKeyPath<CustomizablePalette, Color>) -> Binding<Color> {
        Binding(
            get: { palette[keyPath: keyPath] },
            set: { palette[keyPath: keyPath] = $0 }
        )
    }

    /// Applies a preset custom border: fills the editable fields and activates it
    /// app-wide (overriding the built-in appearance).
    private func applyBorderPreset(
        _ tl: Character, _ tr: Character, _ bl: Character,
        _ br: Character, _ h: Character, _ v: Character
    ) {
        borderTL = String(tl); borderTR = String(tr)
        borderBL = String(bl); borderBR = String(br)
        borderH = String(h); borderV = String(v)
        styling.customBorder = BorderStyle(
            topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br,
            horizontal: h, vertical: v)
    }

    /// Builds a ``BorderStyle`` from the current editable characters (each field's
    /// first character, with an ASCII fallback for an empty field).
    private func currentBorderStyle() -> BorderStyle {
        func first(_ string: String, else fallback: Character) -> Character {
            string.first ?? fallback
        }
        return BorderStyle(
            topLeft: first(borderTL, else: "+"),
            topRight: first(borderTR, else: "+"),
            bottomLeft: first(borderBL, else: "+"),
            bottomRight: first(borderBR, else: "+"),
            horizontal: first(borderH, else: "-"),
            vertical: first(borderV, else: "|"))
    }

    /// A labelled single-character field (clamped to one character) for one
    /// border glyph.
    @ViewBuilder
    private func borderCharField(_ label: String, _ text: Binding<String>) -> some View {
        let clamped = Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = String($0.suffix(1)) })
        VStack(spacing: 0) {
            Text(label).foregroundStyle(.palette.foregroundTertiary)
            TextField("", text: clamped).frame(width: 3)
        }
    }
}
