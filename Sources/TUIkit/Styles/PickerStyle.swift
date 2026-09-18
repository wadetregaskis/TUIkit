//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - PickerStyle Protocol

/// The appearance and interaction style of a ``Picker``.
///
/// To configure the style for a single `Picker` or for every picker in a
/// view hierarchy, use the ``View/pickerStyle(_:)`` modifier.
///
/// ## Built-in Styles
///
/// | Style | Description |
/// |-------|-------------|
/// | ``automatic`` | Platform default — a drop-down menu in TUIkit. |
/// | ``menu`` | A collapsed control that opens a drop-down list. |
/// | ``inline`` | The options shown inline as a selectable list. |
/// | ``radioGroup`` | The options shown as a radio-button group. |
///
/// > Note: In TUIkit ``inline`` and ``radioGroup`` render identically — an
/// > inline list of radio options — because a terminal has no distinct
/// > inline-vs-grouped presentation. The separate styles exist so source
/// > written against SwiftUI keeps compiling. ``menu`` is genuinely
/// > different: it collapses to a single line and expands on demand.
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/pickerStyle(_:)`` puts the style into the environment, and the
/// render cache keeps memoized subtrees honest by comparing each injected value
/// with the one applied there last frame. A value it cannot compare may have
/// changed under a buffer it is about to serve with nothing able to notice, so
/// every memo below one declines to cache at all — not the picker alone, but
/// everything under the modifier.
///
/// All four built-in styles are therefore `Equatable`. None of them holds
/// anything, and the only thing the framework ever reads off a style is
/// `resolvesToMenu`, which is a function of the type and of nothing else — so
/// `==` within a type is vacuously true and two instances of one really do draw
/// the same picker. Between types it is the downcast in the comparison that
/// answers, and a swap across the menu/inline divide changes a picker's height
/// as well as its glyphs: one collapsed line becomes a row per option.
///
/// The comparison is blunter than the presentation, and deliberately so.
/// ``AutomaticPickerStyle`` and ``MenuPickerStyle`` draw identically, as do
/// ``InlinePickerStyle`` and ``RadioGroupPickerStyle``, but a swap within either
/// pair still compares unequal and clears. That costs a redraw the frame did not
/// need; the error runs toward invalidating, never toward serving a stale
/// buffer.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's picker styles declare no such conformance, and this is one
///   of the places a terminal renderer has to differ. SwiftUI diffs the view
///   graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol PickerStyle: Sendable {}

// MARK: - Built-in Picker Styles

/// The default picker style.
///
/// In TUIkit the default resolves to ``MenuPickerStyle`` — a collapsed
/// control that opens a drop-down list.
///
/// `Equatable` for the reason given under ``PickerStyle``: a memo below a value
/// the render cache cannot compare declines to cache.
public struct AutomaticPickerStyle: PickerStyle, Equatable {
    /// Creates an automatic picker style.
    public init() {}
}

/// A picker style that collapses to a single line and opens a drop-down
/// list of options when activated.
///
/// `Equatable` on the same terms as ``AutomaticPickerStyle``, and this is the
/// half that earns the cross-type comparison: replacing it with an inline style
/// turns one line into a row per option, so the swap must read as a change.
public struct MenuPickerStyle: PickerStyle, Equatable {
    /// Creates a menu picker style.
    public init() {}
}

/// A picker style that presents the options inline as a selectable list.
///
/// > Note: In TUIkit this renders identically to ``RadioGroupPickerStyle``.
///
/// `Equatable` on the same terms as ``AutomaticPickerStyle``. Note that the
/// identical rendering does not make it compare equal to
/// ``RadioGroupPickerStyle`` — see ``PickerStyle``.
public struct InlinePickerStyle: PickerStyle, Equatable {
    /// Creates an inline picker style.
    public init() {}
}

/// A picker style that presents the options as a radio-button group.
///
/// `Equatable` on the same terms as ``AutomaticPickerStyle``.
public struct RadioGroupPickerStyle: PickerStyle, Equatable {
    /// Creates a radio-group picker style.
    public init() {}
}

// MARK: - PickerStyle Static Accessors

extension PickerStyle where Self == AutomaticPickerStyle {
    /// The default picker style — a drop-down menu in TUIkit.
    public static var automatic: AutomaticPickerStyle { AutomaticPickerStyle() }
}

extension PickerStyle where Self == MenuPickerStyle {
    /// A picker style that opens a drop-down list of options.
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}

extension PickerStyle where Self == InlinePickerStyle {
    /// A picker style that presents the options inline as a list.
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}

extension PickerStyle where Self == RadioGroupPickerStyle {
    /// A picker style that presents the options as a radio-button group.
    public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() }
}

// MARK: - PickerStyle Resolution

extension PickerStyle {
    /// Whether this style should render as a collapsing drop-down menu.
    ///
    /// ``AutomaticPickerStyle`` and ``MenuPickerStyle`` resolve to the menu
    /// presentation; ``InlinePickerStyle`` and ``RadioGroupPickerStyle``
    /// resolve to the inline radio list.
    var resolvesToMenu: Bool {
        self is MenuPickerStyle || self is AutomaticPickerStyle
    }
}

// MARK: - Environment Key

/// Environment key for the picker style.
private struct PickerStyleKey: EnvironmentKey {
    static let defaultValue: any PickerStyle = AutomaticPickerStyle()
}

extension EnvironmentValues {
    /// The picker style for this environment.
    ///
    /// Controls how ``Picker`` views render. Set via the
    /// ``View/pickerStyle(_:)`` modifier. Default: ``AutomaticPickerStyle``.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``PickerStyle``.
    public var pickerStyle: any PickerStyle {
        get { self[PickerStyleKey.self] }
        set { self[PickerStyleKey.self] = newValue }
    }
}

// MARK: - Picker Style Modifier

extension View {
    /// Sets the style for pickers within this view.
    ///
    /// ```swift
    /// Picker("Theme", selection: $theme) {
    ///     Text("Light").tag(Theme.light)
    ///     Text("Dark").tag(Theme.dark)
    /// }
    /// .pickerStyle(.radioGroup)
    /// ```
    ///
    /// - Parameter style: The picker style to apply.
    /// - Returns: A view whose pickers use the specified style.
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        environment(\.pickerStyle, style)
    }
}
