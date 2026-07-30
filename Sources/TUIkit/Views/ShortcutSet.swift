//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ShortcutSet.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Shortcut Set

/// The keys bound to one action: the framework's own, an app's own, or both.
///
/// Written as a value in a shortcut table (see ``RowShortcuts``), where the four
/// things an app might want to say each have a spelling of their own:
///
/// ```swift
/// .rowShortcuts([
///     .pickUpRow:       .default.and(.init("g")),   // ours, plus Ctrl-G
///     .extendSelection: [.init("e")],               // just Ctrl-E
///     .selectAll:       .unbound,                   // nothing at all
///     // an action not mentioned keeps its defaults
/// ])
/// ```
///
/// ``default`` is what makes "add one more" possible without hard-coding what
/// the framework currently binds — and what makes restoring a binding possible
/// in a nested scope, which an optional could not express unambiguously (`nil`
/// reads as both "no shortcut" and "the usual one").
///
/// The set is unordered on purpose. ``KeyboardShortcut`` is `Comparable`, so
/// everything that *displays* a binding sorts it the same way rather than
/// depending on the order some call site happened to write.
public struct ShortcutSet: Hashable, Sendable, ExpressibleByArrayLiteral {
    /// Whether the framework's own bindings for the action are included.
    public let includesDefaults: Bool

    /// The bindings the app added, over and above the defaults.
    public let explicit: Set<KeyboardShortcut>

    private init(includesDefaults: Bool, explicit: Set<KeyboardShortcut>) {
        self.includesDefaults = includesDefaults
        self.explicit = explicit
    }

    /// Whatever the framework binds to the action — the same as not mentioning
    /// the action at all, and the thing to say when an enclosing scope has
    /// rebound it and this subtree wants the stock behaviour back.
    public static let `default` = Self(includesDefaults: true, explicit: [])

    /// Nothing: the action cannot be reached from the keyboard. The same as an
    /// empty literal (`[]`), spelled out for when that reads better.
    public static let unbound = Self(includesDefaults: false, explicit: [])

    /// Exactly these, replacing the framework's.
    public static func only(_ shortcuts: KeyboardShortcut...) -> Self {
        Self(includesDefaults: false, explicit: Set(shortcuts))
    }

    /// These as well — `.default.and(…)` keeps the framework's bindings and
    /// adds to them, `.only(…).and(…)` extends an explicit set.
    public func and(_ shortcuts: KeyboardShortcut...) -> Self {
        Self(includesDefaults: includesDefaults, explicit: explicit.union(shortcuts))
    }

    /// An array literal is ``only(_:)`` — so `[]` is ``unbound`` and
    /// `[chord]` replaces the defaults with that one chord.
    public init(arrayLiteral elements: KeyboardShortcut...) {
        self.init(includesDefaults: false, explicit: Set(elements))
    }

    /// The keys this set actually binds, given what the framework binds.
    func resolved(defaults: Set<KeyboardShortcut>) -> Set<KeyboardShortcut> {
        includesDefaults ? explicit.union(defaults) : explicit
    }
}

// MARK: - Ordering

extension KeyEquivalent: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.character < rhs.character
    }
}

extension KeyboardShortcut: Comparable {
    /// A total order, so that everything which lists bindings — a help section,
    /// a status-bar hint, a settings screen — presents them the same way.
    ///
    /// The semantic roles sort ahead of key chords (they are the app-level ones,
    /// and they have no key to compare); chords sort by their key, then by their
    /// modifiers, so the same letter's plain / Control / Option forms stay
    /// together in that order.
    ///
    /// It is deliberately an ordering of the *shortcut*, not of the order some
    /// call site listed them in: a display order that depends on authoring order
    /// is stable only while every call site is careful.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    /// `(role rank, key, modifiers)` — `Character` and `Int` are both
    /// `Comparable`, so the tuple comparison is the whole ordering.
    private var sortKey: (Int, Character, Int) {
        switch trigger {
        case .defaultAction: return (0, " ", 0)
        case .cancelAction: return (1, " ", 0)
        case .key(let key, let modifiers): return (2, key.character, modifiers.rawValue)
        }
    }
}
