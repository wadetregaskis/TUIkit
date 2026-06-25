//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContainersPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Static row showing Card, Box, and Panel side by side.
///
/// Purely palette-driven, no state — wrapped in `.equatable()` for
/// subtree memoization during Spinner/Pulse animation frames.
struct ContainerTypesRow: View, Equatable {
    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading) {
                Text("Card").bold().foregroundStyle(.palette.accent)
                Card(borderColor: .palette.border) {
                    Text("A Card view").foregroundStyle(.palette.foreground)
                    Text("with padding").foregroundStyle(.palette.foregroundSecondary)
                }
            }

            VStack(alignment: .leading) {
                Text(".border()").bold().foregroundStyle(.palette.accent)
                Text("Simple bordered content")
                    .foregroundStyle(.palette.foreground)
                    .border()
            }

            VStack(alignment: .leading) {
                Text("Panel").bold().foregroundStyle(.palette.accent)
                Panel("Info", titleColor: .palette.accent) {
                    Text("Title in border").foregroundStyle(.palette.foreground)
                }
            }
        }
    }
}

/// Static row showing a settings panel with footer and alignment examples.
///
/// Purely palette-driven, no state — wrapped in `.equatable()` for
/// subtree memoization during Spinner/Pulse animation frames.
struct SettingsAndAlignmentRow: View, Equatable {
    var body: some View {
        HStack(spacing: 2) {
            DemoSection("Panel (Header + Footer)") {
                Panel("Settings", titleColor: .palette.accent) {
                    Text("Primary text (foreground)").foregroundStyle(.palette.foreground)
                    Text("Secondary text (foregroundSecondary)").foregroundStyle(.palette.foregroundSecondary)
                    Text("Tertiary text (foregroundTertiary)").foregroundStyle(.palette.foregroundTertiary)
                } footer: {
                    Text("Footer: Press Enter to confirm").foregroundStyle(.palette.foreground)
                }
            }

            DemoSection("Content Alignment") {
                // Each bordered box uses `.frame(maxWidth: .infinity)` so the
                // three share the row evenly. When the terminal is wide they
                // expand and you can see "short" pushed against the
                // leading/center/trailing edge — which is the whole point of
                // the demo. When the terminal is narrow they shrink together
                // and the longer label wraps to a second line, but neither
                // box ever disappears and "short" stays visible underneath.
                HStack(spacing: 1) {
                    VStack(alignment: .leading) {
                        Text("Leading align").foregroundStyle(.palette.foreground)
                        Text("short").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .border()

                    VStack(alignment: .center) {
                        Text("Center align").foregroundStyle(.palette.foreground)
                        Text("short").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .border()

                    VStack(alignment: .trailing) {
                        Text("Trailing align").foregroundStyle(.palette.foreground)
                        Text("short").foregroundStyle(.palette.foregroundSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .border()
                }
            }
        }
    }
}

/// Container views demo page.
///
/// Shows various container views including:
/// - Card (bordered container with padding)
/// - Box (simple bordered container)
/// - Panel (container with title in border)
/// - ProgressView (horizontal progress bar)
/// - Collapsible detail section demonstrating `@State` toggle
struct ContainersPage: View {
    @State var showDetails: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ContainerTypesRow().equatable()
            SettingsAndAlignmentRow().equatable()
            // ProgressView used to live here; it now has its own demo page
            // (press the back-tick shortcut on the menu) covering both
            // determinate and indeterminate variants of every style.

            DemoSection("Collapsible Detail (@State)") {
                VStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Button(showDetails ? "Hide Details" : "Show Details") {
                            showDetails.toggle()
                        }
                        Text(showDetails ? "expanded" : "collapsed")
                            .dim()
                    }
                    if showDetails {
                        Panel("Padding Examples", titleColor: .palette.accent) {
                            HStack(spacing: 1) {
                                Text("h:1 v:0").foregroundStyle(.palette.foreground)
                                    .padding(.horizontal, 1)
                                    .border()

                                Text("h:1 v:1").foregroundStyle(.palette.foreground)
                                    .padding(EdgeInsets(horizontal: 1, vertical: 1))
                                    .border()

                                Text("h:1 v:2").foregroundStyle(.palette.foreground)
                                    .padding(EdgeInsets(horizontal: 1, vertical: 2))
                                    .border()
                            }
                        }
                    }
                }
            }

            DemoSection("Appearance & BorderStyle") {
                Text("BorderStyle is determined by Appearance. Press 'a' to cycle.").foregroundStyle(.palette.foregroundSecondary)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Container Views Demo")
        }
    }
}
