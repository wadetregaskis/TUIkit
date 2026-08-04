//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuOpenEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - onMenuOpen

/// The action a subtree's menus run when they open — see
/// ``View/onMenuOpen(_:)``.
///
/// `@unchecked Sendable` on the same terms as every other action closure here:
/// it is created and invoked only on the render loop's single thread.
struct MenuOpenAction: @unchecked Sendable {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct MenuOpenKey: EnvironmentKey {
    static let defaultValue: MenuOpenAction? = nil
}

extension EnvironmentValues {
    /// What to run when a pop-up menu in this subtree opens. `nil` — do
    /// nothing — everywhere it has not been set.
    var menuOpenAction: MenuOpenAction? {
        get { self[MenuOpenKey.self] }
        set { self[MenuOpenKey.self] = newValue }
    }
}

extension View {
    /// Runs `action` each time a pop-up menu in this subtree opens: a `Menu`'s
    /// items appearing, or a ``View/contextMenu(menuItems:)``
    /// popping up.
    ///
    /// The use it exists for is clearing whatever the LAST choice from that menu
    /// left on screen, so that choosing the same item again reads as a new
    /// choice rather than as nothing having happened:
    ///
    /// ```swift
    /// Menu("Actions") {
    ///     Button("Rename") { lastAction = "Rename" }
    ///     Button("Duplicate") { lastAction = "Duplicate" }
    /// }
    /// .onMenuOpen { lastAction = "—" }
    /// ```
    ///
    /// TUIkit-specific: SwiftUI has no equivalent (its menus are system-drawn,
    /// and their open moment is not the app's to observe).
    ///
    /// It fires on the OPEN, never on the close, and never from a render — so it
    /// is safe to change state from, and it runs exactly once per opening,
    /// however the menu was opened (click, Return, or <kbd>Shift</kbd>+<kbd>F10</kbd>).
    ///
    /// - Parameter action: Run as the menu opens.
    public func onMenuOpen(_ action: @escaping () -> Void) -> some View {
        environment(\.menuOpenAction, MenuOpenAction(action: action))
    }
}
