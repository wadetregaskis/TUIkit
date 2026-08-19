//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LabeledContent.swift
//
//  Created by LAYERED.work
//  License: MIT

// `FormatStyle` is Foundation's, for the `value:format:` rows — the same
// modern-Foundation dependency `Text(_:format:)` already carries.
import Foundation

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
        //
        // The leftover goes to the CONTENT, not to a spacer beside it. A
        // `Spacer` is width-flexible and so is a `TextField`, and the stack
        // distributes to flexible children evenly — so a labelled field came
        // out with half the line spent on the gap in front of it. A flexible
        // frame gives the content the whole remainder and aligns a fixed-width
        // content (the `value:` overloads' `Text`) at its trailing edge, which
        // is where the spacer used to put it.
        HStack(spacing: 1) {
            label
            content.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - String-titled convenience

extension LabeledContent where Label == Text {
    /// Creates labelled content with a localized title and custom content.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title shown as the label.
    ///   - content: A view builder producing the content.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(titleKey.localized, content: content)
    }

    /// Creates labelled content with a string title, shown as written.
    ///
    /// - Parameters:
    ///   - title: The title shown as the label.
    ///   - content: A view builder producing the content.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.label = Text(String(title))
        self.content = content()
    }
}

extension LabeledContent where Label == Text, Content == Text {
    /// Creates labelled content with a localized title and a string value.
    ///
    /// Only the title is a key. `value` is the thing being labelled — a
    /// setting's current state, a file's size, someone's name — so it is shown
    /// as written, which is SwiftUI's split too.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title shown as the label.
    ///   - value: The value shown as the content.
    public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) {
        self.init(titleKey.localized, value: value)
    }

    /// Creates labelled content with a string title, shown as written.
    ///
    /// - Parameters:
    ///   - title: The title shown as the label.
    ///   - value: The value shown as the content.
    @_disfavoredOverload
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {
        self.label = Text(String(title))
        self.content = Text(String(value))
    }

    /// Creates labelled content whose value is formatted by a format style.
    ///
    /// ```swift
    /// LabeledContent("row.downloaded", value: bytes, format: .byteCount(style: .file))
    /// LabeledContent("row.progress", value: fraction, format: .percent)
    /// ```
    ///
    /// The value is the thing being labelled, so it is never a lookup key — a
    /// format style is how a *number* becomes text a reader can take in, and
    /// the style carries its own locale. This is ``Text/init(_:format:)``'s
    /// rule applied to a form row, and it saves the row from interpolating a
    /// string by hand, which is how a form ends up with `0.4285714285714286`
    /// in it.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title shown as the label.
    ///   - value: The value shown as the content.
    ///   - format: A format style that converts `value` into a `String`.
    public init<F: FormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: F.FormatInput,
        format: F
    ) where F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(titleKey.localized, value: value, format: format)
    }

    /// Creates labelled content with a title shown as written and a formatted
    /// value.
    ///
    /// - Parameters:
    ///   - title: The title shown as the label.
    ///   - value: The value shown as the content.
    ///   - format: A format style that converts `value` into a `String`.
    @_disfavoredOverload
    public init<S: StringProtocol, F: FormatStyle>(
        _ title: S,
        value: F.FormatInput,
        format: F
    ) where F.FormatInput: Equatable, F.FormatOutput == String {
        self.label = Text(String(title))
        self.content = Text(value, format: format)
    }
}
