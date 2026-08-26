//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldValue.swift
//
//  `TextField("Quantity", value: $count, format: .number)` — a field bound to a
//  typed value rather than to a `String`.
//
//  The whole difficulty is the draft. A field cannot format on every keystroke:
//  the moment you type "1" into a `.currency` field, formatting it would put
//  the cursor behind "$1.00" and the next character would land somewhere
//  nobody asked for. Nor can it parse on every keystroke: "1." and "-" and ""
//  are all things you must be allowed to have typed on the way to a number,
//  and none of them parses.
//
//  So the field holds the text as typed for exactly as long as it is being
//  typed, and reconciles at the two moments the user has said they are
//  finished: Return, and leaving the field. Parsing failure is not an error to
//  report — there is nowhere to report it — it simply leaves the value alone,
//  and clearing the draft makes the field snap back to what the value actually
//  is. That is also what makes a successful commit visible: type `1e3` into a
//  `.number` field and it becomes `1,000`, because the draft is gone and the
//  value is being formatted again.
//
//  This is SwiftUI's behaviour, and it is the part an app would otherwise have
//  to write by hand — a `@State` string, a `Binding` that reads one and writes
//  the other, and two commit points — which is why the initializer earns its
//  place rather than being a spelling of something already easy.
//
//  Created by Wade Tregaskis
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore
import TUIkitView

// MARK: - The value bridge

/// The two operations a value-editing field needs, closed over the binding and
/// the format style at construction so ``TextField`` itself stays non-generic
/// over the value type.
///
/// - Important: Framework infrastructure. Created by
///   ``TextField/init(value:format:prompt:label:)``.
struct _FieldValueFormatting {
    /// The bound value, formatted for display.
    let display: () -> String

    /// Parses `text` and stores the result. Text that does not parse is
    /// discarded — deliberately silently; see the file note.
    let commit: (String) -> Void

    init<F: ParseableFormatStyle>(value: Binding<F.FormatInput>, format: F)
    where F.FormatOutput == String {
        display = { format.format(value.wrappedValue) }
        commit = { text in
            guard let parsed = try? format.parseStrategy.parse(text) else { return }
            value.wrappedValue = parsed
        }
    }
}

// MARK: - The bridging view

/// Holds the draft string and hands an ordinary ``TextField`` a binding to it.
///
/// It exists as a view — rather than as extra state inside `_TextFieldCore` —
/// because `@State` is bound by the *view's own identity* at render time, which
/// is exactly the lifetime the draft needs: it survives the frame-by-frame
/// rebuilding of the tree, and it dies with the field. Everything below it is
/// the plain string-editing field, unchanged and unaware.
///
/// - Important: Framework infrastructure, reached through
///   ``TextField/init(value:format:prompt:label:)``.
struct _FormattedFieldBody<Label: View>: View {
    let formatting: _FieldValueFormatting
    let prompt: Text?
    let label: Label
    let focusID: String?
    let isDisabled: Bool
    let onSubmitAction: (() -> Void)?
    let onEditingChangedAction: ((Bool) -> Void)?

    /// The text as typed, for as long as it is being typed. `nil` means the
    /// field is not mid-edit and is showing the value, formatted.
    @State private var draft: String?

    var body: some View {
        let field = TextField(text: draftBinding, prompt: prompt) { label }
            .disabled(isDisabled)
            .onSubmit {
                commit()
                onSubmitAction?()
            }
            .onEditingChanged { isEditing in
                // Leaving the field is a commit point exactly as Return is —
                // a value the user typed and then tabbed away from was still
                // typed. `TextFieldHandler.onFocusLost` is what delivers this.
                if !isEditing { commit() }
                onEditingChangedAction?(isEditing)
            }
        // Only override the auto-generated identity when the app asked to.
        return focusID.map { field.focusID($0) } ?? field
    }

    /// Reads the draft if there is one and the formatted value if there is
    /// not; writing always starts (or continues) a draft.
    private var draftBinding: Binding<String> {
        Binding(
            get: { draft ?? formatting.display() },
            set: { draft = $0 })
    }

    /// Applies the draft to the value and drops it, so display returns to the
    /// value. A no-op when there is no draft — committing an untouched field
    /// must not write to the binding.
    private func commit() {
        guard let draft else { return }
        formatting.commit(draft)
        self.draft = nil
    }
}

// MARK: - Initializers

extension TextField where Label == Text {
    /// Creates a text field that edits a value through a format style, with a
    /// localized label.
    ///
    /// ```swift
    /// @State private var quantity = 1
    /// @State private var price = Decimal(9.99)
    ///
    /// TextField("field.quantity", value: $quantity, format: .number)
    /// TextField("field.price", value: $price, format: .currency(code: "USD"))
    /// ```
    ///
    /// The field shows the formatted value, edits plain text while it has
    /// focus, and writes the value back when the user presses Return or leaves
    /// the field. Text that does not parse leaves the value untouched and the
    /// field returns to showing it.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the field's title — a literal is looked up,
    ///     see ``LocalizedStringKey``.
    ///   - value: The value to display and edit.
    ///   - format: A format style that both renders and parses the value.
    ///   - prompt: A `Text` shown when the field is empty.
    public init<F: ParseableFormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil
    ) where F.FormatOutput == String {
        self.init(titleKey.localized, value: value, format: format, prompt: prompt)
    }

    /// Creates a text field that edits a value through a format style, with a
    /// title shown as written.
    ///
    /// - Parameters:
    ///   - title: The field's title, describing its purpose.
    ///   - value: The value to display and edit.
    ///   - format: A format style that both renders and parses the value.
    ///   - prompt: A `Text` shown when the field is empty.
    @_disfavoredOverload
    public init<S: StringProtocol, F: ParseableFormatStyle>(
        _ title: S,
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil
    ) where F.FormatOutput == String {
        self.init(value: value, format: format, prompt: prompt) { Text(String(title)) }
    }
}

extension TextField {
    /// Creates a text field that edits a value through a format style, with a
    /// custom label.
    ///
    /// - Parameters:
    ///   - value: The value to display and edit.
    ///   - format: A format style that both renders and parses the value.
    ///   - prompt: A `Text` shown when the field is empty.
    ///   - label: A view that describes the purpose of the field.
    public init<F: ParseableFormatStyle>(
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) where F.FormatOutput == String {
        self.label = label()
        // Unused on this path: the string being edited is the draft the
        // bridging view holds, not a binding the caller owns.
        self.text = .constant("")
        self.prompt = prompt
        self.focusID = nil
        self.isDisabled = false
        self.onSubmitAction = nil
        self.onEditingChangedAction = nil
        self.formatting = _FieldValueFormatting(value: value, format: format)
    }
}
