//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyboardShortcut.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - KeyboardShortcut

/// A semantic keyboard shortcut a control can adopt, mirroring SwiftUI's
/// `KeyboardShortcut`.
///
/// Attach with ``SwiftUICore/View/keyboardShortcut(_:)``:
///
/// ```swift
/// Dialog("Sign in") {
///     TextField("User", text: $user)
///     SecureField("Password", text: $pass)
/// } footer: {
///     Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
///     Button("Sign in") { signIn() }.keyboardShortcut(.defaultAction)
/// }
/// ```
///
/// ``defaultAction`` makes its button the *default button*: Return/Enter
/// activates it whenever the focused control doesn't handle the key itself.
/// A multi-line ``TextEditor`` (Return inserts a newline), a list with a row
/// activation, or a focused `Button` all keep their Return — the default
/// fires only when the key falls through, macOS responder-chain style. A
/// ``TextField`` *without* an `onSubmit` handler lets Return fall through, so
/// pressing Return in a dialog's field triggers the default button.
///
/// > Note: SwiftUI's arbitrary key equivalents
/// > (`keyboardShortcut("s", modifiers: .command)`) are not yet supported —
/// > terminals don't report the Command key — so this type currently offers
/// > only the two semantic actions. (Documented deviation from the full
/// > SwiftUI surface.)
public struct KeyboardShortcut: Hashable, Sendable {
    /// The semantic role this shortcut binds.
    enum Semantic: Hashable, Sendable {
        case defaultAction
        case cancelAction
    }

    let semantic: Semantic

    /// The default button: Return/Enter activates it when the focused control
    /// lets the key fall through.
    public static let defaultAction = Self(semantic: .defaultAction)

    /// The cancel button: Escape activates it when nothing closer to the user
    /// (an open drop-down, an app-level back binding) consumes the key first.
    public static let cancelAction = Self(semantic: .cancelAction)
}

// MARK: - Registry

/// The per-frame registry of semantic shortcut actions.
///
/// Buttons carrying a ``KeyboardShortcut`` register their action here during
/// the render pass; ``InputHandler`` triggers the matching action when a
/// Return/Escape falls through the focused control. Cleared at the start of
/// every render pass, so only what's actually on screen can be triggered —
/// and when overlapping surfaces each register (a dialog over a page), the
/// LAST registration wins, which render order makes the topmost surface.
///
/// `@unchecked Sendable` like its sibling per-frame services
/// (`MouseEventDispatcher`, `KeyEventDispatcher`): touched only from the
/// main run loop (render pass registration + input dispatch).
final class KeyboardShortcutRegistry: @unchecked Sendable {
    private var defaultAction: (() -> Void)?
    private var cancelAction: (() -> Void)?

    /// Clears the frame's registrations (called from the render loop).
    func beginRenderPass() {
        defaultAction = nil
        cancelAction = nil
    }

    /// Registers `action` for `shortcut`; the last registration in a frame wins.
    func register(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        switch shortcut.semantic {
        case .defaultAction: defaultAction = action
        case .cancelAction: cancelAction = action
        }
    }

    /// Runs the action matching a fallen-through key event, if any.
    /// Only unmodified Return/Escape qualify.
    func trigger(for event: KeyEvent) -> Bool {
        guard !event.ctrl, !event.alt, !event.shift else { return false }
        switch event.key {
        case .enter:
            guard let defaultAction else { return false }
            defaultAction()
            return true
        case .escape:
            guard let cancelAction else { return false }
            cancelAction()
            return true
        default:
            return false
        }
    }
}

// MARK: - Assignment

/// The per-frame, claimable carrier ``SwiftUICore/View/keyboardShortcut(_:)``
/// plants in the environment.
///
/// A plain environment *value* would cascade to every button in the subtree —
/// `.keyboardShortcut(.defaultAction)` on a container would mark all of them.
/// A claimable box keeps SwiftUI's attach-to-one-control semantics: the first
/// button rendered under the modifier claims it (which is the wrapped button
/// itself when the modifier is attached directly, the only supported usage).
/// Main-loop-confined like the registry it feeds.
final class KeyboardShortcutAssignment: @unchecked Sendable {
    let shortcut: KeyboardShortcut
    private(set) var isClaimed = false

    init(_ shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
    }

    /// Claims the assignment for one control; returns nil if already claimed.
    func claim() -> KeyboardShortcut? {
        guard !isClaimed else { return nil }
        isClaimed = true
        return shortcut
    }
}

// MARK: - Environment

private struct KeyboardShortcutRegistryKey: EnvironmentKey {
    static let defaultValue: KeyboardShortcutRegistry? = nil
}

private struct AssignedKeyboardShortcutKey: EnvironmentKey {
    static let defaultValue: KeyboardShortcutAssignment? = nil
}

extension EnvironmentValues {
    /// The app's semantic-shortcut registry (nil outside a running app).
    var keyboardShortcutRegistry: KeyboardShortcutRegistry? {
        get { self[KeyboardShortcutRegistryKey.self] }
        set { self[KeyboardShortcutRegistryKey.self] = newValue }
    }

    /// The shortcut assignment awaiting a control, planted by
    /// ``SwiftUICore/View/keyboardShortcut(_:)``.
    var assignedKeyboardShortcut: KeyboardShortcutAssignment? {
        get { self[AssignedKeyboardShortcutKey.self] }
        set { self[AssignedKeyboardShortcutKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Assigns a semantic keyboard shortcut to the wrapped control —
    /// ``KeyboardShortcut/defaultAction`` (Return/Enter) or
    /// ``KeyboardShortcut/cancelAction`` (Escape). Attach it directly to a
    /// single `Button`; see ``KeyboardShortcut`` for the fall-through rules.
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        environment(\.assignedKeyboardShortcut, KeyboardShortcutAssignment(shortcut))
    }
}
