//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LabeledContent.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - LabeledContent

/// A control for labelling a piece of content — a label paired with a value or
/// an arbitrary view.
///
/// Mirrors SwiftUI's `LabeledContent`. It is the row primitive of ``Form``: a
/// columns form right-aligns every `LabeledContent` label to a shared pillar and
/// left-aligns the content after it (the classic macOS form layout).
///
/// ```swift
/// Form {
///     LabeledContent("Name") { TextField("", text: $name) }
///     LabeledContent("Version", value: "1.0.3")
/// }
/// ```
///
/// Used on its own (outside a form), it lays the label out on the leading edge
/// and the content on the trailing edge of the available width.
public struct LabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    /// Creates labelled content with a custom label and content.
    ///
    /// - Parameters:
    ///   - content: A view builder producing the content (a value or control).
    ///   - label: A view builder producing the label.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        // Standalone layout (outside a Form): label leading, content trailing.
        // Inside a Form, the form lays the label/content out itself (pillar
        // alignment) and this body is not used.
        HStack(spacing: 1) {
            label
            Spacer(minLength: 1)
            content
        }
    }
}

// MARK: - String-titled convenience

extension LabeledContent where Label == Text {
    /// Creates labelled content with a string title and custom content.
    ///
    /// - Parameters:
    ///   - title: The title shown as the label.
    ///   - content: A view builder producing the content.
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.label = Text(String(title))
        self.content = content()
    }
}

extension LabeledContent where Label == Text, Content == Text {
    /// Creates labelled content with a string title and a string value.
    ///
    /// - Parameters:
    ///   - title: The title shown as the label.
    ///   - value: The value shown as the content.
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {
        self.label = Text(String(title))
        self.content = Text(String(value))
    }
}
