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

/// Protocol for views that can provide list rows with IDs (eagerly).
///
/// Used by `Section`, whose row set is small and structured. The hot path for a
/// large flat `List` is ``WindowedListRowExtractor`` instead.
@MainActor
protocol ListRowExtractor {
    /// Extracts every list row eagerly, with its associated ID.
    func extractListRows<ID: Hashable>(context: RenderContext) -> [ListRow<ID>]
}

/// A row extractor that supports *windowed* materialisation: the row count and
/// each row's id are resolved on demand (cheap — a count and a key-path read),
/// and a row's content box is built only when that row enters the overflow check
/// or the visible window. A 50,000-row `List` then touches ~viewport rows per
/// frame instead of 50,000 — both id resolution and content are O(visible), not
/// O(total). `ForEach` conforms; `List` prefers this path and falls back to the
/// eager ``ListRowExtractor`` when it isn't available (e.g. heterogeneous
/// content) or the ids can't be expressed as the list's selection type.
///
/// - Important: Conformers must be *id-homogeneous* — whether ``listRowID(at:)``
///   resolves to a given `ID` must not vary by index. `List` relies on this:
///   it probes row 0 once to decide windowability and force-unwraps the rest.
///   `ForEach` satisfies this (one element type, one id key-path).
@MainActor
protocol WindowedListRowExtractor {
    /// The number of rows, in O(1), without building or rendering any content.
    var listRowCount: Int { get }

    /// The id of the row at `index`, resolved cheaply (a key-path read or the
    /// index) without building content. Returns `nil` if the element's id can't
    /// be expressed as `ID` (the same rows the eager path would drop) — the
    /// caller then falls back to eager extraction. Element-natural ids are
    /// preferred, with the row index as the fallback (matching
    /// ``ListRowExtractor/extractListRows``).
    func listRowID<ID: Hashable>(at index: Int) -> ID?

    /// Builds the deferred content for the row at `index` (0-based over the
    /// data). Only called for rows that are actually shown.
    func makeListRowContent(at index: Int, context: RenderContext) -> LazyListRowContent
}

// MARK: - ForEach Conformance

extension ForEach: ListRowExtractor, WindowedListRowExtractor {
    func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        (0..<data.count).compactMap { index -> ListRow<RowID>? in
            // Resolve the row's selection ID up front — it's cheap (a key-path
            // read or the index) and the scroll / selection handler needs it for
            // EVERY row, on- or off-screen. Building and rendering the row view,
            // by contrast, is deferred into the lazy box below so a long List
            // only pays for the rows in its visible window.
            guard let rowID: RowID = rowID(at: index) else { return nil }
            return ListRow(id: rowID, content: makeListRowContent(at: index, context: context))
        }
    }

    var listRowCount: Int { data.count }

    // `RowID`, not `ID` — `ForEach`'s own `ID` generic parameter is in scope here.
    // Resolves one row's id lazily (the windowed `List` asks only for the visible
    // window + the focused row). `nil` when the element's id can't be expressed
    // as `RowID` — that's exactly the row `extractListRows` would drop; the list
    // probes row 0 and bails to the eager path when it's `nil`.
    func listRowID<RowID: Hashable>(at index: Int) -> RowID? {
        rowID(at: index)
    }

    func makeListRowContent(at index: Int, context: RenderContext) -> LazyListRowContent {
        let element = self.element(at: index)
        // Defer view construction, badge extraction, and rendering until the row
        // enters the visible window (see ``LazyListRowContent``).
        return LazyListRowContent { [content] in
            let view = content(element)

            // Extract badge if the view is wrapped in a BadgeModifier. Done on
            // the bare view, before any memo wrapper, so the modifier is found.
            let badge = extractBadgeValue(from: view)

            // Render the view under a per-row child identity (matching
            // ForEach.childViews) so each row's @State / focus / cache entry is
            // distinct — previously every row shared `context`'s identity.
            let rowContext = context.withChildIdentity(type: Content.self, index: index)

            // When the element is Equatable, wrap the row in a value-memo keyed
            // by the element, so an unchanged row is served from the render cache
            // instead of re-rendered. The wrapper is Renderable (adds no child
            // identity), so the inner view keeps the same `rowContext` identity
            // it would have unwrapped — the memo is identity-transparent.
            // _MemoizedRow's own gate declines to cache interactive / volatile rows.
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
    }

    /// The element at a 0-based offset (O(1) — `Data` is `RandomAccessCollection`).
    private func element(at index: Int) -> Data.Element {
        data[data.index(data.startIndex, offsetBy: index)]
    }

    /// Resolves the row ID for the element at `index`: its natural ID when that
    /// matches the requested type, else the index (see ``extractListRows`` for
    /// why the index fallback matters), else `nil`.
    private func rowID<RowID: Hashable>(at index: Int) -> RowID? {
        let elementID = element(at: index)[keyPath: idKeyPath]
        if let id = elementID as? RowID { return id }
        if let id = index as? RowID { return id }
        return nil
    }
}
