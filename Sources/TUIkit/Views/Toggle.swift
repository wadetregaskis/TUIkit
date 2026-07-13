//  TUIKit - Terminal UI Kit for Swift
//  Toggle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ToggleStyle Protocol

/// The appearance and behavior of a toggle.
///
/// To configure the style for a single `Toggle` or for all toggle instances
/// in a view hierarchy, use the `toggleStyle(_:)` modifier.
///
/// ## Built-in Styles
///
/// | Style | Description |
/// |-------|-------------|
/// | `.automatic` | Platform default (checkbox in TUI) |
/// | `.checkbox` | Classic checkbox |
/// | `.switch` | Switch style (renders same as checkbox in TUI) |
///
/// > Note: The built-in `ToggleStyle`s render identically — a checkbox — due to
/// > terminal constraints; the API matches SwiftUI for compatibility. The
/// > *glyphs* of that checkbox (■/□ or ⬛︎/⬜︎ or `[x]`/`[ ]` — see `CheckboxStyle`) are a separate,
/// > TUI-specific choice — see ``CheckboxStyle`` and
/// > ``SwiftUICore/View/checkboxStyle(_:)``.
///
/// ## Custom styles
///
/// Conform to `ToggleStyle` and implement ``makeBody(configuration:)`` to draw a
/// toggle however you like (a different glyph, an `ON`/`OFF` word, …). The
/// built-in styles above don't implement `makeBody` — they render procedurally
/// (with the focus glow and ``CheckboxStyle`` glyphs); only custom styles use it.
public protocol ToggleStyle: Sendable {
    /// A view representing the toggle's appearance.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a toggle.
    ///
    /// - Parameter configuration: The properties of the toggle being styled.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a toggle.
    typealias Configuration = ToggleStyleConfiguration
}

extension ToggleStyle {
    /// Default body for the built-in marker styles, which TUIkit renders
    /// procedurally rather than through `makeBody`. A custom style overrides it.
    @MainActor public func makeBody(configuration: Configuration) -> EmptyView {
        EmptyView()
    }

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any ToggleStyle` existential so ``makeBody(configuration:)`` can
    /// return its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }
}

/// The properties of a toggle, passed to a ``ToggleStyle`` so it can produce the
/// toggle's appearance.
///
/// You don't create this — TUIkit builds one per ``Toggle`` and hands it to a
/// custom style's ``ToggleStyle/makeBody(configuration:)``. Mirrors SwiftUI's
/// `ToggleStyleConfiguration` (`label`, `isOn`) plus terminal-specific focus /
/// hover / enabled flags, exactly as ``ButtonStyleConfiguration`` does, because
/// toggle rendering is procedural.
public struct ToggleStyleConfiguration {
    /// The toggle's label, type-erased.
    public let label: AnyView

    /// A binding to the toggle's on/off state. Read `isOn.wrappedValue`; write it
    /// to flip the toggle.
    public let isOn: Binding<Bool>

    /// Whether the toggle currently holds keyboard focus. (Terminal-specific
    /// addition, like ``ButtonStyleConfiguration/isFocused``.)
    public let isFocused: Bool

    /// Whether the cursor is hovering over the toggle. (Terminal-specific.)
    public let isHovered: Bool

    /// Whether the toggle is enabled. (Terminal-specific.)
    public let isEnabled: Bool
}

// MARK: - Built-in Toggle Styles

/// The default toggle style.
///
/// In TUIkit this is a checkbox; its glyphs come from ``CheckboxStyle`` (■/□ by default; ⬛︎/⬜︎ under Terminal.app
/// by default).
public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
}

/// A toggle style that displays a checkbox followed by its label.
///
/// ```
/// □ Label     (OFF)
/// ■ Label     (ON)
/// ```
///
/// The checkbox glyphs are configurable via ``CheckboxStyle`` (e.g.
/// `.checkboxStyle(.ascii)` for `[ ]` / `[x]`).
public struct CheckboxToggleStyle: ToggleStyle {
    public init() {}
}

/// A toggle style that displays the toggle as a two-position switch.
///
/// In TUIkit this renders a coloured track with a two-cell knob on the side the
/// switch points to — left for off, right for on — over a distinct background
/// (the accent colour when on), so it reads as a switch rather than a checkbox.
public struct SwitchToggleStyle: ToggleStyle {
    public init() {}
}

// MARK: - ToggleStyle Static Extensions

extension ToggleStyle where Self == DefaultToggleStyle {
    /// The default toggle style.
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    /// A toggle style that displays a checkbox followed by its label.
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    /// A toggle style that displays a leading label and a trailing switch.
    ///
    /// > Note: In TUIkit, this renders identically to checkbox style.
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

// MARK: - Environment Key

/// Environment key for toggle style.
private struct ToggleStyleKey: EnvironmentKey {
    static let defaultValue: any ToggleStyle = DefaultToggleStyle()
}

extension EnvironmentValues {
    /// The toggle style for this environment.
    public var toggleStyle: any ToggleStyle {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }
}

// MARK: - Toggle Style Modifier

extension View {
    /// Sets the style for toggles within this view.
    ///
    /// Use this modifier to set a specific style for all toggles within a view:
    ///
    /// ```swift
    /// VStack {
    ///     Toggle("Option 1", isOn: $option1)
    ///     Toggle("Option 2", isOn: $option2)
    /// }
    /// .toggleStyle(.checkbox)
    /// ```
    ///
    /// > Note: In TUIkit, all `ToggleStyle`s currently render as a checkbox; the
    /// > checkbox glyphs are set separately via ``CheckboxStyle``.
    ///
    /// - Parameter style: The toggle style to use.
    /// - Returns: A view with the toggle style set.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        environment(\.toggleStyle, style)
    }

    /// Styles the *label* text of every toggle in this view's subtree (a
    /// `.control(.toggle)`-scoped style entry). The checkbox indicator is
    /// unaffected.
    ///
    /// ```swift
    /// SettingsForm().toggleTextStyle { $0.italic = true }
    /// ```
    public func toggleTextStyle(_ build: (inout StyleAttributes) -> Void) -> some View {
        style(.control(.toggle), build)
    }
}

// MARK: - Toggle

/// A control that toggles between on and off states.
///
/// You create a toggle by providing an `isOn` binding and a label:
///
/// ```swift
/// @State private var isEnabled = false
///
/// Toggle("Enable notifications", isOn: $isEnabled)
/// ```
///
/// ## Rendering
///
/// ```
/// □ Label     (OFF - dimmed)
/// ■ Label     (ON - accent color)
/// ```
///
/// The checkbox glyphs are configurable — see ``CheckboxStyle``.
///
/// When focused, the brackets pulse in the accent color.
///
/// ## Styling
///
/// Use the `toggleStyle(_:)` modifier to customize appearance:
///
/// ```swift
/// Toggle("Option", isOn: $isOn)
///     .toggleStyle(.checkbox)
/// ```
///
/// Available styles: `.automatic`, `.checkbox`, `.switch`
///
/// > Note: In TUIkit, all styles currently render identically as checkbox
/// > due to terminal constraints.
public struct Toggle<Label: View>: View {
    /// The binding to the toggle's boolean state.
    let isOn: Binding<Bool>

    /// The label view.
    let label: Label

    /// The unique focus identifier.
    var focusID: String?

    /// Whether the toggle is disabled.
    var isDisabled: Bool

    public var body: some View {
        _ToggleCore(
            isOn: isOn,
            label: label,
            focusID: focusID,
            isDisabled: isDisabled
        )
    }
}

// MARK: - Toggle Initializers (String Label)

extension Toggle where Label == Text {
    /// Creates a toggle with a string label.
    ///
    /// - Parameters:
    ///   - title: The toggle's label text.
    ///   - isOn: A binding to the toggle's boolean state.
    public init<S: StringProtocol>(
        _ title: S,
        isOn: Binding<Bool>
    ) {
        self.isOn = isOn
        self.label = Text(String(title))
        // Auto-generated focusID from view identity (collision-free)
        self.focusID = nil
        self.isDisabled = false
    }
}

// MARK: - Toggle Initializers (ViewBuilder Label)

extension Toggle {
    /// Creates a toggle with a custom label.
    ///
    /// - Parameters:
    ///   - isOn: A binding to the toggle's boolean state.
    ///   - label: A view that describes the purpose of the toggle.
    public init(
        isOn: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) {
        self.isOn = isOn
        self.label = label()
        self.focusID = nil
        self.isDisabled = false
    }
}

// MARK: - Toggle Modifiers

extension Toggle {
    /// Creates a disabled version of this toggle.
    ///
    /// - Parameter disabled: Whether the toggle is disabled.
    /// - Returns: A new toggle with the disabled state.
    public func disabled(_ disabled: Bool = true) -> Toggle {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier for this toggle.
    ///
    /// - Parameter id: The unique focus identifier.
    /// - Returns: A toggle with the specified focus identifier.
    public func focusID(_ id: String) -> Toggle {
        var copy = self
        copy.focusID = id
        return copy
    }
}
