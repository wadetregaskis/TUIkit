//  🖥️ TUIKit — Terminal UI Kit for Swift
//  View+Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

// MARK: - Environment

extension View {
    /// Sets an environment value for this view and its children.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the environment value.
    ///   - value: The value to set.
    /// - Returns: A view with the modified environment.
    public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        _ value: V
    ) -> some View {
        EnvironmentModifier(content: self, keyPath: keyPath, value: value)
    }
}

// MARK: - Observable Objects

extension View {
    /// Injects an observable object into the environment for this view
    /// and its descendants.
    ///
    /// The object is stored by its type. Descendants can read it via
    /// `@Environment(MyModel.self)`.
    ///
    /// # Example
    ///
    /// ```swift
    /// @Observable
    /// class AppModel {
    ///     var count = 0
    /// }
    ///
    /// let model = AppModel()
    /// ContentView()
    ///     .environment(model)
    /// ```
    ///
    /// - Parameter object: The observable object to inject.
    /// - Returns: A view with the object available in the environment.
    public func environment<T: Observable>(_ object: T) -> some View {
        ObjectEnvironmentModifier(content: self, object: object)
    }
}

// MARK: - Appearance

extension View {
    /// Sets the appearance for this view and its descendants.
    ///
    /// # Example
    ///
    /// ```swift
    /// ContentView()
    ///     .appearance(.rounded)
    ///
    /// // Local override
    /// Panel("Bold Style") {
    ///     content()
    /// }
    /// .appearance(.heavy)
    /// ```
    ///
    /// - Parameter appearance: The appearance to apply.
    /// - Returns: A view with the appearance applied.
    public func appearance(_ appearance: Appearance) -> some View {
        environment(\.appearance, appearance)
    }
}

// MARK: - Palette

extension View {
    /// Sets the color palette for this view and its descendants.
    ///
    /// # Example
    ///
    /// ```swift
    /// ContentView()
    ///     .palette(SystemPalette(.green))
    /// ```
    ///
    /// - Parameter palette: The palette to apply.
    /// - Returns: A view with the palette applied.
    public func palette(_ palette: any Palette) -> some View {
        environment(\.palette, palette)
    }
}

// MARK: - List Style

extension View {
    /// Sets the list style for List views in this view and its descendants.
    ///
    /// The list style controls how lists render, including borders, padding,
    /// and row backgrounds. Built-in styles match SwiftUI's behavior:
    /// - ``PlainListStyle``: Minimal appearance with no borders
    /// - ``InsetGroupedListStyle``: Bordered with inset padding and alternating rows
    ///
    /// # Example
    ///
    /// ```swift
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///     }
    /// }
    /// .listStyle(.plain)
    ///
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///     }
    /// }
    /// .listStyle(.insetGrouped)
    /// ```
    ///
    /// - Parameter style: The list style to apply.
    /// - Returns: A view with the list style applied.
    public func listStyle(_ style: any ListStyle) -> some View {
        environment(\.listStyle, style)
    }

    /// Controls whether a List or Table renders its selection
    /// highlight when the list itself does not have focus.
    ///
    /// Default — and the `.automatic` resolution — is to show the
    /// selected row with a desaturated accent background while
    /// the list is unfocused, matching desktop list-view
    /// convention. Use `.hidden` on transient surfaces (a pop-up
    /// picker, a quick-pick palette) where the unfocused
    /// highlight is more noise than signal.
    ///
    /// # Example
    ///
    /// ```swift
    /// List(items, selection: $selection) {
    ///     ForEach(items) { item in Text(item.name) }
    /// }
    /// .unfocusedSelectionVisibility(.hidden)
    /// ```
    ///
    /// The selection binding itself is unaffected; only the
    /// visual indicator is suppressed when the list lacks focus.
    /// Cascades through the environment so it can be set on a
    /// parent (e.g. a NavigationSplitView column) and inherited
    /// by every selection-bearing descendant.
    ///
    /// - Parameter visibility: The desired visibility.
    /// - Returns: A view with the unfocused-selection visibility
    ///   set on its environment.
    public func unfocusedSelectionVisibility(_ visibility: Visibility) -> some View {
        environment(\.unfocusedSelectionVisibility, visibility)
    }
}
