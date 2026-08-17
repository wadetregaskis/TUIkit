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

            DemoSection("page.contentUnavailable.titleOnly") {
                ContentUnavailableView("page.contentUnavailable.noResults")
            }

            DemoSection("page.contentUnavailable.titleDescription") {
                ContentUnavailableView(
                    "page.contentUnavailable.noMessages",
                    description: "page.contentUnavailable.noMessagesDescription")
            }

            DemoSection("page.contentUnavailable.customForm") {
                ContentUnavailableView {
                    Text("✶  \(L("page.contentUnavailable.nothingSelected"))").bold().foregroundStyle(.palette.accent)
                } description: {
                    Text("page.contentUnavailable.chooseItem")
                        .foregroundStyle(.palette.foregroundSecondary)
                } actions: {
                    Button("page.contentUnavailable.refresh") { refreshes += 1 }
                }
                ValueDisplayRow("page.contentUnavailable.refreshPressed", "\(refreshes)×")
            }

            KeyboardHelpSection(
                "ContentUnavailableView",
                shortcuts: [
                    "page.contentUnavailable.help.placeholder",
                    "page.contentUnavailable.help.tabFocuses",
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.emptyState")
        }
    }
}
