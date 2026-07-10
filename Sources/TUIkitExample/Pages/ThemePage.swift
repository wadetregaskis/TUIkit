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
            get: { styling.checkboxStyle == .ascii ? "ASCII" : "Unicode" },
            set: { name in styling.checkboxStyle = (name == "ASCII") ? .ascii : .unicode }
        )
        let languageSelection = Binding(
            get: { LocalizationService.shared.currentLanguage.rawValue },
            set: { code in
                if let language = LocalizationService.Language(rawValue: code) {
                    LocalizationService.shared.setLanguage(language)
                }
            }
        )
        // Drives the modal colour editor: true while a colour is open for editing.
        let editingBinding = Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 1) {

                DemoSection(L("page.theme.language")) {
                    Picker(L("page.theme.languageLabel"), selection: languageSelection) {
                        ForEach(LocalizationService.Language.allCases, id: \.rawValue) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection(L("page.theme.presetPalette")) {
                    Picker(L("page.theme.presetLabel"), selection: presetSelection) {
                        ForEach(0..<PaletteRegistry.all.count, id: \.self) { index in
                            Text(PaletteRegistry.all[index].name).tag(PaletteRegistry.all[index].id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection(L("page.theme.borderAppearance")) {
                    Picker(L("page.theme.appearanceLabel"), selection: appearanceSelection) {
                        ForEach(0..<appearances.count, id: \.self) { index in
                            Text(appearances[index].name).tag(appearances[index].id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection(L("page.theme.customBorder")) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("page.theme.customBorderDescription"))
                            .foregroundStyle(.palette.foregroundSecondary)

                        HStack(spacing: 1) {
                            Button(L("page.theme.borderRounded")) { applyBorderPreset("╭", "╮", "╰", "╯", "─", "│") }
                            Button("ASCII") { applyBorderPreset("+", "+", "+", "+", "-", "|") }
                            Button(L("page.theme.borderStars")) { applyBorderPreset("*", "*", "*", "*", "*", "*") }
                            Button(L("page.theme.borderBlocks")) { applyBorderPreset("█", "█", "█", "█", "█", "█") }
                            Button(L("page.theme.borderDots")) { applyBorderPreset("·", "·", "·", "·", "·", "·") }
                        }

                        HStack(spacing: 2) {
                            borderCharField("┌", $borderTL)
                            borderCharField("┐", $borderTR)
                            borderCharField("└", $borderBL)
                            borderCharField("┘", $borderBR)
                            borderCharField("─", $borderH)
                            borderCharField("│", $borderV)
                        }

                        Button(L("page.theme.useBuiltInAppearance")) { styling.customBorder = nil }

                        Panel(L("page.theme.livePreviewPanel")) {
                            Text(L("page.theme.boxUsesAppWideBorder"))
                        }
                    }
                    .onChange(of: [borderTL, borderTR, borderBL, borderBR, borderH, borderV]) {
                        // Any edit to a field activates and applies the custom
                        // border live, so typing immediately updates the preview.
                        // "Use built-in appearance" reverts to the built-in border.
                        styling.customBorder = currentBorderStyle()
                    }
                }

                DemoSection(L("page.theme.liveStyling")) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("page.theme.liveStylingDescription"))
                        .foregroundStyle(.palette.foregroundSecondary)

                        Picker(L("page.theme.tintLabel"), selection: tintSelection) {
                            ForEach(0..<Self.tintOptions.count, id: \.self) { index in
                                Text(Self.tintOptions[index].name).tag(Self.tintOptions[index].name)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Toggle(
                            L("page.theme.uppercaseSectionHeaders"),
                            isOn: Binding(
                                get: { styling.uppercaseSectionHeaders },
                                set: { styling.uppercaseSectionHeaders = $0 }))
                        Toggle(
                            L("page.theme.boldButtonText"),
                            isOn: Binding(
                                get: { styling.boldButtons },
                                set: { styling.boldButtons = $0 }))

                        Picker(L("page.theme.checkboxesLabel"), selection: checkboxSelection) {
                            Text("Unicode ⬛").tag("Unicode")
                            Text("ASCII [x]").tag("ASCII")
                        }
                        .pickerStyle(.radioGroup)
                    }
                }

                DemoSection(L("page.theme.semanticColours")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<Self.semanticColors.count, id: \.self) { index in
                            swatchRow(
                                Self.semanticColors[index].name,
                                palette[keyPath: Self.semanticColors[index].keyPath])
                        }
                    }
                }

                DemoSection(L("page.theme.customiseCompact")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<Self.editableColors.count, id: \.self) { index in
                            ColorPicker(
                                Self.editableColors[index].name,
                                selection: colorBinding(Self.editableColors[index].keyPath))
                        }
                    }
                }

                DemoSection(L("page.theme.fullColourEditor")) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L("page.theme.fullColourEditorDescription"))
                            .foregroundStyle(.palette.foregroundSecondary)
                        ForEach(0..<Self.editableColors.count, id: \.self) { index in
                            editorRow(index)
                        }
                    }
                }

                DemoSection(L("page.theme.livePreview")) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            Text("Accent").foregroundStyle(.palette.accent)
                            Text("Success").foregroundStyle(.palette.success)
                            Text("Warning").foregroundStyle(.palette.warning)
                            Text("Error").foregroundStyle(.palette.error)
                            Text("Info").foregroundStyle(.palette.info)
                        }
                        Panel(L("page.theme.samplePanel")) {
                            Text(L("page.theme.bodyText"))
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                    }
                }

                KeyboardHelpSection(
                    L("page.theme.themeHelp"),
                    shortcuts: [
                        L("page.theme.help.choosePreset"),
                        L("page.theme.help.moveFocus"),
                        L("page.theme.help.cyclePalette"),
                        L("page.theme.help.everyChange"),
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
            DemoAppHeader(L("page.theme.title"))
        }
    }

    /// A row in the full-editor section: a live swatch, the colour's name, and a
    /// button that opens the modal ``ColorPickerPanel`` for that colour.
    @ViewBuilder
    private func editorRow(_ index: Int) -> some View {
        let entry = Self.editableColors[index]
        HStack(spacing: 1) {
            Text("███").foregroundStyle(palette[keyPath: entry.keyPath])
            Button("\(L("page.theme.edit")) \(entry.name)…") { editing = index }
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
