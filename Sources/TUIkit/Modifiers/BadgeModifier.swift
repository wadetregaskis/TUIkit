//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BadgeModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that displays a decorative badge on a view.
///
/// Badges are typically used with List rows to show counts, status,
/// or other labels. The badge is rendered right-aligned and styled
/// with a dimmed foreground color.
///
/// The badge value is stored in the environment and propagates to
/// child views. Badges automatically hide when:
/// - The count is 0 (for integer badges)
/// - The label is nil (for optional Text/String badges)
public struct BadgeModifier<Content: View>: View {
    /// The content to apply the badge to.
    let content: Content

    /// The badge value (Int, Text, or String).
    let value: BadgeValue

    public var body: Never {
        fatalError("BadgeModifier renders via Renderable")
    }
}

// MARK: - Badge Value

/// Represents a badge value that can be Int or String.
public enum BadgeValue: Sendable {
    /// An integer badge (0 hides the badge).
    case int(Int)

    /// A String badge (nil hides the badge).
    case string(String?)

    /// Returns true if the badge should be hidden.
    public var isHidden: Bool {
        switch self {
        case .int(let intValue):
            return intValue == 0
        case .string(let string):
            return string == nil || string?.isEmpty == true
        }
    }

    /// Returns the display text for the badge.
    public var displayText: String {
        switch self {
        case .int(let intValue):
            return "\(intValue)"
        case .string(let string):
            return string ?? ""
        }
    }
}

// MARK: - Equatable

extension BadgeModifier: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: BadgeModifier<Content>, rhs: BadgeModifier<Content>) -> Bool {
        lhs.content == rhs.content && lhs.value == rhs.value
    }
}

extension BadgeValue: Equatable {
    public static func == (lhs: BadgeValue, rhs: BadgeValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let lhsValue), .int(let rhsValue)):
            return lhsValue == rhsValue
        case (.string(let lhsString), .string(let rhsString)):
            return lhsString == rhsString
        default:
            return false
        }
    }
}

// MARK: - Badge Extraction

/// Type-erased peek at a ``BadgeModifier``'s value. A protocol conformance
/// check is a cached runtime lookup; the `Mirror` walk it replaces ran on
/// EVERY row of every `List` frame and profiled at 8% of a plain list render
/// (session-list-after.trace, 2026-07-31) — almost all of it for rows with no
/// badge at all.
@MainActor
private protocol BadgeCarrying {
    var carriedBadgeValue: BadgeValue { get }
}

extension BadgeModifier: BadgeCarrying {
    fileprivate var carriedBadgeValue: BadgeValue { value }
}

/// Extracts the badge value from a view if it's wrapped in a BadgeModifier.
///
/// This is used by List to extract badge values during row extraction.
@MainActor
public func extractBadgeValue<V: View>(from view: V) -> BadgeValue? {
    (view as? any BadgeCarrying)?.carriedBadgeValue
}

/// Whether ``extractBadgeValue(from:)`` could ever answer for a view of
/// `type` — a static property of the row TYPE, no instance needed.
///
/// For a caller that defers building its rows (`List`'s windowed extraction,
/// where an unchanged row is served from the render cache without being
/// built), this is what makes the badge peek free for the overwhelmingly
/// common badge-less row: `extractBadgeValue` needs the BUILT view, and
/// building one every frame just to hear "no badge" was the last per-row
/// construction left on the hit path.
@MainActor
public func viewTypeCarriesBadge<V: View>(_ type: V.Type) -> Bool {
    type is any BadgeCarrying.Type
}

/// The badge a `List` ROW carries — ``extractBadgeValue(from:)``, but seeing
/// past `ForEach`'s value memo.
///
/// The two walks that read a row's badge off its view value — `_ListCore`'s
/// child walk (a `ForEach` with a static row beside it) and `Section`'s — are
/// handed the child as it comes out of `ForEach.makeChild`, which wraps an
/// `Equatable`-element row in `_MemoizedRow`. That wrapper is `Renderable` and
/// therefore *opaque* to the cast above, so the badge on every such row was
/// simply not there: `List { Text("Inbox").badge(7); ForEach(names) {
/// Text($0).badge(9) } }` drew the 7 and none of the 9s. This is the same
/// wrapper-eats-metadata shape `_ListCore.sectionRow(of:)` goes through
/// ``_ValueMemoWrapping`` for, and it goes through it the same way.
///
/// The memo's TYPE is asked before its content, which is what keeps this free:
/// ``_ValueMemoWrapping/memoizedContent`` BUILDS the row, and the whole point
/// of the memo is that in steady state most rows are never built. A row whose
/// static type cannot carry a badge — all but a `.badge(_:)`-outermost row —
/// is answered by the type check alone, exactly as the windowed path's
/// ``viewTypeCarriesBadge(_:)`` gate answers it there.
///
/// Only a row that really IS badged is built here. Where the memo then misses,
/// it builds that row a second time for its buffer — which is precisely what
/// the windowed path already pays for a badged row
/// (`extractBadgeValue(from: content(element))` beside the memoized render);
/// where the memo hits, it builds nothing and this is the only build. So the
/// two arrangements are priced alike, instead of the badge being cheap in one
/// and absent in the other.
@MainActor
func extractRowBadgeValue(from view: any View) -> BadgeValue? {
    if let badge = extractBadgeValue(from: view) { return badge }
    guard let memo = view as? any _ValueMemoWrapping,
        viewTypeCarriesBadge(memo.memoizedContentType)
    else { return nil }
    return extractBadgeValue(from: memo.memoizedContent)
}

// MARK: - Renderable

extension BadgeModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Create modified environment with badge value.
        let modifiedEnvironment = context.environment.setting(\EnvironmentValues.badgeValue, to: value)
        let modifiedContext = context.withEnvironment(modifiedEnvironment)

        // Render content with the badge in environment.
        return TUIkit.renderToBuffer(content, context: modifiedContext)
    }
}

// MARK: - Layoutable

extension BadgeModifier: Layoutable {
    /// Measures `content` under the *same* badge-bearing environment the render
    /// uses: a child that draws the badge (a tab, a list row) sizes differently
    /// with it set, so the plain context would under-measure.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let modifiedContext = context.withEnvironment(
            context.environment.setting(\EnvironmentValues.badgeValue, to: value))
        return measureChild(content, proposal: proposal, context: modifiedContext)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension BadgeModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension BadgeModifier: DrawsContentUnchanged {}
