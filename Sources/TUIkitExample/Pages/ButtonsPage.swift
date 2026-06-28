//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonsPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Buttons and focus demo page.
///
/// Shows interactive button features including:
/// - Different button styles (default, primary, success, destructive)
/// - Disabled buttons
/// - Plain style (no border)
/// - ButtonRow for horizontal groups
/// - Focus navigation with Tab
/// - Live click counter demonstrating `@State` persistence across re-renders
struct ButtonsPage: View {
    @State var clickCount: Int = 0
    @State var tintToggle: Bool = true

    var body: some View {
        ScrollView {
            content
        }
        .appHeader {
            DemoAppHeader(L("page.buttons.header"))
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.buttons.section.counter")) {
                HStack(spacing: 2) {
                    Button("+1") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("+10") {
                        clickCount += 10
                    }
                    .buttonStyle(.success)
                    Button(L("page.buttons.reset")) {
                        clickCount = 0
                    }
                    .buttonStyle(.destructive)
                    Text("\(L("page.buttons.clicks")): \(clickCount)")
                        .bold()
                        .foregroundStyle(.palette.accent)
                }
            }

            DemoSection(L("page.buttons.section.styles")) {
                HStack(spacing: 2) {
                    Button(L("page.buttons.default")) {
                        clickCount += 1
                    }
                    Button(L("page.buttons.primary")) {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button(L("page.buttons.success")) {
                        clickCount += 1
                    }
                    .buttonStyle(.success)
                    Button(L("page.buttons.destructive")) {
                        clickCount += 1
                    }
                    .buttonStyle(.destructive)
                }
            }

            DemoSection(L("page.buttons.section.disabled")) {
                HStack(spacing: 2) {
                    Button(L("page.buttons.enabled")) { clickCount += 1 }
                    Button(L("page.buttons.disabled")) {}.disabled()
                }
            }

            DemoSection(L("page.buttons.section.cascadingDisabled")) {
                // .disabled on a container cascades to every control inside.
                VStack(alignment: .leading, spacing: 1) {
                    Button(L("page.buttons.cantClick")) { clickCount += 1 }
                    Toggle(L("page.buttons.cantToggle"), isOn: .constant(true))
                }
                .disabled(true)
            }

            DemoSection(L("page.buttons.section.tinted")) {
                // .tint cascades the accent to every control inside.
                VStack(alignment: .leading, spacing: 1) {
                    Button(L("page.buttons.primary")) { clickCount += 1 }.buttonStyle(.primary)
                    Toggle(L("page.buttons.toggle"), isOn: $tintToggle)
                }
                .tint(.palette.success)
            }

            DemoSection(L("page.buttons.section.plain")) {
                HStack(spacing: 2) {
                    Button("\(L("page.buttons.link")) 1") { clickCount += 1 }
                        .buttonStyle(.plain)
                    Button("\(L("page.buttons.link")) 2") { clickCount += 1 }
                        .buttonStyle(.plain)
                }
            }

            DemoSection(L("page.buttons.section.buttonRow")) {
                ButtonRow(spacing: 3) {
                    Button(L("page.buttons.cancel")) { clickCount += 1 }
                    Button(L("page.buttons.save")) { clickCount += 1 }
                }
                .buttonStyle(.primary)
            }

            DemoSection(L("page.buttons.section.themeableText")) {
                VStack(alignment: .leading, spacing: 1) {
                    // .buttonTextStyle re-themes the label text of every button in
                    // the subtree; the brackets/background stay as the style draws
                    // them.
                    HStack(spacing: 2) {
                        Button(L("page.buttons.one")) { clickCount += 1 }
                        Button(L("page.buttons.two")) { clickCount += 1 }
                        Button(L("page.buttons.delete"), role: .destructive) { clickCount += 1 }
                    }
                    .buttonTextStyle { $0.bold = true; $0.foreground = .green }

                    Text(L("page.buttons.themeableNote"))
                    .foregroundStyle(.palette.foregroundSecondary)
                }
            }

            KeyboardHelpSection(
                L("page.buttons.section.focusNav"),
                shortcuts: [
                    L("page.buttons.help.tab"),
                    L("page.buttons.help.enterSpace"),
                ]
            )
        }
    }
}
