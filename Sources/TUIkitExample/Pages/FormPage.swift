//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FormPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Form demo page: the macOS-style **columns** layout (the default) and the
/// **grouped** layout, both built from `LabeledContent` rows.
struct FormPage: View {
    @State private var name = "Ada Lovelace"
    @State private var email = "ada@analytical.engine"
    @State private var profileName = "Grace Hopper"
    @State private var profileEmail = "grace@navy.mil"
    @State private var pushNotifications = true
    @State private var marketingEmail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("Columns style (.columns — the default, macOS convention)") {
                Form {
                    LabeledContent("Name") { TextField("", text: $name) }
                    LabeledContent("Email") { TextField("", text: $email) }
                    LabeledContent("Version", value: "1.0.3")
                }
            }

            DemoSection("Grouped style (.grouped)") {
                Form {
                    Section("Profile") {
                        LabeledContent("Name") { TextField("", text: $profileName) }
                        LabeledContent("Email") { TextField("", text: $profileEmail) }
                    }
                    Section("Notifications") {
                        LabeledContent("Push") { Toggle("", isOn: $pushNotifications) }
                        LabeledContent("Marketing email") { Toggle("", isOn: $marketingEmail) }
                    }
                }
                .formStyle(.grouped)
            }

            DemoSection("About forms") {
                VStack(alignment: .leading) {
                    Text("Labels right-align to a shared pillar; controls left-align after it.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("The default is .columns (the classic macOS form); .grouped boxes each Section.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("[Tab] move focus between fields").dim()
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Forms", subtitle: "Form · LabeledContent · formStyle(.columns / .grouped)")
        }
    }
}
