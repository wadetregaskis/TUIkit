//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContentUnavailableView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Content Unavailable View

/// A view that displays a placeholder when content is unavailable.
///
/// Use `ContentUnavailableView` to communicate that the current view has
/// no content to display. Common use cases include empty search results,
/// empty lists, and error states.
///
/// The view arranges a label, an optional description, and optional actions
/// vertically, centered in the available space.
///
/// ## Examples
///
/// ```swift
/// // Simple text label
/// ContentUnavailableView("No Items")
///
/// // With description
/// ContentUnavailableView("No Items", description: "Add items to get started.")
///
/// // Full ViewBuilder API
/// ContentUnavailableView {
///     Text("No Results")
/// } description: {
///     Text("Try a different search term.")
/// } actions: {
///     Button("Clear Search") { }
/// }
///
/// // Search preset
/// ContentUnavailableView.search
/// ContentUnavailableView.search(text: "query")
/// ```
public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    /// The label view (typically a title or icon).
    let label: Label

    /// The description view (typically explanatory text).
    let description: Description

    /// The action views (typically buttons).
    let actions: Actions

    /// Creates a content unavailable view with label, description, and actions.
    ///
    /// - Parameters:
    ///   - label: The primary label view.
    ///   - description: The description view below the label.
    ///   - actions: The action views below the description.
    public init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public var body: some View {
        _ContentUnavailableViewCore(
            label: label,
            description: description,
            actions: actions
        )
    }
}

// MARK: - Convenience Initializers

extension ContentUnavailableView where Description == EmptyView, Actions == EmptyView {
    /// Creates a content unavailable view with only a label.
    ///
    /// - Parameter label: The primary label view.
    public init(@ViewBuilder label: () -> Label) {
        self.init(label: label, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Actions == EmptyView {
    /// Creates a content unavailable view with a label and description.
    ///
    /// - Parameters:
    ///   - label: The primary label view.
    ///   - description: The description view below the label.
    public init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description
    ) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Label == Text, Description == EmptyView, Actions == EmptyView {
    /// Creates a content unavailable view with a title string.
    ///
    /// - Parameter title: The title text.
    public init(_ title: String) {
        self.init(label: { Text(title) }, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Label == Text, Description == Text, Actions == EmptyView {
    /// Creates a content unavailable view with a title and description string.
    ///
    /// - Parameters:
    ///   - title: The title text.
    ///   - description: The description text.
    public init(_ title: String, description: String) {
        self.init(label: { Text(title) }, description: { Text(description) }, actions: { EmptyView() })
    }
}

// MARK: - Search Preset

extension ContentUnavailableView where Label == Text, Description == Text, Actions == EmptyView {
    /// A content unavailable view for empty search results.
    ///
    /// Displays "No Results" with a generic description.
    public static var search: ContentUnavailableView<Text, Text, EmptyView> {
        ContentUnavailableView<Text, Text, EmptyView>(
            label: { Text("No Results") },
            description: { Text("Check the spelling or try a new search.") },
            actions: { EmptyView() }
        )
    }

    /// Creates a content unavailable view for empty search results with a query.
    ///
    /// Displays "No Results for '\(text)'" with a generic description.
    ///
    /// - Parameter text: The search query that produced no results.
    /// - Returns: A configured content unavailable view.
    public static func search(text: String) -> ContentUnavailableView<Text, Text, EmptyView> {
        ContentUnavailableView<Text, Text, EmptyView>(
            label: { Text("No Results for '\(text)'") },
            description: { Text("Check the spelling or try a new search.") },
            actions: { EmptyView() }
        )
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of ContentUnavailableView.
///
/// Renders label, description, and actions as a vertically stacked layout,
/// centered horizontally in the available width.
private struct _ContentUnavailableViewCore<Label: View, Description: View, Actions: View>: View, Renderable {
    let label: Label
    let description: Description
    let actions: Actions

    var body: Never {
        fatalError("_ContentUnavailableViewCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette

        // Render label
        let labelBuffer = TUIkit.renderToBuffer(label, context: context)

        // Render description with secondary foreground color
        var descContext = context
        if descContext.environment.foregroundStyle == nil {
            descContext.environment.foregroundStyle = palette.foregroundSecondary
        }
        let descBuffer = TUIkit.renderToBuffer(description, context: descContext)

        // Render actions
        let actionsBuffer = TUIkit.renderToBuffer(actions, context: context)

        // Combine vertically with spacing
        var result = FrameBuffer()

        // A *visually blank* part (e.g. ContentUnavailableView("") whose label
        // is a Text("") that padded itself to spaces) is dropped, not just a
        // zero-length one — otherwise it would reserve an empty row.
        if !labelBuffer.isBlank {
            result.appendVertically(labelBuffer)
        }

        if !descBuffer.isBlank {
            result.appendVertically(descBuffer, spacing: 1)
        }

        if !actionsBuffer.isBlank {
            result.appendVertically(actionsBuffer, spacing: 1)
        }

        // Centre the assembled buffer as one block, applying a
        // single uniform horizontal shift to every line.
        //
        // The previous implementation centred each line
        // independently using its own visible width. That looked
        // marginally nicer when label / description / actions had
        // very different widths, but it made the inner content's
        // hit-test regions (typically on the action Buttons)
        // impossible to shift correctly — `replacingLines` can
        // only carry a single uniform shift, and per-line shifts
        // would leave the action buttons' regions pointing at
        // their pre-centre column positions, so clicks would land
        // a few cells off the actual buttons.
        //
        // Block centring relative to result.width keeps every
        // line's offset consistent, so the buttons' regions stay
        // accurate after shifting. Visually it means shorter
        // lines (e.g. the title) are left-aligned within the
        // bounding box of the widest line rather than individually
        // centred.
        guard !result.isEmpty else { return result }

        let targetWidth = context.availableWidth
        let leftPad = max(0, (targetWidth - result.width) / 2)
        let padding = String(repeating: " ", count: leftPad)
        let centeredLines = result.lines.map { padding + $0 }

        return result.replacingLines(centeredLines, overlayShiftX: leftPad)
    }
}
