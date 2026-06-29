//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocalizationService.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Localization Service

/// Manages language selection and string localization.
///
/// Loads translations from JSON files, resolves localized strings using
/// dot-notation keys, and persists language preference to disk.
public final class LocalizationService: @unchecked Sendable {
    /// Supported languages
    public enum Language: String, Codable, CaseIterable {
        case english = "en"
        case german = "de"
        case french = "fr"
        case italian = "it"
        case spanish = "es"
        case simplifiedChinese = "zh"
        case japanese = "ja"

        /// Human-readable name (in the language itself).
        public var displayName: String {
            switch self {
            case .english: "English"
            case .german: "Deutsch"
            case .french: "Français"
            case .italian: "Italiano"
            case .spanish: "Español"
            case .simplifiedChinese: "简体中文"
            case .japanese: "日本語"
            }
        }
    }

    /// The shared localization service instance.
    public static let shared = LocalizationService()

    /// Currently active language
    public private(set) var currentLanguage: Language {
        didSet {
            saveLanguagePreference(currentLanguage)
            AppState.shared.setNeedsRender()
        }
    }

    /// Cached translations: [languageCode: [dotPath: localizedString]]
    private var translationCache: [String: [String: String]] = [:]

    /// App-supplied translations: [languageCode: [dotPath: localizedString]],
    /// registered by the host application via ``register(translations:)``. These
    /// are checked before the bundled framework strings, so an app can add its
    /// own keys and override framework defaults.
    private var appTranslations: [String: [String: String]] = [:]

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Optional config directory override for testing.
    private let configDirectoryOverride: String?

    /// Creates and initializes the localization service.
    ///
    /// Loads the stored language preference, falling back to system locale
    /// or English if unavailable.
    public init() {
        self.configDirectoryOverride = nil

        // Compute initial language before assignment to avoid didSet side effects.
        let initial: Language
        if let stored = Self.loadLanguagePreference() {
            initial = stored
        } else if let systemLocale = Self.systemPreferredLanguage() {
            initial = systemLocale
        } else {
            initial = .english
        }
        self.currentLanguage = initial

        // Preload current language translations
        lock.lock()
        _ = _translations(for: currentLanguage)
        lock.unlock()
    }

    /// Creates a localization service with a custom config directory.
    ///
    /// Used for testing to isolate file system access.
    init(configDirectoryPath: String) {
        self.configDirectoryOverride = configDirectoryPath

        let initial: Language
        if let stored = Self.loadLanguagePreference(from: configDirectoryPath) {
            initial = stored
        } else {
            initial = .english
        }
        self.currentLanguage = initial

        lock.lock()
        _ = _translations(for: currentLanguage)
        lock.unlock()
    }

    /// Changes the active language and persists the preference.
    ///
    /// - Parameter language: The new language to activate.
    public func setLanguage(_ language: Language) {
        lock.lock()
        defer { lock.unlock() }
        currentLanguage = language
    }

    /// Registers additional translations supplied by the host application.
    ///
    /// The framework only bundles translations for its own strings; an app uses
    /// this to localize its own UI through the same service. The outer dictionary
    /// is keyed by language code (``Language/rawValue`` — e.g. `"en"`, `"de"`,
    /// `"zh"`); the inner dictionary maps dot-notation keys to localized strings.
    /// Registrations merge across calls and take precedence over the bundled
    /// framework strings for the same key. A re-render is requested so visible
    /// strings refresh.
    ///
    /// ```swift
    /// LocalizationService.shared.register(translations: [
    ///     "en": ["app.title": "Settings"],
    ///     "de": ["app.title": "Einstellungen"],
    /// ])
    /// ```
    ///
    /// - Parameter translations: Language-code-keyed translation tables to add.
    public func register(translations: [String: [String: String]]) {
        lock.lock()
        defer { lock.unlock() }
        for (code, table) in translations {
            appTranslations[code, default: [:]].merge(table) { _, new in new }
        }
        AppState.shared.setNeedsRender()
    }

    /// Resolves a localized string using a dot-notation key.
    ///
    /// Falls back to English if the key is missing in the current language,
    /// then to the key itself if not found in English.
    ///
    /// - Parameter key: Dot-notation path (e.g., "button.ok", "error.invalid_input")
    /// - Returns: The localized string, or the key if not found.
    public func string(for key: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        // Try current language
        if let value = _translationValue(key, in: currentLanguage) {
            return value
        }

        // Fall back to English
        if currentLanguage != .english,
            let value = _translationValue(key, in: .english)
        {
            return value
        }

        // Return key as last resort
        return key
    }

    // MARK: - Private Helpers (caller MUST hold lock)

    /// Gets translations dictionary for a language, loading from JSON if needed.
    ///
    /// - Important: Caller must hold `lock`.
    private func _translations(for language: Language) -> [String: String] {
        let code = language.rawValue

        // Return cached if available
        if let cached = translationCache[code] {
            return cached
        }

        // Load from bundled JSON
        if let loaded = loadTranslationsFromBundle(language: code) {
            translationCache[code] = loaded
            return loaded
        }

        // No translations available, return empty
        return [:]
    }

    /// Retrieves a value from translations using dot-notation path.
    ///
    /// App-registered translations (``register(translations:)``) win over the
    /// bundled framework strings for the same key.
    ///
    /// - Important: Caller must hold `lock`.
    private func _translationValue(_ key: String, in language: Language) -> String? {
        if let appValue = appTranslations[language.rawValue]?[key] {
            return appValue
        }
        return _translations(for: language)[key]
    }

    /// Loads translations from bundled JSON file.
    private func loadTranslationsFromBundle(language: String) -> [String: String]? {
        guard
            let url = Bundle.module.url(
                forResource: language,
                withExtension: "json",
                subdirectory: "translations"
            )
        else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let dict =
                try JSONSerialization.jsonObject(
                    with: data,
                    options: .fragmentsAllowed
                ) as? [String: String]
            return dict
        } catch {
            return nil
        }
    }

    /// Returns the system-preferred language if supported.
    private static func systemPreferredLanguage() -> Language? {
        let preferredLanguages = NSLocale.preferredLanguages
        for langCode in preferredLanguages {
            let base = langCode.prefix(2).lowercased()
            if let language = Language(rawValue: base) {
                return language
            }
        }
        return nil
    }

    /// Loads stored language preference from the default config file.
    private static func loadLanguagePreference() -> Language? {
        loadLanguagePreference(from: defaultConfigDirectoryPath())
    }

    /// Loads stored language preference from a specific config directory.
    private static func loadLanguagePreference(from configDirectory: String) -> Language? {
        let path = (configDirectory as NSString).appendingPathComponent("language")
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return Language(rawValue: content)
        } catch {
            return nil
        }
    }

    /// Saves language preference to config file.
    private func saveLanguagePreference(_ language: Language) {
        let path = configFilePath()
        let dirPath = (path as NSString).deletingLastPathComponent

        // Create directory if needed
        do {
            try FileManager.default.createDirectory(
                atPath: dirPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            // Ignore creation errors, will fail on write anyway
        }

        // Write language code
        do {
            try language.rawValue.write(
                toFile: path,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Silently fail if write unsuccessful
        }
    }

    /// Returns the config file path, using override if set.
    private func configFilePath() -> String {
        let dir = configDirectoryOverride ?? Self.defaultConfigDirectoryPath()
        return (dir as NSString).appendingPathComponent("language")
    }

    /// The default config directory for the language preference.
    ///
    /// This is the app-specific, platform-idiomatic directory shared with
    /// `@AppStorage` (see `appConfigDirectory()`): `~/Library/Application
    /// Support/<App>` on macOS, `$XDG_CONFIG_HOME/<App>` (else `~/.config/<App>`)
    /// elsewhere. Per-app, so the language preference lives alongside the app's
    /// other settings and no longer leaks between TUIkit apps.
    static func defaultConfigDirectoryPath() -> String {
        appConfigDirectory().path
    }
}
