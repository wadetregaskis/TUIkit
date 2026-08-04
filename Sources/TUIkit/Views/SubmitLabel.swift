//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SubmitLabel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - SubmitLabel

/// A semantic label for the submit action of a text input — mirrors SwiftUI's
/// `SubmitLabel`.
///
/// In SwiftUI this renders on the on-screen keyboard's Return key ("Go", "Send",
/// "Search", …). A terminal has no such key, so ``View/submitLabel(_:)``
/// stores the value for source-compatibility and future affordances (e.g. a
/// status-bar "Return  Send" hint) rather than drawing anything by default.
///
/// Modelled as an opaque struct with static members, exactly like SwiftUI, so
/// the set of labels can grow without a source break (a `public enum` could not).
public struct SubmitLabel: Sendable, Equatable, Hashable {
    /// The distinct labels, kept internal so ``SubmitLabel`` stays opaque.
    enum Kind: Sendable, Hashable {
        case done, go, send, join, route, search, `return`, next, `continue`
    }

    let kind: Kind

    /// "Done".
    public static let done = Self(kind: .done)
    /// "Go".
    public static let go = Self(kind: .go)
    /// "Send".
    public static let send = Self(kind: .send)
    /// "Join".
    public static let join = Self(kind: .join)
    /// "Route".
    public static let route = Self(kind: .route)
    /// "Search".
    public static let search = Self(kind: .search)
    /// "Return".
    public static let `return` = Self(kind: .return)
    /// "Next".
    public static let next = Self(kind: .next)
    /// "Continue".
    public static let `continue` = Self(kind: .continue)

    /// A short human-readable title for the label, for a future status-bar Return
    /// hint. Internal for now — nothing draws it yet.
    var title: String {
        switch kind {
        case .done: return "Done"
        case .go: return "Go"
        case .send: return "Send"
        case .join: return "Join"
        case .route: return "Route"
        case .search: return "Search"
        case .return: return "Return"
        case .next: return "Next"
        case .continue: return "Continue"
        }
    }
}
