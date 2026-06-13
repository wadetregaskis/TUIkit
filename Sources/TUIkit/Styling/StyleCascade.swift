//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleCascade.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Style cascade

/// The ordered set of scoped style entries an ancestor chain has contributed,
/// carried down the view tree in the environment (`EnvironmentValues.styleCascade`).
///
/// Entries are stored **outermost-first**: each container-level style modifier
/// appends as the environment propagates down, so the last entries are the
/// closest to the view. Resolution merges every entry whose scope matches the
/// view, applying each `merged(over:)` the accumulator — so, **per property, the
/// closest (innermost) matching entry wins**. This is SwiftUI's "nearest modifier
/// wins" rule, generalised with scopes.
///
/// Within a single application point — a `Theme` bundle or one multi-scope
/// `.style` call — entries are appended in ``StyleScope/specificity`` order
/// (broad first, specific last) so the more specific wins there, while any deeper
/// subtree entry still wins by proximity.
public struct StyleCascade: Sendable, Equatable {

    /// One scoped contribution.
    public struct Entry: Sendable, Equatable {
        public let scope: StyleScope
        public let attributes: StyleAttributes

        public init(scope: StyleScope, attributes: StyleAttributes) {
            self.scope = scope
            self.attributes = attributes
        }
    }

    private var entries: [Entry]

    /// An empty cascade (the environment default).
    public init() {
        self.entries = []
    }

    /// Whether no entries have been contributed.
    public var isEmpty: Bool { entries.isEmpty }

    /// Returns a copy with `(scope, attributes)` appended as the new innermost
    /// (closest) entry. No-op for empty attributes.
    public func appending(_ scope: StyleScope, _ attributes: StyleAttributes) -> StyleCascade {
        guard !attributes.isEmpty else { return self }
        var copy = self
        copy.entries.append(Entry(scope: scope, attributes: attributes))
        return copy
    }

    /// The effective attributes for a view matching any of `scopes`, resolved
    /// per property with the closest matching entry winning.
    public func resolve(for scopes: Set<StyleScope>) -> StyleAttributes {
        var result = StyleAttributes()
        for entry in entries where scopes.contains(entry.scope) {
            // entries are outermost-first, so a later (inner) entry merged over
            // the accumulator overrides — innermost wins, per property.
            result = entry.attributes.merged(over: result)
        }
        return result
    }
}
