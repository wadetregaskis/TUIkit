//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StressStrings.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The stress harness's localized strings, keyed by language code then by
/// dot-notation string key. Registered with the shared `LocalizationService`
/// at startup (see `registerStressLocalizations()`), and looked up via `L(_:)`.
///
/// Only English needs to be complete; any key missing from another language
/// falls back to English, then to the key itself.
///
/// Scope: only the interactive shell's own UI and the scenario titles / blurbs /
/// `stresses` summaries / rendered headings — the prose a user reads while
/// driving the menu. The headless `--bench` / `--selfcheck` stdout diagnostics,
/// the `--scenario` id strings, the synthetic sample data, and the table column
/// headers (data-schema tokens) are deliberately left in English.
enum StressStrings {
    static let translations: [String: [String: String]] = [
        "en": en, "de": de, "fr": fr, "it": it, "es": es, "zh": zh, "ja": ja,
    ]
}
