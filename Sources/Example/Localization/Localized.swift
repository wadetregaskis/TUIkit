//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Localized.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Looks up a localized example-app string by its dot-notation key.
///
/// Returns the string for the currently selected ``LocalizationService``
/// language, falling back to English and then to the key itself. Call it inside
/// a view's `body` (it is re-evaluated each render) so switching the language at
/// runtime re-localizes the UI.
///
/// ```swift
/// Text(L("page.toggles.title"))
/// ```
func L(_ key: String) -> String {
    LocalizationService.shared.string(for: key)
}

/// Registers the example app's translation tables with the shared
/// ``LocalizationService`` so ``L(_:)`` can resolve them. Call once at startup.
///
/// The framework only bundles translations for its own strings; an app supplies
/// its own through ``LocalizationService/register(translations:)``. The tables
/// live in ``ExampleStrings`` (one entry per supported language code).
func registerExampleLocalizations() {
    LocalizationService.shared.register(translations: ExampleStrings.translations)
}
