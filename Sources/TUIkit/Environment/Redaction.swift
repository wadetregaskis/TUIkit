//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Redaction.swift
//
//  Hiding content while keeping its shape — placeholder skeletons, private
//  values, stale data.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Reasons

/// The reasons a view's content might be hidden, mirroring SwiftUI's
/// `RedactionReasons`.
///
/// An option set, so reasons combine: a view can be both a placeholder and
/// privacy-sensitive.
public struct RedactionReasons: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The content is not available yet — draw its skeleton.
    ///
    /// Text is replaced with a shade glyph per cell, keeping the spaces, so the
    /// result has the length and word rhythm of the real thing.
    public static let placeholder = Self(rawValue: 1 << 0)

    /// The content is stale: shown, but marked as no longer trustworthy.
    ///
    /// Rendered dim rather than replaced — an out-of-date figure is still worth
    /// reading, which is the whole point of the distinction.
    public static let invalidated = Self(rawValue: 1 << 1)

    /// The content is private and should not be shown.
    ///
    /// Redacted the same way as ``placeholder``: a terminal has no blur.
    public static let privacy = Self(rawValue: 1 << 2)
}

extension RedactionReasons {
    /// The glyph a redacted cell is filled with.
    ///
    /// A light shade rather than a full block: it reads as "something belongs
    /// here" instead of as a solid bar of foreground colour, and it stays
    /// legible on both light and dark palettes.
    static let glyph: Character = "░"

    /// Whether these reasons replace the text rather than merely restyle it.
    var replacesContent: Bool {
        contains(.placeholder) || contains(.privacy)
    }

    /// `text` as it should be DRAWN under these reasons.
    ///
    /// Cell-preserving, not character-preserving: a double-width character
    /// becomes *two* glyphs, so a redacted CJK or emoji string occupies exactly
    /// the columns the real one did. Counting characters here would silently
    /// halve the width of any non-Latin text — the cells-not-characters trap.
    ///
    /// Spaces and newlines survive, so wrapping still breaks in the same places
    /// and the skeleton keeps the shape of the sentence it stands in for.
    func redacting(_ text: String) -> String {
        guard replacesContent, !text.isEmpty else { return text }
        var redacted = ""
        redacted.reserveCapacity(text.count)
        for character in text {
            if character.isWhitespace {
                redacted.append(character)
            } else {
                redacted.append(
                    String(repeating: Self.glyph, count: max(1, character.terminalWidth)))
            }
        }
        return redacted
    }
}

// MARK: - Environment

private struct RedactionReasonsKey: EnvironmentKey {
    static let defaultValue = RedactionReasons()
}

extension EnvironmentValues {
    /// Why the content in this environment is hidden, if it is.
    ///
    /// Read this to redact something the framework cannot redact for you — a
    /// procedurally-drawn control, say:
    ///
    /// ```swift
    /// @Environment(\.redactionReasons) private var reasons
    /// // ...
    /// if reasons.contains(.placeholder) { … }
    /// ```
    public var redactionReasons: RedactionReasons {
        get { self[RedactionReasonsKey.self] }
        set { self[RedactionReasonsKey.self] = newValue }
    }
}

// MARK: - Modifiers

extension View {
    /// Hides this view's content for the given reason.
    ///
    /// The standard use is a loading state that keeps its layout, so nothing
    /// jumps when the real content arrives:
    ///
    /// ```swift
    /// ArticleRow(article: article ?? .placeholder)
    ///     .redacted(reason: article == nil ? .placeholder : [])
    /// ```
    ///
    /// Redaction cascades: every ``Text`` beneath this point is drawn as a
    /// skeleton. Chrome — borders, scrollbars, a control's own glyphs — is not
    /// redacted, matching SwiftUI, where redaction hides content rather than
    /// structure.
    ///
    /// - Parameter reason: The reasons to add to those already in force.
    /// - Returns: A view whose content is redacted.
    public func redacted(reason: RedactionReasons) -> some View {
        RedactionScope(added: reason, content: self)
    }

    /// Removes any redaction applied above this view.
    ///
    /// For the one element that must stay readable inside a redacted subtree —
    /// a heading, a control the user can still press.
    ///
    /// - Returns: A view whose content is not redacted.
    public func unredacted() -> some View {
        environment(\.redactionReasons, [])
    }
}

/// Adds reasons to whatever is already in force, rather than replacing them.
///
/// `redacted(reason:)` *adds*, so it has to read the inherited value before it
/// can write one — and `environment(_:_:)` only writes. Reading it here, in a
/// view's own body, and then deferring to the ordinary
/// `EnvironmentModifier` keeps the render cache's environment-change tracking
/// intact; writing `environment.setting(_:to:)` by hand would skip
/// `noteAppliedEnvironment`, and a memoized subtree would never learn the
/// redaction had changed.
private struct RedactionScope<Content: View>: View {
    @Environment(\.redactionReasons) private var inherited
    let added: RedactionReasons
    let content: Content

    var body: some View {
        content.environment(\.redactionReasons, inherited.union(added))
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension RedactionScope: ContentRewrapping {
    var wrappedContent: Content { content }

    func rewrapping<V: View>(_ view: V) -> any View {
        RedactionScope<V>(added: added, content: view)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension RedactionScope: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension RedactionScope: GridRowProviding where Content: GridRowProviding {}
