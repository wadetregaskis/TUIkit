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
        // Capture the live managers during body evaluation, where `@Environment`
        // resolves to the real render environment. The pickers' `set` closures run
        // later, at commit time, when `@Environment` would resolve to a no-op
        // default — so they must use these captured references, not re-read the
        // wrappers. (Same reason ContentView captures them for its F2/F3 keys.)
        let paletteMgr = paletteManager
        let appearanceMgr = appearanceManager

        let paletteSelection = Binding(
            get: { paletteMgr.current.id },
            set: { id in
                if let palette = palettes.first(where: { $0.id == id }) {
                    paletteMgr.setCurrent(palette)
                }
            }
        )
        let appearanceSelection = Binding(
            get: { appearanceMgr.current.id },
            set: { id in
                if let appearance = appearances.first(where: { $0.id == id }) {
                    appearanceMgr.setCurrent(appearance)
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
                "\(paletteMgr.currentName) · \(appearanceMgr.currentName)")

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
