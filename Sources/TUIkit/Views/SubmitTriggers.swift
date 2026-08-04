//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SubmitTriggers.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - SubmitTriggers

/// The kinds of submit an ``View/onSubmit(of:_:)`` action responds
/// to — mirrors SwiftUI's `SubmitTriggers`.
///
/// A plain ``TextField`` / ``SecureField`` submits with ``text``; the field
/// inside a ``View/searchable(text:placement:prompt:)-(_,_,Text?)`` search
/// affordance submits with ``search``. An `.onSubmit` scoped to `[.text,
/// .search]` fires for both.
public struct SubmitTriggers: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Submitting a text field (Return in a ``TextField`` / ``SecureField``).
    public static let text = Self(rawValue: 1 << 0)

    /// Submitting a search field (Return in a `.searchable` query field).
    public static let search = Self(rawValue: 1 << 1)
}
