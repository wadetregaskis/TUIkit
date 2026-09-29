//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Theme demo page — switch presets, change the border appearance, and build a
/// **custom theme** by editing the palette's colours: **every** one of them,
/// one row each, with the inline `ColorPicker` channels at the end of the row
/// and the full modal `ColorPickerPanel` (RGB / HSL / HSB / CMYK tabs, the
/// palette's semantic roles, and the 256-colour grid) a click or `Return` away
/// on the row's swatch.
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

    /// The six editable characters of the custom border (single chars, typeable
    /// in ASCII; box-drawing glyphs come from the preset buttons). Default to an
    /// ASCII set so the fields start usable.
    /// The selected row of the live preview's list.
    @State private var sampleSelection: Int? = 2
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

    /// Every colour a ``Palette`` defines, paired with its editable key path —
    /// named exactly as the protocol names them, because this page is also
    /// where you look up which colour is which.
    private static let themeColors: [(name: String, keyPath: WritableKeyPath<CustomizablePalette, Color>)] = [
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

    /// The label column, sized to the longest name so the swatches and channel
    /// sliders line up down the whole section (the names are ASCII, so
    /// characters are cells).
    private static let colorLabelWidth = themeColors.map { $0.name.count }.max() ?? 18

    /// The chrome styles offered by the picker, with their display names.
    private static var chromeNames: [(name: String, style: ChromeStyle)] {
        [
            (L("page.theme.chrome.rule"), .rule),
            (L("page.theme.chrome.bordered"), .bordered),
            (L("page.theme.chrome.compact"), .compact),
        ]
    }

    /// A picker binding for ONE bar's style — the
    /// `chromeStyle(appHeader:statusBar:)` half of the API.
    private func chromeBinding(
        _ keyPath: WritableKeyPath<ExampleStyling, ChromeStyle>
    ) -> Binding<String> {
        Binding(
            get: { Self.chromeNames.first { $0.style == styling[keyPath: keyPath] }?.name ?? "" },
            set: { name in
                if let style = Self.chromeNames.first(where: { $0.name == name })?.style {
                    styling[keyPath: keyPath] = style
                }
            }
        )
    }

    /// The same text as the literal above, but reaching `Text` as a *value*, so
    /// the `StringProtocol` overload takes it and no lookup happens.
    private var savedKeyAsVariable: String { "button.save" }

    /// One row of the key demo: the source spelling on the left (verbatim, or
    /// the snippet itself would be looked up), what it renders on the right.
    @ViewBuilder private func keyDemoRow<V: View>(
        _ spelling: String, @ViewBuilder result: () -> V
    ) -> some View {
        HStack(spacing: 2) {
            Text(verbatim: spelling)
                .foregroundStyle(.palette.foregroundSecondary)
                .frame(width: 30)
            result()
        }
    }

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
            get: { appearanceManager?.current.id ?? "" },
            set: { id in
                if let appearance = appearances.first(where: { $0.id == id }) {
                    appearanceManager?.setCurrent(appearance)
                    // Picking a built-in border deactivates any custom one.
                    styling.customBorder = nil
                }
            }
        )
        let chromeNames = Self.chromeNames
        // A binding that moves BOTH bars, mirroring `Scene.chromeStyle(_:)`;
        // `chromeBinding(_:)` below is the per-bar counterpart. Reads back as ""
        // (nothing selected) while the two differ, which is honest: no single
        // style is in force.
        let bothChromeSelection = Binding(
            get: {
                styling.appHeaderStyle == styling.statusBarStyle
                    ? chromeNames.first { $0.style == styling.appHeaderStyle }?.name ?? ""
                    : ""
            },
            set: { name in
                if let style = chromeNames.first(where: { $0.name == name })?.style {
                    styling.appHeaderStyle = style
                    styling.statusBarStyle = style
                }
            }
        )
        let tintSelection = Binding(
            get: { Self.tintOptions.first { $0.color == styling.tint }?.name ?? "None" },
            set: { name in styling.tint = Self.tintOptions.first { $0.name == name }?.color }
        )
        let checkboxSelection = Binding(
            get: {
                // `.automatic` first: it carries the same marks as `.unicode` and
                // is distinguished only by meaning "ask the terminal", so a
                // `.unicode` case ahead of it would swallow it and mislabel the
                // app's actual default.
                switch styling.toggleCharacterSet {
                case .automatic: "Automatic"
                case .ascii: "ASCII"
                case .emoji: "Emoji"
                default: "Unicode"
                }
            },
            set: { name in
                switch name {
                case "Automatic": styling.toggleCharacterSet = .automatic
                case "ASCII": styling.toggleCharacterSet = .ascii
                case "Emoji": styling.toggleCharacterSet = .emoji
                default: styling.toggleCharacterSet = .unicode
                }
            }
        )
        let languageSelection = Binding(
            get: { LocalizationService.shared.currentLanguage.rawValue },
            set: { code in
                if let language = LocalizationService.Language(rawValue: code) {
                    LocalizationService.shared.setLanguage(language)
                }
            }
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {

                DemoSection("page.theme.language") {
                    Picker("page.theme.languageLabel", selection: languageSelection) {
                        ForEach(LocalizationService.Language.allCases, id: \.rawValue) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.theme.keyDemoExplain")
                            .foregroundStyle(.palette.foregroundSecondary)
                        // Four spellings of one string, and only two of them
                        // move. The first three are the SAME source text,
                        // distinguished by whether it is a literal and, when it
                        // is not, whether it was asked to be a key. Switch
                        // language above and watch.
                        keyDemoRow("Text(\"button.save\")") { Text("button.save") }
                        keyDemoRow("Text(key)") { Text(savedKeyAsVariable) }
                        keyDemoRow("Text(LocalizedStringKey(key))") {
                            Text(LocalizedStringKey(savedKeyAsVariable))
                        }
                        keyDemoRow("Text(verbatim:)") { Text(verbatim: "button.save") }
                    }
                    .border(.palette.border)
                }

                DemoSection("page.theme.presetPalette") {
                    Picker("page.theme.presetLabel", selection: presetSelection) {
                        ForEach(0..<PaletteRegistry.all.count, id: \.self) { index in
                            Text(PaletteRegistry.all[index].name).tag(PaletteRegistry.all[index].id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection("page.theme.borderAppearance") {
                    Picker("page.theme.appearanceLabel", selection: appearanceSelection) {
                        ForEach(0..<appearances.count, id: \.self) { index in
                            // `localizedName`, not `name`: the latter is the
                            // identifier capitalised, which is right for a
                            // `Cyclable`'s identity and wrong on a settings
                            // screen — it read "Rounded" in every language.
                            Text(appearances[index].localizedName)
                                .tag(appearances[index].id)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                DemoSection("page.theme.chromeStyle") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("page.theme.chromeStyleDescription")
                            .foregroundStyle(.palette.foregroundSecondary)

                        Picker("page.theme.chrome.bothLabel", selection: bothChromeSelection) {
                            ForEach(chromeNames, id: \.name) { entry in
                                Text(entry.name).tag(entry.name)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text("page.theme.chrome.separately")
                            .foregroundStyle(.palette.foregroundSecondary)
                        HStack(spacing: 3) {
                            Picker(
                                "page.theme.chrome.headerLabel",
                                selection: chromeBinding(\.appHeaderStyle)
                            ) {
                                ForEach(chromeNames, id: \.name) { entry in
                                    Text(entry.name).tag(entry.name)
                                }
                            }
                            Picker(
                                "page.theme.chrome.footerLabel",
                                selection: chromeBinding(\.statusBarStyle)
                            ) {
                                ForEach(chromeNames, id: \.name) { entry in
                                    Text(entry.name).tag(entry.name)
                                }
                            }
                        }
                    }
                }

                DemoSection("page.theme.customBorder") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("page.theme.customBorderDescription")
                            .foregroundStyle(.palette.foregroundSecondary)

                        HStack(spacing: 1) {
                            Button("page.theme.borderRounded") { applyBorderPreset("╭", "╮", "╰", "╯", "─", "│") }
                            Button("ASCII") { applyBorderPreset("+", "+", "+", "+", "-", "|") }
                            Button("page.theme.borderStars") { applyBorderPreset("*", "*", "*", "*", "*", "*") }
                            Button("page.theme.borderBlocks") { applyBorderPreset("█", "█", "█", "█", "█", "█") }
                            Button("page.theme.borderDots") { applyBorderPreset("·", "·", "·", "·", "·", "·") }
                        }

                        HStack(spacing: 2) {
                            borderCharField("┌", $borderTL)
                            borderCharField("┐", $borderTR)
                            borderCharField("└", $borderBL)
                            borderCharField("┘", $borderBR)
                            borderCharField("─", $borderH)
                            borderCharField("│", $borderV)
                        }

                        Button("page.theme.useBuiltInAppearance") { styling.customBorder = nil }

                        Panel("page.theme.livePreviewPanel") {
                            Text("page.theme.boxUsesAppWideBorder")
                        }
                    }
                    .onChange(of: [borderTL, borderTR, borderBL, borderBR, borderH, borderV]) {
                        // Any edit to a field activates and applies the custom
                        // border live, so typing immediately updates the preview.
                        // "Use built-in appearance" reverts to the built-in border.
                        styling.customBorder = currentBorderStyle()
                    }
                }

                DemoSection("page.theme.liveStyling") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("page.theme.liveStylingDescription")
                        .foregroundStyle(.palette.foregroundSecondary)

                        Picker("page.theme.tintLabel", selection: tintSelection) {
                            ForEach(0..<Self.tintOptions.count, id: \.self) { index in
                                Text(Self.tintOptions[index].name).tag(Self.tintOptions[index].name)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Toggle(
                            "page.theme.uppercaseSectionHeaders",
                            isOn: Binding(
                                get: { styling.uppercaseSectionHeaders },
                                set: { styling.uppercaseSectionHeaders = $0 }))
                        Toggle(
                            "page.theme.boldButtonText",
                            isOn: Binding(
                                get: { styling.boldButtons },
                                set: { styling.boldButtons = $0 }))

                        Picker("page.theme.toggleCharacterSetLabel", selection: checkboxSelection) {
                            // The app's default, and now a real option: it follows
                            // the terminal, including the tmux client changing
                            // under a running session.
                            Text("Automatic").tag("Automatic")
                            Text("Unicode ■").tag("Unicode")
                            Text("Emoji \u{2B1B}\u{FE0E}").tag("Emoji")
                            Text("ASCII [x]").tag("ASCII")
                        }
                        .pickerStyle(.radioGroup)
                    }
                }

                DemoSection("page.theme.colours") {
                    // One row per colour, and one row is the whole editor: the
                    // name, a swatch that opens the full modal editor, and the
                    // channel sliders that edit it in place.
                    VStack(alignment: .leading, spacing: 0) {
                        Text("page.theme.coloursDescription")
                            .foregroundStyle(.palette.foregroundSecondary)
                        ForEach(0..<Self.themeColors.count, id: \.self) { index in
                            ColorPicker(
                                Self.themeColors[index].name,
                                selection: colorBinding(Self.themeColors[index].keyPath))
                        }
                    }
                    .colorPickerLabelWidth(Self.colorLabelWidth)
                }

                DemoSection("page.theme.livePreview") {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            Text("Accent").foregroundStyle(.palette.accent)
                            Text("Success").foregroundStyle(.palette.success)
                            Text("Warning").foregroundStyle(.palette.warning)
                            Text("Error").foregroundStyle(.palette.error)
                            Text("Info").foregroundStyle(.palette.info)
                        }
                        Panel("page.theme.samplePanel") {
                            Text("page.theme.bodyText")
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                        // The row fills the palette draws, live: a selected row, the
                        // cursor row, and the two at once as the cursor reaches it.
                        Text("page.theme.rowFillsCaption")
                            .foregroundStyle(.palette.foregroundSecondary)
                        List(selection: $sampleSelection) {
                            ForEach(1...4, id: \.self) { Text(verbatim: "#\($0)") }
                        }
                        .frame(width: 24, height: 6)
                    }
                }

                KeyboardHelpSection(
                    "page.theme.themeHelp",
                    shortcuts: [
                        "page.theme.help.choosePreset",
                        "page.theme.help.moveFocus",
                        "page.theme.help.openSwatch",
                        "page.theme.help.cyclePalette",
                        "page.theme.help.everyChange",
                    ]
                )
            }
        }
        .appHeader {
            DemoAppHeader("menu.item.theme")
        }
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
