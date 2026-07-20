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

            DemoSection(L("page.contentUnavailable.titleOnly")) {
                ContentUnavailableView(L("page.contentUnavailable.noResults"))
            }

            DemoSection(L("page.contentUnavailable.titleDescription")) {
                ContentUnavailableView(
                    L("page.contentUnavailable.noMessages"),
                    description: L("page.contentUnavailable.noMessagesDescription"))
            }

            DemoSection(L("page.contentUnavailable.customForm")) {
                ContentUnavailableView {
                    Text("✶  \(L("page.contentUnavailable.nothingSelected"))").bold().foregroundStyle(.palette.accent)
                } description: {
                    Text(L("page.contentUnavailable.chooseItem"))
                        .foregroundStyle(.palette.foregroundSecondary)
                } actions: {
                    Button(L("page.contentUnavailable.refresh")) { refreshes += 1 }
                }
                ValueDisplayRow(L("page.contentUnavailable.refreshPressed"), "\(refreshes)×")
            }

            KeyboardHelpSection(
                "ContentUnavailableView",
                shortcuts: [
                    L("page.contentUnavailable.help.placeholder"),
                    L("page.contentUnavailable.help.tabFocuses"),
                ]
            )

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.contentUnavailable.title"))
        }
    }
}
