//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollIndicatorLocaleTests.swift
//
//  Numbers rendered into scroll chrome ("N more above/below") must be
//  locale-formatted — grouped with the app language's thousands separator
//  ("12,000" en, "12.000" de, "12 000" fr) — not a bare "12000".
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("scroll indicator number localisation")
struct ScrollIndicatorLocaleTests {

    @Test("localizedInteger groups by locale")
    func groupsByLocale() {
        #expect(localizedInteger(12000, locale: Locale(identifier: "en")) == "12,000")
        #expect(localizedInteger(12000, locale: Locale(identifier: "de")) == "12.000")
        // fr uses a narrow no-break space (U+202F/U+00A0) — assert it's neither
        // a comma nor a dot, and that the digits survive.
        let fr = localizedInteger(12000, locale: Locale(identifier: "fr"))
        #expect(fr.filter(\.isNumber) == "12000")
        #expect(!fr.contains(","), "fr does not group with a comma: \(fr)")
        #expect(!fr.contains("."), "fr does not group with a dot: \(fr)")
        // Small numbers are ungrouped everywhere.
        #expect(localizedInteger(42, locale: Locale(identifier: "en")) == "42")
    }

    @Test("The indicator label carries the grouped count")
    func indicatorLabelGrouped() {
        let en = renderScrollIndicator(
            direction: .down, count: 12000, unit: .lines, width: 40,
            palette: EnvironmentValues().palette, locale: Locale(identifier: "en"))
        #expect(en.stripped.contains("12,000"), "en grouping in the label: \(en.stripped)")

        let de = renderScrollIndicator(
            direction: .down, count: 12000, unit: .lines, width: 40,
            palette: EnvironmentValues().palette, locale: Locale(identifier: "de"))
        #expect(de.stripped.contains("12.000"), "de grouping in the label: \(de.stripped)")
    }

    @Test("The approximate label localises its decimal separator")
    func approximateDecimalLocalised() {
        // 5400 → "~5.4K" (en) / "~5,4K" (de).
        #expect(approximateCountLabel(5400, locale: Locale(identifier: "en")) == "~5.4K")
        #expect(approximateCountLabel(5400, locale: Locale(identifier: "de")) == "~5,4K")
    }

    @Test("A List renders its 'N more' count grouped (default locale)")
    func listIndicatorGrouped() {
        // 3000 items in a short frame → a "N more below" indicator whose count
        // is in the thousands, so grouping is observable. The default app
        // language is English, so a comma is expected.
        struct Item: Identifiable { let id: Int }
        let tuiContext = TUIContext()
        let view = List(
            (0..<3000).map(Item.init), selection: Binding<Int?>.constant(nil)
        ) { item in Text("row \(item.id)") }
        .frame(height: 6)

        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 6,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        let text = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        // English default → the thousands count is grouped with a comma and
        // never appears as a bare four-plus-digit run.
        #expect(text.contains(","), "the count is grouped: \(text)")
        #expect(!text.contains("2999"), "no un-grouped 4-digit count leaks: \(text)")
    }
}
