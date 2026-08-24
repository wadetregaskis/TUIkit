//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+ListRowSeparator.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - List Row Separator Modifier

extension View {
    /// Sets the visibility of row separators within a list.
    ///
    /// Accepted for SwiftUI source compatibility, and inert: a TUIkit `List`
    /// draws no row separators, so `.hidden` is already the state and
    /// `.visible` has nothing to show. A row's own border — `.border()` on the
    /// row content — is the terminal's version of the same idea.
    ///
    /// # Example
    ///
    /// ```swift
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///             .listRowSeparator(.hidden)  // No effect in TUIkit
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - visibility: The visibility of the separator.
    ///   - edges: The edges where separators should be shown. Default is `.all`.
    /// - Returns: The view unchanged (separators are not supported).
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        ListRowSeparatorModifier(content: self, visibility: visibility, edges: edges)
    }
}
