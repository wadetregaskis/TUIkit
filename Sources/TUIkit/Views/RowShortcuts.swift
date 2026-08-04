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

    /// Pick the focused row up, or put it down where it now is — a reorder
    /// driven from the keyboard, for lists that take `onMove`.
    case pickUpRow

    /// Drop the row being carried at the slot it is showing.
    case placeRow

    /// Abandon the move and put the row back where it was picked up.
    case cancelMove

    /// Move the focused row one place up, with no mode to enter or leave.
    case moveRowUp

    /// Move the focused row one place down.
    case moveRowDown

    /// Send the focused row to the top of the list.
    case moveRowToTop

    /// Send the focused row to the bottom.
    case moveRowToBottom

    /// Move the focused row up by a screenful.
    case moveRowPageUp

    /// Move the focused row down by a screenful.
    case moveRowPageDown

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
        // "reorder". Ctrl-R is free: it collides with nothing in TUIkit and
        // with no C0 key (unlike Ctrl-M, which IS Return).
        case .pickUpRow: return [KeyboardShortcut("r", modifiers: .control)]
        // Return and Escape, but only while a row is actually in hand — the
        // one place this control's grammar changes, and the status bar says so.
        case .placeRow: return [.defaultAction]
        case .cancelMove: return [.cancelAction]
        // The editor convention (VS Code's ⌥↑/↓, Xcode's ⌘⌥[/]) as far as a
        // terminal allows it — and it does NOT allow it everywhere: Apple
        // Terminal sends bare ESC[A/B for Up/Down and drops the modifier, so
        // this chord is undeliverable there. That is why it is an accelerator
        // and ``pickUpRow`` is the feature: the mode needs no modifiers at all.
        //
        // TWO chords each, because neither one works everywhere. macOS itself
        // eats ⌃↑/⌃↓ (Mission Control / Application Windows) before any
        // terminal sees them, so on a stock Mac they are dead — but they are
        // the natural binding on Linux, where nothing intercepts them. Option
        // is what macOS leaves alone, and the parser reads it from both the
        // ESC-prefixed and the xterm `;3` forms; Apple Terminal needs "Use
        // Option as Meta key" turned on, and even then strips modifiers from
        // Up/Down specifically. Hence ``pickUpRow``, which needs no modifier
        // at all, remains the route that always works.
        case .moveRowUp:
            return [
                KeyboardShortcut(.upArrow, modifiers: .control),
                KeyboardShortcut(.upArrow, modifiers: .option),
            ]
        case .moveRowDown:
            return [
                KeyboardShortcut(.downArrow, modifiers: .control),
                KeyboardShortcut(.downArrow, modifiers: .option),
            ]
        // Home/End/Page keep their modifiers in more terminals than the arrows
        // do, so these have one binding each.
        case .moveRowToTop: return [KeyboardShortcut(.home, modifiers: .option)]
        case .moveRowToBottom: return [KeyboardShortcut(.end, modifiers: .option)]
        case .moveRowPageUp: return [KeyboardShortcut(.pageUp, modifiers: .option)]
        case .moveRowPageDown: return [KeyboardShortcut(.pageDown, modifiers: .option)]
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
    /// - Parameters:
    ///   - action: The row action whose bound keys are wanted.
    ///   - commandKey: What ⌘ stands in for here; a shortcut written
    ///     the SwiftUI way (`KeyboardShortcut("g")`, i.e. ⌘G) is resolved
    ///     through it, exactly as a `Button`'s shortcut is.
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

    /// The action `event` triggers, if any, and whether Shift was riding along
    /// as an accelerator rather than as part of the binding.
    ///
    /// Shift is looked up first as part of the chord, so an app CAN bind
    /// something to it explicitly; only if that finds nothing is it stripped
    /// and retried. That is what makes Option+Shift+↑ mean "the Option+↑ move,
    /// several rows at a time" without every move action needing a second
    /// binding — the same shape the arrow keys already use for the cursor.
    func action(for event: KeyEvent) -> (action: RowAction, accelerated: Bool)? {
        if let exact = KeyboardShortcut.trigger(for: event).flatMap({ byTrigger[$0] }) {
            return (exact, false)
        }
        guard event.shift else { return nil }
        let unshifted = KeyEvent(key: event.key, ctrl: event.ctrl, alt: event.alt)
        return KeyboardShortcut.trigger(for: unshifted).flatMap { byTrigger[$0] }
            .map { ($0, true) }
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
