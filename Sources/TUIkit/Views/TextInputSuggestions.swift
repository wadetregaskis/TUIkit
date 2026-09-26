//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextInputSuggestions.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Suggestion Entries

/// A single entry contributed to a text field's input-suggestions menu.
enum _TextSuggestionEntry {
    /// A pickable suggestion. `completion` is the text inserted into the
    /// field when it is picked; `nil` derives it from the label's rendered
    /// text at render time (the common `Text("…")` case).
    case option(completion: String?, label: AnyView)

    /// A rule separating suggestion groups (a ``Divider`` in the builder).
    case divider
}

// MARK: - Suggestion Extraction

/// A protocol for views that can contribute entries to
/// ``View/textInputSuggestions(_:)``.
///
/// This mirrors the `PickerOptionProvider` pattern: rather than reflecting
/// over the view tree, each view type that may appear inside a suggestions
/// builder declares how to surface its entries. Views that don't conform
/// (arbitrary containers, images, …) contribute nothing — a suggestion is a
/// `Text`, any view wrapped in ``View/textInputCompletion(_:)``, or a
/// ``Divider``.
@MainActor
protocol TextSuggestionProvider {
    /// Extracts the suggestion entries contained in this view.
    func textSuggestions() -> [_TextSuggestionEntry]
}

extension Text: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        // The completion is derived from the rendered label (its plain
        // string content) when the field builds the menu.
        [.option(completion: nil, label: AnyView(self))]
    }
}

extension Divider: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        [.divider]
    }
}

extension EmptyView: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        []
    }
}

extension TupleView: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        var result: [_TextSuggestionEntry] = []
        func collect<Child: View>(_ view: Child) {
            if let provider = view as? TextSuggestionProvider {
                result.append(contentsOf: provider.textSuggestions())
            }
        }
        repeat collect(each children)
        return result
    }
}

extension ForEach: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        data.flatMap { element -> [_TextSuggestionEntry] in
            if let provider = content(element) as? TextSuggestionProvider {
                return provider.textSuggestions()
            }
            return []
        }
    }
}

extension ConditionalView: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        switch self {
        case .trueContent(let content):
            (content as? TextSuggestionProvider)?.textSuggestions() ?? []
        case .falseContent(let content):
            (content as? TextSuggestionProvider)?.textSuggestions() ?? []
        }
    }
}

extension Optional: TextSuggestionProvider where Wrapped: View {
    func textSuggestions() -> [_TextSuggestionEntry] {
        self.flatMap { ($0 as? TextSuggestionProvider)?.textSuggestions() } ?? []
    }
}

// MARK: - Explicit Completions

/// A view that associates an explicit completion string with its content,
/// for use inside ``View/textInputSuggestions(_:)``.
///
/// - Important: Framework infrastructure. Created by
///   ``View/textInputCompletion(_:)``; do not instantiate directly.
public struct _TextCompletionView<Content: View>: View {
    /// The text inserted into the field when this suggestion is picked.
    let completion: String

    /// The suggestion's label view.
    let content: Content

    public var body: some View {
        content
    }
}

extension _TextCompletionView: TextSuggestionProvider {
    func textSuggestions() -> [_TextSuggestionEntry] {
        [.option(completion: completion, label: AnyView(content))]
    }
}

extension View {
    /// Associates a fully formed completion string with this view when it is
    /// used as a text input suggestion.
    ///
    /// Without this modifier a suggestion's completion is the plain text of
    /// its label; use it when the label decorates or abbreviates the value:
    ///
    /// ```swift
    /// TextField("Ramp", text: $ramp)
    ///     .textInputSuggestions {
    ///         Label("Blocks", systemImage: "square.fill")
    ///             .textInputCompletion("▏▎▍▌▋▊▉")
    ///     }
    /// ```
    ///
    /// - Parameter completion: The text inserted into the field when this
    ///   suggestion is picked.
    /// - Returns: A view carrying the completion for the suggestions menu.
    public func textInputCompletion(_ completion: String) -> some View {
        _TextCompletionView(completion: completion, content: self)
    }
}

// MARK: - Environment

/// What a `.textInputSuggestions` or `.searchSuggestions` above offers: the
/// entries, and whether such a modifier is in force at all — one can be,
/// offering nothing this frame, because its builder filtered everything out.
///
/// Compared by presence and emptiness alone — see `==`.
struct TextSuggestions: Equatable {
    /// The normalized entries, in menu order.
    let entries: [_TextSuggestionEntry]

    /// Whether a suggestions modifier put these here, as opposed to the key's
    /// default.
    let isPresent: Bool

    /// No suggestions modifier in force.
    static let none = Self(entries: [], isPresent: false)

    /// What a suggestions modifier offers.
    static func offering(_ entries: [_TextSuggestionEntry]) -> Self {
        Self(entries: entries, isPresent: true)
    }

    /// Equal when both are present or both are not, and both are empty or
    /// both are not — never by what the entries say.
    ///
    /// An environment value that cannot be compared turns off every memo
    /// beneath it, and the entries cannot be: a label is an `AnyView`, and a
    /// completion is read off the label's RENDERED text. So a List under
    /// `.searchSuggestions` drew every row afresh on every frame. Comparing by
    /// content would be worse — suggestions are rebuilt as the query is typed,
    /// so every keystroke would clear everything below.
    ///
    /// This is enough because the one reader of the entries, a text field
    /// (`TextFieldSuggestions.prepare`), declares a render side effect whenever
    /// suggestions are present, so no memo that holds such a field ever stores
    /// — it re-renders, and re-syncs its handler, as it always did. Any other
    /// memo below holds no reader, so it cannot draw differently for different
    /// entries. The emptiness term is a margin on top: the `▾` a field draws
    /// depends on it, and should a reader ever skip the declaration, a change
    /// of emptiness still clears.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPresent == rhs.isPresent && lhs.entries.isEmpty == rhs.entries.isEmpty
    }
}

/// Environment key carrying the extracted suggestion entries down to the
/// text fields in the modified subtree.
private struct TextInputSuggestionsKey: EnvironmentKey {
    static let defaultValue = TextSuggestions.none
}

extension EnvironmentValues {
    /// The input suggestions available to text fields in this subtree.
    /// Set via ``View/textInputSuggestions(_:)``.
    var textInputSuggestions: TextSuggestions {
        get { self[TextInputSuggestionsKey.self] }
        set { self[TextInputSuggestionsKey.self] = newValue }
    }
}

// MARK: - The Modifier

extension View {
    /// Presents a drop-down menu of input suggestions beneath any
    /// ``TextField`` in this view's subtree while it is focused — the
    /// combo-box pattern: a field that accepts free text *and* offers a menu
    /// of pre-defined or recent values.
    ///
    /// Suggestions are `Text` views (their string is the completion), any
    /// view wrapped in ``View/textInputCompletion(_:)`` (an explicit
    /// completion), and ``Divider``s separating groups:
    ///
    /// ```swift
    /// TextField("City", text: $city)
    ///     .textInputSuggestions {
    ///         ForEach(favouriteCities, id: \.self) { Text($0) }
    ///         if !recentCities.isEmpty {
    ///             Divider()
    ///             ForEach(recentCities, id: \.self) { Text($0) }
    ///         }
    ///     }
    /// ```
    ///
    /// The builder is re-evaluated on every render, so filtering the
    /// suggestions against the field's current text is just a matter of
    /// filtering the data you build them from.
    ///
    /// ## Interaction
    ///
    /// The menu opens ON DEMAND, never just because the field gained focus:
    /// press Down at the caret, or click the `▾` disclosure at the field's
    /// trailing edge (clicking it again — or Escape — closes). Typing keeps
    /// editing the field and leaves the menu's open state alone; Down then
    /// walks the menu (Up from the first row returns to the caret); Enter
    /// picks the highlighted suggestion — filling the field and firing
    /// ``TextField/onSubmit(_:)``, the combo-box convention — while Enter
    /// with no highlight submits as usual and closes the menu. Clicking a
    /// row picks it; the wheel scrolls a long menu. The menu never outlives
    /// the field's focus.
    ///
    /// - Parameter suggestions: A view builder of suggestion entries.
    /// - Returns: A view whose text fields offer the suggestions.
    public func textInputSuggestions<S: View>(
        @ViewBuilder _ suggestions: () -> S
    ) -> some View {
        environment(
            \.textInputSuggestions, .offering(extractTextSuggestions(suggestions())))
    }

    /// Presents input suggestions built from a collection of identifiable
    /// data. See ``View/textInputSuggestions(_:)``.
    ///
    /// - Parameters:
    ///   - suggestions: The data to build suggestions from.
    ///   - content: A view builder producing each element's suggestion.
    /// - Returns: A view whose text fields offer the suggestions.
    public func textInputSuggestions<Data: RandomAccessCollection, Content: View>(
        _ suggestions: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Identifiable {
        environment(
            \.textInputSuggestions,
            .offering(extractTextSuggestions(ForEach(suggestions, content: content))))
    }

    /// Presents input suggestions built from a collection of data, identified
    /// by a key path. See ``View/textInputSuggestions(_:)``.
    ///
    /// - Parameters:
    ///   - suggestions: The data to build suggestions from.
    ///   - id: The key path to each element's identity.
    ///   - content: A view builder producing each element's suggestion.
    /// - Returns: A view whose text fields offer the suggestions.
    public func textInputSuggestions<
        Data: RandomAccessCollection, ID: Hashable, Content: View
    >(
        _ suggestions: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View {
        environment(
            \.textInputSuggestions,
            .offering(extractTextSuggestions(ForEach(suggestions, id: id, content: content))))
    }
}

/// Extracts and normalizes the suggestion entries from a builder's view tree:
/// adjacent and edge dividers are collapsed so conditional groups never leave
/// a stray rule in the menu.
@MainActor
func extractTextSuggestions<S: View>(_ view: S) -> [_TextSuggestionEntry] {
    guard let provider = view as? TextSuggestionProvider else { return [] }
    return DropdownMenu.normalizedEntries(provider.textSuggestions()) { entry in
        if case .divider = entry { return true }
        return false
    }
}

// MARK: - The Field's Menu

/// The render-pass half of a text field's suggestions menu: builds the
/// ``DropdownMenu`` rows from the environment's entries, syncs the field
/// handler's completion list, and attaches the open popup as an overlay.
/// ``TextField``'s core calls this; the keyboard half lives on
/// ``TextFieldHandler``.
@MainActor
enum TextFieldSuggestions {
    /// The prepared menu model for one render pass.
    struct Menu {
        /// The drop-down's entries, in display order.
        let entries: [DropdownMenu.Entry]

        /// Whether the popup is showing this frame (focused, not dismissed,
        /// at least one option).
        let isOpen: Bool
    }

    /// Builds the menu model and syncs the handler's completions/highlight.
    /// Returns `nil` when there are no suggestions, or the field is disabled.
    ///
    /// Reads the entries itself, because reading them obliges it to declare: a
    /// field under a suggestions modifier syncs handler state from labels it
    /// renders on every pass, and nothing in any memo's key sees them — the
    /// environment value compares by presence and emptiness alone
    /// (``TextSuggestions``). So the field makes every memo that holds it
    /// decline, whenever a modifier is present, empty or not and disabled or
    /// not, and a served buffer can never stand in for a render that would
    /// have changed its completions.
    static func prepare(
        isDisabled: Bool,
        handler: TextFieldHandler,
        currentText: String,
        isFocused: Bool,
        context: RenderContext
    ) -> Menu? {
        let suggestions = context.environment.textInputSuggestions
        if suggestions.isPresent {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
        }
        // A disabled field leaves its handler alone, as it always has.
        guard !isDisabled else { return nil }
        let entries = suggestions.entries
        guard !entries.isEmpty else {
            // No suggestions this frame — make sure stale completions don't
            // leave the handler intercepting Down/Enter.
            handler.suggestionCompletions = []
            handler.suggestionHighlight = nil
            return nil
        }
        // Labels render at the SCREEN width, not the field's: the pop-up is
        // an overlay that may grow wider than its control, so a narrow field
        // must not wrap/truncate its option labels.
        var labelContext = context.withAvailableWidth(
            max(context.availableWidth, context.environment.terminalWidth))
        // Every label renders at the field's own identity, so two labels'
        // memos would share one entry and one environment slot. The entries
        // being uncomparable used to keep them all from storing; this keeps
        // them so now that the value compares.
        labelContext.environment.hasUncomparableEnvironmentValue = true
        labelContext.leaveScrollCanvas()

        // The drop-down's own model — the same one the `Picker` builds, so the
        // marker column, the width and the pointer handling are one
        // implementation rather than two that drift.
        var menuEntries: [DropdownMenu.Entry] = []
        var completions: [String] = []
        for entry in entries {
            switch entry {
            case .divider:
                menuEntries.append(.divider)
            case .option(let explicit, let label):
                let rendered = label.renderToBuffer(context: labelContext).lines.first ?? ""
                let completion = explicit ?? rendered.stripped
                // The option whose completion is the field's current text is
                // the "selected" one: the field's value IS the selection.
                menuEntries.append(
                    .option(label: rendered, isSelected: completion == currentText))
                completions.append(completion)
            }
        }

        handler.suggestionCompletions = completions
        // The suggestions are rebuilt every frame (that is how filtering them
        // against the field's text works), so the highlight has to be told what
        // survived.
        handler.suggestionHighlighting.adopt(count: completions.count)
        // Captured at render so a Shift-accelerated Up/Down in the open pop-up
        // can jump at event time, when the environment is out of reach.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier

        let isOpen = isFocused && handler.suggestionsOpen && !completions.isEmpty
        if isOpen, !context.isMeasuring {
            // The menu's Escape (close) takes precedence over any page-level
            // ESC handler while open — surface that in the status bar, as the
            // picker's drop-down does.
            context.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(
                    for: LocalizationKey.StatusBar.closeSuggestions)
        }
        return Menu(entries: menuEntries, isOpen: isOpen)
    }

    /// Renders the open popup and attaches it to the field's buffer as an
    /// overlay anchored one row beneath the field — through the same
    /// ``DropdownMenu`` assembly the `Picker` uses, so the two menus sit on one
    /// grid, size themselves by one rule and answer the pointer identically.
    static func attach(
        menu: Menu,
        to buffer: inout FrameBuffer,
        handler: TextFieldHandler,
        context: RenderContext
    ) {
        DropdownMenu.attach(
            DropdownMenu.OptionMenu(
                entries: menu.entries,
                highlightedOption: handler.suggestionHighlight,
                scroll: handler.suggestionScroll,
                followHighlight: handler.suggestionHighlighting.consumeFollowPending(),
                autoRepeatToken: "textfield-suggestions-\(context.identity.path)"),
            to: &buffer,
            context: context,
            // The pointer is already looking at the row it is over, so a hover
            // moves the highlight without asking the window to scroll.
            onHover: { ordinal in handler.suggestionHighlighting.point(at: ordinal) },
            onActivate: { ordinal in handler.acceptSuggestion(at: ordinal) },
            onDismiss: { handler.suggestionsOpen = false })
    }
}
