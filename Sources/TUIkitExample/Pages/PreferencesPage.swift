//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PreferencesPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Preference Keys

/// A count that every child contributes 1 to; the reduce SUMS the contributions,
/// so an ancestor sees the total number of reporting children — bottom-up value
/// propagation (the mirror image of `@Environment`, which flows top-down).
private struct ChildCountKey: PreferenceKey {
    static var defaultValue: Int { 0 }
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

/// The last status message a child published; the reduce keeps the last one set.
private struct ChildMessageKey: PreferenceKey {
    static var defaultValue: String { "" }
    static func reduce(value: inout String, nextValue: () -> String) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

// MARK: - Preferences Page

/// Preferences demo page.
///
/// Demonstrates `PreferenceKey` / `.preference(...)` / `.onPreferenceChange(...)`:
/// a value bubbling UP from child views to a parent. Each child row contributes
/// `1` to a summed count; the parent header reads the total live, so adding or
/// removing rows updates the header without the parent ever reaching down into
/// the children.
struct PreferencesPage: View {
    @State private var rows: Int = 3
    @State private var reportedCount: Int = 0
    @State private var lastMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            // The header reads the count the children reported from BELOW.
            DemoSection("\(L("page.preferences.parentSection")) — \(L("page.preferences.childrenReporting")): \(reportedCount)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.preferences.description"))
                        .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 2) {
                        Button(L("page.preferences.addChild")) { rows += 1 }
                        Button(L("page.preferences.removeChild")) { rows = max(0, rows - 1) }
                    }

                    // Each child publishes a count of 1 and a message; the
                    // reduce on `ChildCountKey` sums them so the parent header
                    // above shows the live total.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<rows, id: \.self) { index in
                            Text("\(L("page.preferences.childLabel")) #\(index + 1)")
                                .dim()
                                .preference(key: ChildCountKey.self, value: 1)
                                .preference(
                                    key: ChildMessageKey.self,
                                    value: "\(L("page.preferences.childLabel")) #\(index + 1) \(L("page.preferences.reporting"))")
                        }
                    }
                    .border(color: .brightBlack)

                    ValueDisplayRow(L("page.preferences.lastMessage"), lastMessage.isEmpty ? "—" : lastMessage)
                }
            }

            Spacer()
        }
        .onPreferenceChange(ChildCountKey.self) { count in
            reportedCount = count
        }
        .onPreferenceChange(ChildMessageKey.self) { message in
            lastMessage = message
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(L("page.preferences.title"))
        }
    }
}
