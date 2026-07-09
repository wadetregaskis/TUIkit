//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MultilineTextAlignment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Environment key

private struct MultilineTextAlignmentKey: EnvironmentKey {
    // Leading by default — a terminal reads from the top-left, and unaligned
    // wrapped text is flush-left; matches SwiftUI's default.
    static let defaultValue: TextAlignment = .leading
}

extension EnvironmentValues {
    /// How the lines of a multi-line ``Text`` align relative to one another
    /// within the text block, set by ``View/multilineTextAlignment(_:)``.
    ///
    /// Like any environment value it cascades to every descendant, so a single
    /// application near a subtree's root aligns all the wrapped text beneath it.
    /// Defaults to ``TextAlignment/leading``.
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the alignment of the lines of multi-line ``Text`` within this
    /// subtree.
    ///
    /// Wrapped (or explicitly multi-line) text lays each line out relative to
    /// the block's own width — the width of its longest line: ``TextAlignment/leading``
    /// leaves the lines flush-left (a ragged right edge), ``TextAlignment/center``
    /// centres each line, and ``TextAlignment/trailing`` pushes each flush-right.
    /// A single-line `Text` is unaffected, and the block as a whole is still
    /// positioned by its parent (a `.frame` alignment, a stack). Matches
    /// SwiftUI's `multilineTextAlignment(_:)`.
    ///
    /// ```swift
    /// Text("A longer first line\nand a shorter one")
    ///     .multilineTextAlignment(.center)
    /// ```
    ///
    /// - Parameter alignment: The line-to-line alignment.
    /// - Returns: A view whose descendant text uses `alignment`.
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}
