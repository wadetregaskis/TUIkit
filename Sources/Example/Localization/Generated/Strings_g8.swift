//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Strings_g8.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Translation fragment for the SwiftUI-compatibility (§4a) demo additions:
//  Text(_:format:), \.locale, .focusable, .searchable, and EditMode/EditButton.
//  English is the source of truth; every other language falls back to English
//  (then the key) for any key not present, so only "en" needs entries here.

// swiftlint:disable line_length

extension ExampleStrings {
    static let g8: [String: [String: String]] = [
        "en": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Formatted Values · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) renders a value through a Foundation FormatStyle (percent, number, currency).",
            "page.textStyles.section.locale": "Locale · \\.locale",
            "page.textStyles.localeExplain": "The same number, re-formatted by overriding .environment(\\.locale, …) — note the grouping separators.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Focusable views · .focusable()",
            "page.focus.focusableExplain": "Any view becomes a Tab stop with .focusable(); @FocusState then binds to it via .focused(). Tab to the item below — it shows (focused) while it holds focus.",
            "page.focus.focusableUnfocused": "Focusable",
            "page.focus.focusableFocused": "Focusable (focused)",

            // .searchable (Lists page)
            "page.list.searchableSection": "Searchable",
            "page.list.searchableExplain": "A .searchable field filters the list (filtering is app-driven).",
            "page.list.searchableEmpty": "No matches",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · bindings into an @Observable",
            "page.state.bindableDescription": "@Bindable derives a Binding into a mutable property of an @Observable object you already own.",
            "page.state.bindableName": "Name",
            "page.state.bindableSubscribed": "Subscribed",
            "page.state.bindableLive": "Live model",
            "page.state.idSection": ".id() · identity reset",
            "page.state.idDescription": "Changing a view's .id() gives it a fresh identity, so its own @State resets. Increment the counter, then press Reset.",
            "page.state.idCount": "Count",
            "page.state.idHint": "← its own @State",
            "page.state.idReset": "Reset (bump .id)",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "An action sheet: vertically-stacked buttons, the cancel role sorted last, Escape to dismiss.",
            "page.overlays.confirm.trigger": "Delete item…",
            "page.overlays.confirm.result": "Choice",
            "page.overlays.confirm.title": "Delete this item?",
            "page.overlays.confirm.message": "This action cannot be undone.",
            "page.overlays.confirm.delete": "Delete",
            "page.overlays.confirm.cancel": "Cancel",
            "page.overlays.confirm.deleted": "deleted",
            "page.overlays.confirm.cancelled": "cancelled",
        ]
    ]
}

// swiftlint:enable line_length
