//  🖥️ TUIKit — Terminal UI Kit for Swift
//  EditButton.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A button that toggles the environment's edit mode. Mirrors SwiftUI's
/// `EditButton`.
///
/// It reads and drives the `\.editMode` binding, so it must be placed where that
/// binding is in scope:
///
/// ```swift
/// @State private var editMode = EditMode.inactive
///
/// var body: some View {
///     VStack {
///         EditButton()
///         List { … }        // reads \.editMode to reveal its edit affordances
///     }
///     .environment(\.editMode, $editMode)
/// }
/// ```
///
/// When no `\.editMode` binding is in scope it renders as a disabled button, like
/// SwiftUI (whose `EditButton` is inert outside an edit-mode-providing container).
/// > Important: This does **nothing** in TUIkit, and is not expected to. It is
/// > here so that code ported from SwiftUI compiles and reads the same.
/// >
/// > TUIkit's `List` and `Table` follow the macOS style: they are not modal.
/// > Rows drag to reorder, <kbd>Delete</kbd> removes one and the keyboard move
/// > works whenever `onMove`/`onDelete` are present — there is no mode to enter
/// > first, and nothing in the framework reads this value. (SwiftUI agrees
/// > about the platform: it marks `EditMode` and `EditButton` unavailable on
/// > macOS.) An app may still drive and read it for editing UI of its own.
public struct EditButton: View {
    @Environment(\.editMode) private var editMode

    public init() {}

    public var body: some View {
        let isEditing = editMode?.wrappedValue.isEditing ?? false
        return Button(isEditing ? "Done" : "Edit") {
            guard let editMode else { return }
            editMode.wrappedValue = editMode.wrappedValue.isEditing ? .inactive : .active
        }
        .disabled(editMode == nil)
    }
}
