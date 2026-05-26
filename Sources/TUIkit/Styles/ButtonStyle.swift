//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ButtonStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ButtonStyleConfiguration

/// The properties of a button, passed to a ``ButtonStyle`` so it can
/// produce the button's appearance.
///
/// You don't create this type yourself — TUIkit constructs a configuration
/// for each ``Button`` and hands it to the active style's
/// ``ButtonStyle/makeBody(configuration:)`` method.
public struct ButtonStyleConfiguration {
    /// The button's label text.
    ///
    /// - Note: SwiftUI exposes `label` as a type-erased `View`. In TUIkit a
    ///   button's label is always plain text, so the configuration carries
    ///   the `String` directly. This is a deliberate terminal-specific
    ///   deviation — a custom style can wrap it in `Text` if it wants a view.
    public let label: String

    /// The semantic role of the button, if any.
    ///
    /// A style may use this to adjust its appearance — for example, the
    /// built-in styles always colour a ``ButtonRole/destructive`` button
    /// with the palette's error colour.
    public let role: ButtonRole?

    /// Whether the button is currently being pressed.
    ///
    /// - Note: Terminals have no press-and-hold gesture — a key press
    ///   triggers the action instantly — so this is always `false`. It is
    ///   kept for source compatibility with SwiftUI button styles.
    public let isPressed: Bool

    /// Whether the button currently holds keyboard focus.
    ///
    /// - Note: Terminal-specific addition. SwiftUI styles read focus from
    ///   the environment; TUIkit surfaces it directly on the configuration
    ///   because button rendering is procedural.
    public let isFocused: Bool

    /// Whether the button is enabled.
    ///
    /// - Note: Terminal-specific addition mirroring SwiftUI's `\.isEnabled`
    ///   environment value. A disabled button renders dimmed.
    public let isEnabled: Bool

    // Configurations are produced by ``Button`` during rendering, never by
    // client code — the compiler-synthesized memberwise initializer
    // (internal access level) is exactly what's needed.
}

// MARK: - ButtonStyle

/// A type that applies a custom appearance to all buttons within a view
/// hierarchy.
///
/// To configure the button style for a view, apply the
/// ``View/buttonStyle(_:)`` modifier:
///
/// ```swift
/// Button("Save") { save() }
///     .buttonStyle(.primary)
/// ```
///
/// The modifier flows through the environment, so it can also be applied to
/// a container to style every button it contains:
///
/// ```swift
/// VStack {
///     Button("One") { }
///     Button("Two") { }
/// }
/// .buttonStyle(.plain)
/// ```
///
/// ## Built-in Styles
///
/// - ``DefaultButtonStyle`` (``default``) — bracketed, accent-tinted.
/// - ``PrimaryButtonStyle`` (``primary``) — bold, emphasised.
/// - ``DestructiveButtonStyle`` (``destructive``) — error-coloured.
/// - ``SuccessButtonStyle`` (``success``) — success-coloured.
/// - ``PlainButtonStyle`` (``plain``) — no brackets, just the label.
///
/// ## Custom Styles
///
/// Conform to `ButtonStyle` and return a view from
/// ``makeBody(configuration:)``:
///
/// ```swift
/// struct LinkButtonStyle: ButtonStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         Text(configuration.label)
///             .foregroundStyle(configuration.isFocused ? .palette.accent
///                                                       : .palette.foregroundSecondary)
///     }
/// }
/// ```
///
/// - Note: The built-in styles draw terminal-specific flourishes (half-block
///   caps, a pulsing focus glow) that require procedural buffer rendering.
///   Custom styles compose ordinary TUIkit views and modifiers, which is
///   enough for colour and weight changes but cannot reproduce those
///   procedural effects.
public protocol ButtonStyle: Sendable {
    /// A view that represents the body of a button.
    associatedtype Body: View

    /// Creates a view that represents the body of a button.
    ///
    /// - Parameter configuration: The properties of the button being styled.
    /// - Returns: A view describing the button's appearance.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a button.
    typealias Configuration = ButtonStyleConfiguration
}

extension ButtonStyle {
    /// Renders this style's body for `configuration` into a frame buffer.
    ///
    /// Call sites hold the style as `any ButtonStyle`. This method opens the
    /// existential so ``makeBody(configuration:)`` can return its concrete
    /// ``Body`` type, which the renderer then resolves into a buffer.
    @MainActor
    func makeBuffer(
        configuration: Configuration,
        context: RenderContext
    ) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }
}

// MARK: - Built-in Button Styles

/// The default button style: a single-line bracketed button with an
/// accent-tinted background.
///
/// Access this style with the ``ButtonStyle/default`` static property.
public struct DefaultButtonStyle: ButtonStyle {
    /// Creates a default button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .default)
    }
}

/// A bold, emphasised button style that uses the palette's accent colour.
///
/// Access this style with the ``ButtonStyle/primary`` static property.
public struct PrimaryButtonStyle: ButtonStyle {
    /// Creates a primary button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .primary)
    }
}

/// A button style that uses the palette's error colour to signal a
/// destructive action.
///
/// Access this style with the ``ButtonStyle/destructive`` static property.
public struct DestructiveButtonStyle: ButtonStyle {
    /// Creates a destructive button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .destructive)
    }
}

/// A button style that uses the palette's success colour.
///
/// Access this style with the ``ButtonStyle/success`` static property.
public struct SuccessButtonStyle: ButtonStyle {
    /// Creates a success button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .success)
    }
}

/// A minimal button style with no brackets or background — just the label,
/// preceded by a focus indicator when focused.
///
/// Access this style with the ``ButtonStyle/plain`` static property.
public struct PlainButtonStyle: ButtonStyle {
    /// Creates a plain button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _ButtonStyleBody(configuration: configuration, appearance: .plain)
    }
}

// MARK: - ButtonStyle Static Accessors

extension ButtonStyle where Self == DefaultButtonStyle {
    /// The default button style — a bracketed, accent-tinted button.
    public static var `default`: DefaultButtonStyle { DefaultButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// A bold, emphasised button style that uses the accent colour.
    public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    /// A button style that uses the error colour for destructive actions.
    public static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

extension ButtonStyle where Self == SuccessButtonStyle {
    /// A button style that uses the success colour.
    public static var success: SuccessButtonStyle { SuccessButtonStyle() }
}

extension ButtonStyle where Self == PlainButtonStyle {
    /// A minimal button style with no brackets or background.
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

// MARK: - Button Appearance

/// The resolved visual parameters shared by the built-in button styles.
///
/// Framework infrastructure — built-in ``ButtonStyle`` types hand one of
/// these to ``_ButtonStyleBody`` for procedural rendering.
private struct _ButtonAppearance {
    /// The label colour, or `nil` to use the palette accent.
    var foregroundColor: Color?

    /// Whether the label is bold even when unfocused.
    var isBold: Bool

    /// Horizontal padding, in characters, inside the button.
    var horizontalPadding: Int

    /// Whether the button renders without brackets or background.
    var isPlain: Bool

    /// The default appearance — dimmed foreground, not bold.
    static let `default` = Self(
        foregroundColor: Color.palette.foregroundSecondary,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false
    )

    /// The primary appearance — bold, accent-coloured.
    static let primary = Self(
        foregroundColor: Color.palette.accent,
        isBold: true,
        horizontalPadding: 1,
        isPlain: false
    )

    /// The destructive appearance — error-coloured.
    static let destructive = Self(
        foregroundColor: Color.palette.error,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false
    )

    /// The success appearance — success-coloured.
    static let success = Self(
        foregroundColor: Color.palette.success,
        isBold: false,
        horizontalPadding: 1,
        isPlain: false
    )

    /// The plain appearance — no brackets, no background, no padding.
    static let plain = Self(
        foregroundColor: nil,
        isBold: false,
        horizontalPadding: 0,
        isPlain: true
    )
}

// MARK: - Button Style Body

/// The procedural rendering core shared by the built-in button styles.
///
/// - Important: Framework infrastructure. The built-in ``ButtonStyle`` types
///   return this from `makeBody`; it is never used directly.
private struct _ButtonStyleBody: View, Renderable {
    /// The button being styled.
    let configuration: ButtonStyleConfiguration

    /// The resolved visual parameters to draw with.
    let appearance: _ButtonAppearance

    var body: Never {
        fatalError("_ButtonStyleBody renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let isDisabled = !configuration.isEnabled
        let isFocused = configuration.isFocused

        // A destructive role always wins on colour, matching SwiftUI, where
        // the role overrides whatever tint the style would otherwise use.
        let baseForeground: Color? =
            configuration.role == .destructive
            ? Color.palette.error
            : appearance.foregroundColor

        // Focused buttons render bold — this replaces the old explicit
        // "focused style" that was a bold variant of the normal style.
        let isBold = appearance.isBold || isFocused

        let padding = String(repeating: " ", count: appearance.horizontalPadding)
        let paddedLabel = padding + configuration.label + padding

        // Plain: focus indicator prefix + label, no brackets, no background.
        if appearance.isPlain {
            let foregroundColor: Color =
                isDisabled
                ? palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
                : (baseForeground?.resolve(with: palette) ?? palette.accent)

            var textStyle = TextStyle()
            textStyle.foregroundColor = foregroundColor
            textStyle.isBold = isBold && !isDisabled

            let focusPrefix = BorderRenderer.focusIndicatorPrefix(
                isFocused: isFocused && !isDisabled,
                pulsePhase: context.environment.pulsePhase,
                palette: palette
            )
            let styledLabel = ANSIRenderer.render(paddedLabel, with: textStyle)
            return FrameBuffer(lines: [focusPrefix + styledLabel])
        }

        // Standard: half-block caps around an accent-tinted background.
        let buttonBg = palette.accent.opacity(ViewConstants.focusBorderDim)

        // Label foreground: bold = tinted, otherwise a dimmed foreground.
        let labelFg: Color
        if isDisabled {
            labelFg = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground)
        } else if isBold {
            labelFg = baseForeground?.resolve(with: palette) ?? palette.accent
        } else {
            labelFg = palette.foregroundSecondary
        }

        // Caps match the background normally, pulsing to accent when focused.
        let resolvedCapColor: Color
        if isDisabled {
            resolvedCapColor = buttonBg
        } else if isFocused {
            resolvedCapColor = Color.lerp(
                buttonBg,
                palette.accent.opacity(ViewConstants.buttonCapPulseBright),
                phase: context.environment.pulsePhase
            )
        } else {
            resolvedCapColor = buttonBg
        }

        let openCap = ANSIRenderer.colorize(
            String(TerminalSymbols.openCap),
            foreground: resolvedCapColor
        )
        let closeCap = ANSIRenderer.colorize(
            String(TerminalSymbols.closeCap),
            foreground: resolvedCapColor
        )
        let styledLabel = ANSIRenderer.colorize(
            paddedLabel,
            foreground: labelFg,
            background: buttonBg,
            bold: isBold && !isDisabled
        )

        return FrameBuffer(lines: [openCap + styledLabel + closeCap])
    }
}

// MARK: - Environment

/// Environment key for the button style.
private struct ButtonStyleKey: EnvironmentKey {
    static let defaultValue: any ButtonStyle = DefaultButtonStyle()
}

extension EnvironmentValues {
    /// The button style for this environment.
    ///
    /// Controls how ``Button`` views render. Set via the
    /// ``View/buttonStyle(_:)`` modifier. Default: ``DefaultButtonStyle``.
    public var buttonStyle: any ButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

// MARK: - Button Style Modifier

extension View {
    /// Sets the style for buttons within this view.
    ///
    /// Apply this modifier to a single ``Button`` or to a container to style
    /// every button it contains:
    ///
    /// ```swift
    /// Button("Delete") { delete() }
    ///     .buttonStyle(.destructive)
    /// ```
    ///
    /// - Parameter style: The button style to apply.
    /// - Returns: A view whose buttons use the specified style.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        environment(\.buttonStyle, style)
    }
}
