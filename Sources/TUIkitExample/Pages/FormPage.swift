//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FormPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Form demo page: the **same** form rendered two ways — the macOS-style
/// **columns** layout (the default) and the **grouped** layout — for an
/// apples-to-apples comparison. The shared content uses multiple `Section`s and a
/// variety of controls (`TextField`, `SecureField`, `Picker`, `Slider`,
/// `Stepper`, `Toggle`, value rows, and a full-width `Button`).
struct FormPage: View {
    @State private var name = "Ada Lovelace"
    @State private var email = "ada@analytical.engine"
    @State private var password = "babbage"
    @State private var theme = 0
    @State private var density = 1
    @State private var push = true
    @State private var marketing = false
    @State private var volume = 60.0
    @State private var devices = 3

    /// The form's content, shared by both demos so the **only** difference
    /// between them is the `formStyle`. (The bindings are shared too, so it is
    /// literally the same form shown twice.)
    @ViewBuilder private var formContent: some View {
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
        Section("Notifications") {
            // Checkboxes use their own (clickable) label and sit in the control
            // column, box first — the canonical macOS style. A multi-`Text` label
            // is SwiftUI's "title + explanatory text" form: the second line renders
            // below the title, indented to the label and in the secondary colour.
            Toggle(isOn: $push) {
                Text("Push notifications")
                Text("Receive alerts even when the app is closed")
            }
            Toggle("Marketing email", isOn: $marketing)
            LabeledContent("Volume") { Slider(value: $volume, in: 0...100) }
        }
        Section("Account") {
            LabeledContent("Trusted devices") { Stepper("", value: $devices, in: 0...10) }
            LabeledContent("Status", value: "Active")
            // A push button is right-aligned, as on macOS.
            Button("Sign Out", role: .destructive) {}
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("Columns style (.columns — the default, macOS convention)") {
                Form { formContent }
            }

            DemoSection("Grouped style (.grouped) — same content, different style") {
                Form { formContent }
                    .formStyle(.grouped)
            }

            DemoSection("Per-row alignment override (.formRowAlignment)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Buttons right-align to the content edge by default in columns; "
                        + ".formRowAlignment(.leading) overrides one row to the left.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // The wide field sets the content width; the short buttons then
                    // visibly differ: \"Default\" hugs the right edge, \"Overridden\"
                    // the left.
                    Form {
                        LabeledContent("Trusted devices on your account", value: "3")
                        Button("Default") {}
                        Button("Overridden") {}
                            .formRowAlignment(.leading)
                    }
                }
            }

            DemoSection("About forms") {
                VStack(alignment: .leading) {
                    Text("Both demos above show the same form — only the formStyle differs.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("Columns: field labels + bold section headers right-align to a shared")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("pillar; checkboxes sit box-first in the control column; buttons right-align.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("A checkbox label with a 2nd line shows explanatory subtext (secondary,")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("indented to the label) — the SwiftUI title+description label form.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("Grouped: each Section is a bordered box.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("[Tab] move focus · the whole checkbox row (box + label) is clickable").dim()
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
