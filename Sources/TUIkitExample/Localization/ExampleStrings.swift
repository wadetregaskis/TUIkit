//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ExampleStrings.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The example app's localized strings, keyed by language code then by
/// dot-notation string key. Registered with the shared `LocalizationService`
/// at startup (see `registerExampleLocalizations()`), and looked up via `L(_:)`.
///
/// Only English needs to be complete; any key missing from another language
/// falls back to English, then to the key itself.
enum ExampleStrings {
    static let translations: [String: [String: String]] = [
        "en": en,
        "de": de,
        "fr": fr,
        "it": it,
        "es": es,
        "zh": zh,
        "ja": ja,
    ]
}
