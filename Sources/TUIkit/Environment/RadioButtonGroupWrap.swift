//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButtonGroupWrap.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

private struct RadioButtonGroupWrapsAtEdgeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether arrowing past a ``RadioButtonGroup``'s first/last item wraps to
    /// the opposite end (`true`) or relinquishes focus to the next control in
    /// that direction (`false`, the default).
    ///
    /// Set with ``TUIkitView/View/radioButtonGroupWrapsAtEdge(_:)``.
    public var radioButtonGroupWrapsAtEdge: Bool {
        get { self[RadioButtonGroupWrapsAtEdgeKey.self] }
        set { self[RadioButtonGroupWrapsAtEdgeKey.self] = newValue }
    }
}

extension View {
    /// Controls what pressing an arrow key *past* a ``RadioButtonGroup``'s first
    /// or last item does.
    ///
    /// By default, arrowing up from the top item — or down from the bottom
    /// (left/right for a horizontally-laid-out group) — moves focus to the next
    /// focusable control in that direction, just like Tab, so keyboard travel
    /// flows naturally out of the group and through the rest of a form. Apply
    /// this modifier to restore the classic behaviour where focus instead wraps
    /// around to the opposite end of the *same* group.
    ///
    /// ```swift
    /// RadioButtonGroup(selection: $choice) { … }
    ///     .radioButtonGroupWrapsAtEdge()   // Up on the first item → last item
    /// ```
    ///
    /// This is a TUI-specific modifier — SwiftUI has no direct equivalent.
    ///
    /// - Parameter wraps: `true` to wrap at the edge; `false` (equivalent to
    ///   omitting the modifier) to relinquish focus to the neighbouring control.
    public func radioButtonGroupWrapsAtEdge(_ wraps: Bool = true) -> some View {
        environment(\.radioButtonGroupWrapsAtEdge, wraps)
    }
}
