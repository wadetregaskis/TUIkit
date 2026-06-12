//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FixedSizeModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Fixed-Size Environment

/// EnvironmentKey: the immediately-enclosing view should size its width to its
/// content (its "ideal" width) rather than fill the width it is offered.
///
/// Set by ``View/fixedSize(horizontal:vertical:)`` and consumed by views that
/// are otherwise width-greedy — currently `List`, which then sizes to the widest
/// of *all* its rows instead of filling its container. The view that honours it
/// clears it for its own children so the request does not leak down the subtree.
struct FixedSizeWidthKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Whether the enclosing view should hug its content width (see
    /// ``FixedSizeWidthKey``).
    var fixedSizeWidth: Bool {
        get { self[FixedSizeWidthKey.self] }
        set { self[FixedSizeWidthKey.self] = newValue }
    }
}

// MARK: - Fixed-Size Modifier

extension View {
    /// Fixes a view at its ideal size on the chosen axes instead of letting it
    /// grow to fill the space offered.
    ///
    /// Matches SwiftUI's `fixedSize(horizontal:vertical:)`. The common use in
    /// TUIkit is on a `List`, whose default is to fill its container's width: a
    /// horizontally fixed List instead hugs its content, sizing to the widest of
    /// **all** its rows (stable as you scroll — it does not track only the rows
    /// on screen).
    ///
    /// - Parameters:
    ///   - horizontal: Fix the width at the ideal (content) width. Default `true`.
    ///   - vertical: Fix the height at the ideal height. Default `true`.
    ///     (Currently honoured by views that are height-greedy; `List` keeps its
    ///     scrollable height regardless.)
    public func fixedSize(horizontal: Bool = true, vertical: Bool = true) -> some View {
        // Width is the axis that matters for the greedy views we have today; the
        // vertical flag is accepted for API parity and reserved for future use.
        environment(\.fixedSizeWidth, horizontal)
    }
}
