//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EditMode.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The editing state of a view hierarchy. Mirrors SwiftUI's `EditMode`.
///
/// Views that support editing — an editable `List`, an `EditButton` — read the
/// current mode from the `\.editMode` environment binding and react to it.
/// > Important: In TUIkit this is app-level state, not a gate. `EditButton`
/// > drives it and an app can read it, but no `List` or `Table` behaviour
/// > depends on it: editing is enabled by the presence of `onMove`/`onDelete`,
/// > so drag-to-reorder, <kbd>Delete</kbd> and the keyboard move all work
/// > without ever entering a mode. That is deliberate — a terminal UI is
/// > desktop-shaped, and SwiftUI itself marks `EditMode` unavailable on macOS —
/// > and it is why the type exists at all: so an app porting iOS code can carry
/// > its own edit-mode UI across.
public enum EditMode: Sendable, Equatable {
    /// The view is not editable.
    case inactive

    /// The view is temporarily editable (e.g. during a swipe).
    case transient

    /// The view is editable.
    case active

    /// Whether edits are currently allowed.
    public var isEditing: Bool {
        self == .transient || self == .active
    }
}

/// EnvironmentKey for the edit-mode binding.
///
/// A nil-default *optional binding* (not a shared mutable default): edit mode is
/// only present when a container supplies it, exactly like SwiftUI (where
/// `NavigationView` injects it — TUIkit has no equivalent, so the developer
/// provides `.environment(\.editMode, $mode)` above both the editable view and
/// its `EditButton`).
private struct EditModeKey: EnvironmentKey {
    // `Binding` is not `Sendable`, so the immutable `nil` default needs
    // `nonisolated(unsafe)` (the value never mutates, so it is genuinely safe).
    nonisolated(unsafe) static let defaultValue: Binding<EditMode>? = nil
}

extension EnvironmentValues {
    /// A binding to the edit mode of the view hierarchy, or `nil` if none is set.
    public var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
}
