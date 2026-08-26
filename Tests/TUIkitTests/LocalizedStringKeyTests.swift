//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedStringKeyTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// `LocalizedStringKey` — SwiftUI's "a string literal is a lookup key" rule.
///
/// Two things are load-bearing and neither is obvious. First, WHICH overload a
/// call binds to: a literal must be a key and a computed `String` must not, or
/// a file path would be looked up as one. Second, the fallback: a key with no
/// translation must come back as itself, because that is what makes adopting
/// this change nothing for an app that ships no translations.
@MainActor
@Suite("LocalizedStringKey")
struct LocalizedStringKeyTests {

    /// A service with its own config directory, so nothing here reads or
    /// writes the developer's real language preference.
    private func isolatedService() -> LocalizationService {
        LocalizationService(
            configDirectoryPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("tuikit-lsk-tests").path)
    }

    // MARK: - Which overload binds

    @Test("A literal is a key; a String variable is content")
    func overloadResolution() {
        // The whole design rests on this, and it is plain overload resolution
        // rather than anything magic: `LocalizedStringKey` is concrete, the
        // String initializer is generic, and Swift prefers concrete for a
        // literal.
        let key: LocalizedStringKey = "some.key"
        #expect(key.key == "some.key")
        #expect(key.arguments.isEmpty)

        // A computed String must never be treated as a key — it could be a
        // file path, a user's name, anything.
        let computed = "some.key"
        #expect(Text(computed).content == "some.key")
        #expect(Text(verbatim: "some.key").content == "some.key")
    }

    @Test("A Substring binds too")
    func substringBinds() {
        // The generic `StringProtocol` overload is what SwiftUI has, and it
        // buys this: slicing no longer needs an explicit String(...).
        let sentence = "hello world"
        let first = sentence.prefix(5)
        #expect(Text(first).content == "hello")
    }

    // MARK: - Lookup and fallback

    @Test("A key with no translation comes back as itself")
    func fallsBackToTheLiteral() {
        // The property that makes this behaviour-preserving: an app that
        // registers nothing sees exactly the literals it wrote.
        let service = isolatedService()
        let key: LocalizedStringKey = "Not a registered key at all"
        #expect(key.resolved(with: service) == "Not a registered key at all")
    }

    @Test("A registered key resolves to its translation")
    func resolvesARegisteredKey() {
        let service = isolatedService()
        service.register(translations: [
            "en": ["test.lsk.greeting": "Good morning"]
        ])
        let key: LocalizedStringKey = "test.lsk.greeting"
        #expect(key.resolved(with: service) == "Good morning")
    }

    @Test("Text runs a literal through the lookup")
    func textLooksUp() {
        // Registration is in-memory and the key is namespaced to this test, so
        // it cannot collide with anything the app or another suite asks for.
        LocalizationService.shared.register(translations: [
            "en": ["test.lsk.textpath": "resolved through the service"]
        ])
        #expect(Text("test.lsk.textpath").content == "resolved through the service")
        // …and the opt-out still opts out.
        #expect(Text(verbatim: "test.lsk.textpath").content == "test.lsk.textpath")
    }

    @Test("A runtime key looks up once it is asked to be one")
    func explicitKeyFromAVariableLooksUp() {
        // The answer to "my key is in a variable, how do I localise it?" — and
        // the reason the String overload's silence is a design and not a gap.
        // Wrapping is the request; without it a `String` is content, because
        // nothing else can tell a key from a user's name. The Theme page demos
        // all four spellings side by side.
        LocalizationService.shared.register(translations: [
            "en": ["test.lsk.runtimekey": "resolved from a variable"]
        ])
        let computed = "test.lsk" + ".runtimekey"
        #expect(Text(computed).content == "test.lsk.runtimekey")
        #expect(Text(LocalizedStringKey(computed)).content == "resolved from a variable")
    }

    // MARK: - Interpolation

    @Test("Interpolation builds one key for every value")
    func interpolationBuildsAKey() {
        // The point of `%@`: one table entry serves every value, so a
        // translator writes the sentence once.
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(key.key == "Moved %@ rows to %@")
        #expect(key.arguments == ["3", "Backlog"])
    }

    @Test("An untranslated interpolation reads as it was written")
    func interpolationFallback() {
        let service = isolatedService()
        let key: LocalizedStringKey = "Moved \(3) rows to \("Backlog")"
        #expect(key.resolved(with: service) == "Moved 3 rows to Backlog")
    }

    @Test("A translation can reorder the values")
    func positionalArguments() {
        // Word order differs between languages; without positions a
        // translation would be stuck with the English order.
        let service = isolatedService()
        service.register(translations: [
            "en": ["test.lsk.order": "%2$@ gained %1$@ rows"]
        ])
        let key = LocalizedStringKey(key: "test.lsk.order", arguments: ["3", "Backlog"])
        #expect(key.resolved(with: service) == "Backlog gained 3 rows")
    }

    @Test("A value can be formatted where it is interpolated")
    func formatStyleInterpolation() {
        let service = isolatedService()
        let key: LocalizedStringKey = "Done: \(0.5, format: .percent)"
        #expect(key.key == "Done: %@")
        #expect(key.resolved(with: service) == "Done: \(0.5.formatted(.percent))")
    }

    // MARK: - Percent signs that are not placeholders

    @Test("A literal with no values is never scanned")
    func percentInAPlainLiteral() {
        // The common case, and the one that would be most annoying to get
        // wrong: `Text("100% done")` says 100% done.
        let service = isolatedService()
        let key: LocalizedStringKey = "100% done"
        #expect(key.arguments.isEmpty)
        #expect(key.resolved(with: service) == "100% done")
    }

    @Test("A stray percent survives alongside a real placeholder")
    func percentBesideAPlaceholder() {
        // Here scanning IS running, so the `%` has to reach the output rather
        // than swallowing the character after it. The KEY carries it escaped,
        // because the key is printf-shaped and `%%` is how that alphabet
        // spells one percent — which is also what a translator writes in a
        // strings file, and what `substituting` has always accepted.
        let service = isolatedService()
        let key: LocalizedStringKey = "\(50)% of the way"
        #expect(key.key == "%@%% of the way")
        #expect(key.resolved(with: service) == "50% of the way")
    }

    @Test("A percent immediately before an interpolation keeps both")
    func percentImmediatelyBeforeAPlaceholder() {
        // The case the escaping exists for. Unescaped, the literal `%` and the
        // following `%@` fused into `%%` + a stray `@`, so the second argument
        // was dropped and an `@` appeared where it should have been.
        let service = isolatedService()
        let key: LocalizedStringKey = "Save \(5)%\("now")"
        #expect(key.key == "Save %@%%%@")
        #expect(key.resolved(with: service) == "Save 5%now")

        // And a literal percent with no interpolation at all is untouched,
        // since nothing scans a key that has no arguments.
        let bare: LocalizedStringKey = "100% done"
        #expect(bare.resolved(with: service) == "100% done")
    }

    @Test("Percent escapes and C conversions a translator might write")
    func substitutionForms() {
        // These go through `substituting` directly: the strings come from
        // translators, not from the interpolation builder, so they can contain
        // anything a strings file can.
        #expect(LocalizedStringKey.substituting(["x"], into: "100%% and %@") == "100% and x")
        #expect(LocalizedStringKey.substituting(["7"], into: "%d items") == "7 items")
        #expect(LocalizedStringKey.substituting(["7"], into: "%lld items") == "7 items")
        #expect(LocalizedStringKey.substituting(["a", "b"], into: "%@%@") == "ab")
        // A position may repeat; the implicit cursor is not advanced by one.
        #expect(LocalizedStringKey.substituting(["a", "b"], into: "%1$@%1$@") == "aa")
        // Missing arguments leave the placeholder empty rather than trapping.
        #expect(LocalizedStringKey.substituting(["a"], into: "%@%@") == "a")
        // A trailing lone percent is emitted, not dropped.
        #expect(LocalizedStringKey.substituting(["a"], into: "%@ 100%") == "a 100%")
        // A WIDTH pads the value and, crucially, still consumes its argument:
        // the old scan rewound onto the digits, emitted %3d verbatim, and
        // delivered the first argument to the SECOND placeholder.
        #expect(LocalizedStringKey.substituting(["2", "10"], into: "Zeile %3d von %d") == "Zeile   2 von 10")
        #expect(LocalizedStringKey.substituting(["ab"], into: "[%-4d]") == "[ab  ]")
        #expect(LocalizedStringKey.substituting(["3.14"], into: "%.2f rad") == "3.14 rad")
    }

    // MARK: - Value semantics

    @Test("Keys compare by key and arguments")
    func equality() {
        // `Text` is `Equatable` and the render memo leans on it, so a key that
        // compared only by its template would serve a stale buffer when only
        // the interpolated value changed.
        let one: LocalizedStringKey = "Rows: \(1)"
        let two: LocalizedStringKey = "Rows: \(2)"
        #expect(one != two)
        #expect(one == LocalizedStringKey(key: "Rows: %@", arguments: ["1"]))
    }
}
