//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedRenderGuardTests.swift
//
//  The suites that assert the framework's own words now pin English
//  (`RendersEnglishUI.swift`), which is what makes this package runnable for a
//  developer whose locale is not English — and which would also let a UI that
//  had stopped translating altogether look perfectly healthy. Every one of
//  those assertions would still pass.
//
//  This is the case that would not. It renders a real view against a service
//  in German and expects German out, WITHOUT touching the process language:
//  the service is built with `init(configDirectoryPath:)`, which never reads
//  the environment, and handed to one subtree through the environment. So it
//  proves the translated path is live while the rest of the suite holds the
//  process in English — the two are not in tension, which is the whole point.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("A translated UI still renders translated", .rendersEnglishUI)
struct LocalizedRenderGuardTests {

    /// The key is the one an empty `List` and `Table` show, so it is a string
    /// this framework really does put on screen, and its German differs from
    /// its English in every character.
    private static let key = LocalizationKey.Label.noItems.rawValue

    private func render(_ view: some View) -> String {
        renderToBuffer(view, context: makeBareRenderContext(width: 30, height: 3))
            .lines.joined().stripped
    }

    @Test("A subtree given a German service draws German")
    func germanSubtreeRendersGerman() {
        // Its own service, its own directory, and a language set without
        // persisting or asking for a re-render: nothing here is visible to a
        // concurrently running test.
        let directory = NSTemporaryDirectory() + "tuikit-render-guard-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let german = LocalizationService(configDirectoryPath: directory)
        german.pinLanguageForTesting(.german)

        let rendered = render(
            LocalizedString(Self.key).environment(\.localizationService, german))

        #expect(
            rendered.contains("Keine Einträge"),
            "the German table entry reaches the screen: '\(rendered)'")
        // The two ways this can go wrong, told apart. English means the view
        // went back to reading the shared service; the bare key means the
        // German table lost the entry and the English fallback did too.
        #expect(!rendered.contains("No items"), "not the shared service's language: '\(rendered)'")
        #expect(!rendered.contains(Self.key), "not the un-resolved key: '\(rendered)'")
    }

    @Test("The same view with no override draws the app's own language")
    func defaultSubtreeRendersTheAppLanguage() {
        // The control, and the half that keeps the guard honest: the default
        // must still be the shared service, or the paragraph above is true of
        // a view nothing uses.
        let rendered = render(LocalizedString(Self.key))
        #expect(rendered.contains("No items"), "the shared service still decides: '\(rendered)'")
    }
}
