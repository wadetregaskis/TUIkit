//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// Marks this view as searchable, with a string prompt.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: some StringProtocol
    ) -> some View {
        searchable(text: text, placement: placement, prompt: Text(String(prompt)))
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

    /// The magnifier that faces the field from `iconPlacement`'s side: 🔎 is
    /// RIGHT-pointing so it looks rightward into a trailing field, 🔍 is
    /// LEFT-pointing so it looks leftward into a leading one. (The Unicode
    /// names read backwards from the rendered shape at a glance — U+1F50E
    /// RIGHT-POINTING is the one whose lens sits on the right.)
    private var icon: Text {
        Text(iconPlacement == .leading ? "\u{1F50E}" : "\u{1F50D}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                if supportsEmojiChrome, iconPlacement == .leading {
                    icon
                }
                // Scope ONLY the query field to the `.search` submit role, so a
                // Return here fires `.onSubmit(of: .search)` — not `.onSubmit(of:
                // .text)`, and a plain text field in `content` (a sibling) still
                // consumes `.text`.
                TextField("", text: text, prompt: prompt ?? Text("Search"))
                    .onEditingChanged { isSearching = $0 }
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
                .environment(\.dismissSearch, dismissAction)
        }
    }

    /// Ending the search: empty the query, and give the keyboard back.
    ///
    /// The focus move is conditional because the action is callable from
    /// anywhere in the content — a Clear button in a results list is the
    /// canonical shape — and moving focus off a control the user is actually
    /// using would be a bug, not a dismissal. Focus goes to the *next*
    /// focusable, which is the content: the field is drawn above it, so this is
    /// the same step Tab would take out of the field.
    private var dismissAction: DismissSearchAction {
        let text = text
        let focusManager = focusManager
        let wasSearching = isSearching
        return DismissSearchAction {
            text.wrappedValue = ""
            if wasSearching { focusManager?.focusNext() }
        }
    }
}
