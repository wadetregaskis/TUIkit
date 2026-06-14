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

            DemoSection("Themeable label text (.toggleTextStyle)") {
                VStack(alignment: .leading, spacing: 1) {
                    // Only the labels are restyled; the [x] indicator is unaffected.
                    Toggle("Italic, info-coloured label", isOn: $darkModeEnabled)
                    Toggle("…and this one too", isOn: $showHiddenFiles)
                }
                .toggleTextStyle { $0.italic = true; $0.foreground = .palette.info }
            }

            DemoSection("Keyboard Controls") {
                VStack(alignment: .leading) {
                    Text("[Tab] Move focus between toggles").dim()
                    Text("[Space] or [Enter] Toggle the focused item").dim()
                }
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Toggle Demo")
        }
    }
}
