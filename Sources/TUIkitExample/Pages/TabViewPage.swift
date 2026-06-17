//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// TabView demo page.
///
/// Shows the `TabView` control in both of its styles:
/// - `.compact` — a lightweight strip of chip-style tab headers, no chrome
///   around the content (the same style the colour picker uses). The content
///   adds its own padding, since the compact strip deliberately leaves none.
/// - `.bordered` — line-drawing chrome (like `List`, `Table`, the app header)
///   wrapping the tabs *and* the content, with the border opened beneath the
///   active tab so its row flows directly into the content.
///
/// In both styles the content area takes the active tab header's background, so
/// the selected tab reads as one continuous surface with its content. Activating
/// a tab always floats its whole row to the bottom of a wrapped strip, so it sits
/// adjacent to the content it reveals.
struct TabViewPage: View {
    @State private var compactSelection = 0
    @State private var borderedSelection = 0
    @State private var notify = true
    @State private var volume = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Compact Style (no chrome)") {
                TabView(selection: $compactSelection) {
                    Tab("Profile", value: 0) {
                        VStack(alignment: .leading) {
                            Text("Ada Lovelace").bold()
                            Text("First programmer")
                                .foregroundStyle(.palette.foregroundSecondary)
                        }
                        .padding(.top, 1)
                    }
                    Tab("Settings", value: 1) {
                        Toggle("Notifications", isOn: $notify)
                            .padding(.top, 1)
                    }
                    Tab("About", value: 2) {
                        Text("TUIkit · v1.0")
                            .padding(.top, 1)
                    }
                }
                .tabViewStyle(.compact)
            }

            DemoSection("Bordered Style (line-drawing chrome)") {
                TabView(selection: $borderedSelection) {
                    Tab("Overview", value: 0) {
                        Text("A bordered tab view wraps the tabs and content "
                            + "together, opening the border under the active tab.")
                    }
                    Tab("Audio", value: 1) {
                        VStack(alignment: .leading) {
                            Text("Volume")
                            Slider(value: $volume, in: 0...1)
                                .frame(width: 24)
                        }
                    }
                    Tab("Status", value: 2) {
                        Toggle("Online", isOn: $notify)
                    }
                    Tab("Help", value: 3) {
                        Text("Use ◀ ▶ to switch tabs when the strip is focused.")
                    }
                }
                .tabViewStyle(.bordered)
            }

            KeyboardHelpSection(
                "TabView Navigation",
                shortcuts: [
                    "Use [Tab] to focus a tab strip",
                    "Use [←/→] to switch between tabs",
                    "Click a tab header to select it",
                ]
            )

            Spacer()
        }
        .appHeader {
            DemoAppHeader("TabView Demo")
        }
    }
}
