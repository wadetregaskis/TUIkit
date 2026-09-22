//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// A content row the selection cannot name (non-selectable, non-focusable).
    ///
    /// A static row — `List(selection:) { Text("alpha") }` — has no identity of
    /// its own, so the only id it can be given is its index. That works when
    /// the selection is an `Int`, and cannot be expressed at all when it is a
    /// `String`, a `UUID` or a `Set` of either. Such a row is drawn like
    /// ordinary content and simply left out of selection, which is what
    /// SwiftUI does with a row carrying no `tag(_:)`.
    ///
    /// It exists because the alternative was worse: the extraction used to
    /// `continue` past a row whose index would not cast, so a whole list of
    /// static rows silently rendered as the empty placeholder.
    case unselectable
}

// MARK: - Lazy Row Content

/// Where a list's rows sit inside a ``View/gradientExtent(_:)`` ramp spanning
/// the whole list.
///
/// A list renders its rows on demand, so it does not know how tall a row is
/// until it has rendered one — and it has to know before it can decide what
/// colour to render it. So the ramp holds a single row PITCH, seeded from the
/// first row (measured, not rendered) and applied to every row by ordinal. That
/// is exact wherever the rows are the same height, which is a list's ordinary
/// shape, and an estimate otherwise — the same convention the anchored lazy
/// stack window already lives with, for the same reason.
///
/// A class so the list can settle the pitch after the row boxes have been
/// handed out, and a row can read the settled answer at the moment it renders.
@MainActor
final class ListRowRamp {
    /// The rectangle the ramp runs across. `nil` until the list settles it — a
    /// row rendering before then takes no placement, which is only ever the
    /// row the pitch was seeded from, and its place is the origin regardless.
    var frame: GradientFrame?

    /// One row's height, in lines.
    var pitch = 1

    /// Where the row at `index` sits in the ramp.
    func placement(row index: Int) -> GradientFrame? {
        frame?.offset(byX: 0, y: index * pitch)
    }
}

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
    private var thunk: ((GradientFrame?) -> (buffer: FrameBuffer, badge: BadgeValue?))?
    private var cached: (buffer: FrameBuffer, badge: BadgeValue?)?

    /// This row's size without rendering it, when the content can answer —
    /// measured at the width the row would be rendered at, which comes back
    /// beside the size so a flexible row can be read as the render would have
    /// filled it. `nil` where nothing can answer but the render itself.
    ///
    /// Two callers. A list spanning a ramp across its rows has to know how
    /// tall a row is before it can choose the colour to render that row in.
    /// And a list asked to hug its content — `.fixedSize(horizontal:)`, or a
    /// `NavigationSplitView` sizing a sidebar — has to know how wide EVERY row
    /// is, on every frame; rendering two thousand rows to learn that was 93%
    /// of a split-view frame, and a measure through the size memo is a lookup.
    private var measureSize: (() -> (size: ViewSize, availableWidth: Int))?

    /// Whether the row's static type can carry a `.badge(_:)` at all — the
    /// answer ``badge`` would give without building and rendering the row to
    /// give it. `false` means `badge` is `nil` and need not be asked.
    let carriesBadge: Bool

    /// The ramp this row is placed in, or `nil` when no
    /// `.gradientExtent(.subtree)` is in force — which is almost always.
    ///
    /// Read at the moment the row renders rather than when the box is built,
    /// because the list settles the ramp's extent from the first row's height
    /// and that is not known until the boxes exist. A row whose buffer is
    /// already in hand (section chrome) ignores it: it has nothing left to
    /// render, and was placed where it was rendered.
    var gradientRamp: ListRowRamp?

    /// This row's ordinal, for ``gradientRamp``.
    var rowIndex = 0

    /// The identity the row's content is rendered under, when the row came from
    /// a `ForEach` (`nil` for chrome and the eager fallbacks, which have no
    /// per-element identity to speak of).
    ///
    /// Carried here rather than on ``SelectableListRow`` because this is a
    /// class: a new stored property on the struct would change its layout, and
    /// a dependent module built against the old one fails in ways that look
    /// nothing like the cause. It is what lets a `List` recognise a row of its
    /// own as the source of a `.draggable` drag — the drag names the identity of
    /// the view that started it, which is this row's identity or a descendant.
    ///
    /// `nonisolated` because it is an immutable `Sendable` fixed at
    /// construction: reading it must not force the main actor the way reading
    /// the (rendered) buffer does.
    nonisolated let rowIdentity: ViewIdentity?

    /// Defers rendering until the buffer (or badge) is first read.
    init(
        identity: ViewIdentity? = nil,
        carriesBadge: Bool = true,
        measure: (() -> (size: ViewSize, availableWidth: Int))? = nil,
        render: @escaping (GradientFrame?) -> (buffer: FrameBuffer, badge: BadgeValue?)
    ) {
        self.rowIdentity = identity
        self.carriesBadge = carriesBadge
        self.measureSize = measure
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
        self.rowIdentity = nil
        self.carriesBadge = badge != nil
        self.cached = (buffer, badge)
    }

    /// Renders the row if it has not been rendered, leaving the answer in
    /// ``cached``. Separate from the two accessors below so that neither has to
    /// hand back a COPY of the pair to read one half of it.
    private func resolveIfNeeded() {
        guard cached == nil else { return }
        cached = thunk!(gradientRamp?.placement(row: rowIndex))
        thunk = nil  // release the captured view / context
    }

    /// The row's rendered buffer, BORROWED rather than returned.
    ///
    /// The same trade ``FrameBuffer/lines`` makes and for a bigger reason: this
    /// used to read `resolved.buffer`, and `resolved` returned the whole
    /// `(buffer, badge)` pair by value — so every read of one row's buffer
    /// copied a `FrameBuffer` (six arrays retained and released) and then threw
    /// the badge away. A `List` frame reads it several times per drawn row, and
    /// `outlined init with copy of (buffer:badge:)` was 1.7% of a `megalist`
    /// frame with nothing else to show for it.
    var buffer: FrameBuffer {
        _read {
            resolveIfNeeded()
            yield cached!.buffer
        }
    }

    var badge: BadgeValue? {
        resolveIfNeeded()
        return cached!.badge
    }

    /// The row's height, rendering it only if there is no other way to ask.
    var heightWithoutRendering: Int {
        if let cached { return cached.buffer.height }
        if let measureSize { return measureSize().size.height }
        return buffer.height
    }

    /// The width the row's buffer would have, without rendering it — or `nil`
    /// when only the render can say (chrome and the eager fallbacks, which
    /// have already rendered and answer through ``buffer`` for nothing).
    ///
    /// Read as the render would have filled it: a row flexible in width
    /// renders filled to the width it was offered, and a row wider than that
    /// is clamped to it, so this is `buffer.width` by construction rather than
    /// by coincidence — `ListTests` pins the hug to the widest of every row.
    var widthWithoutRendering: Int? {
        if let cached { return cached.buffer.width }
        guard let measureSize else { return nil }
        let measured = measureSize()
        return measured.size.isWidthFlexible
            ? measured.availableWidth
            : min(measured.size.width, measured.availableWidth)
    }
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
/// `LazyListRowContent`): a `List` builds one row per item but only the rows
/// in the visible window are ever rendered. ``type``/``id``/``isSelectable``
/// are resolved eagerly and cheaply, which is all the scroll/selection handler
/// needs for off-screen rows.
public struct SelectableListRow<SelectionValue: Hashable & Sendable>: Sendable {
    /// The row type (header, content with ID, or footer).
    public let type: ListRowType<SelectionValue>

    /// The lazily-rendered buffer + badge for this row.
    let content: LazyListRowContent

    /// A background this row paints instead of the one its type would choose —
    /// how the reorder drop slot carries the "you are steering this" emphasis.
    ///
    /// It has to be painted by the row renderer rather than baked into the
    /// buffer: the leading selection gutter is added around the buffer, so a
    /// background inside it starts one cell late and leaves the row's first
    /// cell at the terminal default.
    ///
    /// A ``RowBackground`` rather than a `Color` so the slot can BREATHE the
    /// way the cursor row does — through the same machinery, so the slot's
    /// lines get their runs without a second path to maintain.
    var backgroundOverride: RowBackground = .none

    /// The rendered content buffer.
    ///
    /// Forces the lazy render on first access (then memoised). Only ever read
    /// for rows in the visible window, so off-screen rows never render.
    @MainActor public var buffer: FrameBuffer {
        // Borrowed through, so a read of a row's buffer copies nothing at
        // either level — see ``LazyListRowContent/buffer``.
        _read { yield content.buffer }
    }

    /// The badge value for this row (from environment). Forces the lazy render.
    @MainActor public var badge: BadgeValue? { content.badge }

    /// ``badge``, without rendering the row to find there is none — see
    /// ``LazyListRowContent/carriesBadge``.
    @MainActor var badgeWithoutRendering: BadgeValue? { content.carriesBadge ? content.badge : nil }

    /// ``buffer``'s width without rendering, where the content can answer —
    /// see ``LazyListRowContent/widthWithoutRendering``.
    @MainActor var widthWithoutRendering: Int? { content.widthWithoutRendering }

    /// The identity this row's content renders under, or `nil` for chrome and
    /// the eager fallbacks. Computed, not stored — see
    /// ``LazyListRowContent/rowIdentity``. Forces nothing.
    var rowIdentity: ViewIdentity? { content.rowIdentity }

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
    /// Only content rows have an ID. Headers, footers and unselectable rows
    /// always return nil.
    public var id: SelectionValue? {
        if case .content(let id) = type {
            return id
        }
        return nil
    }
}
