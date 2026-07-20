//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Localized.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Looks up a localized stress-harness string by its dot-notation key.
///
/// Returns the string for the currently selected ``LocalizationService``
/// language, falling back to English and then to the key itself. Call it inside
/// a view's `body` (it is re-evaluated each render) so switching the language at
/// runtime re-localizes the UI.
///
/// ```swift
/// Text(L("stress.shell.menu.title"))
/// ```
///
/// The stress harness uses its own `stress.*` key namespace and its own
/// translation tables (``StressStrings``), registered separately from the
/// example app's, so the two never collide.
func L(_ key: String) -> String {
    LocalizationService.shared.string(for: key)
}

/// Looks up a localized string by `key`, then substitutes positional
/// placeholders `{0}`, `{1}`, … with `args`.
///
/// Lets a heading keep its interpolated count(s) while only the static phrasing
/// is translated. The placeholder order can be re-arranged per language (e.g. a
/// language that puts the count after the noun), which a Swift string
/// interpolation in the source could not express.
///
/// ```swift
/// // table value (en): "{0} rows × 8 columns"
/// Lf("stress.scenario.table.heading", rows.count)   // -> "20000 rows × 8 columns"
/// ```
func Lf(_ key: String, _ args: CustomStringConvertible...) -> String {
    var result = LocalizationService.shared.string(for: key)
    for (index, value) in args.enumerated() {
        result = result.replacingOccurrences(of: "{\(index)}", with: value.description)
    }
    return result
}

/// Registers the stress harness's translation tables with the shared
/// ``LocalizationService`` so ``L(_:)`` can resolve them. Call once at startup.
///
/// The framework only bundles translations for its own strings; the harness
/// supplies its own through ``LocalizationService/register(translations:)``. The
/// tables live in ``StressStrings`` (one entry per supported language code).
/// Harmless to call in the headless `--bench` / `--selfcheck` modes too — those
/// just never read the resulting strings.
func registerStressLocalizations() {
    LocalizationService.shared.register(translations: StressStrings.translations)
}
