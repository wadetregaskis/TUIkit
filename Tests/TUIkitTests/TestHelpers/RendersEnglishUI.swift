//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RendersEnglishUI.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Declares that a suite's assertions read the framework's OWN words back out
/// of a rendered buffer — "No items", "dismiss", "Done", "No Results" — and so
/// depend on the language `LocalizationService.shared` is in.
///
/// That language comes from the environment: `LANGUAGE` / `LC_ALL` /
/// `LC_MESSAGES` / `LANG`, deliberately and on every platform (it fixed a real
/// Linux bug — see `LocalizationService.systemPreferredLanguage`). Nothing was
/// wrong with the framework; the assertions were wrong to assume English. A
/// developer whose POSIX locale is German could not run this suite at all:
/// measured at 51 issues across 34 tests in 23 files, 52 under Japanese, and
/// **no single locale shows all of them** — `"Information".contains("Info")` is
/// true, so `label.info` passes under de/fr/es while German is on screen.
///
/// The trait is applied per suite rather than set once for the whole target
/// **so the dependency is visible where the assertions are**: a suite that
/// pins English words says so in its declaration.
///
/// # Why a one-way pin, and not save-and-restore
///
/// swift-testing runs suites concurrently **inside one process**, so
/// `LocalizationService.shared` is shared with every test running at the same
/// moment. "Set the language for the duration of this test, then put it back"
/// would open a window during which an unrelated test renders in a language it
/// never asked for — which is the defect this trait exists to prevent (a
/// `setenv("LC_ALL", "ja_JP.UTF-8")` in one test latched Japanese for whole
/// processes; measured 15 failures in 15 runs). So the pin is a latch: English
/// goes on before the suite's tests run and nothing takes it off.
///
/// # What it does not cost
///
/// Nothing in this package tests another language THROUGH the shared service:
/// every language-specific suite builds its own with
/// `LocalizationService(configDirectoryPath:)`, which never consults the
/// environment, and every `register(translations:)` call on the shared service
/// registers an `"en"` table. The pin therefore changes the behaviour of no
/// other test. Coverage of a translated UI is `LocalizedRenderGuardTests`,
/// which renders German through an injected service and is not affected by
/// the process language at all.
struct RendersEnglishUI: SuiteTrait, TestTrait, TestScoping {
    /// Explicit because `Trait` and `SuiteTrait` each provide a default for a
    /// `TestScoping` conformer and a type that is both would inherit neither
    /// unambiguously. Scoping every test as well as the suite costs one
    /// uncontended lock acquisition and makes the trait behave the same
    /// wherever it is written.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? { self }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        LocalizationService.shared.pinLanguageForTesting(.english)
        try await function()
    }
}

extension Trait where Self == RendersEnglishUI {
    /// This suite asserts on the framework's English UI strings; pin them.
    static var rendersEnglishUI: Self { Self() }
}
