//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Strings_g8.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Translation fragment for the SwiftUI-compatibility (§4a) demo additions:
//  Text(_:format:), \.locale, .focusable, .searchable, and EditMode/EditButton.
//  English is the source of truth; every other language falls back to English
//  (then the key) for any key not present, so only "en" needs entries here.

// swiftlint:disable line_length

extension ExampleStrings {
    static let g8: [String: [String: String]] = [
        "en": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Formatted Values · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) renders a value through a Foundation FormatStyle (percent, number, currency).",
            "page.textStyles.section.locale": "Locale · \\.locale",
            "page.textStyles.localeExplain": "The same number, re-formatted by overriding .environment(\\.locale, …) — note the grouping separators.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Focusable views · .focusable()",
            "page.focus.focusableExplain": "Any view becomes a Tab stop with .focusable(); @FocusState then binds to it via .focused(). Tab to the label below.",
            "page.focus.focusableLabel": "Plain text — made focusable",
            "page.focus.focusableFocused": "focused",
            "page.focus.focusableNotFocused": "not focused",

            // .searchable + EditButton (Lists page)
            "page.list.searchableSection": "Searchable + Edit Mode",
            "page.list.searchableExplain": "A .searchable field filters the list (filtering is app-driven); EditButton toggles \\.editMode.",
            "page.list.searchableEmpty": "No matches",
            "page.list.editModeLabel": "Edit mode",
        ]
    ]
}
