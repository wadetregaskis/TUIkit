//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IdentityKey.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Element identity keys

/// The stable string key for a data element's `id`.
///
/// `ForEach` keys each row's identity by its element's id rather than its
/// position, so a row's `@State`, focus and lifecycle follow the element across
/// reorders and insertions. Scroll targeting (`ScrollViewReader.scrollTo(_:)`,
/// `ScrollPosition`, `ScrollAnchor`) addresses the same rows by the same key.
/// **Every one of those sites must derive the key the same way**, or a scroll
/// request silently fails to match the row it names — which is the first reason
/// this is one function rather than a `String(describing:)` at each call site.
///
/// The second is cost. `String(describing:)` cannot print anything until it has
/// probed the value for `TextOutputStreamable`, `CustomStringConvertible` and
/// `CustomDebugStringConvertible` — three runtime conformance lookups, then an
/// existential box, then the formatting itself. It runs once per row per layout
/// pass. In a Time Profiler trace of the `fanout` stress scenario it was
/// **5.1% of all CPU**, effectively all of it inside `swift_dynamicCast`.
///
/// Element ids are, in practice, a very short list of types. Each one below is
/// matched by a metatype comparison — a pointer compare, no conformance lookup
/// — and printed directly.
///
/// - Important: The metatype comparison is not redundant with the cast that
///   follows it. A dynamic cast looks *through* `Optional` and `AnyHashable`,
///   so `id as? Int` alone would succeed for an `Int?` id and yield `"5"` where
///   `String(describing:)` yields `"Optional(5)"` — silently re-keying every
///   row that uses an optional id. Requiring `ID.self == Int.self` first pins
///   the fast path to ids that genuinely are that type; everything else falls
///   through to `String(describing:)` and is unchanged.
///
/// - Parameter id: The element's identifier.
/// - Returns: `String(describing: id)`, by a cheaper route for common id types.
public func identityKey<ID>(_ id: ID) -> String {
    if ID.self == String.self, let value = id as? String { return value }
    if ID.self == Int.self, let value = id as? Int { return String(value) }
    if ID.self == UUID.self, let value = id as? UUID { return value.uuidString }
    return String(describing: id)
}
