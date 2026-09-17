//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedString.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Localized String View

/// A view that displays a localized string using a dot-notation key.
///
/// The string is looked up in the current language from the localization
/// service in the environment, which is the shared one: the render loop
/// republishes it every frame, so this shows the app's language and follows a
/// change to it.
///
/// If the key is missing, falls back to English, then to the key itself.
///
/// # Example
///
/// ```swift
/// VStack {
///     LocalizedString("button.ok")
///     LocalizedString("error.invalid_input")
/// }
/// ```
///
/// Use this for all UI strings that need localization.
public struct LocalizedString: View {
    /// The dot-notation key for the string to display.
    private let key: String

    /// The service that resolves the key, taken from the environment.
    ///
    /// Not `LocalizationService.shared` read directly, which is what this did
    /// before. For an app nothing changes — `applyRuntimeServices` republishes
    /// the shared service into the environment every frame, so the default IS
    /// the shared one — but a view's dependencies should reach it down the
    /// tree rather than around it, and this is the difference between a
    /// subtree being able to render in another language and the whole process
    /// having to switch to do it.
    @Environment(\.localizationService) private var service

    /// Creates a localized string view.
    ///
    /// - Parameter key: The dot-notation key (e.g., "button.ok", "error.invalid_input")
    public init(_ key: String) {
        self.key = key
    }

    public var body: some View {
        Text(service.string(for: key))
    }
}
