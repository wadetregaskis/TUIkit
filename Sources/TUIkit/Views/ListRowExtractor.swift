//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowExtractor.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - List Row

/// A single row in a list, containing an ID and rendered content.
///
/// `ListRow` wraps user-provided content and associates it with an identifier
/// for selection tracking. Rows can span multiple lines (multi-line content).
///
/// The buffer and badge are rendered lazily (see ``LazyListRowContent``): the
/// `id` is resolved eagerly, but the view is built and rendered only when the
/// row is actually shown.
struct ListRow<ID: Hashable> {
    /// The unique identifier for this row.
    let id: ID

    /// The lazily-rendered buffer + badge for this row.
    let content: LazyListRowContent

    /// The rendered content buffer for this row (forces the lazy render).
    @MainActor var buffer: FrameBuffer { content.buffer }

    /// The badge value for this row (forces the lazy render).
    @MainActor var badge: BadgeValue? { content.badge }

    /// The height of this row in lines (forces the lazy render).
    @MainActor var height: Int { content.buffer.height }

    /// Creates a row whose content is rendered on demand.
    init(id: ID, content: LazyListRowContent) {
        self.id = id
        self.content = content
    }

    /// Creates a row from an already-rendered buffer (fallback / chrome paths).
    init(id: ID, buffer: FrameBuffer, badge: BadgeValue?) {
        self.id = id
        self.content = LazyListRowContent(buffer: buffer, badge: badge)
    }
}

// MARK: - List Row Extractor Protocol

/// Protocol for views that can provide list rows with IDs.
@MainActor
protocol ListRowExtractor {
    /// Extracts list rows with their associated IDs.
    func extractListRows<ID: Hashable>(context: RenderContext) -> [ListRow<ID>]
}

// MARK: - ForEach Conformance

extension ForEach: ListRowExtractor {
    func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        data.enumerated().compactMap { (index, element) -> ListRow<RowID>? in
            // Resolve the row's selection ID up front — it's cheap (a key-path
            // read or the index) and the scroll / selection handler needs it
            // for EVERY row, on- or off-screen. Building and rendering the row
            // view, by contrast, is deferred into the lazy box below so a long
            // List only pays for the rows in its visible window.
            let elementID = element[keyPath: idKeyPath]
            let rowID: RowID
            if let id = elementID as? RowID {
                // Prefer the element's natural ID when its type matches the row
                // ID type the caller asked for.
                rowID = id
            } else if let id = index as? RowID {
                // Otherwise fall back to the row index. This makes selectionless
                // Lists with the Int-defaulted overload pick up ForEach rows
                // whose natural IDs are of a different type (e.g. String). The
                // Int-defaulted overload is what Swift's overload resolution
                // picks for `List("title") { ForEach(strings, id: \.self) {…} }`
                // because there's no other constraint to pin SelectionValue, so
                // without this fallback every element's cast would fail and the
                // list would render as empty.
                rowID = id
            } else {
                return nil
            }

            // Defer view construction, badge extraction, and rendering until the
            // row enters the visible window (see ``LazyListRowContent``).
            let rowContent = LazyListRowContent { [content] in
                let view = content(element)

                // Extract badge if the view is wrapped in a BadgeModifier. Done
                // on the bare view, before any memo wrapper, so the modifier is
                // found.
                let badge = extractBadgeValue(from: view)

                // Render the view under a per-row child identity (matching
                // ForEach.childViews) so each row's @State / focus / cache entry
                // is distinct — previously every row shared `context`'s identity.
                let rowContext = context.withChildIdentity(type: Content.self, index: index)

                // When the element is Equatable, wrap the row in a value-memo
                // keyed by the element, so an unchanged row is served from the
                // render cache instead of re-rendered. The wrapper is Renderable
                // (adds no child identity), so the inner view keeps the same
                // `rowContext` identity it would have unwrapped — the memo is
                // identity-transparent. _MemoizedRow's own gate declines to
                // cache interactive / volatile rows.
                let buffer: FrameBuffer
                if let equatableElement = element as? any Equatable {
                    buffer = TUIkit.renderToBuffer(
                        _MemoizedRow(element: AnyEquatableBox(equatableElement), content: view),
                        context: rowContext)
                } else {
                    buffer = TUIkit.renderToBuffer(view, context: rowContext)
                }
                return (buffer, badge)
            }
            return ListRow(id: rowID, content: rowContent)
        }
    }
}
