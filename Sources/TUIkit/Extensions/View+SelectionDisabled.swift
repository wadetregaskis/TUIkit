//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+SelectionDisabled.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Selection Disabled Modifier

extension View {
    /// Disables selection for this view within a List.
    ///
    /// Applied to a list row, this row cannot become the `List`'s selection —
    /// Enter/Space and a click on it do nothing — and it renders with a
    /// dimmed foreground to show it. Up/Down and Page Up/Page Down also route
    /// around it, once it has rendered at least once: like
    /// ``View/deleteDisabled(_:)`` / ``View/moveDisabled(_:)``, the refusal is
    /// reported to the enclosing `List` as the row draws, so a row that has
    /// never been on screen has not yet had the chance to report and cannot
    /// yet be routed around. Home and End jump straight to a boundary and do
    /// not consult it.
    ///
    /// # Example
    ///
    /// ```swift
    /// List(selection: $selection) {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///             .selectionDisabled(item.isLocked)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter isDisabled: Whether selection should be disabled. Default is `true`.
    /// - Returns: A view with selection disabled state applied.
    public func selectionDisabled(_ isDisabled: Bool = true) -> some View {
        SelectionDisabledModifier(content: self, isDisabled: isDisabled)
    }
}
