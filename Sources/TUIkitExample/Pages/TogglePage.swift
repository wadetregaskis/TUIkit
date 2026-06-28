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

            DemoSection("Toggles") {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    Toggle("Dark Mode", isOn: $darkModeEnabled)
                    Toggle("Show Hidden Files", isOn: $showHiddenFiles)
                    Toggle("Disabled (OFF)", isOn: .constant(false)).disabled()
                    Toggle("Disabled (ON)", isOn: .constant(true)).disabled()
                }
            }

            DemoSection("Explanatory subtitle (a multi-Text label)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("A second Text in the label closure renders below the title — "
                        + "indented to the label, in the secondary colour — exactly as in SwiftUI.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle(isOn: $pushNotifications) {
                        Text("Push notifications")
                        Text("Receive alerts even when the app is closed")
                    }
                }
            }

            DemoSection("Themeable label text (.toggleTextStyle)") {
                VStack(alignment: .leading, spacing: 1) {
                    // Only the labels are restyled; the checkbox glyph is unaffected.
                    Toggle("Italic, info-coloured label", isOn: $styledLabelA)
                    Toggle("…and this one too", isOn: $styledLabelB)
                }
                .toggleTextStyle { $0.italic = true; $0.foreground = .palette.info }
            }

            DemoSection("Checkbox glyph style (.checkboxStyle)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CheckboxStyle customises the glyphs. The app-wide default is set "
                        + "on the Theme page; here both are shown side by side.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(".squares (default)").dim()
                            Toggle("On", isOn: .constant(true))
                            Toggle("Off", isOn: .constant(false))
                        }
                        .checkboxStyle(.squares)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(".ascii").dim()
                            Toggle("On", isOn: .constant(true))
                            Toggle("Off", isOn: .constant(false))
                        }
                        .checkboxStyle(.ascii)
                    }
                }
            }

            DemoSection("Toggle style (.toggleStyle)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("All three styles render as a checkbox in the terminal; the API "
                        + "mirrors SwiftUI (.automatic / .checkbox / .switch).")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle("automatic", isOn: .constant(true)).toggleStyle(.automatic)
                    Toggle("checkbox", isOn: .constant(true)).toggleStyle(.checkbox)
                    Toggle("switch", isOn: .constant(true)).toggleStyle(.switch)
                }
            }

            DemoSection("Keyboard Controls") {
                VStack(alignment: .leading) {
                    Text("[Tab] Move focus between toggles").dim()
                    Text("[Space] or [Enter] Toggle the focused item").dim()
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Toggle Demo")
        }
    }
}
