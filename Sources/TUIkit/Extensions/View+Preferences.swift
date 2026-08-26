//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Preferences.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Preference

extension View {
    /// Sets a preference value for this view.
    ///
    /// Preferences propagate up the view hierarchy, allowing child views
    /// to communicate values to their ancestors.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Page Title")
    ///     .preference(key: NavigationTitleKey.self, value: "Home")
    /// ```
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - value: The value to set.
    /// - Returns: A view that sets the preference.
    public func preference<K: PreferenceKey>(key: K.Type, value: K.Value) -> some View {
        PreferenceModifier<Self, K>(content: self, value: value)
    }

    /// Adds an action to perform when a preference value changes.
    ///
    /// # Example
    ///
    /// ```swift
    /// NavigationView {
    ///     content
    /// }
    /// .onPreferenceChange(NavigationTitleKey.self) { title in
    ///     self.title = title
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - action: The action to perform with the new value.
    /// - Returns: A view that reacts to preference changes.
    public func onPreferenceChange<K: PreferenceKey>(
        _ key: K.Type,
        perform action: @escaping (K.Value) -> Void
    ) -> some View where K.Value: Equatable {
        OnPreferenceChangeModifier<Self, K>(content: self, action: action)
    }
}

// MARK: - Navigation Title

extension View {
    /// Sets the navigation title for this view.
    ///
    /// # Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("Content")
    /// }
    /// .navigationTitle("Home")
    /// ```
    ///
    /// A string **literal** binds here, so the title is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter titleKey: The key for the navigation title.
    /// - Returns: A view with the navigation title preference set.
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        preference(key: NavigationTitleKey.self, value: titleKey.localized)
    }

    /// Sets the navigation title from a string, displayed as written.
    ///
    /// - Parameter title: The navigation title.
    /// - Returns: A view with the navigation title preference set.
    @_disfavoredOverload
    public func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        preference(key: NavigationTitleKey.self, value: String(title))
    }

    /// Sets the navigation title for this view from a ``Text``.
    ///
    /// Mirrors SwiftUI's `navigationTitle(_:)` `Text` overload. The navigation
    /// title renders as a plain string, so the `Text`'s styling (colour, bold, …)
    /// is not carried — a terminal text-richness limit, not a parity gap.
    ///
    /// - Parameter title: The navigation title as a `Text`.
    /// - Returns: A view with the navigation title preference set.
    public func navigationTitle(_ title: Text) -> some View {
        preference(key: NavigationTitleKey.self, value: title.content)
    }

    /// Hides the navigation bar's Back control for this screen.
    ///
    /// Mirrors SwiftUI's `navigationBarBackButtonHidden(_:)`. Apply it inside a
    /// pushed screen; the enclosing ``NavigationStack`` reads it when it draws
    /// the bar above that screen.
    ///
    /// ```swift
    /// .navigationDestination(for: Step.self) { step in
    ///     Wizard(step)
    ///         .navigationBarBackButtonHidden(step.isCommitting)
    /// }
    /// ```
    ///
    /// The **breadcrumb trail goes with it**. On a wide terminal the bar draws
    /// the trail instead of a Back button, and every crumb in it pops — so a
    /// bar that dropped the button and kept the trail would have hidden one way
    /// back and left three, which is not what the modifier says. The title
    /// stays, and takes the width the button was using.
    ///
    /// **Escape still goes back.** SwiftUI hides the button without disabling
    /// the swipe-back gesture, and Escape is this framework's counterpart to
    /// that gesture rather than to the button. A screen that must not be left
    /// at all wants this *and* something that consumes Escape.
    ///
    /// - Parameter hidesBackButton: Whether to hide the control. Default `true`.
    /// - Returns: A view that publishes the preference.
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        preference(key: NavigationBackButtonHiddenKey.self, value: hidesBackButton)
    }
}
