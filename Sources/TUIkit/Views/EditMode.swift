//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EditMode.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The editing state of a view hierarchy. Mirrors SwiftUI's `EditMode`.
///
/// Views that support editing — an editable `List`, an `EditButton` — read the
/// current mode from the `\.editMode` environment binding and react to it.
/// > Important: This does **nothing** in TUIkit, and is not expected to. It is
/// > here so that code ported from SwiftUI compiles and reads the same.
/// >
/// > TUIkit's `List` and `Table` follow the macOS style: they are not modal.
/// > Rows drag to reorder, <kbd>Delete</kbd> removes one and the keyboard move
/// > works whenever `onMove`/`onDelete` are present — there is no mode to enter
/// > first, and nothing in the framework reads this value. (SwiftUI agrees
/// > about the platform: it marks `EditMode` and `EditButton` unavailable on
/// > macOS.) An app may still drive and read it for editing UI of its own.
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
