//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TruncationModeEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Environment key

private struct TruncationModeKey: EnvironmentKey {
    /// Tail by default, as in SwiftUI: the start of a string is the part that
    /// identifies it, so it is the part worth keeping.
    static let defaultValue: TruncationMode = .tail
}

extension EnvironmentValues {
    /// Where text that does not fit loses its middle — set by
    /// ``View/truncationMode(_:)``.
    ///
    /// Like any environment value it cascades, so one application near a
    /// subtree's root decides how every piece of clipped text in it reads. A
    /// ``Text``'s own ``Text/truncationMode(_:)`` still wins for that one view.
    /// Defaults to ``TruncationMode/tail``.
    public var truncationMode: TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets where text in this subtree is truncated when it does not fit.
    /// Matches SwiftUI's `truncationMode(_:)`.
    ///
    /// Which end to sacrifice depends on where the meaning lives. A file path
    /// identifies itself at the END, so a list of paths wants
    /// ``TruncationMode/head``; a sentence identifies itself at the start, so
    /// prose wants ``TruncationMode/tail`` (the default).
    ///
    /// ```swift
    /// VStack {
    ///     ForEach(paths, id: \.self) { Text($0) }
    /// }
    /// .truncationMode(.head)      // "…/Sources/TUIkit/Views/Text.swift"
    /// ```
    ///
    /// Text is truncated whenever it cannot fit — a line limit, a frame too
    /// narrow for a word, a table cell — so this applies wherever that happens,
    /// not only under `.lineLimit(_:)`.
    ///
    /// - Parameter mode: Which part of the text to keep.
    /// - Returns: A view whose descendant text truncates with `mode`.
    public func truncationMode(_ mode: TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }
}
