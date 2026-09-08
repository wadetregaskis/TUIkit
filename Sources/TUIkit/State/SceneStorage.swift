//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneStorage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - SceneStorage

/// A property wrapper for state restored per scene. Matches SwiftUI's
/// `@SceneStorage`.
///
/// ```swift
/// struct BrowserView: View {
///     @SceneStorage("selectedTab") private var selectedTab = "inbox"
///
///     var body: some View {
///         TabView(selection: $selectedTab) { … }
///     }
/// }
/// ```
///
/// ## How this differs from `@AppStorage` — and why it mostly doesn't
///
/// SwiftUI draws the line by *scope*: `@AppStorage` is one value for the whole
/// app, `@SceneStorage` is one per window, so two windows of the same document
/// can be scrolled to different places. That distinction is real when an app
/// has several scenes and meaningless when it has one — and a terminal app has
/// exactly one, filling the terminal. SwiftUI behaves the same way in that
/// case, which is the point: the same source keeps working.
///
/// So the two differ here in exactly one respect, and it is the one that
/// survives having a single scene: **the namespace**. Scene storage is written
/// under a `scene.` prefix, so `@SceneStorage("tab")` and `@AppStorage("tab")`
/// are different values rather than the same one under two names. Which one to
/// reach for is then a statement of intent — "this is where the user was" (a
/// tab, a scroll position, a selection) versus "this is what the user chose" (a
/// theme, a font size) — and that intent is worth keeping legible even when the
/// mechanism underneath is shared.
///
/// > Note: SwiftUI does not guarantee scene storage survives a relaunch — it is
///   for *state restoration*, and the system may discard it. TUIkit persists it
///   the same way `@AppStorage` persists, so it does survive. Relying on it as
///   durable storage is still a bad idea for the reason SwiftUI names: a value
///   nobody chose deliberately should not outlive the reason it was written.
@propertyWrapper
public struct SceneStorage<Value: Codable> {
    /// The scene-scoped key actually written.
    private let key: String

    /// The value used when nothing has been stored.
    private let defaultValue: Value

    /// Where it is stored.
    private let storage: StorageBackend

    /// The namespace that separates scene state from app preferences.
    private static var prefix: String { "scene." }

    /// Creates scene storage with the default backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    public init(wrappedValue: Value, _ key: String) {
        self.key = Self.prefix + key
        self.defaultValue = wrappedValue
        self.storage = StorageDefaults.backend
    }

    /// Creates scene storage with a custom backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    ///   - storage: Where to store it.
    public init(wrappedValue: Value, _ key: String, store storage: StorageBackend) {
        self.key = Self.prefix + key
        self.defaultValue = wrappedValue
        self.storage = storage
    }

    /// The current value.
    public var wrappedValue: Value {
        get {
            storage.value(forKey: key) ?? defaultValue
        }
        nonmutating set {
            storage.setValue(newValue, forKey: key)
            AppState.shared.setNeedsRender()
        }
    }

    /// A binding to the stored value.
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

// MARK: - Sendability

/// Sendable exactly when the value it stores is — see the note on
/// ``AppStorage``, which this mirrors down to the stored properties.
///
/// SwiftUI spells its own as `@unchecked Sendable where Value: Sendable`; this
/// one needs no `@unchecked`, because the three things it stores are a
/// `String`, a `Value` and a ``StorageBackend``, and the constraint covers the
/// only one of those that isn't already `Sendable`.
extension SceneStorage: Sendable where Value: Sendable {}
