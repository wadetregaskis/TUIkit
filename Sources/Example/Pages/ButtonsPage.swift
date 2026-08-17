//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonsPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
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
            DemoAppHeader("menu.item.buttons")
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.buttons.section.counter") {
                HStack(spacing: 2) {
                    Button("+1") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("+10") {
                        clickCount += 10
                    }
                    .buttonStyle(.success)
                    Button("page.buttons.reset") {
                        clickCount = 0
                    }
                    .buttonStyle(.destructive)
                    Text("\(L("page.buttons.clicks")): \(clickCount)")
                        .bold()
                        .foregroundStyle(.palette.accent)
                }
            }

            DemoSection("page.buttons.section.styles") {
                HStack(spacing: 2) {
                    Button("page.buttons.default") {
                        clickCount += 1
                    }
                    Button("page.buttons.primary") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("page.buttons.success") {
                        clickCount += 1
                    }
                    .buttonStyle(.success)
                    Button("page.buttons.destructive") {
                        clickCount += 1
                    }
                    .buttonStyle(.destructive)
                }
            }

            DemoSection("page.buttons.section.disabled") {
                HStack(spacing: 2) {
                    Button("page.buttons.enabled") { clickCount += 1 }
                    Button("page.buttons.disabled") {}.disabled()
                }
            }

            DemoSection("page.buttons.section.cascadingDisabled") {
                // .disabled on a container cascades to every control inside.
                VStack(alignment: .leading, spacing: 1) {
                    Button("page.buttons.cantClick") { clickCount += 1 }
                    Toggle("page.buttons.cantToggle", isOn: .constant(true))
                }
                .disabled(true)
            }

            DemoSection("page.buttons.section.tinted") {
                // .tint cascades the accent to every control inside. The toggle
                // drives it: flip it off and the green tint (on the button AND on
                // the toggle's own checkbox) disappears — a live cascade demo.
                VStack(alignment: .leading, spacing: 1) {
                    Button("page.buttons.primary") { clickCount += 1 }.buttonStyle(.primary)
                    Toggle("page.buttons.toggle", isOn: $tintToggle)
                }
                .tint(tintToggle ? .palette.success : nil)
            }

            DemoSection("page.buttons.section.plain") {
                HStack(spacing: 2) {
                    Button("\(L("page.buttons.link")) 1") { clickCount += 1 }
                        .buttonStyle(.plain)
                    Button("\(L("page.buttons.link")) 2") { clickCount += 1 }
                        .buttonStyle(.plain)
                }
            }

            DemoSection("page.buttons.section.buttonRow") {
                ButtonRow(spacing: 3) {
                    Button("page.buttons.cancel") { clickCount += 1 }
                    Button("page.buttons.save") { clickCount += 1 }
                }
                .buttonStyle(.primary)
            }

            DemoSection("page.buttons.section.themeableText") {
                VStack(alignment: .leading, spacing: 1) {
                    // .buttonTextStyle re-themes the label text of every button in
                    // the subtree; the brackets/background stay as the style draws
                    // them.
                    HStack(spacing: 2) {
                        Button("page.buttons.one") { clickCount += 1 }
                        Button("page.buttons.two") { clickCount += 1 }
                        Button("page.buttons.delete", role: .destructive) { clickCount += 1 }
                    }
                    .buttonTextStyle { $0.bold = true; $0.foreground = .green }

                    Text("page.buttons.themeableNote")
                    .foregroundStyle(.palette.foregroundSecondary)
                }
            }

            // A Link is a button that opens a URL, so it belongs with the other
            // activatable controls: Tab to it and press Enter, or click it.
            DemoSection("page.buttons.section.links") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.newControls.linkHint").foregroundStyle(.palette.foregroundSecondary)
                    Link("swift.org", destination: URL(string: "https://swift.org")!)
                    Link(destination: URL(string: "https://github.com/apple/swift")!) {
                        Label("apple/swift", systemImage: "swift")
                    }
                }
            }

            KeyboardHelpSection(
                "page.buttons.section.focusNav",
                shortcuts: [
                    "page.buttons.help.tab",
                    "page.buttons.help.enterSpace",
                ]
            )
        }
    }
}
