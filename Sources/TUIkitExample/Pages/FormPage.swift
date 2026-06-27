//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FormPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Form demo page: the macOS-style **columns** layout (the default) and the
/// **grouped** layout, each with multiple `Section`s and a variety of controls
/// (`TextField`, `SecureField`, `Picker`, `Slider`, `Stepper`, `Toggle`, value
/// rows, and a full-width `Button`).
struct FormPage: View {
    // Columns-form state.
    @State private var name = "Ada Lovelace"
    @State private var email = "ada@analytical.engine"
    @State private var password = "babbage"
    @State private var theme = 0
    @State private var density = 1

    // Grouped-form state.
    @State private var push = true
    @State private var marketing = false
    @State private var volume = 60.0
    @State private var devices = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("Columns style (.columns — the default, macOS convention)") {
                Form {
                    Section("Profile") {
                        LabeledContent("Name") { TextField("", text: $name) }
                        LabeledContent("Email") { TextField("", text: $email) }
                        LabeledContent("Password") { SecureField("", text: $password) }
                    }
                    Section("Appearance") {
                        LabeledContent("Theme") {
                            Picker("", selection: $theme) {
                                Text("Light").tag(0)
                                Text("Dark").tag(1)
                                Text("System").tag(2)
                            }
                        }
                        LabeledContent("Density") {
                            Picker("", selection: $density) {
                                Text("Compact").tag(0)
                                Text("Comfortable").tag(1)
                            }
                        }
                        LabeledContent("Version", value: "1.0.3")
                    }
                }
            }

            DemoSection("Grouped style (.grouped)") {
                Form {
                    Section("Notifications") {
                        LabeledContent("Push") { Toggle("", isOn: $push) }
                        LabeledContent("Marketing email") { Toggle("", isOn: $marketing) }
                        LabeledContent("Volume") { Slider(value: $volume, in: 0...100) }
                    }
                    Section("Account") {
                        LabeledContent("Trusted devices") { Stepper("", value: $devices, in: 0...10) }
                        LabeledContent("Status", value: "Active")
                        Button("Sign Out", role: .destructive) {}
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
                    Text("A row that isn't LabeledContent (e.g. the Sign Out button) spans the full width.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("[Tab] move focus between fields").dim()
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Forms", subtitle: "Form · LabeledContent · Section · formStyle(.columns / .grouped)")
        }
    }
}
