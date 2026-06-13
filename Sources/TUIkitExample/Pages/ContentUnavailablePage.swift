//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContentUnavailablePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// `ContentUnavailableView` demo — the standard placeholder for empty states
/// (no results, nothing selected, an empty inbox, …), shown across its
/// initialiser variants: title-only, title + description, and a fully custom
/// label / description / actions form.
struct ContentUnavailablePage: View {
    @State private var refreshes = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Title only") {
                ContentUnavailableView("No Results")
            }

            DemoSection("Title + description") {
                ContentUnavailableView(
                    "No Messages",
                    description: "Messages you receive will appear here.")
            }

            DemoSection("Custom label, description & actions") {
                ContentUnavailableView {
                    Text("✶  Nothing Selected").bold().foregroundStyle(.palette.accent)
                } description: {
                    Text("Choose an item from the list to see its details.")
                        .foregroundStyle(.palette.foregroundSecondary)
                } actions: {
                    Button("Refresh") { refreshes += 1 }
                }
                ValueDisplayRow("Refresh pressed:", "\(refreshes)×")
            }

            KeyboardHelpSection(
                "ContentUnavailableView",
                shortcuts: [
                    "A placeholder for empty states — pair it with `if items.isEmpty`",
                    "[Tab] focuses the action button, [Enter]/[Space] activates it",
                ]
            )

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Empty State Demo")
        }
    }
}
