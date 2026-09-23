//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Searchable.swift
//
//  Created by LAYERED.work
//  License: MIT

extension View {
    /// Marks this view as searchable, presenting a search field bound to `text`.
    ///
    /// Mirrors SwiftUI's `searchable(text:placement:prompt:)`. As in SwiftUI, the
    /// framework only surfaces the field and writes the binding — **filtering is
    /// the app's job**: observe `text` and filter your own content.
    ///
    /// ```swift
    /// List(results) { Text($0.name) }
    ///     .searchable(text: $query)   // you filter `results` by `query`
    /// ```
    ///
    /// - Note: A terminal has no navigation toolbar to float a search field into,
    ///   so `placement` is accepted for source compatibility but the field always
    ///   renders at the top of the searchable subtree.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit in the search field.
    ///   - placement: The preferred placement (inert in a terminal — see the note).
    ///   - prompt: A `Text` to display when the search field is empty.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        _ = placement
        return SearchableModifier(content: self, text: text, prompt: prompt)
    }

    /// Marks this view as searchable, with a localized prompt.
    ///
    /// A string **literal** binds here, so the prompt is a lookup key — see
    /// ``LocalizedStringKey``.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, placement: placement, prompt: Text(prompt))
    }

    /// Marks this view as searchable, with a prompt displayed as written.
    @_disfavoredOverload
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: some StringProtocol
    ) -> some View {
        searchable(text: text, placement: placement, prompt: Text(String(prompt)))
    }
}

// MARK: - Suggestions

extension View {
    /// Offers a menu of suggestions under the search field of an enclosing
    /// ``View/searchable(text:placement:prompt:)-(_,_,LocalizedStringKey)``.
    ///
    /// Mirrors SwiftUI's `searchSuggestions(_:)`, and is written where SwiftUI
    /// writes it — outside the `searchable`, which is what scopes it to the
    /// search field rather than to every text field in the content:
    ///
    /// ```swift
    /// List(matches) { Text($0.name) }
    ///     .searchable(text: $query)
    ///     .searchSuggestions {
    ///         ForEach(recentQueries, id: \.self) { Text($0) }
    ///         Divider()
    ///         Text("everything").searchCompletion("*")
    ///     }
    /// ```
    ///
    /// A suggestion is a `Text` (its string is what the field is filled with),
    /// any view carrying a ``View/searchCompletion(_:)``, or a ``Divider``
    /// between groups — the same vocabulary
    /// ``View/textInputSuggestions(_:)`` accepts, because it is the same menu
    /// underneath. The builder is re-evaluated every render, so filtering the
    /// suggestions against the current query is a matter of filtering the data
    /// you build them from.
    ///
    /// The menu opens on demand rather than on focus — Down at the caret, or a
    /// click on the `▾` at the field's trailing edge — and Return on a
    /// highlighted row fills the field and submits, so
    /// `.onSubmit(of: .search)` fires. See ``View/textInputSuggestions(_:)``
    /// for the interaction in full.
    ///
    /// - Parameter suggestions: A view builder of suggestion entries.
    /// - Returns: A view whose enclosed search field offers the suggestions.
    public func searchSuggestions<S: View>(
        @ViewBuilder _ suggestions: () -> S
    ) -> some View {
        environment(\.searchSuggestions, .offering(extractTextSuggestions(suggestions())))
    }

    /// Associates a completed query with this view when it is used as a search
    /// suggestion — SwiftUI's `searchCompletion(_:)`.
    ///
    /// Without it, choosing a suggestion puts its label's plain text in the
    /// field; use this where the label decorates or abbreviates what should
    /// actually be searched for.
    ///
    /// ```swift
    /// Label("Everything", systemImage: "asterisk").searchCompletion("*")
    /// ```
    ///
    /// It is ``View/textInputCompletion(_:)`` under a second name, which is
    /// SwiftUI's own arrangement: two menus, one for a search field and one for
    /// any text field, each with a spelling that reads right at its call site,
    /// and one mechanism beneath both.
    ///
    /// - Parameter completion: The text the field is filled with when this
    ///   suggestion is chosen.
    /// - Returns: A view carrying the completion for the suggestions menu.
    public func searchCompletion(_ completion: String) -> some View {
        textInputCompletion(completion)
    }
}

/// Environment key carrying suggestions down to the enclosed search field.
///
/// Separate from ``EnvironmentValues/textInputSuggestions`` because the two
/// differ in WHO they are for: that one reaches every ``TextField`` in the
/// subtree, this one only the field ``SearchableModifier`` draws. Sharing the
/// key would make `.searchSuggestions` silently arm any text field the caller
/// happens to have in their content.
private struct SearchSuggestionsKey: EnvironmentKey {
    static let defaultValue = TextSuggestions.none
}

extension EnvironmentValues {
    /// Suggestions for the enclosing search field. Set via
    /// ``View/searchSuggestions(_:)``.
    var searchSuggestions: TextSuggestions {
        get { self[SearchSuggestionsKey.self] }
        set { self[SearchSuggestionsKey.self] = newValue }
    }
}

/// Composes a search field above the searchable content. Pure composition — no
/// `_*Core`, no overlay, no focus machinery (Box.swift is the reference model).
struct SearchableModifier<Content: View>: View {
    let content: Content
    let text: Binding<String>
    let prompt: Text?

    /// Whether the field holds focus — the value ``EnvironmentValues/isSearching``
    /// publishes to `content`.
    ///
    /// State rather than a focus query, because the field's focus ID is
    /// generated from its own render identity and nothing out here knows it.
    /// `onEditingChanged` is precisely the focus transition (``TextFieldHandler``
    /// fires it from `onFocusReceived`/`onFocusLost`), so the state tracks
    /// focus rather than approximating it.
    @State private var isSearching = false

    /// What ending this search does, handed to the content — see
    /// ``SearchDismissal``.
    @State private var dismissal = SearchDismissal()

    /// Taken out of the environment here, in the body, because the closure
    /// below runs during event dispatch — outside any render, where an
    /// `@Environment` read is nil.
    @Environment(\.focusManager) private var focusManager

    /// The bare `⌕` (U+2315 telephone recorder) is drawn tiny and thin-lined by
    /// Terminal.app, so it reads as noise beside the field rather than a search
    /// affordance. On terminals that render emoji chrome legibly we use a bold
    /// magnifier instead; elsewhere we draw no icon at all and let the "Search"
    /// prompt carry the meaning (a mis-drawn glyph is worse than none).
    @Environment(\.supportsEmojiChrome) private var supportsEmojiChrome

    /// Which side the icon sits on — and therefore which magnifier it is.
    @Environment(\.searchFieldIconPlacement) private var iconPlacement

    /// What ``View/searchSuggestions(_:)`` above us offered, on its way to the
    /// query field alone.
    @Environment(\.searchSuggestions) private var suggestions

    /// The magnifier that faces the field from `iconPlacement`'s side: 🔎 is
    /// RIGHT-pointing so it looks rightward into a trailing field, 🔍 is
    /// LEFT-pointing so it looks leftward into a leading one. (The Unicode
    /// names read backwards from the rendered shape at a glance — U+1F50E
    /// RIGHT-POINTING is the one whose lens sits on the right.)
    private var icon: Text {
        Text(iconPlacement == .leading ? "\u{1F50E}" : "\u{1F50D}")
    }

    var body: some View {
        // Refreshed on every evaluation, so the action the content was handed
        // — perhaps frames ago, and served from a memo since — ends the search
        // as it stands now.
        dismissal.text = text
        dismissal.focusManager = focusManager
        dismissal.isSearching = isSearching
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                if supportsEmojiChrome, iconPlacement == .leading {
                    icon
                }
                // Scope ONLY the query field to the `.search` submit role, so a
                // Return here fires `.onSubmit(of: .search)` — not `.onSubmit(of:
                // .text)`, and a plain text field in `content` (a sibling) still
                // consumes `.text`.
                queryField
                    .environment(\.submitTriggerRole, .search)
                if supportsEmojiChrome, iconPlacement == .trailing {
                    icon
                }
            }
            // Both values reach the CONTENT only, which is where SwiftUI puts
            // them: they answer questions about the field, and the field is the
            // framework's, not the caller's.
            content
                .environment(\.isSearching, isSearching)
                .environment(\.searchDismissal, dismissal)
        }
    }

    /// The query field, carrying whatever `.searchSuggestions` offered.
    ///
    /// The hand-off is what scopes the suggestions: they arrive on an
    /// environment key of their own and are turned into the general
    /// text-field key HERE, on this one field, so a `TextField` the caller has
    /// in `content` is not armed by a modifier that never mentioned it.
    ///
    /// Left alone when there are none, rather than written as an empty list:
    /// a `.textInputSuggestions` set above the whole searchable is a
    /// deliberate statement about every field in it, and clearing it here
    /// would make the search field the one exception.
    @ViewBuilder
    private var queryField: some View {
        // The fallback prompt is the framework's word, not the caller's, so it
        // comes from the table. `Text(verbatim:)` because the lookup has
        // already happened — see `ContentUnavailableView.search`.
        let defaultPrompt = Text(
            verbatim: LocalizationService.shared.string(for: LocalizationKey.Label.search))
        let field = TextField("", text: text, prompt: prompt ?? defaultPrompt)
            .onEditingChanged { isSearching = $0 }
        if suggestions.entries.isEmpty {
            field
        } else {
            field.environment(\.textInputSuggestions, suggestions)
        }
    }
}
