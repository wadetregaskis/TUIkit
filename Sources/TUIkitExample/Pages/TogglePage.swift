//  TUIKit - Terminal UI Kit for Swift
//  TogglePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Toggle demo page.
struct TogglePage: View {
    @State var notificationsEnabled: Bool = false
    @State var darkModeEnabled: Bool = true
    @State var showHiddenFiles: Bool = false

    // Distinct state for the "themeable label" demo so toggling those rows
    // doesn't alias (and visibly flip) the "Dark Mode" / "Show Hidden Files"
    // toggles above.
    @State var styledLabelA: Bool = true
    @State var styledLabelB: Bool = false

    // Toggle whose label carries explanatory subtext.
    @State var pushNotifications: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.toggle.section.toggles")) {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle(L("page.toggle.enableNotifications"), isOn: $notificationsEnabled)
                    Toggle(L("page.toggle.darkMode"), isOn: $darkModeEnabled)
                    Toggle(L("page.toggle.showHiddenFiles"), isOn: $showHiddenFiles)
                    Toggle(L("page.toggle.disabledOff"), isOn: .constant(false)).disabled()
                    Toggle(L("page.toggle.disabledOn"), isOn: .constant(true)).disabled()
                }
            }

            DemoSection(L("page.toggle.section.explanatory")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.toggle.explanatoryNote"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(isOn: $pushNotifications) {
                        Text(L("page.toggle.pushNotifications"))
                        Text(L("page.toggle.pushSubtitle"))
                    }
                }
            }

            DemoSection(L("page.toggle.section.themeableLabel")) {
                VStack(alignment: .leading, spacing: 1) {
                    // Only the labels are restyled; the checkbox glyph is unaffected.
                    Toggle(L("page.toggle.italicLabel"), isOn: $styledLabelA)
                    Toggle(L("page.toggle.andThisOne"), isOn: $styledLabelB)
                }
                .toggleTextStyle { $0.italic = true; $0.foreground = .palette.info }
            }

            DemoSection(L("page.toggle.section.checkboxGlyph")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.toggle.checkboxNote"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(".squares") (\(L("page.toggle.default")))").dim()
                            Toggle(L("page.toggle.on"), isOn: .constant(true))
                            Toggle(L("page.toggle.off"), isOn: .constant(false))
                        }
                        .checkboxStyle(.squares)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(".ascii").dim()
                            Toggle(L("page.toggle.on"), isOn: .constant(true))
                            Toggle(L("page.toggle.off"), isOn: .constant(false))
                        }
                        .checkboxStyle(.ascii)
                    }
                }
            }

            DemoSection(L("page.toggle.section.toggleStyle")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.toggle.toggleStyleNote"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle("automatic", isOn: .constant(true)).toggleStyle(.automatic)
                    Toggle("checkbox", isOn: .constant(true)).toggleStyle(.checkbox)
                    Toggle("switch", isOn: .constant(true)).toggleStyle(.switch)
                }
            }

            DemoSection(L("page.toggle.section.keyboard")) {
                VStack(alignment: .leading) {
                    Text(L("page.toggle.help.tab")).dim()
                    Text(L("page.toggle.help.spaceEnter")).dim()
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.toggle.header"))
        }
    }
}
