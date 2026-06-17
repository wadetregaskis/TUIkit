//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// TabView demo page.
///
/// Shows the `TabView` control in both of its styles:
/// - `.compact` — a lightweight strip of chip-style tab headers with no chrome
///   around the content (the style the colour picker uses). Here it's set to
///   leading alignment via `.tabViewHeaderAlignment(_:)`.
/// - `.bordered` — folder tabs sitting on a line-drawing content box (like
///   `List` / `Table` / the app header). Inactive tabs are separated from the
///   content by the box's top border; the active tab's row floats to the bottom
///   and the border curves around it (`╯ … ╰`) so the tab and body read as one.
///   The strip is centred by default and the content is padded for breathing
///   room (both adjustable via `.tabViewHeaderAlignment(_:)` /
///   `.tabViewContentPadding(_:)`).
///
/// In both styles the active tab and the content share a subtle surface (a quiet
/// lift above the base background, like the status bar / app header), and the
/// active tab breathes on the pulse clock while the strip is focused.
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
                    }
                    Tab("Settings", value: 1) {
                        Toggle("Notifications", isOn: $notify)
                    }
                    Tab("About", value: 2) {
                        Text("TUIkit · v1.0")
                    }
                }
                .tabViewStyle(.compact)
                .tabViewHeaderAlignment(.leading)
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
