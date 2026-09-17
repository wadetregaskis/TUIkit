//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationExtensionsTests.swift
//
//  `LocalizationExtensions.swift` was 0% covered — all four of its functions.
//  The one with a contract worth losing is ``Appearance/localizedName``, whose
//  fallback branch is spelled `localized == key` because
//  `LocalizationService.string(for:)` returns the key when nothing matches.
//  That is a fact about ANOTHER type, and nothing tied the two together: change
//  `string(for:)` to return `""` (or a `⟨missing⟩` marker) for an unknown key —
//  a reasonable-looking diagnostic improvement — and every app-registered
//  appearance silently shows an empty name.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Localization extensions")
struct LocalizationExtensionsTests {

    /// A namespaced appearance id the framework does not bundle a key for —
    /// standing in for one an app added.
    private static let customID = Appearance.ID(rawValue: "test-custom-appearance")

    private func custom(_ id: Appearance.ID) -> Appearance {
        Appearance(id: id, borderStyle: .rounded)
    }

    private func rendered(_ view: some View) -> String {
        renderToBuffer(view, context: makeBareRenderContext(width: 40, height: 4))
            .lines.map(\.stripped).joined()
    }

    // MARK: - Text(localized:)

    @Test("Text(localized:) resolves the key through the service")
    func textLocalizedResolvesKey() {
        #expect(rendered(Text(localized: "button.ok")) == "OK")
    }

    @Test("Text(localized:) shows the key itself when nothing matches")
    func textLocalizedFallsBackToKey() {
        // Same last-resort as `string(for:)`: a missing key is visible in the
        // UI rather than blank, which is how a missing translation gets noticed.
        #expect(rendered(Text(localized: "test.no.such.key")) == "test.no.such.key")
    }

    // MARK: - AppState language forwarding

    @Test("AppState language accessors forward to the shared service")
    func appStateForwardsLanguage() throws {
        let appState = AppState()

        #expect(appState.currentLanguage == LocalizationService.shared.currentLanguage)

        // Deliberately set the language it ALREADY has. `setLanguage` is a
        // forward to the shared, process-wide service, and swift-testing runs
        // this suite in parallel with others that assert English strings — so
        // actually switching languages here would flake them. Re-setting the
        // current value still executes the forward, which is the whole body.
        //
        // The forward also PERSISTS, which that reasoning missed: the shared
        // service writes to the config directory named after the running
        // process, so this test wrote `~/Library/Application Support/
        // swiftpm-testing-helper/language` — a real file in the developer's own
        // home, which outlives the run and is then read back as the stored
        // preference, ahead of the environment, by every later one. So the
        // write goes to a directory of this test's own, and that it landed
        // there is asserted: nothing covered the persisting half of this path.
        let directory = NSTemporaryDirectory() + "tuikit-loc-forward-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let current = appState.currentLanguage
        LocalizationService.shared.withPersistence(redirectedTo: directory) {
            appState.setLanguage(current)
        }

        #expect(appState.currentLanguage == current)
        #expect(LocalizationService.shared.currentLanguage == current)
        let written = (directory as NSString).appendingPathComponent("language")
        let stored = try String(contentsOfFile: written, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stored == current.rawValue, "the forward persisted \(stored), not \(current.rawValue)")
    }

    // MARK: - Appearance.localizedName

    /// `doubleLine` is the discriminating case: `name` capitalises the raw id to
    /// "Doubleline", while the bundled English string is "Double line". Any
    /// built-in whose two spellings coincide (Rounded, Line, Heavy) cannot tell
    /// a lookup from the fallback.
    @Test("A built-in appearance's localizedName comes from the table, not from name")
    func builtInAppearanceIsLookedUp() {
        #expect(Appearance.doubleLine.name == "Doubleline")
        #expect(
            Appearance.doubleLine.localizedName
                == LocalizationService.shared.string(for: "appearance.doubleLine"))
        #expect(
            Appearance.doubleLine.localizedName != Appearance.doubleLine.name,
            "a fallback to `name` would read 'Doubleline'")
    }

    @Test("Every bundled appearance resolves to a real string, never to its key")
    func everyBundledAppearanceHasAKey() {
        for appearance in AppearanceRegistry.all {
            #expect(appearance.localizedName != "appearance.\(appearance.rawId.rawValue)")
            #expect(!appearance.localizedName.isEmpty)
        }
    }

    @Test("An app's own appearance with no key falls back to name")
    func unknownAppearanceFallsBackToName() {
        let appearance = custom(Self.customID)

        #expect(appearance.localizedName == appearance.name)
        #expect(appearance.localizedName != "appearance.\(Self.customID.rawValue)")
    }

    @Test("An app that registers a key for its own appearance gets it")
    func registeredAppearanceIsLookedUp() {
        let id = Appearance.ID(rawValue: "test-registered-appearance")
        LocalizationService.shared.register(translations: [
            "en": ["appearance.\(id.rawValue)": "Registered!"]
        ])

        #expect(custom(id).localizedName == "Registered!")
        #expect(custom(id).localizedName != custom(id).name)
    }
}
