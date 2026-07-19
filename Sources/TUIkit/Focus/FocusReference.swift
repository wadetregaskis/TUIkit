//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusReference.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Imperative focus handle

/// A lightweight handle to one element's focus, over a ``FocusManager``.
///
/// `FocusReference` is the imperative counterpart to the declarative
/// `@FocusState` property wrapper: where `@FocusState` binds a control's focus
/// to a view's state, a `FocusReference` is a plain object you query and drive
/// by id. Create one with the id and the focus manager (typically from
/// `context.environment.focusManager`):
///
/// ```swift
/// let focus = FocusReference(id: "my-button", focusManager: manager)
/// if focus.isFocused { /* render focused style */ }
/// focus.requestFocus()
/// ```
///
/// - Note: This type used to be called `FocusState`; that name now belongs to
///   the SwiftUI-shaped `@FocusState` property wrapper.
public class FocusReference {
    /// The focus ID.
    public let id: String

    /// The focus manager that tracks focus state.
    private let focusManager: FocusManager

    /// Creates a focus reference with the given ID and focus manager.
    ///
    /// - Parameters:
    ///   - id: The unique focus ID. Defaults to a new UUID.
    ///   - focusManager: The focus manager to query and mutate.
    public init(id: String = UUID().uuidString, focusManager: FocusManager) {
        self.id = id
        self.focusManager = focusManager
    }

    /// Whether this element is currently focused.
    public var isFocused: Bool {
        focusManager.isFocused(id: id)
    }
}

// MARK: - Public API

extension FocusReference {
    /// Requests focus for this element.
    public func requestFocus() {
        focusManager.focus(id: id)
    }
}
