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
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    /// The character this equivalent matches, compared case-insensitively (the
    /// case of a typed key is carried by ``EventModifiers/shift``, not by the
    /// character, exactly as SwiftUI treats it).
    public let character: Character

    public init(_ character: Character) {
        self.character = character
    }

    public init(extendedGraphemeClusterLiteral value: Character) {
        self.init(value)
    }

    /// The space bar.
    public static let space = Self(" ")
}

/// The modifier keys a shortcut requires.
///
/// TUI-specific reality: a terminal reports Control, Option/Alt and Shift, and
/// does **not** report Command — see `Documentation/Terminal-compatibility.md`.
/// A shortcut declared with ``command`` therefore can never fire here. That is
/// left deliberately literal rather than quietly rewritten to a bare key: an
/// app that says ⌘Q should not fire on a lone "q".
public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Never reported by a terminal — see the type documentation.
    public static let command = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    /// Accepted for source compatibility with SwiftUI; a terminal cannot
    /// distinguish the numeric pad, so it never matches.
    public static let numericPad = Self(rawValue: 1 << 4)
    public static let all: Self = [.command, .control, .option, .shift, .numericPad]

    /// The modifiers a terminal actually reports on `event`.
    init(_ event: KeyEvent) {
        var result: Self = []
        if event.ctrl { result.insert(.control) }
        if event.alt { result.insert(.option) }
        if event.shift { result.insert(.shift) }
        self = result
    }
}

public struct KeyboardShortcut: Hashable, Sendable {
    /// What activates this shortcut.
    enum Trigger: Hashable, Sendable {
        case defaultAction
        case cancelAction
        case key(KeyEquivalent, EventModifiers)
    }

    let trigger: Trigger

    /// The default button: Return/Enter activates it when the focused control
    /// lets the key fall through.
    public static let defaultAction = Self(trigger: .defaultAction)

    /// The cancel button: Escape activates it when nothing closer to the user
    /// (an open drop-down, an app-level back binding) consumes the key first.
    public static let cancelAction = Self(trigger: .cancelAction)

    /// A key equivalent, à la SwiftUI's `KeyboardShortcut(_:modifiers:)`.
    ///
    /// The default is SwiftUI's `.command`, which a terminal never reports —
    /// so a TUI shortcut is almost always written with `modifiers: []`, a bare
    /// key. That is the form a terminal menu wants anyway: "press 1 for the
    /// first item".
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.trigger = .key(key, modifiers)
    }

    private init(trigger: Trigger) {
        self.trigger = trigger
    }

    /// The character this shortcut is triggered by, when it is a key
    /// equivalent — what a menu row prints as its hint.
    public var displayCharacter: Character? {
        if case .key(let key, _) = trigger { return key.character }
        return nil
    }
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
    private var actions: [KeyboardShortcut.Trigger: () -> Void] = [:]

    /// Clears the frame's registrations (called from the render loop).
    func beginRenderPass() {
        actions.removeAll(keepingCapacity: true)
    }

    /// Registers `action` for `shortcut`; the last registration in a frame wins.
    func register(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        actions[shortcut.trigger] = action
    }

    /// Runs the action matching a fallen-through key event, if any.
    ///
    /// Unmodified Return/Escape drive the two semantic roles; a character key
    /// drives a key equivalent whose modifiers match exactly what the terminal
    /// reported. Exactly, not "at least": a shortcut on plain "q" must not fire
    /// on Ctrl-Q.
    func trigger(for event: KeyEvent) -> Bool {
        let modifiers = EventModifiers(event)
        switch event.key {
        case .enter where modifiers.isEmpty:
            return run(.defaultAction)
        case .escape where modifiers.isEmpty:
            return run(.cancelAction)
        case .character(let character):
            // Case-insensitive, with the case itself carried by `.shift` — so
            // "A" typed with Shift matches a shortcut declared `("a", [.shift])`
            // and not one declared `("a", [])`.
            let folded = Character(character.lowercased())
            return run(.key(KeyEquivalent(folded), modifiers))
        default:
            return false
        }
    }

    /// Runs the registered action for `trigger`, reporting whether there was one.
    private func run(_ trigger: KeyboardShortcut.Trigger) -> Bool {
        guard let action = actions[trigger] else { return false }
        action()
        return true
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

    /// Assigns a key-equivalent shortcut to the wrapped control — SwiftUI's
    /// `keyboardShortcut(_:modifiers:)`.
    ///
    /// ```swift
    /// Button("Text Styles") { page = .textStyles }
    ///     .keyboardShortcut("1", modifiers: [])
    /// ```
    ///
    /// `modifiers` defaults to SwiftUI's `.command`, which a terminal never
    /// reports — pass `[]` for the bare-key form a TUI actually wants. See
    /// ``EventModifiers``.
    public func keyboardShortcut(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command
    ) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }
}
