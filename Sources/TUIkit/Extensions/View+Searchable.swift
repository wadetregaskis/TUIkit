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

    /// The bare `⌕` (U+2315 telephone recorder) is drawn tiny and thin-lined by
    /// Terminal.app, so it reads as noise beside the field rather than a search
    /// affordance. On terminals that render emoji chrome legibly we use the bold
    /// 🔍 magnifier instead; elsewhere we draw no icon at all and let the "Search"
    /// prompt carry the meaning (a mis-drawn glyph is worse than none).
    @Environment(\.supportsEmojiChrome) private var supportsEmojiChrome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                if supportsEmojiChrome {
                    Text("\u{1F50D}")
                }
                // Scope ONLY the query field to the `.search` submit role, so a
                // Return here fires `.onSubmit(of: .search)` — not `.onSubmit(of:
                // .text)`, and a plain text field in `content` (a sibling) still
                // consumes `.text`.
                TextField("", text: text, prompt: prompt ?? Text("Search"))
                    .environment(\.submitTriggerRole, .search)
            }
            content
        }
    }
}
