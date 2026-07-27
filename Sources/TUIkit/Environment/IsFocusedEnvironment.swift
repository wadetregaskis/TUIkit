//  🖥️ TUIKit — Terminal UI Kit for Swift
//  IsFocusedEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

private struct IsFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the nearest focusable ancestor holds the focus — mirrors
    /// SwiftUI's `\.isFocused`.
    ///
    /// A built-in control draws its own focus affordance, so it never needs
    /// this. It exists for the case where the focusable thing is *your* view:
    /// ``SwiftUICore/View/contextMenu(menuItems:)`` makes whatever it is
    /// attached to a focus stop (a menu you cannot reach is a menu you cannot
    /// open from the keyboard), and only that content knows what part of itself
    /// should say so.
    ///
    /// Pair it with ``EnvironmentValues/selectionEmphasis`` to get an
    /// affordance that keeps step with every built-in control and honours
    /// ``SwiftUICore/View/selectionIndicatorStyle(_:)`` — pulse, blink or a
    /// static accent — without deciding any of that yourself:
    ///
    /// ```swift
    /// struct RightClickTarget: View {
    ///     @Environment(\.isFocused) private var isFocused
    ///     @Environment(\.selectionEmphasis) private var emphasis
    ///     @Environment(\.palette) private var palette
    ///
    ///     var body: some View {
    ///         Text("Right-click me")
    ///             .border(color: isFocused
    ///                 ? emphasis(true).color(dim: palette.border, bright: palette.accent)
    ///                 : palette.border)
    ///     }
    /// }
    /// ```
    public var isFocused: Bool {
        get { self[IsFocusedKey.self] }
        set { self[IsFocusedKey.self] = newValue }
    }
}
