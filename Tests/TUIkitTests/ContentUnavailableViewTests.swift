//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentUnavailableViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("ContentUnavailableView Tests", .rendersEnglishUI)
struct ContentUnavailableViewTests {

    @Test("Full init renders label, description, and actions")
    func fullInit() {
        let view = ContentUnavailableView {
            Text("Title")
        } description: {
            Text("Description text")
        } actions: {
            Text("[Action]")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("Title"))
        #expect(content.contains("Description text"))
        #expect(content.contains("[Action]"))
    }

    @Test("Label-only init renders just the label")
    func labelOnly() {
        let view = ContentUnavailableView {
            Text("Only Label")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("Only Label"))
    }

    @Test("String convenience init renders title text")
    func stringInit() {
        let view = ContentUnavailableView("Empty State")
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("Empty State"))
    }

    @Test("String with description init renders both")
    func stringWithDescription() {
        let view = ContentUnavailableView("No Items", description: "Add items to get started.")
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("No Items"))
        #expect(content.contains("Add items to get started."))
    }

    @Test("Search preset renders 'No Results' text")
    func searchPreset() {
        let view = ContentUnavailableView<Text, Text, EmptyView>.search
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("No Results"))
        #expect(content.contains("Check the spelling"))
    }

    @Test("Search with text renders query in title")
    func searchWithText() {
        let view = ContentUnavailableView<Text, Text, EmptyView>.search(text: "swift")
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("No Results for 'swift'"))
    }

    /// The two tests above pin the ENGLISH words, which is what a reader wants
    /// to see and is also what a re-hardcoded literal would still satisfy. This
    /// one pins where they come from: the preset's prose is the framework's, so
    /// it must be read out of the table rather than written in the source, or a
    /// translated app shows English inside an otherwise translated screen.
    ///
    /// Every assertion here is one that can actually fail, which took two
    /// attempts to get right and is the part worth reading. "The view contains
    /// `service.string(for: .noResults)`" looks like a localization check and
    /// is a tautology: the view is BUILT from that call, so when the entry is
    /// missing both sides degrade to the dotted key together and it passes.
    /// Mutation-tested — deleting `label.noResults` from en.json is caught by
    /// `searchPreset` above, which pins the English words, and was not caught
    /// by that spelling at all.
    ///
    /// So the lookup-agreement assertions are gone, and what is left is the
    /// three properties the English-words tests cannot see: that a table entry
    /// exists at all rather than echoing its key, that the query placeholder
    /// survives into every language, and that substitution actually runs.
    @Test("The search preset's prose comes from the translation table")
    func searchPresetIsLocalized() {
        let service = LocalizationService.shared

        // Not the key echoed back — that is what a missing entry looks like.
        for key in [
            LocalizationKey.Label.noResults, .noResultsFor, .noResultsHint,
        ] {
            #expect(service.string(for: key) != key.rawValue, "no entry for \(key.rawValue)")
        }

        // Every language must keep the `%@`, or the query vanishes rather than
        // merely landing in the wrong place.
        for language in LocalizationService.Language.allCases {
            let isolated = LocalizationService(
                configDirectoryPath: NSTemporaryDirectory() + "tuikit-cuv-\(UUID().uuidString)")
            isolated.setLanguage(language)
            #expect(
                isolated.string(for: LocalizationKey.Label.noResultsFor).contains("%@"),
                "\(language.rawValue) dropped the query placeholder")
        }

        // …and substitution runs, so neither the placeholder nor the query is
        // left behind on screen.
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let queried = renderToBuffer(
            ContentUnavailableView<Text, Text, EmptyView>.search(text: "swift"), context: context
        ).lines.joined()
        #expect(queried.contains("swift"), "the query must reach the screen")
        #expect(!queried.contains("%@"), "the placeholder must not")
    }

    @Test("Label and description init renders both sections")
    func labelAndDescription() {
        let view = ContentUnavailableView {
            Text("Header")
        } description: {
            Text("Subtext")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        let content = buffer.lines.joined()
        #expect(content.contains("Header"))
        #expect(content.contains("Subtext"))
    }

    @Test("Content is centered horizontally")
    func horizontalCentering() {
        let view = ContentUnavailableView("Centered")
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        #expect(!buffer.isEmpty)
        // The line should have leading spaces for centering
        if let firstLine = buffer.lines.first {
            let stripped = firstLine.stripped
            let leadingSpaces = stripped.prefix(while: { $0 == " " }).count
            // "Centered" is 8 chars in 80-wide terminal → ~36 leading spaces
            #expect(leadingSpaces > 0)
        }
    }

    @Test("Full init with all sections produces multiple lines")
    func multipleLinesSections() {
        let view = ContentUnavailableView {
            Text("Label")
        } description: {
            Text("Desc")
        } actions: {
            Text("Act")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        // Label + spacing + description + spacing + actions = at least 5 lines
        #expect(buffer.height >= 5)
    }
}
