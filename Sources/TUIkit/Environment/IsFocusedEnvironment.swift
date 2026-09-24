//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// ``View/focusable(_:)`` makes one a Tab stop, and
    /// ``View/contextMenu(menuItems:)`` does the same for whatever it is
    /// attached to (a menu you cannot reach is a menu you cannot open from the
    /// keyboard). Either way only that content knows what part of itself should
    /// say so.
    ///
    /// Pair it with ``EnvironmentValues/selectionEmphasis`` to get an
    /// affordance that keeps step with every built-in control and honours
    /// ``View/selectionIndicatorStyle(_:)`` — pulse, blink or a
    /// static accent — without deciding any of that yourself:
    ///
    /// ```swift
    /// struct RightClickTarget: View {
    ///     @Environment(\.isFocused) private var isFocused
    ///     @Environment(\.selectionEmphasis) private var emphasis
    ///     @Environment(\.palette) private var palette
    ///
    ///     var body: some View {
    ///         let ends = palette.accent.breathEnds(
    ///             dimmedTo: ViewConstants.focusBorderDim, over: palette.background)
    ///         Text("Right-click me")
    ///             .border(isFocused
    ///                 ? emphasis(true).color(dim: ends.dim, bright: ends.bright)
    ///                 : palette.border)
    ///     }
    /// }
    /// ```
    ///
    /// The dim end is a faded accent, not the unfocused `palette.border`: the
    /// bottom of the breath has to be distinguishable from not being focused,
    /// or every breath blinks the focus out.
    ///
    /// This value stays `true` while the view does not appear active (see
    /// ``EnvironmentValues/appearsActive``), because it answers a question about
    /// behaviour: the focus is still here, and the keys come here when input
    /// returns. The look should say the same — every built-in control keeps its
    /// focus indication on screen meanwhile, and holds it still — and the
    /// emphasis already does that for you: while the view does not appear active
    /// it hands back one still frame, half-way between the two ends.
    ///
    /// That reads the clock as it renders, which costs a full render pass per
    /// tick of the pulse. See <doc:AnimatingYourOwnView> for the cheap route.
    public var isFocused: Bool {
        get { self[IsFocusedKey.self] }
        set { self[IsFocusedKey.self] = newValue }
    }
}
