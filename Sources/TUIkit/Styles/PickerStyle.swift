//  🖥️ TUIKit — Terminal UI Kit for Swift
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
public protocol PickerStyle: Sendable {}

// MARK: - Built-in Picker Styles

/// The default picker style.
///
/// In TUIkit the default resolves to ``MenuPickerStyle`` — a collapsed
/// control that opens a drop-down list.
public struct AutomaticPickerStyle: PickerStyle {
    /// Creates an automatic picker style.
    public init() {}
}

/// A picker style that collapses to a single line and opens a drop-down
/// list of options when activated.
public struct MenuPickerStyle: PickerStyle {
    /// Creates a menu picker style.
    public init() {}
}

/// A picker style that presents the options inline as a selectable list.
///
/// > Note: In TUIkit this renders identically to ``RadioGroupPickerStyle``.
public struct InlinePickerStyle: PickerStyle {
    /// Creates an inline picker style.
    public init() {}
}

/// A picker style that presents the options as a radio-button group.
public struct RadioGroupPickerStyle: PickerStyle {
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
