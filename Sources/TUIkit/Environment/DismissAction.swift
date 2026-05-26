//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DismissAction.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Dismiss Action

/// An action that exits the application's run loop, mirroring SwiftUI's
/// `DismissAction`.
///
/// SwiftUI's `@Environment(\.dismiss)` dismisses the current presentation
/// context (sheet, popover, …). A TUIkit app has one top-level scene that
/// fills the whole terminal, so dismissing it is equivalent to quitting:
/// the run loop falls out naturally, ``AppRunner`` restores the terminal,
/// and `App.main()` returns. Unlike calling `exit(0)`, this lets normal
/// Swift cleanup run.
///
/// # Example
///
/// ```swift
/// struct ContentView: View {
///     @Environment(\.dismiss) private var dismiss
///
///     var body: some View {
///         Button("Quit") { dismiss() }
///     }
/// }
/// ```
public struct DismissAction: Sendable {
    /// Creates a dismiss action.
    ///
    /// The default action signals the application's shared ``AppState`` to
    /// exit on its next loop iteration.
    public init() {}

    /// Triggers the action. Equivalent to writing `dismiss()`.
    public func callAsFunction() {
        AppState.shared.requestExit()
    }
}

// MARK: - Environment Key

/// Environment key for the dismiss action.
private struct DismissActionKey: EnvironmentKey {
    static let defaultValue = DismissAction()
}

extension EnvironmentValues {
    /// An action that exits the application's run loop.
    ///
    /// Read this with `@Environment(\.dismiss)` and call it like a function:
    ///
    /// ```swift
    /// @Environment(\.dismiss) private var dismiss
    /// // ...
    /// dismiss()
    /// ```
    ///
    /// The call returns immediately; the run loop notices the request on its
    /// next iteration and shuts down cleanly. The terminal is restored to
    /// its prior state before `App.main()` returns.
    public var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}
