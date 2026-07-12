//  🖥️ TUIKit — Terminal UI Kit for Swift
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

/// Environment key carrying the extracted suggestion entries down to the
/// text fields in the modified subtree.
private struct TextInputSuggestionsKey: EnvironmentKey {
    static let defaultValue: [_TextSuggestionEntry] = []
}

extension EnvironmentValues {
    /// The input suggestions available to text fields in this subtree.
    /// Set via ``View/textInputSuggestions(_:)``.
    var textInputSuggestions: [_TextSuggestionEntry] {
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
            \.textInputSuggestions, extractTextSuggestions(suggestions()))
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
            extractTextSuggestions(ForEach(suggestions, content: content)))
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
            extractTextSuggestions(ForEach(suggestions, id: id, content: content)))
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
        /// The drop-down rows (options carry their rendered content).
        let rows: [DropdownMenu.Row]

        /// The row index of each option, in option order.
        let optionRowIndices: [Int]

        /// The widest option label, for sizing the popup.
        let maxLabelWidth: Int

        /// Whether the popup is showing this frame (focused, not dismissed,
        /// at least one option).
        let isOpen: Bool
    }

    /// Builds the menu model and syncs the handler's completions/highlight.
    /// Returns `nil` when there are no suggestions.
    static func prepare(
        entries: [_TextSuggestionEntry],
        handler: TextFieldHandler,
        currentText: String,
        isFocused: Bool,
        context: RenderContext
    ) -> Menu? {
        guard !entries.isEmpty else {
            // No suggestions this frame — make sure stale completions don't
            // leave the handler intercepting Down/Enter.
            handler.suggestionCompletions = []
            handler.suggestionHighlight = nil
            return nil
        }
        let palette = context.environment.palette

        var rows: [DropdownMenu.Row] = []
        var completions: [String] = []
        var optionRowIndices: [Int] = []
        var maxLabelWidth = 0
        for entry in entries {
            switch entry {
            case .divider:
                rows.append(.divider)
            case .option(let explicit, let label):
                let rendered = label.renderToBuffer(context: context).lines.first ?? ""
                let completion = explicit ?? rendered.stripped
                // The row whose completion is the field's current text gets
                // the ✓ marker — the field's value is "selected".
                let marker =
                    completion == currentText
                    ? ANSIRenderer.colorize(
                        DropdownMenu.selectedMarker, foreground: palette.accent)
                    : " "
                optionRowIndices.append(rows.count)
                rows.append(.option(" " + marker + " " + rendered))
                completions.append(completion)
                maxLabelWidth = max(maxLabelWidth, rendered.strippedLength)
            }
        }

        handler.suggestionCompletions = completions
        if let highlight = handler.suggestionHighlight, highlight >= completions.count {
            handler.suggestionHighlight = completions.isEmpty ? nil : completions.count - 1
        }

        let isOpen = isFocused && handler.suggestionsOpen && !optionRowIndices.isEmpty
        if isOpen, !context.isMeasuring {
            // The menu's Escape (close) takes precedence over any page-level
            // ESC handler while open — surface that in the status bar, as the
            // picker's drop-down does.
            context.environment.statusBar.escapeLabelOverride = "close suggestions"
        }
        return Menu(
            rows: rows,
            optionRowIndices: optionRowIndices,
            maxLabelWidth: maxLabelWidth,
            isOpen: isOpen)
    }

    /// Renders the open popup and attaches it to the field's buffer as an
    /// overlay anchored one row beneath the field.
    static func attach(
        menu: Menu,
        to buffer: inout FrameBuffer,
        handler: TextFieldHandler,
        context: RenderContext
    ) {
        // Same width recipe as the picker's drop-down: marker column + label
        // + padding, plus a gap column when the scrollbar takes the rightmost
        // interior column; clamped to the space the field actually has.
        let wantsBar = DropdownMenu.wantsScrollbar(
            rowCount: menu.rows.count, context: context)
        let desiredInner = menu.maxLabelWidth + 4 + (wantsBar ? 1 : 0)
        let innerWidth = max(6, min(desiredInner, max(6, context.availableWidth - 2)))

        let highlightedRow = handler.suggestionHighlight.flatMap { ordinal in
            menu.optionRowIndices.indices.contains(ordinal)
                ? menu.optionRowIndices[ordinal] : nil
        }
        let ordinalByRow = Dictionary(
            uniqueKeysWithValues: menu.optionRowIndices.enumerated().map { ($1, $0) })

        let followHighlight = handler.suggestionFollowPending
        handler.suggestionFollowPending = false

        let popupBuffer = DropdownMenu.popup(
            DropdownMenu.Configuration(
                rows: menu.rows,
                highlightedRow: highlightedRow,
                innerWidth: innerWidth,
                scroll: handler.suggestionScroll,
                followHighlight: followHighlight,
                autoRepeatToken: "textfield-suggestions-\(context.identity.path)"),
            context: context,
            onHover: { row in
                guard let ordinal = ordinalByRow[row] else { return }
                handler.suggestionHighlight = ordinal
            },
            onActivate: { row in
                guard let ordinal = ordinalByRow[row] else { return }
                handler.acceptSuggestion(at: ordinal)
            }
        )
        buffer.overlays.append(
            OverlayLayer(
                offsetX: 0,
                offsetY: 1,
                content: popupBuffer,
                level: .popover,
                anchorHeight: 1
            )
        )
    }
}
