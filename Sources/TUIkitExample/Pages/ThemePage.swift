//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ThemePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Theme demo page — switch the **global** colour palette and border appearance.
///
/// Both selections apply app-wide, not just to this page. The pickers drive the
/// shared ``ThemeManager`` instances from the environment (`paletteManager` /
/// `appearanceManager`) — the very managers the render loop reads when building
/// every frame's environment — so changing a theme here immediately re-colours
/// every other page, the app header, and the status bar.
///
/// The pickers bind *directly* to the managers (no local `@State`), keeping a
/// single source of truth: `get` reports the manager's current selection, `set`
/// applies the chosen item app-wide and triggers a re-render. The palette can
/// also be cycled from any page with `F2` (see `ContentView`).
struct ThemePage: View {
    @Environment(\.paletteManager) private var paletteManager
    @Environment(\.appearanceManager) private var appearanceManager

    var body: some View {
        let palettes = PaletteRegistry.all
        let appearances = AppearanceRegistry.all

        // The pickers bind directly to the shared managers. `@Environment`
        // resolves correctly inside these `set` closures (they run at commit
        // time, outside `body`) — so no local capture is needed.
        let paletteSelection = Binding(
            get: { paletteManager.current.id },
            set: { id in
                if let palette = palettes.first(where: { $0.id == id }) {
                    paletteManager.setCurrent(palette)
                }
            }
        )
        let appearanceSelection = Binding(
            get: { appearanceManager.current.id },
            set: { id in
                if let appearance = appearances.first(where: { $0.id == id }) {
                    appearanceManager.setCurrent(appearance)
                }
            }
        )

        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Colour Palette") {
                Picker("Palette", selection: paletteSelection) {
                    ForEach(0..<palettes.count, id: \.self) { index in
                        Text(palettes[index].name).tag(palettes[index].id)
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

            DemoSection("Live Preview") {
                VStack(alignment: .leading, spacing: 1) {
                    // Semantic colours re-resolve against the selected palette.
                    HStack(spacing: 2) {
                        Text("Accent").foregroundStyle(.palette.accent)
                        Text("Success").foregroundStyle(.palette.success)
                        Text("Warning").foregroundStyle(.palette.warning)
                        Text("Error").foregroundStyle(.palette.error)
                        Text("Info").foregroundStyle(.palette.info)
                    }
                    // The panel border reflects the selected appearance.
                    Panel("Sample Panel") {
                        Text("Borders use the selected appearance; text uses the palette.")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                }
            }

            ValueDisplayRow(
                "Active theme:",
                "\(paletteManager.currentName) · \(appearanceManager.currentName)")

            KeyboardHelpSection(
                "Theme",
                shortcuts: [
                    "Use [Tab] to move between the palette and appearance pickers",
                    "Use [↑/↓] to choose, [Enter]/[Space] to apply",
                    "Press [F2] / [F3] from any page to cycle palette / appearance",
                    "Selections apply to every page, the app header, and the status bar",
                ]
            )

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Theme Demo")
        }
    }
}
