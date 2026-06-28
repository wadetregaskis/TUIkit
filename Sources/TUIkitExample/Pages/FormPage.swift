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
        Section(L("page.form.profile")) {
            LabeledContent(L("page.form.name")) { TextField("", text: $name) }
            LabeledContent(L("page.form.email")) { TextField("", text: $email) }
            LabeledContent(L("page.form.password")) { SecureField("", text: $password) }
        }
        Section(L("page.form.appearance")) {
            LabeledContent(L("page.form.theme")) {
                Picker("", selection: $theme) {
                    Text(L("page.form.light")).tag(0)
                    Text(L("page.form.dark")).tag(1)
                    Text(L("page.form.system")).tag(2)
                }
            }
            LabeledContent(L("page.form.density")) {
                Picker("", selection: $density) {
                    Text(L("page.form.compact")).tag(0)
                    Text(L("page.form.comfortable")).tag(1)
                }
            }
            LabeledContent(L("page.form.version"), value: "1.0.3")
        }
        Section(L("page.form.notifications")) {
            // Checkboxes use their own (clickable) label and sit in the control
            // column, box first — the canonical macOS style. A multi-`Text` label
            // is SwiftUI's "title + explanatory text" form: the second line renders
            // below the title, indented to the label and in the secondary colour.
            Toggle(isOn: $push) {
                Text(L("page.form.pushNotifications"))
                Text(L("page.form.pushNotificationsDetail"))
            }
            Toggle(L("page.form.marketingEmail"), isOn: $marketing)
            LabeledContent(L("page.form.volume")) { Slider(value: $volume, in: 0...100) }
        }
        Section(L("page.form.account")) {
            LabeledContent(L("page.form.trustedDevices")) { Stepper("", value: $devices, in: 0...10) }
            LabeledContent(L("page.form.status"), value: L("page.form.statusActive"))
            // A push button is right-aligned, as on macOS.
            Button(L("page.form.signOut"), role: .destructive) {}
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection(L("page.form.columnsSection")) {
                Form { formContent }
            }

            DemoSection(L("page.form.groupedSection")) {
                Form { formContent }
                    .formStyle(.grouped)
            }

            DemoSection(L("page.form.rowAlignmentSection")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.form.rowAlignmentDescription"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    // The wide field sets the content width; the short buttons then
                    // visibly differ: \"Default\" hugs the right edge, \"Overridden\"
                    // the left.
                    Form {
                        LabeledContent(L("page.form.trustedDevicesAccount"), value: "3")
                        Button(L("page.form.defaultButton")) {}
                        Button(L("page.form.overriddenButton")) {}
                            .formRowAlignment(.leading)
                    }
                }
            }

            DemoSection(L("page.form.aboutSection")) {
                VStack(alignment: .leading) {
                    Text(L("page.form.aboutSameForm"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.form.aboutColumns1"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.form.aboutColumns2"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.form.aboutCheckbox1"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.form.aboutCheckbox2"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.form.aboutGrouped"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.form.aboutFocusHint")).dim()
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.form.title"), subtitle: "Form · LabeledContent · Section · formStyle(.columns / .grouped)")
        }
    }
}
