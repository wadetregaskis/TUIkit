//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineLimitEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - LineLimit

/// How many lines a piece of text may occupy — a *decided* answer, which
/// "unset" is not.
///
/// SwiftUI spells a line limit `Int?`, where `nil` means **unlimited**. That
/// works for a modifier argument but not for a stored value that also has to
/// record whether anybody set one: a cascading `.lineLimit(2)` needs a `Text`
/// to be able to say "no limit for me", and with a bare `Int?` that is the same
/// value as "nobody said", so an inherited limit could never be reset. The two
/// meanings therefore get separate spellings: this type says what the limit IS,
/// and `Optional` around it says whether it was stated.
///
/// The public modifiers still take `Int?`, matching SwiftUI exactly. This is
/// what they store.
public enum LineLimit: Sendable, Equatable {
    /// No cap — the text occupies as many lines as it needs (or as its
    /// container allows).
    case unlimited

    /// At most `count` lines; the last one absorbs the remainder and is
    /// truncated. Clamped to at least 1 where it is applied, so `.lines(0)`
    /// cannot render a text away entirely.
    case lines(Int)

    /// The cap as a row count, or `nil` for ``unlimited`` — the form the
    /// wrapping code wants.
    var rowCount: Int? {
        switch self {
        case .unlimited: nil
        case .lines(let count): max(1, count)
        }
    }

    /// Builds a limit from SwiftUI's `Int?` spelling, where `nil` is
    /// *unlimited* rather than *unset*.
    init(_ limit: Int?) {
        self = limit.map(Self.lines) ?? .unlimited
    }
}

// MARK: - Environment key

private struct LineLimitKey: EnvironmentKey {
    /// Unlimited by default, as in SwiftUI: text wraps until something else
    /// stops it.
    static let defaultValue: LineLimit = .unlimited
}

extension EnvironmentValues {
    /// The line limit cascaded by ``View/lineLimit(_:)``, which every ``Text``
    /// below obeys unless it set its own.
    ///
    /// Defaults to ``LineLimit/unlimited``.
    public var lineLimit: LineLimit {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the maximum number of lines text in this subtree may occupy.
    /// Matches SwiftUI's `lineLimit(_:)`.
    ///
    /// ```swift
    /// VStack {
    ///     ForEach(messages) { Text($0.body) }
    /// }
    /// .lineLimit(2)               // every message shows at most two lines
    /// ```
    ///
    /// Pass `nil` for no limit — which, inside a subtree that cascaded one, is
    /// how a branch opts back out:
    ///
    /// ```swift
    /// VStack {
    ///     Text(summary)           // two lines
    ///     Text(detail).lineLimit(nil)   // as many as it needs
    /// }
    /// .lineLimit(2)
    /// ```
    ///
    /// A ``Text``'s own ``Text/lineLimit(_:)`` wins over this for that one
    /// view, exactly as ``Text/truncationMode(_:)`` wins over
    /// ``View/truncationMode(_:)``. Where the text is cut is that separate
    /// choice; this only says how many lines there are.
    ///
    /// A ``Table``'s cells are values rather than views, so a column's line
    /// count stays its own — see ``TableColumn/lineLimit(_:)``.
    ///
    /// - Parameter number: The maximum number of lines, or `nil` for no limit.
    /// - Returns: A view whose descendant text is capped at `number` lines.
    public func lineLimit(_ number: Int?) -> some View {
        environment(\.lineLimit, LineLimit(number))
    }
}
