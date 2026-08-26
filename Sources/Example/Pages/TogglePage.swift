//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TogglePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Toggle demo page.
struct TogglePage: View {
    @State private var notificationsEnabled: Bool = false
    @State private var darkModeEnabled: Bool = true
    @State private var showHiddenFiles: Bool = false

    // Distinct state for the "themeable label" demo so toggling those rows
    // doesn't alias (and visibly flip) the "Dark Mode" / "Show Hidden Files"
    // toggles above.
    @State private var styledLabelA: Bool = true
    @State private var styledLabelB: Bool = false

    // Toggle whose label carries explanatory subtext.
    @State private var pushNotifications: Bool = true

    // Shared by the three "Toggle style" rows so they flip together — flipping any
    // one shows every style in the same on/off state for a side-by-side compare.
    @State private var styleDemoOn: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.toggle.section.toggles") {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("page.toggle.enableNotifications", isOn: $notificationsEnabled)
                    Toggle("page.toggle.darkMode", isOn: $darkModeEnabled)
                    Toggle("page.toggle.showHiddenFiles", isOn: $showHiddenFiles)
                    Toggle("page.toggle.disabledOff", isOn: .constant(false)).disabled()
                    Toggle("page.toggle.disabledOn", isOn: .constant(true)).disabled()
                }
            }

            DemoSection("page.toggle.section.explanatory") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.toggle.explanatoryNote")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(isOn: $pushNotifications) {
                        Text("page.toggle.pushNotifications")
                        Text("page.toggle.pushSubtitle")
                    }
                }
            }

            DemoSection("page.toggle.section.themeableLabel") {
                VStack(alignment: .leading, spacing: 1) {
                    // Only the labels are restyled; the checkbox glyph is unaffected.
                    Toggle("page.toggle.italicLabel", isOn: $styledLabelA)
                    Toggle("page.toggle.andThisOne", isOn: $styledLabelB)
                }
                .toggleTextStyle { $0.italic = true; $0.foreground = .palette.info }
            }

            DemoSection("page.toggle.section.toggleCharacterSet") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.toggle.toggleCharacterSetNote")
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 4) {
                        // The "(default)" tag follows the terminal-adaptive
                        // `.automatic`: emoji under Apple's Terminal.app,
                        // unicode everywhere else.
                        checkboxColumn(".unicode", style: .unicode)
                        checkboxColumn(".emoji", style: .emoji)
                        checkboxColumn(".ascii", style: .ascii)
                    }
                }
            }

            DemoSection("page.toggle.section.toggleStyle") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.toggle.toggleStyleNote")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle("automatic", isOn: $styleDemoOn).toggleStyle(.automatic)
                    Toggle("checkbox", isOn: $styleDemoOn).toggleStyle(.checkbox)
                    Toggle("switch", isOn: $styleDemoOn).toggleStyle(.switch)
                }
            }

            DemoSection("page.toggle.section.keyboard") {
                VStack(alignment: .leading) {
                    Text("page.toggle.help.tab").dim()
                    Text("page.toggle.help.spaceEnter").dim()
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.toggles")
        }
    }

    /// One column of the checkbox-glyph comparison: the style's name (tagged
    /// "(default)" when it is what `.automatic` resolves to on this terminal)
    /// over an on/off pair rendered in that style.
    private func checkboxColumn(_ name: String, style: ToggleCharacterSet) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(style == .automatic ? "\(name) (\(L("page.toggle.default")))" : name).dim()
            Toggle("page.toggle.on", isOn: .constant(true))
            Toggle("page.toggle.off", isOn: .constant(false))
            // The switch under the same glyph style — under `.ascii` a
            // bracketed track with a sliding knob (`[o ]` / `[ o]`) instead of
            // the block-glyph coloured track.
            Toggle("page.toggle.on", isOn: .constant(true)).toggleStyle(.switch)
            Toggle("page.toggle.off", isOn: .constant(false)).toggleStyle(.switch)
        }
        .toggleCharacterSet(style)
    }
}
