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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Interactive Counter (@State)") {
                HStack(spacing: 2) {
                    Button("+1") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("+10") {
                        clickCount += 10
                    }
                    .buttonStyle(.success)
                    Button("Reset") {
                        clickCount = 0
                    }
                    .buttonStyle(.destructive)
                    Text("Clicks: \(clickCount)")
                        .bold()
                        .foregroundStyle(.palette.accent)
                }
            }

            DemoSection("Button Styles") {
                HStack(spacing: 2) {
                    Button("Default") {
                        clickCount += 1
                    }
                    Button("Primary") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("Success") {
                        clickCount += 1
                    }
                    .buttonStyle(.success)
                    Button("Destructive") {
                        clickCount += 1
                    }
                    .buttonStyle(.destructive)
                }
            }

            DemoSection("Disabled Button") {
                HStack(spacing: 2) {
                    Button("Enabled") { clickCount += 1 }
                    Button("Disabled") {}.disabled()
                }
            }

            DemoSection("Plain Style (No Border)") {
                HStack(spacing: 2) {
                    Button("Link 1") { clickCount += 1 }
                        .buttonStyle(.plain)
                    Button("Link 2") { clickCount += 1 }
                        .buttonStyle(.plain)
                }
            }

            DemoSection("ButtonRow (Horizontal Group)") {
                ButtonRow(spacing: 3) {
                    Button("Cancel") { clickCount += 1 }
                    Button("Save") { clickCount += 1 }
                }
                .buttonStyle(.primary)
            }

            KeyboardHelpSection(
                "Focus Navigation",
                shortcuts: [
                    "Use [Tab] to move focus between buttons",
                    "Use [Enter] or [Space] to press the focused button",
                ]
            )

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Buttons & Focus Demo")
        }
    }
}
