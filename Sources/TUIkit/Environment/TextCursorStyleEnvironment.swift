//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextCursorStyleEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Environment Key

/// Environment key for the text cursor style.
private struct TextCursorStyleKey: EnvironmentKey {
    static let defaultValue = TextCursorStyle()
}

extension EnvironmentValues {
    /// The text cursor style for text fields.
    ///
    /// Set this value using the `.textCursor(_:)` modifier:
    ///
    /// ```swift
    /// TextField("Name", text: $name)
    ///     .textCursor(.bar, animation: .blink)
    /// ```
    public var textCursorStyle: TextCursorStyle {
        get { self[TextCursorStyleKey.self] }
        set { self[TextCursorStyleKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Sets the text cursor style for text fields within this view.
    ///
    /// Use this modifier to customize the cursor appearance in ``TextField``
    /// and ``SecureField`` components.
    ///
    /// ```swift
    /// TextField("Name", text: $name)
    ///     .textCursor(.bar)
    /// ```
    ///
    /// - Parameter style: The cursor style to use.
    /// - Returns: A view with the cursor style applied.
    public func textCursor(_ style: TextCursorStyle) -> some View {
        environment(\.textCursorStyle, style)
    }

    /// Sets the text cursor style with separate shape and animation parameters.
    ///
    /// How fast the cursor animates is set apart from its style, with
    /// ``View/indicatorAnimationSpeed(_:for:)`` for
    /// ``IndicatorAnimations/textCursor``:
    ///
    /// ```swift
    /// TextField("Code", text: $code)
    ///     .textCursor(.underscore, animation: .blink)
    ///     .indicatorAnimationSpeed(.doubleSpeed, for: .textCursor)
    /// ```
    ///
    /// - Parameters:
    ///   - shape: The cursor shape.
    ///   - animation: The cursor animation. Defaults to `.pulse`.
    /// - Returns: A view with the cursor style applied.
    public func textCursor(
        _ shape: TextCursorStyle.Shape,
        animation: TextCursorStyle.Animation = .pulse
    ) -> some View {
        environment(\.textCursorStyle, TextCursorStyle(shape: shape, animation: animation))
    }
}
