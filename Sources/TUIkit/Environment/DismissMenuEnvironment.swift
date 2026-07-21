//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DismissMenuEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - dismissMenu

/// An action that closes the enclosing pop-up menu — set by a ``ContextMenu`` on
/// its item subtree, read by ``Button`` so selecting an item runs its action AND
/// closes the menu (SwiftUI's menu auto-dismiss behaviour).
///
/// `@unchecked Sendable`: the closure is created and invoked only on the render
/// loop's single thread — the same latitude every action closure relies on — so
/// it can be a concurrency-safe environment default.
struct DismissMenuAction: @unchecked Sendable {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct DismissMenuKey: EnvironmentKey {
    static let defaultValue: DismissMenuAction? = nil
}

extension EnvironmentValues {
    /// Closes the enclosing pop-up menu, if any. `nil` outside a menu's item
    /// subtree, so a ``Button`` elsewhere on the page is unaffected.
    var dismissMenu: DismissMenuAction? {
        get { self[DismissMenuKey.self] }
        set { self[DismissMenuKey.self] = newValue }
    }
}
