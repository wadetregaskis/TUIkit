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
    ///
    /// `reservesSpace` makes the count a floor as well as a ceiling: the text
    /// occupies exactly that many lines whether or not it needs them. It
    /// travels WITH the count rather than beside it because that is what it
    /// qualifies — a descendant that states a new limit is stating a new
    /// reservation too, and a `Bool` of its own would linger over it.
    case lines(Int, reservesSpace: Bool = false)

    /// The cap as a row count, or `nil` for ``unlimited`` — the form the
    /// wrapping code wants.
    var rowCount: Int? {
        switch self {
        case .unlimited: nil
        case .lines(let count, _): max(1, count)
        }
    }

    /// The number of lines that must be occupied however short the text is, or
    /// `nil` when it may shrink to fit.
    var reservedLines: Int? {
        switch self {
        case .lines(let count, true): max(1, count)
        default: nil
        }
    }

    /// Builds a limit from SwiftUI's `Int?` spelling, where `nil` is
    /// *unlimited* rather than *unset*.
    init(_ limit: Int?, reservesSpace: Bool = false) {
        self = limit.map { .lines($0, reservesSpace: reservesSpace) } ?? .unlimited
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

    /// Caps text in this subtree at `limit` lines, and — when `reservesSpace`
    /// is true — makes it occupy that many whether it needs them or not.
    /// Matches SwiftUI's `lineLimit(_:reservesSpace:)`.
    ///
    /// The reservation is what a list of rows wants. Without it a row whose
    /// subtitle happens to wrap is one line taller than its neighbours, and the
    /// whole column shuffles as the data changes:
    ///
    /// ```swift
    /// ForEach(items) { item in
    ///     VStack(alignment: .leading) {
    ///         Text(item.title)
    ///         Text(item.subtitle).lineLimit(2, reservesSpace: true)
    ///     }
    /// }
    /// ```
    ///
    /// Every row is now the same height, and the short subtitles simply leave a
    /// blank line where the second one would go.
    ///
    /// The floor is honoured only as far as the parent allows: squeezed into
    /// fewer rows than it reserved, the text draws what fits rather than
    /// spilling out of the space it was given.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of lines.
    ///   - reservesSpace: Whether the text also occupies that many lines when
    ///     it is shorter.
    /// - Returns: A view whose descendant text is capped, and optionally
    ///   padded, at `limit` lines.
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        environment(\.lineLimit, LineLimit(limit, reservesSpace: reservesSpace))
    }
}
