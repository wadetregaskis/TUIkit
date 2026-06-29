//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocalizationServiceTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - Localization Service Tests

@Suite("LocalizationService")
final class LocalizationServiceTests {
    /// Isolated config dir so these tests never read or write the user's real
    /// language preference (the app's own config dir, e.g. `~/Library/Application
    /// Support/<App>/language` on macOS, `~/.config/<App>/language` on Linux).
    /// swift-testing builds a fresh suite instance per test, so each gets — and
    /// cleans up — its own.
    let configDir: String
    var sut: LocalizationService

    init() {
        configDir = NSTemporaryDirectory() + "tuikit-loc-\(UUID().uuidString)"
        sut = LocalizationService(configDirectoryPath: configDir)
        sut.setLanguage(.english)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: configDir)
    }

    // MARK: - Bundle Loading Tests

    @Test("Loads English translations from bundle")
    func loadEnglishTranslations() {
        let sut = LocalizationService(configDirectoryPath: configDir)
        let englishStrings = sut.string(for: "button.ok")
        #expect(englishStrings == "OK")
    }

    @Test("Loads German translations from bundle")
    func loadGermanTranslations() {
        let sut = LocalizationService(configDirectoryPath: configDir)
        sut.setLanguage(.german)
        let germanStrings = sut.string(for: "button.ok")
        #expect(germanStrings == "OK")
    }

    @Test("Loads French translations from bundle")
    func loadFrenchTranslations() {
        let sut = LocalizationService(configDirectoryPath: configDir)
        sut.setLanguage(.french)
        let frenchStrings = sut.string(for: "button.cancel")
        #expect(frenchStrings == "Annuler")
    }

    @Test("Loads Italian translations from bundle")
    func loadItalianTranslations() {
        let sut = LocalizationService(configDirectoryPath: configDir)
        sut.setLanguage(.italian)
        let italianStrings = sut.string(for: "button.yes")
        #expect(italianStrings == "Sì")
    }

    @Test("Loads Spanish translations from bundle")
    func loadSpanishTranslations() {
        let sut = LocalizationService(configDirectoryPath: configDir)
        sut.setLanguage(.spanish)
        let spanishStrings = sut.string(for: "button.no")
        #expect(spanishStrings == "No")
    }

    // MARK: - String Resolution Tests

    @Test("Resolves dot-notation keys")
    func resolvesDotNotationKeys() {
        let string = sut.string(for: "button.ok")
        #expect(string == "OK")
    }

    @Test("Resolves nested keys")
    func resolvesNestedKeys() {
        let string = sut.string(for: "error.invalid_input")
        #expect(string == "Invalid input")
    }

    @Test("Resolves all key categories")
    func resolvesAllKeyCategories() {
        #expect(sut.string(for: "button.save") == "Save")
        #expect(sut.string(for: "label.name") == "Name")
        #expect(sut.string(for: "error.not_found") == "Not found")
        #expect(sut.string(for: "placeholder.search") == "Search...")
        #expect(sut.string(for: "menu.file") == "File")
        #expect(sut.string(for: "dialog.confirm") == "Confirm")
        #expect(sut.string(for: "validation.email_invalid") == "Invalid email address")
    }

    // MARK: - Fallback Tests

    @Test("Falls back to English when key missing in current language")
    func fallsBackToEnglish() {
        sut.setLanguage(.german)
        let string = sut.string(for: "button.ok")
        #expect(string != "button.ok")
    }

    @Test("Returns key when not found in any language")
    func returnsKeyWhenNotFound() {
        let unknownKey = "nonexistent.key.that.does.not.exist"
        let string = sut.string(for: unknownKey)
        #expect(string == unknownKey)
    }

    @Test("Fallback chain works correctly")
    func fallbackChain() {
        sut.setLanguage(.german)
        let germanString = sut.string(for: "button.ok")
        #expect(germanString == "OK")

        sut.setLanguage(.english)
        let englishString = sut.string(for: "button.ok")
        #expect(englishString == "OK")
        #expect(germanString == englishString)
    }

    // MARK: - Language Switching Tests

    @Test("Switches language successfully")
    func switchesLanguage() {
        sut.setLanguage(.english)
        #expect(sut.currentLanguage == .english)

        sut.setLanguage(.german)
        #expect(sut.currentLanguage == .german)

        sut.setLanguage(.french)
        #expect(sut.currentLanguage == .french)
    }

    @Test("Language property returns current language")
    func languageProperty() {
        sut.setLanguage(.english)
        #expect(sut.currentLanguage == .english)

        sut.setLanguage(.italian)
        #expect(sut.currentLanguage == .italian)
    }

    @Test("Resolves strings after language switch")
    func resolvesStringsAfterSwitch() {
        sut.setLanguage(.english)
        var string = sut.string(for: "button.save")
        #expect(string == "Save")

        sut.setLanguage(.german)
        string = sut.string(for: "button.save")
        #expect(string == "Speichern")

        sut.setLanguage(.french)
        string = sut.string(for: "button.save")
        #expect(string == "Enregistrer")
    }

    // MARK: - Persistence Tests

    @Test("Saves language preference to config file")
    func savesLanguagePreference() throws {
        let tempDir = NSTemporaryDirectory() + "tuikit-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = LocalizationService(configDirectoryPath: tempDir)
        service.setLanguage(.german)

        let path = (tempDir as NSString).appendingPathComponent("language")
        let content = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        #expect(content == "de")
    }

    @Test("Loads language preference from config file")
    func loadsLanguagePreference() throws {
        let tempDir = NSTemporaryDirectory() + "tuikit-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let path = (tempDir as NSString).appendingPathComponent("language")
        try "fr".write(toFile: path, atomically: true, encoding: .utf8)

        let service = LocalizationService(configDirectoryPath: tempDir)
        #expect(service.currentLanguage == .french)
    }

    @Test("Handles missing config file gracefully")
    func handlesMissingConfigFile() {
        let tempDir = NSTemporaryDirectory() + "tuikit-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let service = LocalizationService(configDirectoryPath: tempDir)
        #expect(service.currentLanguage == .english)
    }

    @Test("Handles invalid config file content gracefully")
    func handlesInvalidConfigFile() throws {
        let tempDir = NSTemporaryDirectory() + "tuikit-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let path = (tempDir as NSString).appendingPathComponent("language")
        try "invalid_lang_code".write(toFile: path, atomically: true, encoding: .utf8)

        let service = LocalizationService(configDirectoryPath: tempDir)
        #expect(service.currentLanguage == .english)
    }

    // MARK: - Language Enum Tests

    @Test("Language enum raw values are correct")
    func languageRawValues() {
        #expect(LocalizationService.Language.english.rawValue == "en")
        #expect(LocalizationService.Language.german.rawValue == "de")
        #expect(LocalizationService.Language.french.rawValue == "fr")
        #expect(LocalizationService.Language.italian.rawValue == "it")
        #expect(LocalizationService.Language.spanish.rawValue == "es")
        #expect(LocalizationService.Language.simplifiedChinese.rawValue == "zh")
        #expect(LocalizationService.Language.japanese.rawValue == "ja")
        #expect(LocalizationService.Language.allCases.count == 7)
    }

    @Test("Language enum display names are correct")
    func languageDisplayNames() {
        #expect(LocalizationService.Language.english.displayName == "English")
        #expect(LocalizationService.Language.german.displayName == "Deutsch")
        #expect(LocalizationService.Language.french.displayName == "Français")
        #expect(LocalizationService.Language.italian.displayName == "Italiano")
        #expect(LocalizationService.Language.spanish.displayName == "Español")
        #expect(LocalizationService.Language.simplifiedChinese.displayName == "简体中文")
        #expect(LocalizationService.Language.japanese.displayName == "日本語")
    }

    @Test("Simplified Chinese and Japanese translations resolve")
    func asianLanguageTranslations() {
        sut.setLanguage(.simplifiedChinese)
        #expect(sut.string(for: "button.ok") == "确定")
        #expect(sut.string(for: "button.cancel") == "取消")

        sut.setLanguage(.japanese)
        #expect(sut.string(for: "button.cancel") == "キャンセル")
        #expect(sut.string(for: "menu.file") == "ファイル")
    }

    // MARK: - App-registered translations

    @Test("App-registered translations resolve and override the bundled strings")
    func appRegisteredTranslations() {
        sut.setLanguage(.english)
        sut.register(translations: [
            "en": ["app.title": "Settings", "button.ok": "Okay"],
            "de": ["app.title": "Einstellungen"],
        ])
        // App key resolves.
        #expect(sut.string(for: "app.title") == "Settings")
        // App value overrides the bundled framework string.
        #expect(sut.string(for: "button.ok") == "Okay")

        // The app key resolves in the registered language too.
        sut.setLanguage(.german)
        #expect(sut.string(for: "app.title") == "Einstellungen")
        // German has no app override for button.ok, so the bundled German wins.
        #expect(sut.string(for: "button.ok") == "OK")
    }

    @Test("An unregistered app key falls through to the key itself")
    func unregisteredAppKeyFallsThrough() {
        #expect(sut.string(for: "app.totally.unknown.key") == "app.totally.unknown.key")
    }

    @Test("Language enum is codable")
    func languageIsCodable() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let english = LocalizationService.Language.english
        let encodedEnglish = try? encoder.encode(english)
        let decodedEnglish = try? decoder.decode(LocalizationService.Language.self, from: encodedEnglish ?? Data())
        #expect(decodedEnglish == english)

        let german = LocalizationService.Language.german
        let encodedGerman = try? encoder.encode(german)
        let decodedGerman = try? decoder.decode(LocalizationService.Language.self, from: encodedGerman ?? Data())
        #expect(decodedGerman == german)
    }

    // MARK: - Caching Tests

    @Test("Caches translation dictionaries")
    func cacheTranslations() {
        _ = sut.string(for: "button.ok")

        let string1 = sut.string(for: "button.ok")
        let string2 = sut.string(for: "button.ok")
        #expect(string1 == string2)
    }

    @Test("Cache is per-language")
    func cacheIsPerLanguage() {
        sut.setLanguage(.english)
        let englishString = sut.string(for: "button.save")
        #expect(englishString == "Save")

        sut.setLanguage(.german)
        let germanString = sut.string(for: "button.save")
        #expect(germanString == "Speichern")

        sut.setLanguage(.english)
        let englishAgain = sut.string(for: "button.save")
        #expect(englishAgain == "Save")
    }
}

// MARK: - Localization Key Tests

@Suite("LocalizationKey")
final class LocalizationKeyTests {
    /// Isolated config dir — see `LocalizationServiceTests`; keeps the suite from
    /// reading or writing the user's real language preference.
    let configDir: String
    var service: LocalizationService

    init() {
        configDir = NSTemporaryDirectory() + "tuikit-lockey-\(UUID().uuidString)"
        service = LocalizationService(configDirectoryPath: configDir)
        service.setLanguage(.english)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: configDir)
    }

    @Test("Button keys resolve correctly")
    func buttonKeys() {
        #expect(service.string(for: LocalizationKey.Button.ok) == "OK")
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Cancel")
        #expect(service.string(for: LocalizationKey.Button.save) == "Save")
        #expect(service.string(for: LocalizationKey.Button.delete) == "Delete")
    }

    @Test("Label keys resolve correctly")
    func labelKeys() {
        #expect(service.string(for: LocalizationKey.Label.name) == "Name")
        #expect(service.string(for: LocalizationKey.Label.description) == "Description")
        #expect(service.string(for: LocalizationKey.Label.value) == "Value")
        #expect(service.string(for: LocalizationKey.Label.status) == "Status")
    }

    @Test("Error keys resolve correctly")
    func errorKeys() {
        #expect(service.string(for: LocalizationKey.Error.invalidInput) == "Invalid input")
        #expect(service.string(for: LocalizationKey.Error.notFound) == "Not found")
        #expect(service.string(for: LocalizationKey.Error.accessDenied) == "Access denied")
    }

    @Test("Placeholder keys resolve correctly")
    func placeholderKeys() {
        #expect(service.string(for: LocalizationKey.Placeholder.search) == "Search...")
        #expect(service.string(for: LocalizationKey.Placeholder.enterText) == "Enter text...")
        #expect(service.string(for: LocalizationKey.Placeholder.selectOption) == "Select an option...")
    }

    @Test("Menu keys resolve correctly")
    func menuKeys() {
        #expect(service.string(for: LocalizationKey.Menu.file) == "File")
        #expect(service.string(for: LocalizationKey.Menu.edit) == "Edit")
        #expect(service.string(for: LocalizationKey.Menu.view) == "View")
    }

    @Test("Dialog keys resolve correctly")
    func dialogKeys() {
        #expect(service.string(for: LocalizationKey.Dialog.confirm) == "Confirm")
        #expect(service.string(for: LocalizationKey.Dialog.deleteConfirmation) == "Are you sure you want to delete this?")
        #expect(service.string(for: LocalizationKey.Dialog.success) == "Operation completed successfully")
    }

    @Test("Validation keys resolve correctly")
    func validationKeys() {
        #expect(service.string(for: LocalizationKey.Validation.emailInvalid) == "Invalid email address")
        #expect(service.string(for: LocalizationKey.Validation.passwordTooShort) == "Password must be at least 8 characters")
        #expect(service.string(for: LocalizationKey.Validation.usernameTaken) == "Username already exists")
    }

    @Test("Keys work across all languages")
    func keysAcrossLanguages() {
        service.setLanguage(.german)
        #expect(service.string(for: LocalizationKey.Button.ok) == "OK")

        service.setLanguage(.french)
        #expect(service.string(for: LocalizationKey.Button.cancel) == "Annuler")

        service.setLanguage(.italian)
        #expect(service.string(for: LocalizationKey.Error.notFound) == "Non trovato")
    }

    @Test("Key enum raw values match string keys")
    func keyRawValues() {
        #expect(LocalizationKey.Button.ok.rawValue == "button.ok")
        #expect(LocalizationKey.Error.notFound.rawValue == "error.not_found")
        #expect(LocalizationKey.Label.name.rawValue == "label.name")
    }
}
