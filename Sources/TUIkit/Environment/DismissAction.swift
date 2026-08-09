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
/// SwiftUI's `@Environment(\.dismiss)` dismisses whatever presented the view
/// that reads it. A TUIkit app has one top-level scene that fills the whole
/// terminal, so at the top level dismissing is equivalent to quitting: the run
/// loop falls out naturally, `AppRunner` restores the terminal, and
/// `App.main()` returns. Unlike calling `exit(0)`, this lets normal Swift
/// cleanup run.
///
/// Inside a ``NavigationStack``'s pushed screen it means what SwiftUI means:
/// go back one screen. The stack installs its own action into the environment
/// for the screen it presents, so the same `dismiss()` call does the right
/// thing wherever it is written.
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
    /// What dismissing does here, or `nil` for the top-level meaning (exit).
    ///
    /// A stored closure rather than a subclass or a flag, because the set of
    /// things that can present a view is open-ended: whatever presents one
    /// supplies the action that undoes it.
    private let action: (@MainActor @Sendable () -> Void)?

    /// Creates a dismiss action that exits the application's run loop.
    public init() {
        self.action = nil
    }

    /// Creates a dismiss action that runs `action` — for a presenting view to
    /// put into the environment of what it presents.
    public init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    /// Triggers the action. Equivalent to writing `dismiss()`.
    @MainActor
    public func callAsFunction() {
        if let action {
            action()
        } else {
            AppState.shared.requestExit()
        }
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
