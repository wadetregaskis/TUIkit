//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RowShortcuts.swift
//
//  The customisable keyboard bindings of a `List` / `Table` — one table, since
//  the two share one handler and one behaviour set. An app that wants them to
//  differ scopes the modifier, which is what environment values are for.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Row Action

/// A keyboard-driven operation on the rows of a ``List`` or ``Table``.
///
/// The actions with *chord* bindings, not the structural keys: arrows, Home/End
/// and Page Up/Down navigate, Return activates, and those are the control's
/// grammar rather than shortcuts to be rebound.
///
/// Cases will be added as more row operations arrive; that is a semantic-version
/// event, not a reason to avoid switching over this exhaustively.
public enum RowAction: Hashable, CaseIterable, Sendable {
    /// Select every row (multi-selection lists only).
    case selectAll

    /// Turn extend-selection mode on or off, so the arrow keys grow the
    /// selection without a modifier the terminal may not report.
    case extendSelection

    /// What TUIkit binds this action to out of the box.
    ///
    /// Control chords throughout, and deliberately: `Ctrl`+letter is not a
    /// modifier *report* that a terminal may or may not forward, it is a
    /// distinct byte in the C0 range that every terminal has sent since ASCII.
    /// Bare keys are left free for an app's own use (and for row type-ahead).
    public var defaultShortcuts: Set<KeyboardShortcut> {
        switch self {
        case .selectAll: return [KeyboardShortcut("a", modifiers: .control)]
        case .extendSelection: return [KeyboardShortcut("v", modifiers: .control)]
        }
    }
}

// MARK: - Row Shortcuts

/// The row shortcuts in force for a subtree — TUIkit's, with an app's changes
/// on top.
///
/// ```swift
/// List(selection: $selection) { … }
///     .rowShortcuts([
///         .extendSelection: [.init("e")],           // Ctrl-E instead of Ctrl-V
///         .selectAll: .default.and(.init("g")),     // Ctrl-A *and* Ctrl-G
///     ])
/// ```
///
/// An action that isn't mentioned keeps its defaults, so an override never has
/// to restate the rest of the table. See ``ShortcutSet`` for the four things a
/// value can say.
public struct RowShortcuts: Hashable, Sendable {
    /// The app's changes, by action. Empty for the stock table.
    public let overrides: [RowAction: ShortcutSet]

    /// TUIkit's own bindings, unchanged.
    public static let `default` = Self()

    public init(_ overrides: [RowAction: ShortcutSet] = [:]) {
        self.overrides = overrides
    }

    /// The keys bound to `action`, in ``KeyboardShortcut``'s own order so every
    /// caller that lists them — a help section, a status-bar hint — agrees.
    ///
    /// - Parameter commandKey: What ⌘ stands in for here; a shortcut written
    ///   the SwiftUI way (`KeyboardShortcut("g")`, i.e. ⌘G) is resolved through
    ///   it, exactly as a `Button`'s shortcut is.
    public func shortcuts(
        for action: RowAction, commandKey: CommandKeyBinding = .control
    ) -> [KeyboardShortcut] {
        let set = overrides[action] ?? .default
        return set.resolved(defaults: action.defaultShortcuts)
            .compactMap { $0.resolved(commandKey: commandKey) }
            .sorted()
    }

    /// The chord to *show* for `action` when there is only room for one — the
    /// framework's own binding if it survived, else the first in order.
    ///
    /// Adding an alias should not quietly rename the hint the user has learned.
    public func hint(
        for action: RowAction, commandKey: CommandKeyBinding = .control
    ) -> String? {
        let bound = shortcuts(for: action, commandKey: commandKey)
        let stock = action.defaultShortcuts.compactMap { $0.resolved(commandKey: commandKey) }
        return (bound.first { stock.contains($0) } ?? bound.first)?.displayString
    }

    /// The chord → action map the key handler dispatches through, built once
    /// per render rather than scanned per keystroke.
    func lookup(commandKey: CommandKeyBinding) -> RowShortcutLookup {
        var byTrigger: [KeyboardShortcut.Trigger: RowAction] = [:]
        // Defaults first, then the overrides on top: an app that binds Ctrl-A to
        // something else means it, and the default that used to hold that chord
        // yields rather than fighting over it.
        for pass in [false, true] {
            for action in RowAction.allCases {
                let set = overrides[action] ?? .default
                let shortcuts = pass ? set.explicit : (set.includesDefaults ? action.defaultShortcuts : [])
                for shortcut in shortcuts {
                    guard let resolved = shortcut.resolved(commandKey: commandKey) else { continue }
                    // Two OVERRIDES on one chord is a mistake only the app can
                    // fix, so say so — and still resolve it the same way every
                    // run (RowAction's declaration order), never by whichever
                    // way the dictionary happened to hash.
                    let clash = pass ? byTrigger[resolved.trigger] : nil
                    if let existing = clash, existing != action,
                        overrides[existing]?.explicit.contains(shortcut) == true
                    {
                        assertionFailure(
                            "rowShortcuts binds \(resolved.displayString ?? "?") to both "
                                + "\(existing) and \(action); the first wins")
                        continue
                    }
                    byTrigger[resolved.trigger] = action
                }
            }
        }
        return RowShortcutLookup(byTrigger: byTrigger)
    }
}

/// The resolved chord → action map, captured by the key handler at render time
/// (the environment is out of reach when the key actually arrives).
struct RowShortcutLookup: Sendable {
    private let byTrigger: [KeyboardShortcut.Trigger: RowAction]

    init(byTrigger: [KeyboardShortcut.Trigger: RowAction] = [:]) {
        self.byTrigger = byTrigger
    }

    /// The stock table, for a handler that never had a render to capture one
    /// (tests, and the frame before the first render).
    static let `default` = RowShortcuts.default.lookup(commandKey: .control)

    /// The action `event` triggers, if any.
    func action(for event: KeyEvent) -> RowAction? {
        KeyboardShortcut.trigger(for: event).flatMap { byTrigger[$0] }
    }
}

// MARK: - Environment

private struct RowShortcutsKey: EnvironmentKey {
    static let defaultValue = RowShortcuts.default
}

extension EnvironmentValues {
    /// The row shortcuts in force — see ``RowShortcuts``.
    public var rowShortcuts: RowShortcuts {
        get { self[RowShortcutsKey.self] }
        set { self[RowShortcutsKey.self] = newValue }
    }
}

extension View {
    /// Rebinds the keyboard shortcuts of every `List` and `Table` in this
    /// subtree.
    ///
    /// Actions not mentioned keep their defaults. A nested call *replaces* the
    /// overrides an enclosing one set (environment values cascade by
    /// replacement, as everywhere else), which is why ``ShortcutSet/default``
    /// exists: an inner scope can put one action back the way TUIkit ships it
    /// without knowing what that is.
    ///
    /// ```swift
    /// page.rowShortcuts([.extendSelection: [.init("e")]])
    /// ```
    ///
    /// - Parameter overrides: The actions to change, and what to bind them to.
    /// - Returns: A view whose lists and tables use those bindings.
    public func rowShortcuts(_ overrides: [RowAction: ShortcutSet]) -> some View {
        environment(\.rowShortcuts, RowShortcuts(overrides))
    }
}
