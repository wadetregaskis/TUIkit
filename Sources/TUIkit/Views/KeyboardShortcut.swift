//  🖥️ TUIKit — Terminal UI Kit for Swift
//  KeyboardShortcut.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - KeyboardShortcut

/// The key a ``KeyboardShortcut`` is triggered by, mirroring SwiftUI's
/// `KeyEquivalent`.
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    /// The character this equivalent matches, always folded to lower case.
    ///
    /// A terminal does not report Shift for a printable key — it sends the
    /// shifted *character*: "A" arrives as one byte with no modifier bits at
    /// all (see `KeyEvent.parse`). So the case of the literal IS the shift,
    /// and carrying both would let a shortcut be written that can never fire.
    /// `KeyEquivalent("A")` therefore normalises to `"a"` plus
    /// ``impliesShift``, which is SwiftUI's reading of an uppercase literal.
    public let character: Character

    /// Whether the literal was uppercase, i.e. the shortcut wants the shifted
    /// key. Unioned into the shortcut's modifiers at construction.
    public let impliesShift: Bool

    public init(_ character: Character) {
        self.character = Character(character.lowercased())
        self.impliesShift = character.isUppercase
    }

    public init(extendedGraphemeClusterLiteral value: Character) {
        self.init(value)
    }

    /// The space bar.
    public static let space = Self(" ")

    // The non-printable keys, spelled the way SwiftUI spells them — same names,
    // same scalars. The arrows and navigation keys are AppKit's private-use
    // function-key block (`NSUpArrowFunctionKey` = U+F700 and its neighbours),
    // which is what SwiftUI's own `KeyEquivalent` uses; the rest are their
    // control characters. A terminal sends these as escape sequences rather
    // than as these scalars, so ``KeyboardShortcut/trigger(for:)`` maps a parsed
    // ``Key`` onto them — nothing ever types one of these characters directly.
    /// The up arrow.
    public static let upArrow = Self("\u{F700}")
    /// The down arrow.
    public static let downArrow = Self("\u{F701}")
    /// The left arrow.
    public static let leftArrow = Self("\u{F702}")
    /// The right arrow.
    public static let rightArrow = Self("\u{F703}")
    /// Page Up.
    public static let pageUp = Self("\u{F72C}")
    /// Page Down.
    public static let pageDown = Self("\u{F72D}")
    /// Home.
    public static let home = Self("\u{F729}")
    /// End.
    public static let end = Self("\u{F72B}")
    /// Forward delete.
    public static let deleteForward = Self("\u{F728}")
    /// Backspace / delete-backwards.
    public static let delete = Self("\u{7F}")
    /// Return.
    public static let `return` = Self("\u{D}")
    /// Escape.
    public static let escape = Self("\u{1B}")
    /// Tab.
    public static let tab = Self("\u{9}")

    // Identity is the folded character alone. `impliesShift` records how the
    // literal was written so the initialiser can fold it into the shortcut's
    // modifiers, and must not survive into the lookup key — otherwise
    // `KeyEquivalent("A")` and `KeyEquivalent("a")` hash apart and a typed "A"
    // could never find the binding its own case just created.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.character == rhs.character
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(character)
    }
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

/// A keyboard shortcut a control can adopt, mirroring SwiftUI's
/// `KeyboardShortcut`: either a key equivalent (``init(_:modifiers:)``) or one
/// of the two semantic roles.
///
/// Attach with ``View/keyboardShortcut(_:)``:
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
/// > Note: A terminal never reports the Command key, so SwiftUI's default
/// > `modifiers: .command` is remapped at registration to whatever
/// > ``EnvironmentValues/commandKey`` says stands in for it here — see
/// > ``CommandKeyBinding``.
public struct KeyboardShortcut: Hashable, Sendable {
    /// What activates this shortcut.
    enum Trigger: Hashable, Sendable {
        case defaultAction
        case cancelAction
        case key(KeyEquivalent, EventModifiers)
    }

    private(set) var trigger: Trigger

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
        // An uppercase literal IS the shift — see `KeyEquivalent`.
        self.trigger = Self.normalised(key, key.impliesShift ? modifiers.union(.shift) : modifiers)
    }

    /// The spelled-out forms of the two semantic roles ARE those roles —
    /// SwiftUI defines `.defaultAction` as unmodified Return and
    /// `.cancelAction` as unmodified Escape. An incoming bare Return/Escape
    /// event resolves to the role before the key table
    /// (see ``trigger(for:)``), so an un-normalised `.key(.return, [])`
    /// could never fire: registered, listed, and permanently dead.
    private static func normalised(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> Trigger {
        guard modifiers.isEmpty else { return .key(key, modifiers) }
        if key == .return { return .defaultAction }
        if key == .escape { return .cancelAction }
        return .key(key, modifiers)
    }

    /// This shortcut with ``EventModifiers/command`` replaced per `binding`,
    /// ready to register. Non-command shortcuts pass through untouched.
    func resolved(commandKey binding: CommandKeyBinding) -> Self? {
        guard case .key(let key, var modifiers) = trigger, modifiers.contains(.command) else {
            return self
        }
        modifiers.remove(.command)
        switch binding {
        case .unavailable: return nil
        case .control: modifiers.insert(.control)
        case .option: modifiers.insert(.option)
        case .bare: break
        }
        var resolved = self
        // A `.bare` stand-in can strip ⌘⏎ / ⌘⎋ down to the semantic roles'
        // own keys — normalise here too, or the resolved form is dead.
        resolved.trigger = Self.normalised(key, modifiers)
        return resolved
    }

    /// Whether a terminal can actually deliver this shortcut.
    ///
    /// `false` for the Control combinations the C0 range spends on other keys:
    /// Ctrl-I is Tab, Ctrl-J and Ctrl-M are newline and Return, Ctrl-[ is
    /// Escape — `KeyEvent.parse` matches those *before* the Ctrl-letter range,
    /// so they never arrive as a modified letter and never can. Ctrl-C and
    /// Ctrl-Z are taken by the shell's job control. Consult it after
    /// `resolved(commandKey:)` — that is where a ⌘ shortcut becomes a
    /// Control one and can collide.
    public var isDeliverableInTerminal: Bool {
        guard case .key(let key, let modifiers) = trigger else { return true }
        if modifiers.contains(.command) { return false }
        guard modifiers.contains(.control) else { return true }
        return !"cijmz[".contains(key.character)
    }

    private init(trigger: Trigger) {
        self.trigger = trigger
    }

    /// The trigger `event` would fire, or `nil` for a key no shortcut can name.
    ///
    /// The one place a `KeyEvent` becomes a shortcut key, because the Shift rule
    /// is easy to get wrong and expensive to get wrong twice: Shift comes from
    /// the CASE, not from `event.shift`. A terminal sends a shifted printable as
    /// the shifted character with no modifier bits, so trusting the flag would
    /// make `("a", [.shift])` permanently dead and let `("a", [])` fire for "A".
    static func trigger(for event: KeyEvent) -> Trigger? {
        let modifiers = EventModifiers(event)
        switch event.key {
        // A BARE Return or Escape is the semantic role — the default button,
        // the cancel button. Held with a modifier it is an ordinary key
        // equivalent, so `⌥⏎` can be bound without disturbing either role.
        case .enter where modifiers.isEmpty:
            return .defaultAction
        case .escape where modifiers.isEmpty:
            return .cancelAction
        case .character(let character):
            var modifiers = modifiers
            modifiers.remove(.shift)
            if character.isUppercase { modifiers.insert(.shift) }
            return .key(KeyEquivalent(character), modifiers)
        default:
            // The non-printable keys, via the table below. Function keys and
            // pasted text are not bindable, and map to nothing.
            return equivalents[event.key].map { .key($0, modifiers) }
        }
    }

    /// A parsed ``Key`` as the ``KeyEquivalent`` that stands for it. A terminal
    /// sends these as escape sequences, never as the scalars themselves, so this
    /// is the only way one is ever produced.
    private static let equivalents: [Key: KeyEquivalent] = [
        .enter: .return, .escape: .escape, .tab: .tab, .space: .space,
        .up: .upArrow, .down: .downArrow, .left: .leftArrow, .right: .rightArrow,
        .pageUp: .pageUp, .pageDown: .pageDown, .home: .home, .end: .end,
        .backspace: .delete, .delete: .deleteForward,
    ]

    /// The printable form of this shortcut — what a menu row prints as its
    /// hint — or `nil` for the semantic roles, which have no key to show.
    ///
    /// Terminal conventions, not Apple's key glyphs: `^S` for Control (what
    /// every TUI menu from nano to htop prints) and `M-s` for Option/Alt (its
    /// Meta name). ⌃⌥⇧⌘ would read better on a Mac but are ambiguous-width
    /// characters, so a CJK-configured terminal would advance two cells and
    /// shear the column they are aligned in.
    ///
    /// Call it on a *resolved* shortcut (see `resolved(commandKey:)`);
    /// `.command` has no printable form here because it is never what actually
    /// fires.
    public var displayString: String? {
        guard case .key(let key, let modifiers) = trigger else { return nil }
        var prefix = ""
        if modifiers.contains(.control) { prefix += "^" }
        if modifiers.contains(.option) { prefix += "M-" }
        // A non-printable key prints as its name, not as the private-use
        // scalar that stands for it (see `KeyEquivalent.upArrow`) — which would
        // otherwise reach the screen as a missing-glyph box.
        if let name = Self.keyNames[key] { return prefix + name }
        // Shift is the character's case — a terminal has no other way to say
        // it — and a Control shortcut is conventionally printed uppercase too.
        let shifted = modifiers.contains(.shift) || modifiers.contains(.control)
        let character = shifted ? String(key.character).uppercased() : String(key.character)
        return prefix + character
    }

    /// How the non-printable keys are named in a hint. Arrows as arrows; the
    /// rest in the words a terminal UI uses, since ⇞/⌫ are ambiguous-width and
    /// would shear an aligned column on a CJK-configured terminal (the same
    /// reason ``displayString`` spells Control as `^`).
    private static let keyNames: [KeyEquivalent: String] = [
        .upArrow: "↑", .downArrow: "↓", .leftArrow: "←", .rightArrow: "→",
        .pageUp: "PgUp", .pageDown: "PgDn", .home: "Home", .end: "End",
        .delete: "Del", .deleteForward: "FwdDel", .return: "Return",
        .escape: "Esc", .tab: "Tab", .space: "Space",
    ]
}

// MARK: - Command key

/// How ``EventModifiers/command`` is delivered in a terminal, which cannot
/// report the Command key itself.
///
/// The point is portability: the same `View` source should run under SwiftUI
/// and under TUIkit, and SwiftUI source says `⌘S`. Rather than making every
/// shared shortcut spell out a terminal-specific modifier, an app states once —
/// at its root — which key stands in for Command here.
///
/// ```swift
/// WindowGroup { RootView() }
///     .commandKey(.control)     // ⌘S is Ctrl-S in the terminal
/// ```
///
/// TUI-specific: SwiftUI has no equivalent, because on its platforms the
/// question does not arise.
public enum CommandKeyBinding: Sendable, Hashable {
    /// Control. The default, and the only modifier every terminal reports for
    /// letters — but it collides with the C0 range; see
    /// ``KeyboardShortcut/isDeliverableInTerminal``.
    case control

    /// Option / Alt. Reported as an ESC prefix or the high bit, and only when
    /// the terminal is configured for it (Apple Terminal composes accented
    /// characters instead unless "Use Option as Meta key" is on), so this is
    /// the less reliable choice — see `Documentation/Terminal-compatibility.md`.
    case option

    /// The bare key, no modifier. Closest to how a TUI usually binds commands,
    /// and the most collision-prone: `⌘Q` becomes plain "q".
    case bare

    /// `.command` shortcuts simply do not fire. Pick this to be certain
    /// nothing is silently rebound.
    case unavailable
}

private struct CommandKeyBindingKey: EnvironmentKey {
    static let defaultValue = CommandKeyBinding.control
}

extension EnvironmentValues {
    /// Which terminal modifier stands in for Command — see
    /// ``CommandKeyBinding``. Defaults to ``CommandKeyBinding/control``.
    public var commandKey: CommandKeyBinding {
        get { self[CommandKeyBindingKey.self] }
        set { self[CommandKeyBindingKey.self] = newValue }
    }
}

extension View {
    /// Chooses which terminal modifier stands in for Command in this subtree,
    /// so SwiftUI source written with `⌘` shortcuts works unchanged.
    ///
    /// - Parameter binding: The stand-in; see ``CommandKeyBinding``.
    /// - Returns: A view whose `.command` shortcuts bind to `binding`.
    public func commandKey(_ binding: CommandKeyBinding) -> some View {
        environment(\.commandKey, binding)
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
    /// on Ctrl-Q. The event → trigger rule itself is
    /// ``KeyboardShortcut/trigger(for:)``, shared with the row-shortcut table.
    func trigger(for event: KeyEvent) -> Bool {
        guard let trigger = KeyboardShortcut.trigger(for: event) else { return false }
        return run(trigger)
    }

    /// Runs the registered action for `trigger`, reporting whether there was one.
    private func run(_ trigger: KeyboardShortcut.Trigger) -> Bool {
        guard let action = actions[trigger] else { return false }
        action()
        return true
    }
}

// MARK: - Assignment

/// The per-frame, claimable carrier ``View/keyboardShortcut(_:)``
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
    private var claimant: ViewIdentity?

    init(_ shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
    }

    /// Claims the assignment for the control at `identity`; returns nil if
    /// some other control already holds it.
    ///
    /// Keyed by identity rather than a bare "claimed" flag because a control
    /// asks more than once per frame: the measure pass needs the shortcut to
    /// size the space its hint occupies, and the render pass then needs it
    /// again to register the action. A one-shot claim would hand it to the
    /// measure and leave the render — the pass that actually registers — with
    /// nothing.
    func claim(by identity: ViewIdentity) -> KeyboardShortcut? {
        if let claimant, claimant != identity { return nil }
        claimant = identity
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
    /// ``View/keyboardShortcut(_:)``.
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
