//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Picker.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Picker Option Extraction

/// A picker option recovered from a tagged view, before its tag has been
/// matched to a concrete selection-value type.
struct _RawPickerOption {
    /// The option's tag, still type-erased.
    let tagValue: AnyHashable

    /// The option's label view.
    let label: AnyView
}

/// A protocol for views that can contribute options to a ``Picker``.
///
/// This mirrors the `ButtonProvider` pattern used by ``Alert``: rather than
/// reflecting over the view tree, each view type that may appear inside a
/// picker's content closure declares how to surface its tagged options.
@MainActor
protocol PickerOptionProvider {
    /// Extracts the tagged options contained in this view.
    func pickerOptions() -> [_RawPickerOption]
}

extension _TaggedView: PickerOptionProvider {
    func pickerOptions() -> [_RawPickerOption] {
        [_RawPickerOption(tagValue: tagValue, label: AnyView(content))]
    }
}

extension EmptyView: PickerOptionProvider {
    func pickerOptions() -> [_RawPickerOption] {
        []
    }
}

extension TupleView: PickerOptionProvider {
    func pickerOptions() -> [_RawPickerOption] {
        var result: [_RawPickerOption] = []
        func collect<Child: View>(_ view: Child) {
            if let provider = view as? PickerOptionProvider {
                result.append(contentsOf: provider.pickerOptions())
            }
        }
        repeat collect(each children)
        return result
    }
}

extension ForEach: PickerOptionProvider {
    func pickerOptions() -> [_RawPickerOption] {
        data.flatMap { element -> [_RawPickerOption] in
            if let provider = content(element) as? PickerOptionProvider {
                return provider.pickerOptions()
            }
            return []
        }
    }
}

// MARK: - Picker Entry

/// A picker option whose tag has been resolved to the picker's concrete
/// selection-value type.
struct _PickerEntry<SelectionValue: Hashable> {
    /// The value selected when this option is chosen.
    let tag: SelectionValue

    /// The option's label view.
    let label: AnyView
}

// MARK: - Picker

/// A control for selecting one value from a set of mutually exclusive
/// options.
///
/// Each option is a view tagged with the value it represents, using the
/// ``View/tag(_:)`` modifier. The tag type must match the picker's
/// `selection` binding.
///
/// ```swift
/// @State private var theme: Theme = .light
///
/// Picker("Theme", selection: $theme) {
///     Text("Light").tag(Theme.light)
///     Text("Dark").tag(Theme.dark)
///     Text("System").tag(Theme.system)
/// }
/// ```
///
/// ## Styles
///
/// The presentation is controlled by ``View/pickerStyle(_:)``:
///
/// - ``MenuPickerStyle`` (and the default ``AutomaticPickerStyle``) collapse
///   the picker to a single line that opens a drop-down list of options.
/// - ``InlinePickerStyle`` and ``RadioGroupPickerStyle`` present the options
///   inline as a radio-button group.
///
/// ## Keyboard
///
/// The picker is focusable with Tab. For a menu picker, Enter, Space, or
/// Down opens the drop-down; the arrow keys move the highlight; Enter or
/// Space commits the highlighted option; Escape closes without changing the
/// selection. For an inline picker, the arrow keys move between options and
/// Enter or Space selects.
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
    /// A binding to the selected value.
    let selection: Binding<SelectionValue>

    /// The picker's option content.
    let content: Content

    /// The picker's label, shown as a heading above the options.
    let label: Label

    /// The unique focus identifier, or `nil` to auto-generate one.
    var focusID: String?

    /// Whether the picker is disabled.
    var isDisabled: Bool

    /// The active picker style, resolved from the environment.
    @Environment(\.pickerStyle) private var pickerStyle

    /// Creates a picker with a custom label.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:)``.
    ///   - label: A view builder for the picker's label.
    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.selection = selection
        self.content = content()
        self.label = label()
        self.focusID = nil
        self.isDisabled = false
    }

    public var body: some View {
        // Tag the picker subtree so its label/option Text resolves
        // `.control(.picker)` style entries (`.pickerTextStyle { … }`).
        pickerBody.environment(\.controlKind, .picker)
    }

    @ViewBuilder private var pickerBody: some View {
        let entries = resolvedEntries()
        if pickerStyle.resolvesToMenu {
            VStack(alignment: .leading, spacing: 0) {
                _PickerLabel(label: label)
                _PickerMenuCore(
                    entries: entries,
                    selection: selection,
                    focusID: focusID,
                    isDisabled: isDisabled
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                _PickerLabel(label: label)
                radioGroup(entries: entries)
            }
        }
    }

    /// Walks the content tree and resolves every tagged option whose tag
    /// matches the picker's selection-value type.
    private func resolvedEntries() -> [_PickerEntry<SelectionValue>] {
        guard let provider = content as? PickerOptionProvider else { return [] }
        return provider.pickerOptions().compactMap { raw in
            guard let value = raw.tagValue.base as? SelectionValue else { return nil }
            return _PickerEntry(tag: value, label: raw.label)
        }
    }

    /// Builds the radio-button group used for the inline / radio-group
    /// styles, reusing ``RadioButtonGroup`` rather than duplicating its
    /// focus and keyboard machinery.
    private func radioGroup(
        entries: [_PickerEntry<SelectionValue>]
    ) -> RadioButtonGroup<SelectionValue> {
        let items = entries.map { entry in
            RadioButtonItem(entry.tag) { entry.label }
        }
        let group = RadioButtonGroup(selection: selection, items: items)
        let identified = focusID.map { group.focusID($0) } ?? group
        return identified.disabled(isDisabled)
    }
}

// MARK: - Picker Label

/// Renders a picker's label, collapsing to **zero height** when the label is
/// empty or all-whitespace — so an unlabelled picker (e.g. `Picker("", …)`)
/// doesn't show a blank first line above its options.
private struct _PickerLabel<Label: View>: View, Renderable, Layoutable {
    let label: Label

    var body: Never { fatalError("_PickerLabel renders via Renderable") }

    /// The collapsed picker label sizes to its content (it does not fill), so a
    /// single render is its exact, fixed measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIkit.renderToBuffer(label, context: context)
        return buffer.isBlank ? FrameBuffer() : buffer
    }
}

// MARK: - Convenience Initializer

extension Picker where Label == Text {
    /// Creates a picker with a text label.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:)``.
    public init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content, label: { Text(title) })
    }
}

// MARK: - Picker Convenience Modifiers

extension Picker {
    /// Creates a disabled version of this picker.
    ///
    /// - Parameter disabled: Whether the picker is disabled.
    /// - Returns: A new picker with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Picker {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this picker.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A picker with the specified focus identifier.
    public func focusID(_ id: String) -> Picker {
        var copy = self
        copy.focusID = id
        return copy
    }
}

extension View {
    /// Styles the *label and option* text of every picker in this view's subtree
    /// (a `.control(.picker)`-scoped style entry).
    ///
    /// ```swift
    /// SettingsForm().pickerTextStyle { $0.foreground = .palette.accent }
    /// ```
    public func pickerTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.picker), build)
    }
}
