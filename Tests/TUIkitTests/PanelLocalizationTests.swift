//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PanelLocalizationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// The framework's own words on its panels and empty containers go through
/// the translation tables. A `String`-typed name can only ever bind the
/// verbatim initializer, so the rule is checked at the SOURCE: the names the
/// views hold are keys the tables know.
@MainActor
@Suite("Panel and placeholder localization")
struct PanelLocalizationTests {
    @Test("Every semantic colour role in the picker is a framework key")
    func semanticNamesAreKeys() {
        for entry in ColorPickerPanel.semanticColors {
            #expect(LocalizationKey.Label(rawValue: entry.name) != nil, "\(entry.name)")
        }
    }

    @Test("The default empty-list placeholder is resolved, in the current language")
    func emptyPlaceholderIsResolved() {
        let placeholder = ViewConstants.localizedEmptyListPlaceholder
        #expect(placeholder == LocalizationService.shared.string(for: LocalizationKey.Label.noItems))
        #expect(placeholder != LocalizationKey.Label.noItems.rawValue)
    }

    @Test("The empty-list placeholder is translated")
    func emptyPlaceholderIsTranslated() throws {
        let configDir = NSTemporaryDirectory() + "tuikit-loc-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: configDir) }
        let service = LocalizationService(configDirectoryPath: configDir)
        service.setLanguage(.german)
        #expect(service.string(for: LocalizationKey.Label.noItems) == "Keine Einträge")
        #expect(service.string(for: LocalizationKey.Label.noItems) != ViewConstants.emptyListPlaceholder)
    }
}
