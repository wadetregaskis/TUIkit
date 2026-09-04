//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// Anywhere *inside* something dismissable it means what SwiftUI means, because
/// each of those installs its own action into the environment of what it
/// presents: a ``NavigationStack``'s pushed screen goes back one screen, and a
/// `sheet`, `modal`, `fullScreenCover`, `popover`, `alert` or
/// `confirmationDialog` closes — the same act as that presentation's Escape
/// route, so an `onDismiss` runs for either. The same `dismiss()` call
/// therefore does the right thing wherever it is written, and the exit-the-app
/// meaning above is only what is left when nothing encloses the view.
///
/// - Important: That fallback is why installing the action is not optional. A
///   presentation that forgets leaves its content holding the top-level
///   meaning, and `Button("Done") { dismiss() }` — the shape SwiftUI's own
///   documentation teaches — quits the program instead of closing the sheet.
///   `PresentationDismissTests` pins every presentation against that.
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

    /// Whether this view is inside something that was PRESENTED — a sheet,
    /// modal, full-screen cover, popover, alert or confirmation dialog.
    ///
    /// SwiftUI's `\.isPresented`, and the read-only companion to
    /// ``EnvironmentValues/dismiss``: the same presentations that publish a
    /// dismissal publish this, so a view can tell whether calling `dismiss()`
    /// will close something or quit the application.
    ///
    /// ```swift
    /// @Environment(\.isPresented) private var isPresented
    ///
    /// // A footer that only makes sense in a sheet.
    /// if isPresented { Button("Done") { dismiss() } }
    /// ```
    ///
    /// A pushed ``NavigationStack`` screen reports `false`, as it does in
    /// SwiftUI: it was navigated to, not presented.
    public internal(set) var isPresented: Bool {
        get { self[IsPresentedKey.self] }
        set { self[IsPresentedKey.self] = newValue }
    }
}

/// Environment key for ``EnvironmentValues/isPresented``.
private struct IsPresentedKey: EnvironmentKey {
    static let defaultValue = false
}
