//  TUIKit - Terminal UI Kit for Swift
//  SecureFieldPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// SecureField demo page.
///
/// Shows secure text field features including:
/// - Password masking with bullet characters (●)
/// - Cursor navigation (left/right/home/end)
/// - Text editing (insert, backspace, delete)
/// - onSubmit action
/// - Disabled state
/// - Prompt text
struct SecureFieldPage: View {
    @State var password: String = ""
    @State var confirmPassword: String = ""
    @State var apiKey: String = ""
    @State var disabledPassword: String = "secret123"
    @State var submittedPassword: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.secureField.section.passwordFields")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.password")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField(L("page.secureField.password"), text: $password)
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.confirm")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("Confirm", text: $confirmPassword, prompt: Text(L("page.secureField.reenterPassword")))
                    }
                }
            }

            DemoSection(L("page.secureField.section.onSubmit")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.apiKey")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField(L("page.secureField.apiKey"), text: $apiKey)
                            .onSubmit {
                                submittedPassword = "\(L("page.secureField.submittedPrefix")) \(apiKey.count) \(L("page.secureField.characters"))"
                            }
                    }
                    if !submittedPassword.isEmpty {
                        HStack(spacing: 1) {
                            Text("\(L("page.secureField.status")):").foregroundStyle(.palette.foregroundSecondary)
                            Text(submittedPassword).foregroundStyle(.palette.success)
                        }
                    }
                }
            }

            DemoSection(L("page.secureField.section.disabled")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.disabled")):").foregroundStyle(.palette.foregroundSecondary)
                        SecureField("Disabled", text: $disabledPassword).disabled()
                    }
                }
            }

            DemoSection(L("page.secureField.section.validation")) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.length")):").foregroundStyle(.palette.foregroundSecondary)
                        Text("\(password.count) \(L("page.secureField.characters"))")
                            .foregroundStyle(password.count >= 8 ? .palette.success : .palette.warning)
                    }
                    HStack(spacing: 1) {
                        Text("\(L("page.secureField.match")):").foregroundStyle(.palette.foregroundSecondary)
                        if password.isEmpty && confirmPassword.isEmpty {
                            Text(L("page.secureField.enterPasswords")).dim()
                        } else if password == confirmPassword {
                            Text(L("page.secureField.passwordsMatch")).foregroundStyle(.palette.success)
                        } else {
                            Text(L("page.secureField.passwordsDiffer")).foregroundStyle(.palette.error)
                        }
                    }
                }
            }

            KeyboardHelpSection(shortcuts: [
                L("page.secureField.help.typeInsert"),
                L("page.secureField.help.moveCursor"),
                L("page.secureField.help.jumpStartEnd"),
                L("page.secureField.help.backspace"),
                L("page.secureField.help.delete"),
                L("page.secureField.help.submit"),
                L("page.secureField.help.nextField"),
            ])

            Spacer()
        }
        .padding(.horizontal, 1)
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.secureField.header"))
        }
    }
}
