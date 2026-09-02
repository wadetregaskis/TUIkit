//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueDisplayRow.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A label-value row for displaying current state in demo pages.
///
/// Renders the label in secondary color and the value in bold accent color.
///
/// # Example
///
/// ```swift
/// ValueDisplayRow("page.slider.volume", String(format: "%.0f%%", volume * 100))
/// ValueDisplayRow("page.list.selection", selection ?? L("common.none"))
/// ```
///
/// Only the **label** is a localization key, exactly as `LabeledContent(_:value:)`
/// is in the framework: the value is the thing being shown, and translating it
/// would be wrong. A label that is a computed `String` is displayed as given.
struct ValueDisplayRow: View {
    let label: String
    let value: String

    /// Creates a row with a localized label.
    ///
    /// - Parameters:
    ///   - labelKey: The key for the row's label.
    ///   - value: The value to display, as written.
    init(_ labelKey: LocalizedStringKey, _ value: String) {
        self.init(labelKey.localized, value)
    }

    /// Creates a row labelled as written.
    ///
    /// - Parameters:
    ///   - label: The row's label.
    ///   - value: The value to display.
    @_disfavoredOverload
    init<S: StringProtocol>(_ label: S, _ value: String) {
        self.label = String(label)
        self.value = value
    }

    var body: some View {
        HStack(spacing: 1) {
            Text(label).foregroundStyle(.palette.foregroundSecondary)
            Text(value).bold().foregroundStyle(.palette.accent)
        }
    }
}
