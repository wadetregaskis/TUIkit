//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SelectableListRow.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - List Row Type

/// Defines the type of a row in a List, controlling selectability and focus behavior.
///
/// Section headers and footers are non-selectable visual separators, while content rows
/// are individually selectable and focusable. This enum provides type-safe classification.
public enum ListRowType<SelectionValue: Hashable & Sendable>: Sendable, Equatable {
    /// A section header (non-selectable, non-focusable).
    ///
    /// Headers render with dimmed styling and never participate in selection or focus.
    case header

    /// A content row with a selectable ID.
    ///
    /// Content rows are individually selectable and focusable. The associated ID
    /// is used for selection binding and focus navigation.
    case content(id: SelectionValue)

    /// A section footer (non-selectable, non-focusable).
    ///
    /// Footers render with dimmed styling and never participate in selection or focus.
    case footer
}

// MARK: - Lazy Row Content

/// A row's rendered buffer and badge, produced on demand and then memoised.
///
/// `List` extraction builds one of these per row but renders *none* up front:
/// the closure runs only when a row enters the visible window (or, for a list
/// short enough that it might fit, when the overflow check has to sum a few
/// heights). A 2,000-row list therefore renders ~viewport rows per frame
/// instead of all 2,000 — the per-frame cost becomes O(visible), not O(total).
/// The result is cached so the windowing, width, and compose passes that each
/// read the buffer don't trigger a re-render.
///
/// Rendering runs the view pipeline, which is `@MainActor`, so this box is
/// `@MainActor` too. That also makes it `Sendable`, which is what lets
/// ``SelectableListRow`` remain `Sendable` while carrying deferred content.
@MainActor
final class LazyListRowContent {
    private var thunk: (() -> (buffer: FrameBuffer, badge: BadgeValue?))?
    private var cached: (buffer: FrameBuffer, badge: BadgeValue?)?

    /// Defers rendering until the buffer (or badge) is first read.
    init(_ render: @escaping () -> (buffer: FrameBuffer, badge: BadgeValue?)) {
        self.thunk = render
    }

    /// Wraps an already-rendered buffer. Used for section headers/footers and
    /// the single-row fallbacks — there are only ever a handful of those and
    /// they are always shown, so deferring them would buy nothing.
    ///
    /// `nonisolated` so the (nonisolated) `SelectableListRow` / `ListRow`
    /// buffer initializers can wrap an already-rendered buffer without hopping
    /// to the main actor — it only stores a `Sendable` tuple, runs no pipeline.
    nonisolated init(buffer: FrameBuffer, badge: BadgeValue?) {
        self.cached = (buffer, badge)
    }

    private var resolved: (buffer: FrameBuffer, badge: BadgeValue?) {
        if let cached { return cached }
        let value = thunk!()
        cached = value
        thunk = nil  // release the captured view / context
        return value
    }

    var buffer: FrameBuffer { resolved.buffer }
    var badge: BadgeValue? { resolved.badge }
}

// MARK: - Selectable List Row

/// A List row with type information for selection and focus handling.
///
/// This structure replaces the generic ListRow to provide type-safe classification
/// of rows as headers, content, or footers. The type determines:
/// - Whether the row is selectable/focusable
/// - How the row renders (dimmed for headers/footers, normal for content)
/// - Whether the row ID participates in selection binding
///
/// The row's ``buffer`` and ``badge`` are rendered lazily (see
/// ``LazyListRowContent``): a `List` builds one row per item but only the rows
/// in the visible window are ever rendered. ``type``/``id``/``isSelectable``
/// are resolved eagerly and cheaply, which is all the scroll/selection handler
/// needs for off-screen rows.
public struct SelectableListRow<SelectionValue: Hashable & Sendable>: Sendable {
    /// The row type (header, content with ID, or footer).
    public let type: ListRowType<SelectionValue>

    /// The lazily-rendered buffer + badge for this row.
    let content: LazyListRowContent

    /// The rendered content buffer.
    ///
    /// Forces the lazy render on first access (then memoised). Only ever read
    /// for rows in the visible window, so off-screen rows never render.
    @MainActor public var buffer: FrameBuffer { content.buffer }

    /// The badge value for this row (from environment). Forces the lazy render.
    @MainActor public var badge: BadgeValue? { content.badge }

    /// Creates a selectable list row with type, buffer, and optional badge.
    ///
    /// The buffer is already rendered; use this for chrome (section
    /// headers/footers) and fallback single-row cases. The hot ForEach path
    /// uses the lazy initializer instead.
    ///
    /// - Parameters:
    ///   - type: The row type (header, content, or footer).
    ///   - buffer: The rendered row content.
    ///   - badge: The badge value for this row (default: nil).
    public init(type: ListRowType<SelectionValue>, buffer: FrameBuffer, badge: BadgeValue? = nil) {
        self.type = type
        self.content = LazyListRowContent(buffer: buffer, badge: badge)
    }

    /// Creates a selectable list row whose content is rendered on demand.
    init(type: ListRowType<SelectionValue>, content: LazyListRowContent) {
        self.type = type
        self.content = content
    }

    /// Indicates whether this row can be selected and focused.
    ///
    /// Only content rows are selectable. Headers and footers are always false.
    public var isSelectable: Bool {
        if case .content = type {
            return true
        }
        return false
    }

    /// The row ID if this is a content row, otherwise nil.
    ///
    /// Only content rows have an ID. Headers and footers always return nil.
    public var id: SelectionValue? {
        if case .content(let id) = type {
            return id
        }
        return nil
    }
}
