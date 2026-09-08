//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _ListCore.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// `_ListCore` is a single cohesive render core (the windowed row source, the
// list core, and the content view that draws it) whose pieces are tightly
// coupled through the row/selection/overflow model; splitting it across files
// purely to satisfy the length ceiling would scatter that model for no clarity
// gain — the same rationale by which `type_body_length` is disabled project-wide.
// swiftlint:disable file_length

/// The horizontal cells `renderPlainLine`/`renderLineWithBadge` add around a
/// row's content: a 1-cell gutter on the left and at least 1 cell of padding on
/// the right. Row-width proposals must subtract this so a width-greedy row
/// still fits the interior after composition.
private let listRowGutter = 2

// MARK: - Row Source (windowed materialisation)

/// A windowed view over a `List`'s rows.
///
/// Every row's ``ListRowType`` (and thus its id) is known eagerly and cheaply —
/// that's all the scroll/selection handler needs for off-screen rows. Each row's
/// content *buffer*, by contrast, is materialised lazily and memoised, so only
/// the rows the overflow check and the visible window actually walk get built.
/// For a large flat `List` that's O(viewport) row boxes per frame instead of
/// O(total) — the dominant idle cost on long lists was allocating a content box
/// for every row every frame even though ~viewport are shown.
///
/// The eager paths (Sections, heterogeneous content) wrap their already-built
/// rows via ``eager(_:)``; ``row(at:)`` simply hands those back.
@MainActor
private final class RowSource<SelectionValue: Hashable & Sendable> {
    /// The number of rows. Known cheaply — O(1) for the windowed path
    /// (`ForEach.listRowCount`); the array length for the eager paths.
    let count: Int

    /// Whether every row is selectable content — true for the windowed `ForEach`
    /// path and the all-content fallbacks, false only for a heterogeneous row set
    /// (Sections, which interleave non-selectable header/footer rows). The
    /// handler reads this to skip building a per-row id map and selectable-index
    /// set for the all-content case, which is what keeps a huge flat list O(1) to
    /// set up. See ``_ListCore/resolvePopulatedHandler``.
    let allContent: Bool

    /// Resolves a row's type/id on demand — builds no content. O(1) per call, so
    /// the windowed path resolves ids only for the rows the handler / window
    /// actually touch (the visible window + the focused row), not all N.
    private let typeAt: (Int) -> ListRowType<SelectionValue>

    /// Builds the deferred content box for a row index.
    private let make: (Int) -> LazyListRowContent

    /// The rows' data, comparable, when the source can say what it is — the
    /// hug memo's snapshot (``_ListCore/widestRowWidth(source:context:)``).
    /// `nil` for the eager sources, whose rows are already built.
    let signature: AnyEquatableBox?

    /// Per-frame memo so a row touched by both the overflow check and the visible
    /// window (or re-read by the compose pass) is built — and rendered — once.
    private var materialized: [Int: SelectableListRow<SelectionValue>] = [:]

    /// The ramp a `.gradientExtent(.subtree)` gradient runs down these rows —
    /// see ``ListRowRamp`` and ``_ListCore/settleRowRamp(_:context:)``. Inert
    /// (`frame` nil) unless a gradient actually spans this list.
    ///
    /// Handed to each row's content box as the box is built, which is the last
    /// moment before that row can render and the first at which its index is in
    /// hand. Its extent is settled after that, which is why it is a reference.
    let gradientRamp = ListRowRamp()

    init(
        count: Int,
        allContent: Bool,
        signature: AnyEquatableBox? = nil,
        typeAt: @escaping (Int) -> ListRowType<SelectionValue>,
        make: @escaping (Int) -> LazyListRowContent
    ) {
        self.count = count
        self.allContent = allContent
        self.signature = signature
        self.typeAt = typeAt
        self.make = make
    }

    /// Wraps an already-built, materialised row array (the eager Section /
    /// fallback paths). The set is small, so indexing it for `typeAt` and
    /// scanning it for `allContent` are both cheap.
    static func eager(_ rows: [SelectableListRow<SelectionValue>]) -> RowSource {
        RowSource(
            count: rows.count,
            allContent: rows.allSatisfy(\.isSelectable),
            typeAt: { rows[$0].type },
            make: { rows[$0].content })
    }

    // `count` is the stored row count (an `Int`), not a Collection, so the
    // empty_count rule misfires — `isEmpty` is precisely what we're defining.
    // swiftlint:disable:next empty_count
    var isEmpty: Bool { count == 0 }

    /// The row's type/id at `index` — cheap, builds no content.
    func type(at index: Int) -> ListRowType<SelectionValue> { typeAt(index) }

    /// The fully-formed row at `index`, materialising (and memoising) its content
    /// box on first access. Reading the row's `.buffer` renders it once (cached).
    func row(at index: Int) -> SelectableListRow<SelectionValue> {
        if let existing = materialized[index] { return existing }
        let content = make(index)
        content.gradientRamp = gradientRamp
        content.rowIndex = index
        let row = SelectableListRow(type: typeAt(index), content: content)
        materialized[index] = row
        return row
    }
}

// MARK: - List Core (Internal Rendering)

/// Internal core view that handles list rendering inside a
/// ContainerView.
///
/// # Interaction model
///
/// Selection, focus, and scroll position are three independent
/// concepts:
///
/// - **Scroll position** is moved by the mouse wheel (3 lines per
///   tick by default — see ``ViewConstants/mouseWheelScrollLines``).
///   Wheel scrolling NEVER changes the selection or the focused
///   row; it can scroll either out of view. This matches every
///   major desktop list-view convention (Finder, Explorer, VS
///   Code, etc.). The previous "wheel = arrow key" implementation
///   made unfocused lists look unscrollable until the invisible
///   selection bumped the viewport edge — exactly the wrong UX.
///
/// - **Selection / focus** is moved by the arrow keys when the
///   list itself has focus, and by clicking a row. Pressing an
///   arrow on a focused list whose selection has been scrolled
///   off-screen scrolls the viewport back to the new selection,
///   via the usual ``ItemListHandler/ensureFocusedItemVisible``
///   path.
///
/// - **Selection visibility when unfocused** defaults to hidden
///   (a desaturated highlight is too noisy in many contexts).
///   Opt-in with ``View/unfocusedSelectionVisibility(_:)``.
struct _ListCore<SelectionValue: Hashable & Sendable, Content: View, Footer: View>: View, Renderable, Layoutable {
    let title: String?
    let content: Content
    let footer: Footer?
    let singleSelection: Binding<SelectionValue?>?
    let multiSelection: Binding<Set<SelectionValue>>?
    let selectionMode: SelectionMode
    let focusID: String?
    let isDisabled: Bool
    let emptyPlaceholder: String
    let showFooterSeparator: Bool
    /// Row activation ("open") — Enter on the focused row (via the handler)
    /// or a double-click (via the container mouse handler). See
    /// ``List/onRowActivate(_:)``.
    let primaryAction: ((SelectionValue) -> Void)?

    var body: Never {
        fatalError("_ListCore renders via Renderable")
    }

    /// The List is greedy on both axes: it fills the width it is offered and pads
    /// to fill the height. So its size is simply the offered space — and crucially
    /// no rows are built or measured here. Previously, being `Renderable`-only,
    /// the layout measure pass discovered the List's size by rendering the whole
    /// list (windowed, but still the visible rows) every frame; now the measure
    /// pass is O(1).
    ///
    /// Both axes are reported *flexible* (the offered extent is a minimum, per
    /// the ``ViewSize`` contract, which names `List` as the canonical
    /// height-filling view). Reporting the filled height as *fixed* — as this
    /// once did — made every unframed List an immovable full-height demand, so
    /// sibling Lists in a `VStack` starved: the distributor's overflow branch
    /// placed the first at full height and collapsed the rest to zero (issue
    /// #6). Flexible height instead lands in the weighted-share branch, which
    /// splits the column evenly. Hugging content is opt-in via
    /// `.fixedSize(horizontal:)`, which proposes an unbounded width.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let height = proposal.height ?? context.availableHeight
        // Default: greedy on both axes, no rows built — the O(1) measure that
        // makes the layout pass cheap.
        guard context.environment.fixedSizeWidth else {
            return ViewSize(
                width: proposal.width ?? context.availableWidth, height: height,
                isWidthFlexible: true, isHeightFlexible: true)
        }
        // `.fixedSize(horizontal:)`: hug content — the widest of ALL rows, stable
        // across scroll. Opt-in, so building the rows to measure them is fine, and
        // the reported width is fixed (not flexible) so a stack hugs around it.
        return ViewSize.fixed(allRowsContentWidth(context: context), height)
    }

    /// The List's hugged width: the widest of every row (plus a title and the
    /// border), independent of the scroll position. Only used on the
    /// `.fixedSize(horizontal:)` path. Clears the fixed-size flag for the rows so
    /// the request doesn't leak into their own content.
    private func allRowsContentWidth(context: RenderContext) -> Int {
        var rowContext = context
        rowContext.environment.fixedSizeWidth = false
        let source = extractRows(from: content, context: rowContext)
        let widest = widestRowWidth(source: source, context: rowContext)
        let titleWidth = title.map { $0.strippedLength + 2 } ?? 0
        let borderOverhead = context.environment.listStyle.showsBorder ? 2 : 0
        // The widest row still gets its gutters when composed, so the hugged
        // width must include them or the row's trailing cells are clipped.
        return max(widest + listRowGutter, titleWidth) + borderOverhead
    }

    /// The widest row's cells, badge included — the answer a hug needs, from
    /// every row, on every frame it hugs.
    ///
    /// Kept in the size memo under the list's own identity, checked against
    /// the rows' DATA: a `NavigationSplitView` asks its sidebar to hug on
    /// every frame, and walking two thousand rows to answer — a content box,
    /// a closure pair and an identity node per row, then a memo lookup each
    /// — was 62% of a frame whose rows had not changed. The data is the
    /// snapshot because it is what the rows are a function of, which is the
    /// assumption the row memo already makes (its "captured data" hole is
    /// this one's too). The entry lives under the list's identity, so a
    /// `@State` write in any row clears it (the list is the row's ancestor),
    /// an environment change above the list clears it (the list is below the
    /// modifier), and a row that read a per-frame value declines it — the
    /// same three rules as a row's own memo. Sources that cannot say what
    /// their data is (sections, eager fallbacks) walk every time.
    private func widestRowWidth(source: RowSource<SelectionValue>, context: RenderContext) -> Int {
        let key = RenderCache.SizeKey(
            identity: context.identity,
            proposalWidth: context.availableWidth, proposalHeight: nil,
            // Height-independent on purpose: a row's width does not change
            // with the height the list was offered, and the measure and
            // render passes offer different ones.
            availableWidth: context.availableWidth, availableHeight: 0,
            hasExplicitWidth: context.hasExplicitWidth, hasExplicitHeight: context.hasExplicitHeight)
        let memo: (cache: RenderCache, signature: AnyEquatableBox)? =
            if let cache = context.renderCache, let signature = source.signature {
                (cache, signature)
            } else {
                nil
            }
        if let memo {
            // The list itself never marks: it is not a memoising view. Without
            // this the entry would be pruned at the end of the pass it was
            // stored in.
            memo.cache.markActive(context.identity)
            if let cached = memo.cache.lookupSize(key: key, view: memo.signature) {
                return cached.width
            }
        }
        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        var walkContext = context
        if existingTracker == nil {
            walkContext = context.withEnvironment(
                context.environment.setting(\.volatileReadTracker, to: tracker))
        }
        let unsafeBefore = tracker.cacheUnsafeCount
        let widest = (0..<source.count).map { index in
            let row = source.row(at: index)
            // A badge is composed OUTSIDE the row's own buffer
            // (`renderLineWithBadge`: content, ≥1 fill, badge), so the hugged
            // width must reserve its cells too — in SwiftUI a badge is an
            // overlay outside layout, but a terminal cell grid has no
            // overlay: sizing a column to "fit" its rows must mean fitting
            // their badges, or the widest row always loses its badge.
            // Asked only of a row whose type can carry one — the rest say so
            // without rendering — and the width is measured, not rendered:
            // a `NavigationSplitView` asks its sidebar to hug on EVERY frame,
            // and rendering two thousand rows to answer was 93% of a frame,
            // in a measure pass the row memo cannot serve. The size memo can.
            let badgeCells: Int =
                if let badge = row.badgeWithoutRendering, !badge.isHidden, row.isSelectable {
                    badge.displayText.strippedLength + 1
                } else {
                    0
                }
            return (row.widthWithoutRendering ?? row.buffer.width) + badgeCells
        }.max() ?? 0
        if let memo, tracker.cacheUnsafeCount == unsafeBefore,
            !walkContext.environment.hasUncomparableEnvironmentValue
        {
            memo.cache.storeSize(key: key, view: memo.signature, size: ViewSize.fixed(widest, 0))
        }
        return widest
    }

    /// Captures the populated-state values that the mouse-
    /// handler attachment needs from the content rendering
    /// pass. `nil` in the empty-list case.
    private struct PopulatedRenderState {
        let handler: ItemListHandler<SelectionValue>
        let focusID: String
        /// Where this frame was DRAWN from — the handler's raw scroll position
        /// with any absorbed top clip already resolved away (see
        /// ``ScrollWindowOrigin/absorbing(offset:topClip:firstRowHeight:)``). The
        /// click mapping must measure from this, not from the handler, or the
        /// absorbed frame puts every row a line off its hit band.
        let origin: WindowOrigin
        let visibleRowYRanges: [VisibleRowRange]
        /// The rows behind ``visibleRowYRanges``, index-aligned with it (both
        /// are built from the same visible-window walk). Their buffers carry
        /// the rows' own hit-test regions, which `attachMouseHandlers` merges
        /// into the list's buffer.
        let visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)]

        /// The rows' `.dropDestination(for:action:)` insertion action, if any —
        /// what makes this list a landing place for a drag from elsewhere.
        var dropInsertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?
        /// The buffer column of the scrollbar and its line-height, when one is
        /// drawn (`nil` column = no bar). Drives the bar's mouse handler in
        /// `attachMouseHandlers`.
        var scrollbarColumn: Int?
        var scrollbarHeight = 0
        /// How many columns a row's own content occupies, past the gutter —
        /// the clip limit for anything positioned in the row's coordinates.
        var rowContentWidth = 0
    }

    private typealias VisibleRowRange = (
        rowIndex: Int, yStart: Int, height: Int, type: ListRowType<SelectionValue>
    )

    /// The first row of the window and how many of its lines are scrolled off
    /// above it — the one position the whole render path measures from, settled by
    /// ``ScrollRowWindow``.
    private typealias WindowOrigin = (offset: Int, topClip: Int)

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette
        let style = context.environment.listStyle
        let stateStorage = context.stateStorage!

        // Rows beyond the viewport are skipped, not gone: retain their state
        // (see StateStorage.retainSubtree). Render path only, per the
        // measure-side-effect rule.
        if !context.isMeasuring {
            stateStorage.retainSubtree(context.identity)
        }

        // Two border cells or none, on each axis: top + bottom rows, and left +
        // right columns.
        let borderOverhead = style.showsBorder ? 2 : 0

        // `.fixedSize(horizontal:)` makes the List hug its content; clear the flag
        // before extracting so it doesn't leak into the rows' own content. The
        // List's own honouring of it reads `context.environment.fixedSizeWidth`
        // (still set) in `buildPopulatedContent`.
        //
        // On the ordinary fill path, propose each row the width it actually gets
        // on screen: the interior minus the row gutters that `renderPlainLine`
        // adds around it. Extracting rows at the List's own full width let a
        // width-greedy row (`HStack { … Spacer() … }`) fill all of it, only for
        // the gutter + border clamp to chop the trailing cells — silently hiding
        // a right-flushed trailing view (issue #5).
        var rowContext = context
        if context.environment.fixedSizeWidth {
            rowContext.environment.fixedSizeWidth = false
        } else {
            rowContext.availableWidth = max(
                1, context.availableWidth - borderOverhead - listRowGutter)
        }
        // Where the rows state the edits they refuse, gathered as they render.
        // Installed BEFORE extraction because the row thunks capture this
        // context and the handler does not exist yet; the results are handed to
        // the handler once the visible rows have been materialised.
        let editRestrictions = RowEditRestrictions()
        rowContext.environment.listRowEditRestrictions = editRestrictions
        let source = extractRows(from: content, context: rowContext)
        settleRowRamp(source, context: rowContext)

        // Vertical chrome around the scrollable content; reserve
        // only what is actually present.
        let footerHeight = footer != nil ? 2 : 0  // footer line + separator
        // A BORDERED container draws the title inside its top border row
        // (`ContainerView.chromeHeight` counts borders and the footer separator
        // and nothing else), so it costs no line of its own — charging one
        // anyway showed a titled list one row fewer than fits, with a stray
        // blank line at the bottom of the slot. Borderless (`.plain`) does
        // render the title as its own row (`renderBorderless`), so there the
        // line is real. `_ListCore`'s own click mapping already agreed: its
        // `topInset` counts the border and the padding, never a title.
        let titleOverhead = (title != nil && !style.showsBorder) ? 1 : 0
        let targetContentHeight = max(
            1,
            context.availableHeight - borderOverhead - titleOverhead - footerHeight
        )

        let contentLines: [String]
        var contentRuns: [AnimatedCellRun] = []
        let renderState: PopulatedRenderState?
        if source.isEmpty {
            contentLines = buildEmptyStateLines(context: context)
            // Empty is not inert. The list still occupies its frame, so it is
            // still somewhere a drag can be dropped — and everything that makes
            // that true (the container's hit region, the drop destination, the
            // auto-scroll zone) hangs off this state. Without it, emptying a
            // list made it permanently unfillable: nothing to hit-test, so a
            // drag over it resolved no target and flew home.
            renderState = emptyRenderState(
                source: source, context: context, stateStorage: stateStorage,
                targetContentHeight: targetContentHeight)
        } else {
            let result = buildPopulatedContent(
                source: source,
                editRestrictions: editRestrictions,
                context: context,
                stateStorage: stateStorage,
                palette: palette,
                style: style,
                targetContentHeight: targetContentHeight
            )
            contentLines = result.lines
            contentRuns = result.runs
            renderState = result.state
        }

        // Pad content to fill the available height (SwiftUI
        // behavior: List is greedy).
        var paddedContentLines = contentLines
        if paddedContentLines.count < targetContentHeight {
            let extra = targetContentHeight - paddedContentLines.count
            paddedContentLines.append(contentsOf: Array(repeating: "", count: extra))
        }

        var buffer = renderContainer(
            title: title,
            config: ContainerConfig(
                borderStyle: context.environment.appearance.borderStyle,
                borderColor: palette.border,
                titleColor: nil,
                padding: style.rowPadding,
                showFooterSeparator: showFooterSeparator,
                hasBorder: style.showsBorder
            ),
            content: _ListContentView(lines: paddedContentLines, runs: contentRuns),
            footer: footer,
            context: context
        )

        if let state = renderState {
            attachMouseHandlers(
                to: &buffer,
                context: context,
                state: state,
                paddingTop: style.rowPadding.top
            )
            // Compositing, not click handling — so it runs even when the list
            // is disabled or has no mouse dispatcher. See `attachRowOverlays`.
            attachRowOverlays(
                to: &buffer,
                context: context,
                state: state,
                paddingTop: style.rowPadding.top
            )
            attachRowOpacity(
                to: &buffer,
                context: context,
                state: state,
                paddingTop: style.rowPadding.top
            )
        }
        return buffer
    }

    /// Settles the ramp a `.gradientExtent(.subtree)` gradient runs down this
    /// list's rows. Does nothing at all when no gradient spans the list, which
    /// is almost always.
    ///
    /// The list has to know how tall a row is before it can decide what colour
    /// to render one in, and its rows render on demand — so the first row is
    /// MEASURED (never rendered twice) and answers for the rest, exactly as the
    /// uniform lazy-stack window seeds its pitch from row 0. Rows of one height
    /// — a list's ordinary shape — are then placed exactly, at any scroll
    /// offset, with nothing walked; mixed heights are an estimate, which is what
    /// the anchored stack window already lives with.
    ///
    /// The extent is the rows, not the viewport: a row keeps its colour as the
    /// list scrolls, and forty rows in a ten-row list show the first quarter of
    /// the ramp — the same rule the stacks follow.
    private func settleRowRamp(_ source: RowSource<SelectionValue>, context: RenderContext) {
        guard context.gradientFrame != nil, !source.isEmpty else { return }
        let pitch = max(1, source.row(at: 0).content.heightWithoutRendering)
        source.gradientRamp.pitch = pitch
        source.gradientRamp.frame = context.gradientContentFrame(
            width: context.availableWidth, height: source.count * pitch)
    }

    // MARK: - Empty-state placeholder

    /// Builds the single-line empty-state content for a list
    /// with no rows. The placeholder is padded out to the
    /// available width so an empty list keeps its full size
    /// instead of collapsing to the title's width.
    private func buildEmptyStateLines(context: RenderContext) -> [String] {
        let placeholderWidth = emptyPlaceholder.strippedLength
        // +2 for the "─ … ─" border decorations around the title.
        let titleWidth = title.map { $0.strippedLength + 2 } ?? 0
        let intrinsicWidth = max(placeholderWidth, titleWidth)
        let targetWidth: Int
        if context.hasExplicitWidth {
            // Subtract the two border columns only when the style draws a border;
            // a borderless (`.plain`) list fills the full available width.
            let borderOverhead = context.environment.listStyle.showsBorder ? 2 : 0
            targetWidth = max(intrinsicWidth, context.availableWidth - borderOverhead)
        } else {
            targetWidth = intrinsicWidth
        }
        let extra = max(0, targetWidth - placeholderWidth)
        return [emptyPlaceholder + String(repeating: " ", count: extra)]
    }

    // MARK: - Populated content

    /// Renders the populated-state content lines and captures
    /// the state the mouse handler needs (the handler itself,
    /// the persisted focus ID, and the per-row y-ranges so
    /// clicks can be translated back to a row index).
    private func buildPopulatedContent(
        source: RowSource<SelectionValue>,
        /// Where the rows report the edits they refuse. Filled as they render,
        /// so it is only meaningful after the visible window is materialised.
        editRestrictions: RowEditRestrictions,
        context: RenderContext,
        stateStorage: StateStorage,
        palette: any Palette,
        style: any ListStyle,
        targetContentHeight: Int
    ) -> (lines: [String], runs: [AnimatedCellRun], state: PopulatedRenderState) {
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "list",
            propertyIndex: 1  // focusID
        )
        // Whether the rows overflow — and so whether a scrollbar or an
        // indicator line is wanted — cannot be settled before the handler is in
        // hand: a drag hovering this list borrows a row's worth of content for
        // its landing slot, and only the handler knows a drag is hovering.
        let (handler, overflowing, wantsScrollbar) = resolvePopulatedHandler(
            source: source,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: targetContentHeight
        )
        // The slot is drawn among the rows and takes a line of the same content
        // area, so the rows get one less to walk. Reserved HERE, once, rather
        // than inside each window rule: the two rules disagree about indicator
        // lines but not about this.
        let rowBudget = max(1, targetContentHeight - (handler.dropSlotAddsRow ? 1 : 0))
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. `engageFocus`
        // still runs with the true answer: it publishes the Escape claim and
        // the status bar's Return verb, and sets `isFocusEngaged`, none of
        // which are focus EFFECTS.
        let listHasFocus = context.indicatesFocus(
            handler.engageFocus(context: context, focusID: persistedFocusID))

        // Which rows are on screen — the shared rule, so this cannot drift from
        // the two `Table` composers again (`ScrollRowWindow`). It reserves a line
        // for each indicator actually present at this offset, so the rows plus
        // indicators fill the content area exactly: no wasted blank line at the
        // ends (which used to push the "N more below" indicator one row too high)
        // and no overflow in the middle.
        //
        // The CONJUNCTION with `overflowing`, because that is what the rule's
        // `drawsTextIndicators` means to it — "does a line come out of the
        // content area". A list whose rows all fit has nothing hidden to
        // announce, and a bar or hidden indicators spend a column or nothing
        // rather than a line. `Table` folds the same conjunction into
        // `handler.drawsScrollIndicators` itself; this keeps the two apart and
        // combines them here.
        let window = ScrollRowWindow.resolve(
            scrollOffset: handler.scrollOffset, count: source.count,
            contentHeight: rowBudget, topClip: handler.scrollTopClipLines,
            drawsTextIndicators: handler.drawsScrollIndicators && overflowing,
            height: { source.row(at: $0).buffer.height })
        // Where this frame is DRAWN from: the window may have absorbed a top clip
        // (or a whole first row) an indicator would have cost more to announce
        // than it hides. Threaded through every consumer — the indicators, the
        // row clip, the published bands, the click mapping — because a renderer
        // drawing from the absorbed origin while the hit test measures from the
        // raw one puts every row a line off its band (exactly how the `Table`
        // broke before it did the same).
        let origin: WindowOrigin = (window.range.lowerBound, window.topClip)
        // Materialised from the range the rule settled. `source.row(at:)` builds
        // and renders the content box on demand and MEMOISES it, so the rows the
        // walk already touched cost a dictionary hit here.
        var visibleRows = window.range.map { (index: $0, row: source.row(at: $0)) }
        // Sync the viewport to the DATA rows this window covers — BEFORE the
        // reorder decoration rewrites them. The dragged row and the drop slot
        // are drawing, not data: a row in the user's hand is still counted by
        // `itemCount` and is not hidden below, and a slot has no data behind it
        // at all. Counting either makes the indicator predicates disagree with
        // the extent and invent a "1 more row below".
        handler.viewportHeight = max(1, visibleRows.count)
        // …and the offset they were drawn FROM, which is the resolved origin,
        // not `scrollOffset`. See ``ItemListHandler/drawnOffset``.
        handler.drawnOffset = origin.offset
        // A `.dimmed` / `.cursor` drag rewrites the rows here, AFTER the
        // window walk: the drag shows an extra row that is not in the data, so
        // it must not take part in choosing which data rows are visible.
        // The rows have rendered by now, so whatever they refused is known.
        // Only rows that were DRAWN can have reported, which is exactly the set
        // an edit can name: Delete acts on the focused row and a drag on the
        // grabbed one, and both are on screen.
        handler.deleteDisabledRows = editRestrictions.deleteDisabled
        handler.moveDisabledRows = editRestrictions.moveDisabled
        visibleRows = decorateForReorder(
            visibleRows, handler: handler, context: context, palette: palette)

        let rowWidth = rowWidth(
            source: source, visibleRows: visibleRows, style: style, context: context)

        let lines: [String]
        let visibleRowYRanges: [VisibleRowRange]
        let animatedRuns: [AnimatedCellRun]
        var scrollbarColumn: Int?
        var scrollbarHeight = 0
        var rowContentWidth = 0
        if wantsScrollbar {
            let bar = listScrollbarCells(
                source: source,
                origin: origin,
                visibleRows: visibleRows,
                contentHeight: targetContentHeight,
                handler: handler,
                context: context,
                palette: palette
            )
            let contentRowWidth = max(1, rowWidth - 1)
            (lines, visibleRowYRanges, animatedRuns) = composeScrollbarRowLines(
                visibleRows: visibleRows,
                handler: handler,
                origin: origin,
                listHasFocus: listHasFocus,
                contentRowWidth: contentRowWidth,
                bar: bar,
                style: style,
                context: context
            )
            // The bar is the last interior column: the border's cell when the
            // style draws one — a `.plain` list has none, and a constant 1 here
            // registered the bar's hit region one column PAST the drawn bar, off
            // the buffer's edge — then the left padding, the content, and the bar
            // cell. Matches the content inset used for click mapping (see
            // attachMouseHandlers).
            scrollbarColumn = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + contentRowWidth
            scrollbarHeight = bar.count
            rowContentWidth = max(0, contentRowWidth - 1)
        } else {
            (lines, visibleRowYRanges, animatedRuns) = composeRowLines(
                handler: handler,
                origin: origin,
                visibleRows: visibleRows,
                listHasFocus: listHasFocus,
                rowWidth: rowWidth,
                contentHeight: targetContentHeight,
                style: style,
                context: context
            )
            rowContentWidth = max(0, rowWidth - 1)
        }

        return (
            lines: lines,
            runs: animatedRuns,
            state: PopulatedRenderState(
                handler: handler,
                focusID: persistedFocusID,
                origin: origin,
                visibleRowYRanges: visibleRowYRanges,
                visibleRows: visibleRows,
                dropInsertion: (source.allContent
                    ? content as? DynamicViewContentActions : nil)?.dropInsertionAction,
                scrollbarColumn: scrollbarColumn,
                scrollbarHeight: scrollbarHeight,
                rowContentWidth: rowContentWidth
            )
        )
    }

    /// The interaction state of a list with no rows: a real handler (its
    /// `itemCount` freshly zeroed, so the stale count from its last populated
    /// frame cannot leak into a drop index), no rows, no bands, and whatever
    /// drop action the content declared.
    ///
    /// Rows are the only thing missing. The bands the last populated frame
    /// published are cleared for us: this state carries no `visibleRowYRanges`,
    /// and the render path both branches share publishes whatever it finds
    /// there — an empty list, here. (`Table` clears them in its own empty
    /// branch instead, its populated paths not sharing one publisher. Both
    /// arrive at the same place; only this one gets it for free.) The drop
    /// destination then resolves index 0 through its own `?? itemCount`
    /// fallback, with no new arithmetic anywhere.
    ///
    /// It registers with the focus system exactly as the populated path does.
    /// An empty list is still a Tab stop, an enclosing `ScrollView` still has
    /// to be able to find it to reveal it — and, the case that bites, a list
    /// the user is *in* when its last row goes away must not take their focus
    /// with it: registration is per frame, so a frame that skips it drops the
    /// control out of the ring and leaves focus nowhere.
    private func emptyRenderState(
        source: RowSource<SelectionValue>,
        context: RenderContext,
        stateStorage: StateStorage,
        targetContentHeight: Int
    ) -> PopulatedRenderState {
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "list",
            propertyIndex: 1  // focusID
        )
        let (handler, _, _) = resolvePopulatedHandler(
            source: source,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            context: context,
            contentHeight: targetContentHeight
        )
        // The empty path needs the registration and the escape claim, not the
        // answer — there are no rows for the focus to be on.
        handler.engageFocus(context: context, focusID: persistedFocusID)
        return PopulatedRenderState(
            handler: handler,
            focusID: persistedFocusID,
            origin: (0, 0),
            visibleRowYRanges: [],
            visibleRows: [],
            dropInsertion: (source.allContent
                ? content as? DynamicViewContentActions : nil)?.dropInsertionAction
        )
    }

    /// Whether the rows can't all fit in `targetContentHeight` lines — i.e.
    /// whether the list scrolls and shows indicators.
    ///
    /// Exactly the old `totalRowLines > targetContentHeight` test, but it stops
    /// summing the moment the running total exceeds the area instead of first
    /// rendering *every* row. For the common case (rows are at least one line
    /// tall) that short-circuits after ~`targetContentHeight` rows, so a
    /// 2,000-row List in a 40-line area renders ~40 rows here, not 2,000 — and
    /// when the list isn't scrolled those are the very rows about to be shown,
    /// whose buffers ``LazyListRowContent`` memoises (no re-render downstream).
    /// It walks all rows only when their total height genuinely fits the area
    /// (a short list, which is rendered in full anyway).
    /// - Parameter plusLines: Lines the rows must share the area with — the
    ///   landing slot a hovering drag borrows (see
    ///   ``ItemListHandler/dropSlotAddsRow``). Counted here rather than
    ///   subtracted from the height by each caller, so every consumer of
    ///   `overflowing` sees one answer.
    private func rowsOverflow(
        _ source: RowSource<SelectionValue>,
        targetContentHeight: Int,
        plusLines: Int = 0
    ) -> Bool {
        // More rows than target lines is overflow by counting alone — every
        // row renders at least its own line. This matters: the walk below
        // touches rows from the HEAD of the list, and touching a row's
        // `buffer` resolves (renders) it — so a deep-scrolled list resolved
        // ~a viewport of rows it wasn't even showing, every frame, just to
        // answer this predicate (~25% of a megalist frame).
        if source.count + plusLines > targetContentHeight { return true }
        var totalRowLines = plusLines
        for index in 0..<source.count {
            totalRowLines += source.row(at: index).buffer.height
            if totalRowLines > targetContentHeight { return true }
        }
        return false
    }

    /// Whether a drag hovering this list is opening a landing slot that no row
    /// of ours left to make room for — the condition
    /// ``ItemListHandler/dropSlotAddsRow`` names.
    ///
    /// Gated on a slot being OPEN here, not merely on a compatible drag being
    /// in flight somewhere. Granting the row for the whole drag would need no
    /// handler at all — and would not have forced the resolver to answer three
    /// things at once — but a list the pointer is nowhere near would then
    /// advertise "▼ 1 more row below" with nothing below it, which is the
    /// phantom indicator this renderer has already been fixed for once.
    private func borrowsDropRow(
        _ source: RowSource<SelectionValue>,
        handler: ItemListHandler<SelectionValue>, context: RenderContext
    ) -> Bool {
        // A reorder of this list's OWN rows asks the same question about the
        // same line, and answers it the same way — see
        // ``ItemListHandler/reorderSlotNeedsALine``, which is the twin of the
        // paragraph below and is shared with `Table`.
        guard handler.externalDropSlot != nil else { return handler.reorderSlotNeedsALine }
        // A drag that started HERE has already had its row taken out of the
        // drawing (see `decorateForReorder`), so its slot replaces a line
        // rather than adding one.
        guard let session = context.environment.dragAndDropSession else { return true }
        guard session.isDragSource(within: context.identity) else { return true }
        // …but only a row that is ON SCREEN can leave the drawing. `carriedRow`
        // looks for the source among the VISIBLE rows and finds nothing once
        // the viewport has moved past it — auto-scrolling toward the end does
        // exactly that — so from there on nothing is freed and the slot needs a
        // line of its own, the same as a foreign drag's. Without this the
        // extent said the rows still fit, and the position after the last row
        // could not be reached: the furthest the pointer could aim was the
        // second-last line.
        return !sourceRowIsOnScreen(source, session: session, handler: handler)
    }

    /// Whether the row the in-flight drag came from is inside the window this
    /// frame will draw — the condition under which it leaves the drawing.
    ///
    /// Asked of ``ItemListHandler/visibleRange`` rather than the resolved
    /// window, because the answer feeds the row budget the window is computed
    /// from. The two agree except at the boundary, where being one row out
    /// costs one reserved line — a state the overflow machinery already
    /// expresses. Reading `rowIdentity` forces no row to render, and the walk
    /// covers a viewport's worth at most.
    private func sourceRowIsOnScreen(
        _ source: RowSource<SelectionValue>,
        session: DragAndDropSession,
        handler: ItemListHandler<SelectionValue>
    ) -> Bool {
        for index in handler.visibleRange where index < source.count {
            if let identity = source.row(at: index).rowIdentity,
                session.isDragSource(within: identity)
            {
                return true
            }
        }
        return false
    }

    /// Fetches (or creates) the persistent ``ItemListHandler``
    /// and syncs its per-frame inputs to match the current
    /// rows, selection bindings, focus state, and disabled
    /// state.
    ///
    /// Intentionally does NOT call
    /// ``ItemListHandler/ensureFocusedItemVisible()`` — wheel
    /// scrolling is independent of the focused row (matches
    /// Finder / Explorer / VS Code), and the focus-changing
    /// paths inside the handler already call it themselves.
    /// Also decides `overflowing` and `showsScrollbar`, which it cannot be
    /// handed: both depend on ``ItemListHandler/dropSlotAddsRow``, a question
    /// about the handler's own drag state. That ordering — box, row count,
    /// borrowed drop row, and only then "do the rows fit" — is the whole reason
    /// this returns three things.
    private func resolvePopulatedHandler(
        source: RowSource<SelectionValue>,
        persistedFocusID: String,
        stateStorage: StateStorage,
        context: RenderContext,
        contentHeight: Int
    ) -> (handler: ItemListHandler<SelectionValue>, overflowing: Bool, showsScrollbar: Bool) {
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: 0)
        let handlerBox: StateBox<ItemListHandler<SelectionValue>> = stateStorage.storage(
            for: handlerKey,
            default: ItemListHandler(
                focusID: persistedFocusID,
                itemCount: source.count,
                // Provisional twice over: replaced below once the real overflow
                // answer exists, and again by the window walk. A freshly created
                // list has no drag hovering it, so this can never be the value
                // anything decides on.
                viewportHeight: contentHeight,
                selectionMode: selectionMode,
                canBeFocused: !isDisabled(in: context)
            )
        )
        let handler = handlerBox.value
        handler.itemCount = source.count
        // A drag from elsewhere draws its landing slot as an extra line —
        // nothing left this list to make room for it — so while one is hovering
        // the list has a row's worth of content more than it has rows.
        handler.dropSlotAddsRow = borrowsDropRow(source, handler: handler, context: context)
        handler.syncReturningRows(with: context.environment.dragAndDropSession)
        // BEFORE the rows are composed: the slot's position is decided down
        // there, and under auto-scroll the answer it would otherwise use was
        // resolved against the previous frame's rows.
        handler.carryReorderTargetThroughAutoScroll()
        // A list only scrolls (and shows indicators) when its rows — plus that
        // borrowed line — don't all fit in the content area.
        let overflowing = rowsOverflow(
            source, targetContentHeight: contentHeight,
            plusLines: handler.dropSlotAddsRow ? 1 : 0)
        // Which indicator this list draws, if any: a bar down the trailing
        // edge (the default), the "N more" text lines, or — when the visibility
        // says so — nothing at all. Decided before the offset-1 snap below,
        // which only saves an indicator line a bar doesn't have.
        // `.fitting(contentHeight:)`: below three lines the "N more" pair would
        // take the whole content area and the rows would be unreachable at any
        // offset. Applied HERE, at the one point the list resolves them, so
        // every consumer downstream — the window origin, the row budget, the
        // max offset, the overscroll settle, the composers — agrees.
        let indicators = context.environment
            .verticalScrollIndicators(overflowing: overflowing)
            .fitting(contentHeight: contentHeight)
        let showsScrollbar = indicators.bar
        // Clamp the offset against the largest possible visible-row
        // count (one indicator, at an end); the exact viewport is
        // finalised by `ScrollRowWindow` once the offset is known.
        let provisionalViewport =
            overflowing ? max(1, contentHeight - 1) : contentHeight
        handler.contentHeight = contentHeight
        // A scrollbar draws no "N more" indicator line, so the scroll-bound
        // arithmetic must not reserve one (else the bottom over-scrolls, leaving
        // a blank row-height remainder).
        handler.showsScrollbar = showsScrollbar
        // …and neither does a list whose indicators are hidden outright, which
        // is why this is the resolved answer rather than `!showsScrollbar`.
        handler.drawsScrollIndicators = indicators.text
        handler.viewportHeight = provisionalViewport
        handler.canBeFocused = !isDisabled(in: context)
        // Everything the handler's EVENTS will read out of the environment, in
        // one shared call — see `ItemListHandler.syncFrameInputs`, which exists
        // because this block used to be hand-copied here and in Table's two
        // composers, and a capture added to one of the three was silently dead
        // on the other two.
        //
        // `keyboardMoveIsLive: false` — a List's composer draws a drop slot, so
        // the faint copy at it is the preview. Stated rather than left to the
        // default, which is what makes this the same statement Table's two paths
        // make and therefore comparable with them.
        //
        // `rowHeight` — List rows can be any height (the renderer already windows
        // by real line heights), so the focus-reveal AND offset-clamp arithmetic
        // must accumulate the same heights; otherwise a Down past the fold leaves
        // the focused multi-line row off screen ("selection disappears") and the
        // tail rows are unreachable. Set before the clamp below, so this frame's
        // clamp uses this frame's rows. Lazy and memoised: only a viewport's
        // worth is ever queried, so single-line lists pay nothing new and
        // windowed lists stay O(visible).
        handler.syncFrameInputs(
            environment: context.environment,
            reorderFeedback: context.environment.rowReorderFeedback,
            keyboardMoveIsLive: false,
            rowHeight: { source.row(at: $0).buffer.height })
        // §1.5: how far past its edges this view may be pushed, re-resolved
        // every frame (a `.viewport`-relative allowance moves with the
        // terminal) and pulling any existing excursion back inside it.
        handler.resolveOverscroll(
            environment: context.environment, contentHeight: contentHeight,
            reservesIndicatorLine: indicators.text && overflowing)
        // Mutating the *persistent* scroll position must happen only on the
        // real render pass, never while measuring. A `List` with no explicit
        // height that shares space with a flexible sibling (e.g. a trailing
        // `Spacer`) is measured with the FULL available height — much larger
        // than the height it ends up rendering into — so a measure-pass
        // `clampScrollOffset()` would clamp `scrollOffset` against a viewport
        // (and therefore a `maxOffset`) far smaller than the real one, pulling
        // the offset back every frame. The symptom: the list can't be scrolled
        // (wheel / arrows / Page Down / End) the last screenful to its bottom.
        // The render pass below runs last and clamps with the true viewport, so
        // legitimate clamping (e.g. a filter shrinking the row count) still
        // happens every frame.
        if !context.isMeasuring {
            handler.clampScrollOffset()
            handler.clampTopClip()
            // Never rest at offset 1 — see `settleRestingOffset`, which both
            // List and Table call so the rule cannot drift between them again.
            handler.settleRestingOffset(
                overflowing: overflowing, drawsTextIndicators: indicators.text,
                firstRowHeight: source.row(at: 0).buffer.height)
        }

        // Wire up id resolution + the selectable-index set. For an all-content
        // windowed list (the hot path) both are O(1): ids resolve lazily per
        // visible row through `idAt`, and an empty `selectableIndices` already
        // means "every row is selectable" (see ItemListHandler) — so we never
        // materialise a 50k-entry id array or a 50k-index Set per frame. The id
        // reads that remain are O(visible). A heterogeneous row set (Sections,
        // with non-selectable headers/footers) is small, so it builds the
        // explicit maps eagerly as before.
        if source.allContent {
            handler.idAt = { index in
                if case .content(let id) = source.type(at: index) { return id }
                return nil
            }
            handler.itemIDs = []
            handler.selectableIndices = []
        } else {
            var selectableIndices = Set<Int>()
            var itemIDs: [SelectionValue?] = []
            itemIDs.reserveCapacity(source.count)
            for index in 0..<source.count {
                if case .content(let id) = source.type(at: index) {
                    itemIDs.append(id)
                    selectableIndices.insert(index)
                } else {
                    itemIDs.append(nil)
                }
            }
            handler.idAt = nil
            handler.itemIDs = itemIDs
            handler.selectableIndices = selectableIndices
        }
        handler.singleSelection = singleSelection
        handler.multiSelection = multiSelection
        // A hierarchical list's rows come from an `OutlineGroup`, which is what
        // knows how to open one — reached the same way `.onMove` / `.onDelete`
        // are, by asking the content.
        let outline = content as? any OutlineRowActivating
        handler.outlineActivation = outline
        // Return ACTIVATES the focused row, and for a branch with no other
        // action the activation is to disclose it. An app's own
        // `.onRowActivate` still wins — Left / Right keep the tree reachable
        // when it does.
        handler.primaryAction =
            primaryAction
            ?? outline.map { activating in
                { id in
                    activating.setRowExpanded(
                        AnyHashable(id), to: nil, includingDescendants: false)
                }
            }
        // An editable `ForEach` (`.onDelete` / `.onMove`) makes the focused row
        // deletable via the Delete / Backspace key and draggable to reorder.
        // Wired ONLY for the homogeneous all-content list, where a row's focus
        // index equals its data offset — a Section's header / footer rows would
        // shift that mapping, so a Section-nested ForEach isn't exposed here.
        let dynamicActions = source.allContent ? content as? DynamicViewContentActions : nil
        handler.onDelete = dynamicActions?.deleteAction
        handler.onMove = dynamicActions?.moveAction
        // Apply whichever anchor is in effect (§1.1): a `.row` designation pins
        // that row as data changes around it, a `.bottom` edge follows the tail.
        // Render pass only — it mutates the persistent offset — and after the id
        // resolver above so a row key resolves. A no-op for every list with
        // neither `.anchorPosition` nor `defaultScrollAnchor`.
        if !context.isMeasuring {
            handler.applyAnchorHold()
        }
        return (handler, overflowing, showsScrollbar)
    }

    /// Stitches together the row content with top / bottom
    /// scroll indicators and returns both the rendered lines
    /// and the y-ranges each visible row occupies inside that
    /// list (used by the click hit-test to find the row index
    /// for a given click position).
    private func composeRowLines(
        handler: ItemListHandler<SelectionValue>,
        origin: WindowOrigin,
        visibleRows: [(Int, SelectableListRow<SelectionValue>)],
        listHasFocus: Bool,
        rowWidth: Int,
        contentHeight: Int,
        style: any ListStyle,
        context: RenderContext
    ) -> (lines: [String], ranges: [VisibleRowRange], runs: [AnimatedCellRun]) {
        let palette = context.environment.palette
        // The indicator lines are chrome — they describe where the content sits —
        // so the rows are collected separately and an overscroll slide moves only
        // them (§1.5). `lines` is assembled from the three parts at the end.
        var rowLines: [String] = []
        var ranges: [VisibleRowRange] = []
        /// Every animated run among `rowLines` — the breathing rows' whole-line
        /// pulses and the rows' own narrower runs alike. Turned into
        /// ``AnimatedCellRun``s at the end, once the reorder clip and the
        /// overscroll slide have had their say about where those lines actually
        /// ended up.
        var pulseRuns: [RowRun] = []
        var topIndicator: (text: String, animation: AnimatedCellRun?)?
        var bottomIndicator: (text: String, animation: AnimatedCellRun?)?

        // A focused list with no scrollbar pulses its "N more" indicators as
        // its focus cue (in addition to the pulsing cursor row) — the
        // scrollbar-less counterpart to the bar's own pulse.
        //
        // A CYCLE, not this tick's colour: the indicator hands its own cells to
        // the run loop and reads no clock, the way `ScrollView`'s already does.
        // Built ONLY when an indicator will actually be drawn — a list whose
        // indicators are hidden draws none of it, and this path also serves
        // `.scrollIndicators(.hidden)`, which reaches it precisely BECAUSE
        // there is no bar to send it down the other one.
        let drawsIndicator =
            handler.drawsScrollIndicators
            && (origin.offset > 0 || origin.topClip > 0 || handler.hasContentBelow)
        let indicatorCycle =
            drawsIndicator
            ? scrollIndicatorCycle(isFocused: listHasFocus, context: context) : nil
        let numberLocale = context.environment.locale

        if handler.drawsScrollIndicators, origin.offset > 0 || origin.topClip > 0 {
            topIndicator = renderScrollIndicator(
                direction: .up,
                count: max(1, origin.offset),
                unit: .rows,
                width: rowWidth,
                palette: palette,
                cycle: indicatorCycle,
                locale: numberLocale
            )
        }

        // The content area fills EXACTLY, under either granularity: the bottom
        // row may be partially clipped (as the top row already can be, via
        // `scrollTopClipLines`), so the list's height never changes with which
        // rows happen to be visible.
        let indicatorLines =
            (topIndicator == nil ? 0 : 1)
            + (handler.drawsScrollIndicators && handler.hasContentBelow ? 1 : 0)
        let rowLineBudget = max(1, contentHeight - indicatorLines)
        var rowLinesEmitted = 0

        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isCursorRow(rowIndex) && listHasFocus
            let isSelected = handler.isSelected(at: rowIndex)
            let rendered = renderRow(
                row: row,
                state: RowDrawState(
                    isFocused: isFocused, isSelected: isSelected,
                    isReturningHome: handler.returningRows.contains(rowIndex)),
                rowWidth: rowWidth,
                sectionContentIndex: sectionContentIndex,
                style: style,
                context: context,
                palette: palette
            )
            // The top visible row enters partially, its first `clip` lines
            // scrolled off above the viewport (clipped by the RESOLVED origin,
            // which is also what the window walk, the indicators, the bands and
            // the click mapping measure from), and the bottom row leaves
            // partially, clipped at the budget.
            //
            // During a reorder hold the budget clip is deferred to
            // `clipReorderOverrun` below, which knows not to clip THROUGH the
            // slot — a blind mid-loop clip took away the only thing on screen
            // saying where the rows would land when the slot was last.
            var budget: Int?
            if handler.reorder == nil {
                let remaining = rowLineBudget - rowLinesEmitted
                if remaining <= 0 { break }
                budget = remaining
            }
            let (styledLines, pulseFrames, childRuns) = clipRow(
                rendered,
                topClip: rowIndex == origin.offset ? origin.topClip : 0,
                budget: budget)
            let yStart = rowLines.count
            rowLines.append(contentsOf: styledLines)
            if let pulseFrames {
                pulseRuns += pulseFrames.enumerated().map {
                    RowRun(
                        y: yStart + $0.offset, x: 0, width: rowWidth, frames: $0.element,
                        frameDuration: AnimationClock.cursor.tickInterval, clock: .cursor)
                }
            }
            pulseRuns += childRuns.map { $0.moved(to: yStart + $0.y) }
            rowLinesEmitted += styledLines.count
            ranges.append((
                rowIndex: rowIndex,
                yStart: yStart,
                height: styledLines.count,
                type: row.type
            ))
            if case .content = row.type { sectionContentIndex += 1 }
        }

        // A drag never changes how much is on screen, so a reorder frame's
        // overrun is clipped here, slot-aware: the per-row clip above stands
        // down for a hold, and the window fit before the slot was added, so
        // held rows scrolled out of it overflow the content area by the slot's
        // height.
        if handler.reorder != nil {
            clipReorderOverrun(
                lines: &rowLines, ranges: &ranges, pulseRuns: &pulseRuns,
                budget: rowLineBudget)
        }

        if handler.drawsScrollIndicators, handler.hasContentBelow {
            bottomIndicator = renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                unit: .rows,
                width: rowWidth,
                palette: palette,
                cycle: indicatorCycle,
                locale: numberLocale
            )
        }

        return slideAndWrap(
            rowLines: rowLines, ranges: ranges, pulseRuns: pulseRuns,
            topIndicator: topIndicator, bottomIndicator: bottomIndicator,
            handler: handler, rowWidth: rowWidth)
    }

    /// Applies the overscroll slide to the rows, then wraps the (unmoved) "N
    /// more" indicators back around them.
    ///
    /// The rows' bands and their animated runs are relative to the assembled
    /// lines, so both take the slide AND the top indicator's offset. A row —
    /// or a run — slid off screen is dropped rather than left claiming cells
    /// that are no longer its own.
    private func slideAndWrap(
        rowLines: [String], ranges: [VisibleRowRange],
        pulseRuns: [RowRun],
        topIndicator: (text: String, animation: AnimatedCellRun?)?,
        bottomIndicator: (text: String, animation: AnimatedCellRun?)?,
        handler: ItemListHandler<SelectionValue>, rowWidth: Int
    ) -> (lines: [String], ranges: [VisibleRowRange], runs: [AnimatedCellRun]) {
        let blank = String(repeating: " ", count: max(0, rowWidth))
        let slidRows = handler.overscrollState.slid(rowLines, blank: blank)
        let topOffset = topIndicator == nil ? 0 : 1
        let assembled = [topIndicator?.text].compactMap { $0 } + slidRows
            + [bottomIndicator?.text].compactMap { $0 }
        let moved = slidRanges(ranges, handler: handler, lineCount: slidRows.count)
            .map {
                (rowIndex: $0.rowIndex, yStart: $0.yStart + topOffset, height: $0.height,
                 type: $0.type)
            }
        var runs = slidRuns(
            pulseRuns, handler: handler, lineCount: slidRows.count, topOffset: topOffset)
        // The indicators are chrome, not rows: the slide moves the rows past
        // them and leaves them where they are, so their runs sit at the first
        // and last assembled lines whatever the rows did.
        if let top = topIndicator?.animation { runs.append(top.shifted(byX: 0, y: 0)) }
        if let bottom = bottomIndicator?.animation {
            runs.append(bottom.shifted(byX: 0, y: assembled.count - 1))
        }
        return (assembled, moved, runs)
    }

    /// One run per breathing line, moved by the overscroll slide the way
    /// ``slidRanges`` moves the row bands, and offset past the top indicator.
    private func slidRuns(
        _ pulseRuns: [RowRun], handler: ItemListHandler<SelectionValue>,
        lineCount: Int, topOffset: Int
    ) -> [AnimatedCellRun] {
        pulseRuns.compactMap { run in
            var y = run.y
            if handler.overscrollState.excursion != 0 {
                guard let moved = handler.overscrollState.slidRange(
                    yStart: y, height: 1, lineCount: lineCount)
                else { return nil }
                y = moved.yStart
            }
            guard !run.frames.isEmpty else { return nil }
            return AnimatedCellRun(
                offsetX: run.x, offsetY: y + topOffset, width: run.width,
                frames: run.frames, frameDuration: run.frameDuration, clock: run.clock)
        }
    }

    /// The vertical scrollbar cells for a list, one styled single-cell string per
    /// content line. Metrics are in *lines* (the user's spec — a five-line row
    /// scrolls as five units).
    ///
    /// Cost discipline: when every visible row is one line (the common case, and
    /// every windowed mega-list), line == row, so the extent is just the row count
    /// and nothing extra is materialised. Only a list actually showing a taller
    /// row sums the true line heights — and only because a bar is displayed; a
    /// `.hidden` list (the default) never reaches here at all.
    private func listScrollbarCells(
        source: RowSource<SelectionValue>,
        origin: WindowOrigin,
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        contentHeight: Int,
        handler: ItemListHandler<SelectionValue>,
        context: RenderContext,
        palette: any Palette
    ) -> [String] {
        let extentLines: Int
        let offsetLines: Int
        if visibleRows.allSatisfy({ $0.row.buffer.height == 1 }) {
            extentLines = source.count
            offsetLines = origin.offset
        } else {
            // Reading an off-screen row's height means MATERIALISING and
            // rendering it — far dearer than the Table twin's wrap, and needed
            // only to place a thumb. So the visible rows (already rendered,
            // free to read) are exact and the rest follow
            // ``ScrollExtentPrecision``. A line-granularity top clip adds its
            // hidden lines to the offset, so the thumb tracks fine wheel steps
            // exactly at the top of the travel.
            var onScreen: [Int: Int] = [:]
            onScreen.reserveCapacity(visibleRows.count)
            for entry in visibleRows { onScreen[entry.index] = entry.row.buffer.height }
            // DATA rows only. A reorder decorates the window with a landing
            // slot carrying the sentinel index −1, and when that slot is the
            // last entry the upper bound came out `-1 + 1 == 0` against a lower
            // bound past it — an inverted Range, which traps. `Table`'s twin
            // takes its range from the handler for exactly this reason.
            let dataRows = visibleRows.filter { $0.index != ItemListHandler<SelectionValue>.reorderSlotRowIndex }
            let visible =
                (dataRows.first?.index ?? origin.offset)
                ..< ((dataRows.last?.index).map { $0 + 1 } ?? origin.offset)
            // Everything that shapes an off-screen row's rendered height, so a
            // stale mean cannot outlive the layout that produced it (see
            // `extentMeanCache`). Content edits under an unchanged signature
            // are the documented estimate trade.
            var hasher = Hasher()
            hasher.combine(source.count)
            hasher.combine(context.availableWidth)
            hasher.combine(context.environment.scrollExtentPrecision)
            let signature = hasher.finalize()
            let cachedMean =
                handler.extentMeanCache.flatMap { $0.signature == signature ? $0.mean : nil }
            let metrics = ScrollExtentEstimator.lineMetrics(
                visible: visible, count: source.count, topClip: origin.topClip,
                precision: context.environment.scrollExtentPrecision,
                cachedMean: cachedMean,
                height: { onScreen[$0] ?? source.row(at: $0).buffer.height })
            if !context.isMeasuring, let mean = metrics.mean {
                handler.extentMeanCache = (signature: signature, mean: mean)
            }
            (extentLines, offsetLines) = (metrics.extent, metrics.offset)
        }

        return ScrollbarRenderer.verticalScrollbar(
            height: contentHeight, extent: extentLines, viewport: contentHeight, offset: offsetLines,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: ScrollbarColors(
                thumb: palette.foregroundSecondary, track: ScrollbarColors.track(in: palette),
                arrow: palette.foregroundTertiary))
    }

    /// Like ``composeRowLines`` but draws a vertical scrollbar (`bar`, one styled
    /// cell per content line) in the rightmost column instead of the "N more" text
    /// indicators. Each rendered line gets its own bar cell, so a tall row covers
    /// as many bar cells as it is lines tall.
    private func composeScrollbarRowLines(
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        handler: ItemListHandler<SelectionValue>,
        origin: WindowOrigin,
        listHasFocus: Bool,
        contentRowWidth: Int,
        bar: [String],
        style: any ListStyle,
        context: RenderContext
    ) -> (lines: [String], ranges: [VisibleRowRange], runs: [AnimatedCellRun]) {
        let palette = context.environment.palette
        let contentHeight = bar.count
        let emptyCell = ANSIRenderer.colorize(" ", background: ScrollbarColors.track(in: palette))
        func barCell(at line: Int) -> String { line < bar.count ? bar[line] : emptyCell }

        // Content-only row lines. The bar cell is merged in at the END, keyed by
        // absolute line index, so an overscroll slide moves the rows and leaves
        // the bar where it is.
        var lines: [String] = []
        var ranges: [VisibleRowRange] = []
        /// The breathing rows' lines and every frame of each, at their position
        /// among `lines` — turned into runs at the end, after the reorder clip
        /// and the overscroll slide (see composeRowLines).
        var pulseRuns: [RowRun] = []
        var sectionContentIndex = 0
        for (rowIndex, row) in visibleRows {
            if case .header = row.type { sectionContentIndex = 0 }
            let isFocused = handler.isCursorRow(rowIndex) && listHasFocus
            let isSelected = handler.isSelected(at: rowIndex)
            let rendered = renderRow(
                row: row,
                state: RowDrawState(
                    isFocused: isFocused, isSelected: isSelected,
                    isReturningHome: handler.returningRows.contains(rowIndex)),
                rowWidth: contentRowWidth,
                sectionContentIndex: sectionContentIndex,
                style: style,
                context: context,
                palette: palette
            )
            // The top visible row enters partially and the bottom leaves
            // partially — see `clipRow`, which both paths share. The bar area's
            // height is a hard budget here whatever the granularity, because a
            // bar spends no line on indicators (the same `showsBar ||` shape the
            // Table uses); during a reorder hold it defers to the slot-aware
            // `clipReorderOverrun`, as `composeRowLines` does.
            var budget: Int?
            if handler.reorder == nil {
                let remaining = contentHeight - lines.count
                if remaining <= 0 { break }
                budget = remaining
            }
            let (styledLines, pulseFrames, childRuns) = clipRow(
                rendered,
                topClip: rowIndex == origin.offset ? origin.topClip : 0,
                budget: budget)
            let yStart = lines.count
            // An intrinsically over-wide row must not push the bar cell past
            // the interior (where the container clamp would cut the bar off);
            // hard-clip it to the content column, matching the container's
            // own clipping of over-wide rows on the bar-less path. A run's
            // frames go through the same fit, or the run would claim more
            // cells than its line occupies and paint over the bar.
            func fitted(_ rowLine: String) -> String {
                let width = rowLine.strippedLength
                guard width > contentRowWidth else {
                    return rowLine + String(repeating: " ", count: contentRowWidth - width)
                }
                let (cut, cutWidth) = rowLine.ansiAwarePrefixWithWidth(
                    visibleCount: contentRowWidth, knownVisibleWidth: width)
                return cut + String(repeating: " ", count: max(0, contentRowWidth - cutWidth))
            }
            for (offset, rowLine) in styledLines.enumerated() {
                lines.append(fitted(rowLine))
                if let frames = pulseFrames?[offset] {
                    pulseRuns.append(
                        RowRun(
                            y: yStart + offset, x: 0, width: contentRowWidth,
                            frames: frames.map(fitted),
                            frameDuration: AnimationClock.cursor.tickInterval, clock: .cursor))
                }
            }
            // The row's own runs need no `fitted` pass — they were already
            // rejected in `renderRow` if they reached past the content column,
            // which is the same boundary the hard clip above enforces.
            pulseRuns += childRuns.map { $0.moved(to: yStart + $0.y) }
            ranges.append((
                rowIndex: rowIndex,
                yStart: yStart,
                height: styledLines.count,
                type: row.type
            ))
            if case .content = row.type { sectionContentIndex += 1 }
        }
        // Slot-aware overrun clip for a reorder hold (see composeRowLines).
        if handler.reorder != nil {
            clipReorderOverrun(
                lines: &lines, ranges: &ranges, pulseRuns: &pulseRuns, budget: contentHeight)
        }

        // Fill the area below the last row so the bar spans the full height.
        let blank = String(repeating: " ", count: contentRowWidth)
        while lines.count < contentHeight { lines.append(blank) }

        // §1.5: slide the rows within the bar's span, then pair each with its
        // bar cell by absolute line index — the bar itself never moves.
        let slid = handler.overscrollState.slid(lines, blank: blank)
        return (
            slid.enumerated().map { $0.element + barCell(at: $0.offset) },
            slidRanges(ranges, handler: handler, lineCount: slid.count),
            slidRuns(pulseRuns, handler: handler, lineCount: slid.count, topOffset: 0))
    }

    /// A row's lines, its pulse frames and its own runs, clipped TOGETHER.
    ///
    /// The three have to move as one: a run is spliced over cells by position,
    /// so `pulseFrames[i]` must stay the frames of `lines[i]` and a run whose
    /// line was scrolled away must go with it. An off-by-one here repaints the
    /// row above or below, every tick, forever — which is why both assembly
    /// paths call this rather than each doing it, and drifting.
    ///
    /// - Parameters:
    ///   - topClip: Lines scrolled off above the viewport (the top visible row
    ///     only). Never the whole row: one line always survives.
    ///   - budget: Lines still available below, or `nil` when the caller clips
    ///     elsewhere (a reorder hold defers to `clipReorderOverrun`, which knows
    ///     not to clip through the slot).
    private func clipRow(
        _ rendered: RenderedRow, topClip: Int, budget: Int?
    ) -> (lines: [String], pulseFrames: [[String]]?, childRuns: [RowRun]) {
        var lines = rendered.lines
        var pulseFrames = rendered.pulseFrames
        var childRuns = rendered.childRuns
        if topClip > 0 {
            let clipped = min(topClip, lines.count - 1)
            lines.removeFirst(clipped)
            pulseFrames?.removeFirst(clipped)
            childRuns = childRuns.compactMap {
                $0.y >= clipped ? $0.moved(to: $0.y - clipped) : nil
            }
        }
        if let budget, lines.count > budget {
            let dropped = lines.count - budget
            lines.removeLast(dropped)
            pulseFrames?.removeLast(dropped)
        }
        return (lines, pulseFrames, childRuns.filter { $0.y < lines.count })
    }

    /// Clips a reorder frame's overrun — away from the SLOT, never through it.
    ///
    /// WHICH end gives way, and by how much, is
    /// ``ItemListHandler/reorderOverrun(lineCount:budget:endsWithSlot:)``,
    /// shared with `Table.clipOverrun`; see it for the rule and for why the
    /// `max(1, budget)` floor this used to carry is gone. What is left here is
    /// the application, which is the List's own: its ranges and pulse runs
    /// travel with the lines they describe, and one clipped away above the
    /// viewport goes with it.
    private func clipReorderOverrun(
        lines: inout [String], ranges: inout [VisibleRowRange],
        pulseRuns: inout [RowRun], budget: Int
    ) {
        let clip = ItemListHandler<SelectionValue>.reorderOverrun(
            lineCount: lines.count, budget: budget,
            endsWithSlot: ranges.last?.rowIndex == Self.reorderSlotRowIndex)
        let overrun = max(clip.front, clip.back)
        guard overrun > 0 else { return }
        if clip.front > 0 {
            lines.removeFirst(overrun)
            // The runs move with the lines they describe, and one clipped away
            // above the viewport goes with it.
            pulseRuns = pulseRuns.compactMap {
                $0.y >= overrun ? $0.moved(to: $0.y - overrun) : nil
            }
            ranges = ranges.compactMap { range in
                let end = range.yStart + range.height - overrun
                guard end > 0 else { return nil }
                let start = max(0, range.yStart - overrun)
                return (
                    rowIndex: range.rowIndex, yStart: start, height: end - start,
                    type: range.type)
            }
        } else {
            lines.removeLast(overrun)
            let cap = lines.count
            pulseRuns = pulseRuns.filter { $0.y < cap }
            ranges = ranges.compactMap { range in
                guard range.yStart < cap else { return nil }
                return (
                    rowIndex: range.rowIndex, yStart: range.yStart,
                    height: min(range.height, cap - range.yStart), type: range.type)
            }
        }
    }

    /// The row ranges after an overscroll slide, dropping any pushed off screen.
    private func slidRanges(
        _ ranges: [VisibleRowRange], handler: ItemListHandler<SelectionValue>, lineCount: Int
    ) -> [VisibleRowRange] {
        guard handler.overscrollState.excursion != 0 else { return ranges }
        return ranges.compactMap { range in
            guard
                let moved = handler.overscrollState.slidRange(
                    yStart: range.yStart, height: range.height, lineCount: lineCount)
            else { return nil }
            return (
                rowIndex: range.rowIndex, yStart: moved.yStart, height: moved.height,
                type: range.type)
        }
    }

    // MARK: - Mouse handler wiring

    /// Registers the list's container-wide mouse handler and
    /// emits its hit-test region (inserted at the front of the
    /// regions array so interactive children inside rows still
    /// win their clicks — this region is the fallback).
    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        paddingTop: Int
    ) {
        guard !isDisabled(in: context), !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        // A bordered container places content at y = 1 (below the top border);
        // a borderless (`.plain`) list has NO top border row, so its content
        // starts at y = 0. Add the configured top padding. The captured row
        // y-ranges are already relative to the content (they include the
        // scroll-indicator's own row when present), so this inset is the
        // entire translation needed. (Hardcoding `1` here shifted every
        // borderless click up a row — clicking row 2 selected row 1.)
        let topInset = (context.environment.listStyle.showsBorder ? 1 : 0) + paddingTop

        publishRowBands(state: state)

        // The scrollbar's own handler goes in first so the container's later
        // insert(at: 0) pushes it to a higher index — hit-tested ahead of the
        // container (reverse iteration) for its single column. The bar's metrics
        // are in lines while its offset is in rows, so dragging is exact for
        // uniform 1-line rows and proportional for taller rows (arrows/track stay
        // exact). Its own repeat token lets it auto-repeat independently.
        let showsBorder = context.environment.listStyle.showsBorder
        if let barColumn = state.scrollbarColumn, state.scrollbarHeight > 0 {
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: state.handler, length: state.scrollbarHeight,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barHandlerID = mouseDispatcher.register(
                ScrollbarRenderer.focusing(
                    barHandler, focusID: state.focusID,
                    focusManager: context.environment.focusManager))
            // A bordered list's bar sits against the right border: widen the
            // bar's region over that border column too — a click there is
            // almost certainly aimed at the bar, not at "select whatever row
            // shares this y" (the handler only reads y, so the extra column
            // costs nothing).
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: barColumn, offsetY: topInset,
                    width: showsBorder ? 2 : 1,
                    height: state.scrollbarHeight, handlerID: barHandlerID),
                at: 0
            )
            ScrollbarRenderer.driveAutoRepeat(
                state: state.handler,
                token: "list-scrollbar-repeat-\(context.identity.path)", context: context)
        }

        // Selection needs a click on the CONTENT columns: the border is
        // chrome, and a click there (however row-aligned its y) must not
        // select — see the x-guard in the handler. Clamped: a degenerate
        // (sub-2-column) list still yields a valid, empty range.
        let borderInset = showsBorder ? 1 : 0
        let contentColumns = borderInset..<max(borderInset, buffer.width - borderInset)
        let mouseHandlerID = mouseDispatcher.register(
            containerMouseHandler(
                state: state,
                focusManager: focusManager,
                dragSession: context.environment.dragAndDropSession,
                dispatcher: mouseDispatcher,
                topInset: topInset,
                // Where a row's own content starts: past the border, the style's
                // leading padding, and `renderPlainLine`'s 1-cell gutter — the
                // same column the row's hit regions are translated by. A
                // `.cursor` drag measures its grab point from here, so the row
                // rides the cursor on the exact cell that was pressed.
                rowContentLeft: borderInset + context.environment.listStyle.rowPadding.leading + 1,
                contentColumns: contentColumns
            )
        )
        // The rows are a landing place for drags from elsewhere. It borrows the
        // container's region: same rectangle, and the drop target only needs
        // the geometry — clicks still go to the container's own closure.
        registerRowTargets(
            zoneID: mouseHandlerID, state: state, context: context,
            topInset: topInset, contentColumns: contentColumns, insertion: state.dropInsertion)
        // Insert at index 0 so any interactive child inside a
        // row (Button, TextField, Stepper) still wins the
        // dispatcher's reverse-iteration match. This region is
        // the fallback — it fires only when nothing more
        // specific matched.
        // The list's focusID rides on this region: it is how an enclosing
        // ScrollView locates the focused list to scroll it into view
        // (`snapViewportToFocusedControl` scans regions by focusID).
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: mouseHandlerID,
                focusID: state.focusID
            ),
            at: 0
        )

        // A one-row region at the keyboard cursor's on-screen line, stamped
        // with the SAME focusID and inserted ahead of the container region:
        // `snapViewportToFocusedControl` takes the FIRST region matching the
        // focused ID, so an enclosing ScrollView follows the cursor row — not
        // the list's top — as the selection moves through a list taller than
        // the outer viewport, and its indicator-aware fire condition keeps
        // the row from resting hidden under "▲ N more above". At index 0 the
        // dispatcher's reverse iteration never routes a click here before the
        // container region, so reusing its handler is inert.
        if let (position, _) = zip(state.visibleRowYRanges, state.visibleRows)
            .first(where: { $0.1.index == state.handler.focusedIndex })
        {
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: 0,
                    offsetY: topInset + position.yStart,
                    width: buffer.width,
                    height: max(1, position.height),
                    handlerID: mouseHandlerID,
                    focusID: state.focusID
                ),
                at: 0
            )
        }

        // Rows render into standalone (per-frame memoised) buffers, so their
        // own hit-test regions — per-row `.onMouseEvent`, Buttons and other
        // interactive children — must be carried into the list's buffer
        // explicitly, translated to each row's on-screen position. Without
        // this merge the container fallback above is the ONLY region that
        // ever sees a click, and the "children win" contract is vacuously
        // false. Rows re-render every frame (the row memo lives on the
        // per-frame RowSource), so the handler ids are current. Appended
        // after the container's insert(at: 0) — higher indices, which the
        // dispatcher's reverse iteration matches first.
        let style = context.environment.listStyle
        // Border column (when drawn) + the leading space `renderPlainLine`
        // prefixes to every row line.
        let rowContentX = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + 1
        for (position, visible) in zip(state.visibleRowYRanges, state.visibleRows) {
            // Line granularity: the top row's first `clip` lines are scrolled
            // off above the viewport, so its row-local coordinates shift up
            // by that much. Every other row has no clip. Measured from the
            // RESOLVED origin — the same one the rows were drawn from.
            let clip = visible.index == state.origin.offset ? state.origin.topClip : 0
            for region in visible.row.buffer.hitTestRegions {
                // Rows can be partially visible — the top row clipped above
                // (line granularity), the last row clipped below: intersect
                // each region with the row-local window of lines actually
                // shown, [clip, clip + position.height).
                let start = max(region.offsetY, clip)
                let end = min(region.offsetY + region.height, clip + position.height)
                guard end > start else { continue }
                buffer.hitTestRegions.append(
                    HitTestRegion(
                        offsetX: rowContentX + region.offsetX,
                        offsetY: topInset + position.yStart + (start - clip),
                        width: region.width,
                        height: end - start,
                        handlerID: region.handlerID,
                        focusID: region.focusID
                    )
                )
            }
        }
    }

    /// Carries the rows' overlay layers into the list's buffer.
    ///
    /// A modal, alert or popover presented from row content is emitted into
    /// that row's standalone (per-frame memoised) buffer, and would otherwise
    /// never reach the root compositor — an invisible dialog that has already
    /// grabbed the keyboard.
    ///
    /// Separate from ``attachMouseHandlers`` on purpose, though it used to live
    /// inside it. That function returns early for a DISABLED list and for one
    /// with no mouse dispatcher, which are both perfectly good reasons not to
    /// register click handling and neither of which has anything to do with
    /// compositing — so `List { row.sheet(…) }.disabled(true)` dropped the
    /// overlay for every row, visible ones included, while the presentation
    /// went on activating its focus section and taking the keyboard. Gated on
    /// the measure pass alone: a measure buffer is discarded, so an overlay
    /// left on one describes a dialog that was never drawn.
    ///
    /// Anchored layers translate to the row's on-screen position (`shifted`
    /// leaves screen-centred layers untouched). A layer that is a SURFACE —
    /// a drop-down, a menu, a dialog — is then left alone, because floating
    /// above the in-flow content is the point of an overlay and a picker on
    /// the last row must not lose its options to the list's own edge.
    ///
    /// A layer carrying a piece of a row's own DRAWING is clipped to the list,
    /// which is the same rule ``ScrollView`` applies — there for a SOURCED
    /// reason (SwiftUI's `scrollClipDisabled(_:)` documents that "by default, a
    /// scroll view clips its content to its bounds"), here for an inferred one.
    /// **That SwiftUI's `List` clips is reasoning, not a measurement**: no
    /// documentation was found saying so, and it is believed because a `List`
    /// scrolls and because `.offset(x: 7)` on a row of a 14-wide list was
    /// painting over the page beside it, which is certainly wrong.
    ///
    /// The clip is to the list's OUTER box, so displaced drawing can still
    /// overwrite the list's own border — `.offset(x: 7)` in a 14-wide bordered
    /// list eats the right `│`. Strictly better than before (it used to run
    /// past the border and onto the page) and not yet right. Clipping to the
    /// content box needs a rect-shaped clip on ``OverlayLayer``, whose current
    /// one is anchored at the origin.
    private func attachRowOverlays(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        paddingTop: Int
    ) {
        guard !context.isMeasuring else { return }
        let style = context.environment.listStyle
        let topInset = (style.showsBorder ? 1 : 0) + paddingTop
        let rowContentX = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + 1
        let bounds = (width: buffer.width, height: buffer.height)
        for (position, visible) in zip(state.visibleRowYRanges, state.visibleRows) {
            let clip = visible.index == state.origin.offset ? state.origin.topClip : 0
            for layer in visible.row.buffer.shiftedOverlays(
                byX: rowContentX, y: topInset + position.yStart - clip)
            {
                // `centered` as well as `isOpaque`, though today every centred
                // layer is a modal and so opaque: a centred layer's offset is a
                // post-centre delta rather than a position, so clipping one
                // against these bounds would be arithmetic on the wrong number.
                guard !layer.isOpaque, !layer.centered else {
                    buffer.overlays.append(layer)
                    continue
                }
                if let clipped = layer.clipped(toWidth: bounds.width, height: bounds.height) {
                    buffer.overlays.append(clipped)
                }
            }
        }
    }

    /// Moves the rows' opacity regions into the list's coordinates.
    ///
    /// Unlike an overlay, a region names cells that are IN the list's own
    /// picture, so it clips to the row's visible extent on both axes: a row
    /// half-scrolled off the top must not fade the border above it, and a
    /// region wider than the row must not reach the scrollbar. That is the
    /// same reasoning that clips hit regions in ``ScrollView`` — and the
    /// opposite of what the runs do, because a run carries a fixed picture
    /// that a clip would misalign, while a rectangle survives being trimmed.
    ///
    /// The extra column matches the runs' `1 + offsetX`: every row line begins
    /// with the selection gutter, which the row's own buffer knows nothing of.
    private func attachRowOpacity(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        state: PopulatedRenderState,
        paddingTop: Int
    ) {
        guard !context.isMeasuring else { return }
        let style = context.environment.listStyle
        let topInset = (style.showsBorder ? 1 : 0) + paddingTop
        let rowContentX = (style.showsBorder ? 1 : 0) + style.rowPadding.leading + 1
        for (position, visible) in zip(state.visibleRowYRanges, state.visibleRows) {
            let clip = visible.index == state.origin.offset ? state.origin.topClip : 0
            for region in visible.row.buffer.opacityRegions {
                let top = max(region.offsetY, clip)
                let bottom = min(region.offsetY + region.height, clip + position.height)
                let right = min(region.offsetX + region.width, state.rowContentWidth)
                guard bottom > top, right > region.offsetX else { continue }
                var clipped = region
                clipped.offsetY = top
                clipped.height = bottom - top
                clipped.width = right - region.offsetX
                buffer.opacityRegions.append(
                    clipped.shifted(byX: rowContentX, y: topInset + position.yStart - clip))
            }
        }
    }

    /// Rewrites the visible rows for an in-flight `.dimmed` / `.cursor` reorder.
    ///
    /// The dragged row LEAVES its place: the list closes up behind it and a slot
    /// opens where it would land, holding a faint copy of it under `.dimmed` and
    /// nothing at all under `.cursor`. So the list keeps its length, and what is
    /// on screen is exactly the order a drop would produce — the preview IS the
    /// result, rather than the result plus a leftover.
    ///
    /// What "no slot" means differs by mode, and that is what the two guards
    /// below say. `.dimmed` draws the row only at the slot, so with nowhere to
    /// drop it there is nothing to draw and the list is left untouched.
    /// `.cursor` has the row on the pointer for the whole drag, so it must be
    /// out of the list for the whole drag too — drawn in both places at once it
    /// would read as a duplicate — and the missing gap is what says releasing
    /// here would put it back.
    ///
    /// The slot is typed as a footer, not as content: it carries no id, so
    /// selection ignores it, and it is not a row the keyboard cursor can sit on.
    /// It IS a drop target though — `publishRowBands` gives it a `dropIndex` —
    /// because after every step of the drag the pointer is resting on it.
    private func decorateForReorder(
        _ visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        handler: ItemListHandler<SelectionValue>,
        context: RenderContext,
        palette: any Palette
    ) -> [(index: Int, row: SelectableListRow<SelectionValue>)] {
        // The overwhelmingly common frame has nothing in hand and no external
        // drag hovering: the decoration is the identity, and building the
        // by-index dictionary plus the drawn-rows walk just to reproduce the
        // input was ~11% of a plain List frame's render (session-list.trace,
        // 2026-07-31). Bail before any of it.
        guard !handler.reorderRemovedRows.isEmpty || handler.externalDropSlot != nil else {
            return visibleRows
        }
        // EVERY row in hand, stacked: they land as one block, so the slot is
        // one gap the size of all of them. Showing only the grabbed row made a
        // multi-row drag look like the rest had been deleted.
        let byIndex = Dictionary(
            visibleRows.map { ($0.index, $0.row) }, uniquingKeysWith: { first, _ in first })
        let held = handler.reorderRemovedRows.compactMap { index in
            byIndex[index].map { (index: index, buffer: $0.buffer) }
        }
        // Within a block, the row the cursor is on stays at full strength while
        // its travelling companions go faint — otherwise the slot's pulse is on
        // every one of them and marks none. See `reorderPrimaryHeldRow`; `nil`
        // for one row and for every mouse drag, which keep the old rendering.
        let primary = handler.reorderPrimaryHeldRow
        var body: FrameBuffer
        switch handler.effectiveReorderFeedback {
        case .dimmed:
            body =
                stacked(held.map { $0.index == primary ? $0.buffer : dimmed($0.buffer) })
                ?? blankRow(like: nil)
        case .cursor, .live: body = blankRow(like: stacked(held.map(\.buffer)))
        }
        // Held rows that have scrolled out of the window were never rendered,
        // so there is no buffer to show for them — but the slot must still be
        // the size of the whole block (the drop moves ALL of it; a Table
        // renders its lines straight from `data` and never has this gap, a
        // List row is an arbitrary view that only exists rendered inside the
        // window). Pad with one blank line per unseen row — their true height
        // is unknowable unrendered, and single-line is the overwhelming case.
        let removedCount = handler.reorderRemovedRows.count
        if body.height < removedCount {
            let width = max(1, body.width)
            body = FrameBuffer(
                lines: body.lines
                    + Array(
                        repeating: String(repeating: " ", count: width),
                        count: removedCount - body.height))
        }
        // A keyboard move has no pointer to say where the row is, so the slot
        // says it: the row you are steering is emphasised, not a gap. Carried as
        // a background the ROW renderer paints — baked into the buffer it began
        // one cell late, because the selection gutter is added around the
        // buffer, leaving the slot's first cell at the terminal default.
        let heldBackground = heldSlotBackground(
            handler: handler, context: context, palette: palette)
        // Which rows to draw, and where the slot goes among them, is the shared
        // arithmetic — `Table` asks the same question of the same handler.
        return handler.reorderDrawnRows(
            visibleRows.map(\.index), excluding: carriedRow(visibleRows, context: context)
        ).compactMap { drawn in
            switch drawn {
            case .row(let index):
                return byIndex[index].map { (index: index, row: $0) }
            case .slot:
                var slot = SelectableListRow<SelectionValue>(type: .footer, buffer: body)
                slot.backgroundOverride = heldBackground
                return (Self.reorderSlotRowIndex, slot)
            }
        }
    }

    /// The visible row a `.draggable` drag took out of THIS list, or `nil` when
    /// the drag started anywhere else.
    ///
    /// Such a row is in the user's hand: `DraggableModifier` already renders it
    /// blank, because a view that is floating at the cursor must not also be
    /// sitting in place. That is right for a chip in a plain container, and one
    /// line too many in a list that is ALSO opening a landing slot for the same
    /// drag — the blank and the gap are both "where the row would go". So the
    /// row is dropped from the drawing entirely and the slot is the only gap,
    /// exactly as `.onMove`'s own reorder has always drawn it.
    ///
    /// Matched by IDENTITY rather than by the rendered path: the drag names the
    /// `.draggable` view, which lives INSIDE the row, so the row is an ancestor
    /// of it — and comparing path strings by prefix would let row 1 answer for
    /// row 11.
    private func carriedRow(
        _ visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        context: RenderContext
    ) -> Int? {
        guard let session = context.environment.dragAndDropSession else { return nil }
        return visibleRows.first { entry in
            guard let identity = entry.row.rowIdentity else { return false }
            return session.isDragSource(within: identity)
        }?.index
    }

    /// The colour that marks the slot as the row you are steering — the same
    /// pulse a focused, selected row uses, so "in hand" reads as emphasis
    /// rather than as a hole in the list. Only for a keyboard move: a mouse
    /// drag has the pointer itself to say where the row is.
    private func heldSlotBackground(
        handler: ItemListHandler<SelectionValue>, context: RenderContext, palette: any Palette
    ) -> RowBackground {
        guard handler.isKeyboardMove else { return .none }
        // Literally the same pulse, from the same place: the sentence above is
        // a claim the code now cannot break.
        return .focusedSelection(in: context, palette: palette)
    }

    /// The same buffer with every line drawn faint — `.dimmed`'s preview of the
    /// row, shown at the slot it would land in.
    ///
    /// Persistent, not a bare wrapper: a row of several styled runs carries a
    /// reset per run, and each one would otherwise end the dim early.
    private func dimmed(_ buffer: FrameBuffer) -> FrameBuffer {
        FrameBuffer(lines: buffer.lines.map { ANSIRenderer.applyPersistentDim($0) })
    }

    /// The rows in hand as one buffer, in data order — what travels together,
    /// and so what the slot has to make room for. `nil` for no rows at all (an
    /// external drag hovering, which has no rows of ours to show).
    private func stacked(_ buffers: [FrameBuffer]) -> FrameBuffer? {
        guard !buffers.isEmpty else { return nil }
        return FrameBuffer(lines: buffers.flatMap(\.lines))
    }

    /// A gap the size of the dragged rows — `.cursor`'s "they land here".
    private func blankRow(like buffer: FrameBuffer?) -> FrameBuffer {
        let height = max(1, buffer?.height ?? 1)
        let width = max(1, buffer?.width ?? 1)
        return FrameBuffer(
            lines: Array(repeating: String(repeating: " ", count: width), count: height))
    }

    /// Hands this frame's row geometry to the handler for the reorder drag to
    /// hit-test against.
    ///
    /// It has to come from the handler rather than the mouse closure's captured
    /// copy: a ``RowReorderFeedback/live`` drag reorders the rows underneath the
    /// cursor, so press-frame bands would describe an order that no longer
    /// exists (and a wheel tick can scroll them out from under any mode).
    private func publishRowBands(state: PopulatedRenderState) {
        typealias Handler = ItemListHandler<SelectionValue>
        state.handler.publishRowBands(state.visibleRowYRanges.map { range in
            let entry: Handler.DrawnBand.Content
            if case .content = range.type {
                entry = .row(range.rowIndex)
            } else if range.rowIndex == Self.reorderSlotRowIndex {
                entry = .slot
            } else {
                entry = .chrome(rowIndex: range.rowIndex)
            }
            return Handler.DrawnBand(entry: entry, yStart: range.yStart, height: range.height)
        })
    }

    /// The sentinel row index the reorder drop slot is decorated with — it has
    /// no data behind it, so it cannot carry a real offset. Shared with `Table`.
    private static var reorderSlotRowIndex: Int {
        ItemListHandler<SelectionValue>.reorderSlotRowIndex
    }

    /// Registers everything this frame's rows can receive: a reorder of their
    /// own, and a drop from elsewhere.
    ///
    /// Both borrow the container's region — same rectangle, and both only need
    /// the geometry; clicks still go to the container's own closure. Neither is
    /// conditional on `isScrollEnabled` (the auto-scroll zone is): a drop is not
    /// a scroll, and a list that did not register is one a gesture cannot land
    /// in.
    ///
    /// The drop destination reports WHERE — the
    /// `ForEach.dropDestination(for:action:)` half of the drag-and-drop story.
    /// While a compatible drag hovers, the pointer's row becomes a landing slot
    /// (the same gap a `.cursor` reorder opens, drawn by the same code). On
    /// release the app is told the index it was pointing at.
    private func registerRowTargets(
        zoneID: HitTestRegion.HandlerID,
        state: PopulatedRenderState,
        context: RenderContext,
        topInset: Int,
        contentColumns: Range<Int>,
        insertion: (accepts: (Any) -> Bool, perform: (Int, [Any]) -> Void)?
    ) {
        let handler = state.handler
        // A drag hovering near an edge scrolls the rows to reveal an off-screen
        // drop target. Auto-scroll IS a scroll, so `.scrollDisabled` withholds
        // this one — unlike the two registrations below it.
        if context.environment.isScrollEnabled {
            context.environment.dragAndDropSession?.registerAutoScrollZone(
                DragAndDropSession.AutoScrollZone(
                    handlerID: zoneID, vertical: handler, horizontal: nil,
                    delayNanos: context.environment.dragAutoScrollDelay.clampedNanoseconds,
                    // A title sits above the rows, and a footer (with its
                    // separator) below them — chrome the rows never occupy. Left
                    // in, they eat the hot margin at that edge: a footered list
                    // only scrolled downward once the cursor was over the footer,
                    // the same defect a Table's header caused at the top.
                    topInset: title != nil ? 1 : 0,
                    bottomInset: footer != nil ? 2 : 0,
                    shiftStep: context.environment.shiftStepMultiplier))
        }
        if handler.onMove != nil {
            context.environment.dragAndDropSession?.registerReorderHost(
                DragAndDropSession.ReorderHost(
                    focusID: state.focusID, handlerID: zoneID, topInset: topInset,
                    contentColumns: contentColumns, handler: handler))
        }
        guard let insertion, let session = context.environment.dragAndDropSession else {
            handler.externalDropSlot = nil
            return
        }
        session.registerTarget(
            DragAndDropSession.Target(
                handlerID: zoneID,
                accepts: insertion.accepts,
                perform: { payload, _ in
                    insertion.perform(handler.takeExternalDropSlot(), [payload])
                    return true
                },
                setTargeted: { targeted in
                    if !targeted { handler.externalDropSlot = nil }
                },
                hovering: { _, y in
                    // The band under the pointer names the row it would land
                    // BEFORE; past the last row it appends. Through the handler
                    // so the line is remembered — an auto-scroll tick has to ask
                    // the same question again with no pointer event to go on.
                    handler.hoverExternalDrop(atContentY: y - topInset)
                }))
    }

    /// Builds the closure that the container-wide hit-test
    /// region invokes. Routes wheel to the handler's scroll
    /// position (never the selection), left-release to row hit-
    /// testing + focus, and rejects everything else.
    private func containerMouseHandler(
        state: PopulatedRenderState,
        focusManager: FocusManager?,
        dragSession: DragAndDropSession?,
        dispatcher: MouseEventDispatcher,
        topInset: Int,
        rowContentLeft: Int,
        contentColumns: Range<Int>
    ) -> @MainActor (MouseEvent) -> Bool {
        let captureHandler = state.handler
        let captureFocusID = state.focusID
        let rowRanges = state.visibleRowYRanges
        let capturedPrimaryAction = primaryAction
        let capturedRows = state.visibleRows
        // Where inside the grabbed row the press landed — the cell a `.cursor`
        // drag keeps under the pointer. Held in the closure because the closure
        // IS the gesture: the dispatcher captures it at press and routes the
        // whole drag back here, however many renders intervene.
        let grab = RowReorderGrabPoint()
        return { event in
            // Wheel scrolling moves the viewport, NEVER the
            // selection — same model as Finder / Explorer /
            // VS Code; arrow keys handle selection. Routed
            // through the shared ScrollableOffsetState
            // helper so the math lives in one place.
            if captureHandler.handleWheelEvent(event) { return true }

            if event.button == .left {
                // Row at the cursor (content columns only), from the press-frame
                // bands. Those are exact for the CLICK path — a press and its
                // release describe one unchanging layout — and it is the only
                // path that needs a row's type, and so its selection id. The
                // reorder path deliberately reads the handler's freshly
                // published bands instead: `.live` feedback moves the rows out
                // from under this captured copy as the drag goes.
                func rowAt(y: Int) -> (rowIndex: Int, type: ListRowType<SelectionValue>)? {
                    let yInLines = y - topInset
                    guard contentColumns.contains(event.x),
                        let hit = rowRanges.first(where: {
                            yInLines >= $0.yStart && yInLines < $0.yStart + $0.height
                        })
                    else { return nil }
                    return (hit.rowIndex, hit.type)
                }

                /// The drag's position in the handler's content-line space, or
                /// `nil` once the cursor leaves the rows, in either axis. The
                /// session path asks the same two questions in
                /// `DragAndDropSession.contentY(in:)`, and the two must agree.
                var dragContentY: Int? {
                    contentColumns.contains(event.x)
                        ? captureHandler.rowSpaceContentY(event.y - topInset) : nil
                }

                switch event.phase {
                case .pressed:
                    // Pick up the row for a possible reorder (only when the
                    // ForEach is reorderable). Claim the press either way so the
                    // matching drag / release routes back here.
                    if captureHandler.onMove != nil, let hit = rowAt(y: event.y),
                        case .content = hit.type
                    {
                        captureHandler.beginReorder(grabbing: hit.rowIndex)
                        // Which control the gesture belongs to is the session's
                        // to know from here on: every event after this one is
                        // answered by whichever list is on screen under that
                        // focus identity, not by the one this closure captured.
                        captureHandler.armReorderSession(
                            dragSession, focusID: captureFocusID)
                        // Focus follows the gesture, so the keyboard reaches
                        // this list for the length of it — that is what lets the
                        // navigators scroll a list that was not focused before
                        // the drag began.
                        focusManager?.focus(id: captureFocusID)
                        let band = captureHandler.visibleRowBands.first { $0.rowIndex == hit.rowIndex }
                        grab.x = max(0, event.x - rowContentLeft)
                        grab.y = max(0, event.y - topInset - (band?.yStart ?? 0))
                    }
                    return true

                case .dragged:
                    // Edge auto-scroll applies to reordering too, and the two
                    // feedback modes that open no drag session (`.live`,
                    // `.dimmed`) have to say so explicitly. Armed on the first
                    // MOTION rather than at the press: arming a motionless
                    // long-press near an edge started scrolling the list out
                    // from under a click once the dwell elapsed, with nothing
                    // in hand. Gated on the grab actually having begun — this
                    // closure claims every press, including ones that missed
                    // the reorderable rows.
                    dragSession?.armReorderAutoScrollOnMotion(owner: captureHandler)
                    // Any motion during a grab is a reorder, not a click. What
                    // that looks like is the feedback mode's business — and
                    // `.cursor`'s business reaches outside the list: its row is
                    // carried on the pointer, above every other view, which only
                    // the drag session can draw.
                    // Tracked through the session, which resolves the gesture
                    // against the list rendering NOW and localises the cursor
                    // by that list's rectangle — the captured coordinates
                    // describe the press frame, which is a different place the
                    // moment anything moves. Without a session (a headless
                    // harness) there is only ever one list, so the captured
                    // handler and coordinates are the same answer.
                    let held = dragSession?.reorderHandler ?? captureHandler
                    let wasActive = held.isReordering
                    if let dragSession {
                        dragSession.trackReorder()
                    } else {
                        captureHandler.dragReorder(toContentY: dragContentY)
                    }
                    let current = dragSession?.reorderHandler ?? captureHandler
                    let floating = current.reorderFloatingRows
                    if let dragSession, !floating.isEmpty {
                        let carried = floating.compactMap { index in
                            capturedRows.first { $0.index == index }?.row.buffer
                        }
                        if !wasActive, !carried.isEmpty {
                            // Hand the rows' own buffers to the session, which
                            // floats them at the cursor above everything else.
                            // Their hit regions go — a copy of a row riding the
                            // pointer must not also be clickable.
                            var preview = FrameBuffer(lines: carried.flatMap(\.lines))
                            preview.hitTestRegions = []
                            // The whole block travels, so the grab point moves
                            // down it by however much of the block was above the
                            // row the pointer took hold of — otherwise a block
                            // grabbed by its last row hangs from its first.
                            let above = current.reorderHeldRowsAboveGrab.reduce(0) { sum, index in
                                sum + (capturedRows.first { $0.index == index }?.row.buffer.height ?? 1)
                            }
                            // `begin` trims the preview's padding and clamps
                            // the grab point into what survives, so a press
                            // past the end of a short row still anchors the
                            // floating copy under the pointer.
                            dragSession.begin(
                                payload: RowReorderPayload(), preview: preview,
                                grabX: grab.x, grabY: grab.y + above)
                        } else {
                            // …and advance it on every later movement. `begin`
                            // samples the cursor once; only `dragMoved` tracks
                            // it, and a reorder drag reaches this closure rather
                            // than the `.draggable` modifier that normally calls
                            // it — which is why the row once sat at the position
                            // the drag began for the whole gesture.
                            dragSession.dragMoved()
                        }
                    }
                    return true

                case .released:
                    // Whatever this turns out to be — a drop, or a click that
                    // never moved — the gesture is over, so let go of the edge
                    // auto-scroll. (`end()` below only runs for a real drop.)
                    dragSession?.disarmAutoScroll()
                    // A cancel already put the rows back and ended the drag; the
                    // release that follows is the tail of a cancelled gesture,
                    // not a click on whatever is under the pointer. The SESSION
                    // is asked first: after a page round-trip the handler latch
                    // sits on the adopted replacement, which the fallback below
                    // is not (see `DragAndDropSession.cancelReorder`).
                    if dragSession?.consumeReorderCancellation() == true { return true }
                    let releasing = dragSession?.reorderHandler ?? captureHandler
                    if releasing.reorderCancelled {
                        releasing.reorderCancelled = false
                        return true
                    }
                    // A reorder drop, if this gesture was one. `.live` has
                    // already moved the rows; the other modes move them exactly
                    // there. Committed through the session for the same reason
                    // the drag is tracked through it — and it is the same shape
                    // as `performDrop`, deliberately.
                    if dragSession?.performReorderDrop()
                        ?? captureHandler.dropReorder(atContentY: dragContentY)
                    {
                        focusManager?.focus(id: captureFocusID)
                        return true
                    }

                    // Not a reorder — the original click / selection path.
                    // Translate event.y → row index by walking the captured
                    // y-ranges. Clicks on a row's CONTENT columns select it and
                    // focus the list; clicks on chrome — the border columns,
                    // empty area — just focus (the border shares a y with some
                    // row, but nobody clicking a frame means "select that row").
                    if let hit = rowAt(y: event.y), case .content(let id) = hit.type {
                        // A double-click fires the row's activation ("open"); a
                        // single click selects with macOS semantics (plain =
                        // sole selection, shift = range, ctrl/option = toggle).
                        if captureHandler.completesMultiClick(
                            on: hit.rowIndex, clickCount: event.clickCount),
                            let action = capturedPrimaryAction
                        {
                            captureHandler.focusedIndex = hit.rowIndex
                            // This gesture is spent: the next press begins a
                            // new count, so a second double-click opens once
                            // more rather than once per click.
                            dispatcher.endMultiClickSequence()
                            action(id)
                        } else {
                            captureHandler.handleClickSelection(at: hit.rowIndex, event: event)
                        }
                    }
                    focusManager?.focus(id: captureFocusID)
                    return true

                default:
                    return false
                }
            }
            return false
        }
    }

    // MARK: - Row Extraction

    private func extractRows(from content: Content, context: RenderContext) -> RowSource<SelectionValue> {
        // Section first (it conforms to both Section- and List-RowExtractor, and
        // its row set — header/content/footer — is small and built eagerly).
        if let section = content as? SectionRowExtractor {
            return .eager(extractSectionRows(from: section, context: context))
        }

        // Windowed path (ForEach): the row count is known in O(1) and each row's
        // id is resolved lazily, so the handler/window touch only ~viewport ids
        // (plus the focused row) instead of all N. A row's content box is still
        // built only when the overflow check or the visible window walks to it.
        // This is the hot path for a large flat List and what makes per-frame
        // cost O(visible), not O(total). Falls through to the eager path when the
        // ids can't be expressed as SelectionValue.
        if let windowed = content as? WindowedListRowExtractor {
            let count = windowed.listRowCount
            // The conformer is id-homogeneous (see WindowedListRowExtractor), so
            // row 0's resolvability decides the whole list: probe it once rather
            // than resolving all N ids up front. An empty list windows trivially.
            if count == 0 || (windowed.listRowID(at: 0) as SelectionValue?) != nil {
                return RowSource(
                    count: count,
                    allContent: true,
                    signature: windowed.listRowsSignature,
                    typeAt: { index in
                        // Force-unwrap is safe: row 0 resolved and the data is
                        // id-homogeneous, so every index resolves as SelectionValue.
                        let id: SelectionValue = windowed.listRowID(at: index)!
                        return .content(id: id)
                    },
                    make: { index in windowed.makeListRowContent(at: index, context: context) })
            }
        }

        // Eager ListRowExtractor (e.g. a ForEach whose ids couldn't all resolve).
        if let extractor = content as? ListRowExtractor {
            let rows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
            return .eager(
                rows.map {
                    SelectableListRow(
                        type: $0.id.map { .content(id: $0) } ?? .unselectable, content: $0.content)
                })
        }

        // ChildViewProvider (TupleView with multiple children). The *view*
        // provider, not the buffer-only ChildInfoProvider: each row's original
        // view is needed to peel off its `.badge(_:)`, and a `ForEach` spliced
        // between static rows only flattens on this path.
        if let provider = content as? ChildViewProvider {
            return .eager(extractFromChildren(provider: provider, context: context))
        }

        // Fallback: render as a single content row, carrying its badge
        // (`List { Text("Notifications").badge(5) }`).
        let badge = extractBadgeValue(from: content)
        // One row IS the whole list, so a ramp spanning the list spans this row
        // and nothing else — its own measured height is the extent.
        var rowRenderContext = context
        if context.gradientFrame != nil {
            let measured = measureChild(
                content, proposal: ProposedSize(width: context.availableWidth, height: nil),
                context: context)
            rowRenderContext = context.placingGradientChild(
                context.gradientContentFrame(
                    width: context.availableWidth, height: max(1, measured.height)),
                x: 0, y: 0)
        }
        let buffer = TUIkit.renderToBuffer(content, context: rowRenderContext)
        // An `EmptyView` is not a row. This used to fall out of the id cast
        // failing, which meant it depended on the SELECTION type: a list of
        // `EmptyView` was empty with a `String?` selection and a blank row
        // with an `Int?` one.
        guard !buffer.lines.isEmpty else { return .eager([]) }
        // A static row's only possible id is its index, which cannot be
        // expressed when the selection is a String, a UUID or a Set of
        // either. It is still a row: it draws, it just cannot be selected —
        // SwiftUI's own treatment of a row carrying no `tag(_:)`. This used
        // to return NO rows, so such a list rendered as the empty placeholder.
        return .eager([
            SelectableListRow(
                type: (0 as? SelectionValue).map { .content(id: $0) } ?? .unselectable,
                content: LazyListRowContent(buffer: buffer, badge: badge))
        ])
    }

    /// Extracts one row per flattened child (TupleView content), each carrying
    /// the badge of its `.badge(_:)` wrapper, if any.
    private func extractFromChildren(
        provider: ChildViewProvider,
        context: RenderContext
    ) -> [SelectableListRow<SelectionValue>] {
        var result: [SelectableListRow<SelectionValue>] = []
        // These rows render HERE rather than through a deferred box, so this is
        // where a ramp spanning the list has to place them. There are only ever
        // a handful and none is deferred, so unlike the windowed path this can
        // measure them all and place every row exactly — no pitch, no estimate.
        // Measured only when a ramp is in force.
        let children = provider.childViews(context: context).filter { !$0.isSpacer }
        var gradientFrame: GradientFrame?
        var gradientTops: [Int] = []
        if context.gradientFrame != nil {
            var top = 0
            for child in children {
                gradientTops.append(top)
                top += child.measure(
                    proposal: ProposedSize(width: context.availableWidth, height: nil),
                    context: context
                ).height
            }
            gradientFrame = context.gradientContentFrame(
                width: context.availableWidth, height: max(1, top))
        }

        for child in children {
            // See `extractRows`: an index-identified row is unselectable rather
            // than absent when the selection type cannot hold an index. The
            // count advances only over rows that took an id, so the ids stay
            // 0, 1, 2 … for the Int case they exist for.
            let type: ListRowType<SelectionValue> =
                (result.count as? SelectionValue).map { .content(id: $0) } ?? .unselectable
            let badge = extractBadgeValue(from: child.wrappedView)
            let buffer = child.render(
                width: context.availableWidth, height: context.availableHeight,
                context: context.placingGradientChild(
                    gradientFrame, x: 0,
                    y: result.count < gradientTops.count ? gradientTops[result.count] : 0))
            result.append(SelectableListRow(type: type, content: LazyListRowContent(buffer: buffer, badge: badge)))
        }

        return result
    }

    /// Extracts typed rows from a Section (header + content + footer).
    private func extractSectionRows(
        from section: SectionRowExtractor,
        context: RenderContext
    ) -> [SelectableListRow<SelectionValue>] {
        var rows: [SelectableListRow<SelectionValue>] = []
        let info = section.extractSectionInfo(context: context)

        // Header (non-selectable)
        if let headerBuffer = info.headerBuffer {
            rows.append(SelectableListRow(type: .header, buffer: headerBuffer))
        }

        // Content rows (selectable)
        if let extractor = section as? ListRowExtractor {
            let contentRows: [ListRow<SelectionValue>] = extractor.extractListRows(context: context)
            for row in contentRows {
                // Thread the lazy box through — don't force `.buffer` / `.badge`.
                rows.append(
                    SelectableListRow(
                        type: row.id.map { .content(id: $0) } ?? .unselectable,
                        content: row.content))
            }
        } else {
            // Fallback: render content as single row (if Section content is not ForEach)
            // Use the content buffer from SectionInfo
            // Note: This row is still selectable but uses index-based ID
            if !info.contentBuffer.lines.isEmpty {
                rows.append(
                    SelectableListRow(
                        type: (0 as? SelectionValue).map { .content(id: $0) } ?? .unselectable,
                        buffer: info.contentBuffer))
            }
        }

        // Footer (non-selectable)
        if let footerBuffer = info.footerBuffer {
            rows.append(SelectableListRow(type: .footer, buffer: footerBuffer))
        }

        return rows
    }

    // MARK: - Visible Row Calculation

    /// Determines which rows are visible, reserving a line for each
    /// scroll indicator that is actually present at the current
    /// offset.
    ///
    /// The reservation is dynamic: at the top or bottom only one
    /// indicator shows, so one more row fits than in the middle
    /// (where both show). This is what keeps the rows-plus-indicators
    /// height equal to ``contentHeight`` everywhere — eliminating the
    /// wasted blank line at the ends that used to bump the "N more
    /// below" indicator one row too high.
    /// The width the rows are laid out at. The List is greedy on width (SwiftUI
    /// parity): fill the available interior, growing past it only when a row is
    /// itself wider than the space offered. Sizing to the widest *visible* row
    /// (the old non-explicit path) made the List's box jump width as you
    /// scrolled past wider/narrower rows; filling keeps it stable.
    ///
    /// `.fixedSize(horizontal:)` instead hugs content: the widest of ALL rows
    /// (not just the visible ones — that's what keeps it stable), so the box is
    /// content-sized and constant.
    private func rowWidth(
        source: RowSource<SelectionValue>,
        visibleRows: [(index: Int, row: SelectableListRow<SelectionValue>)],
        style: any ListStyle,
        context: RenderContext
    ) -> Int {
        if context.environment.fixedSizeWidth {
            // The same question `allRowsContentWidth` answers on the measure
            // side, from the same memo; a badge's cells are outside the row
            // buffer, which is what this width sizes.
            return widestRowWidth(source: source, context: context)
        }
        // Fill the interior: full available width when borderless (`.plain`),
        // minus the two border columns when bordered.
        let maxRowWidth = visibleRows.map { $0.row.buffer.width }.max() ?? 0
        let borderOverhead = style.showsBorder ? 2 : 0
        return max(maxRowWidth, context.availableWidth - borderOverhead)
    }

    // MARK: - Row Rendering

    /// What this frame knows about one row that changes how it is drawn.
    ///
    /// Three booleans travelling together rather than three parameters: they
    /// are all "the state of THIS row right now", they are all read from the
    /// handler at the same moment, and both assembly paths have to ask for the
    /// same three or drift.
    private struct RowDrawState {
        let isFocused: Bool
        let isSelected: Bool
        /// The row's picture is still walking home to it, so it keeps its space
        /// and draws nothing in it — see ``ItemListHandler/returningRows``.
        let isReturningHome: Bool
    }

    private func renderRow(
        row: SelectableListRow<SelectionValue>,
        state: RowDrawState,
        rowWidth: Int,
        sectionContentIndex: Int,
        style: any ListStyle,
        context: RenderContext,
        palette: any Palette
    ) -> RenderedRow {
        // A row that names its own background (the reorder slot) keeps it; the
        // rest ask their type and state.
        let background: RowBackground
        if case .none = row.backgroundOverride {
            background = rowBackground(
                rowType: row.type,
                isFocused: state.isFocused,
                isSelected: state.isSelected,
                sectionContentIndex: sectionContentIndex,
                style: style,
                context: context,
                palette: palette)
        } else {
            background = row.backgroundOverride
        }

        // The mark for the one-cell gutter every row already reserves — the
        // same answer the `Table` puts in its own, from the same place, because
        // an empty gutter beside a filled one was the whole of the
        // inconsistency. On the FIRST line only, as the badge is: a tall row is
        // one entry in the list, and one entry earns one mark.
        let indicator =
            row.isSelectable
            ? RowSelectionIndicator.forRow(
                isFocused: state.isFocused, isSelected: state.isSelected,
                context: context, palette: palette)
            : RowSelectionIndicator(glyph: " ", color: palette.foregroundTertiary)
        let gutter =
            indicator.isBlank
            ? " " : ANSIRenderer.colorize(indicator.glyph, foreground: indicator.color)

        // Check for badge on the row (only for content rows, on first line only)
        let badge = row.badge
        let shouldRenderBadge = badge != nil && !badge!.isHidden && row.isSelectable

        /// The row's lines over a given background — the ONE description of what
        /// this row looks like, called once for the frame on screen and once per
        /// point of a pulse for the runs that replay it.
        func lines(over backgroundColor: Color?) -> [String] {
            row.buffer.lines.enumerated().map { lineIndex, line in
                if shouldRenderBadge && lineIndex == 0 {
                    return renderLineWithBadge(
                        line: line,
                        badge: badge!,
                        rowWidth: rowWidth,
                        backgroundColor: backgroundColor,
                        palette: palette,
                        gutter: gutter
                    )
                } else {
                    return renderPlainLine(
                        line: line,
                        rowWidth: rowWidth,
                        backgroundColor: backgroundColor,
                        gutter: lineIndex == 0 ? gutter : " "
                    )
                }
            }
        }

        /// The row content's own runs, moved past the leading pad this renderer
        /// adds. Dropped where they cannot be trusted:
        ///
        /// - **Past the row's width.** A run that would extend beyond the cells
        ///   the row occupies paints over the scrollbar or the border.
        /// - **On a badged line**, whose content is truncated to make room —
        ///   after which a column no longer means what the child said it meant.
        ///
        /// A dropped run is not a frozen animation: nothing yet relies on this
        /// path to move, and everything that animates inside a row still asks
        /// the run loop to re-render it. It is a missed saving, not a bug.
        var childRuns: [RowRun] = []
        for run in row.buffer.animatedCells where run.offsetY < row.buffer.lines.count {
            // `isAnimating` for the same reason `RenderLoop` filters on it
            // before keeping a frame's runs: a still run holds the animation
            // clock open forever to repaint a picture that cannot change.
            guard run.isAnimating, !(shouldRenderBadge && run.offsetY == 0),
                run.width > 0, 1 + run.offsetX + run.width <= rowWidth
            else { continue }
            childRuns.append(
                RowRun(
                    y: run.offsetY, x: 1 + run.offsetX, width: run.width, frames: run.frames,
                    frameDuration: run.frameDuration, clock: run.clock))
        }

        // A row whose picture is still walking back to it keeps its space and
        // draws nothing in it — see ``ItemListHandler/returningRows``. Blanked
        // from the FINISHED lines rather than short-circuited above, so the
        // blank is exactly as wide as the row it stands in for, gutter and
        // badge column included, whatever this renderer did to get there.
        // Nothing animates: a run would paint over the blank on its next tick.
        guard !state.isReturningHome else {
            return RenderedRow(
                lines: lines(over: nil).map { String(repeating: " ", count: $0.strippedLength) },
                pulseFrames: nil, childRuns: [])
        }
        guard case .pulsing(let cycle, let dim, let bright) = background, cycle.isAnimating else {
            return RenderedRow(
                lines: lines(over: background.colorNow), pulseFrames: nil, childRuns: childRuns)
        }
        // A breathing row repaints its WHOLE line every tick, so a narrower run
        // on the same line would be overwritten by it — two animations claiming
        // one cell, and the wider one wins. The row's own runs are dropped for
        // the duration, which is the cursor row only.
        //
        // And then something has to move them, because a producer that left a
        // run behind is no longer asking to be re-rendered — that is the whole
        // point of leaving one. So the list takes over the asking on the
        // dropped run's behalf, at the clock the run would have advanced on. A
        // spinner on the cursor row therefore costs exactly what every spinner
        // used to cost, and only while the cursor is on its row.
        if !childRuns.isEmpty, !context.isMeasuring {
            context.requestAnimation(
                token: "list-dropped-run-\(context.identity.path)",
                frequency: 1.0 / AnimationClock.cursor.tickInterval)
        }
        // Transposed to line-major, because that is how the runs are asked for:
        // one run per LINE, carrying that line at every point of the cycle.
        let perStep = cycle.colors(dim: dim, bright: bright).map { lines(over: $0) }
        let step = cycle.step % max(1, perStep.count)
        return RenderedRow(
            lines: perStep[step],
            pulseFrames: (0..<row.buffer.lines.count).map { line in perStep.map { $0[line] } })
    }

    /// A row's rendered lines, plus — when its background breathes — every frame
    /// of each line, ready to become an ``AnimatedCellRun`` once the caller
    /// knows where on screen the line ended up.
    private struct RenderedRow {
        let lines: [String]
        /// `pulseFrames[line][step]`, or `nil` for a row that does not animate.
        let pulseFrames: [[String]]?
        /// Runs the row's OWN content left behind — a spinner, a blinking
        /// cursor, a pulsing badge — with `line` an index into ``lines`` and `x`
        /// already past the row's leading pad. Empty for the overwhelming
        /// majority of rows.
        var childRuns: [RowRun] = []
    }

    /// One animated run positioned within the lines being assembled: `y` is the
    /// index of the line it sits on, and everything else is what the run will
    /// carry once that line's final position is known.
    ///
    /// Both kinds of run travel as this — a whole-line pulse (`x == 0`, `width`
    /// the row's width) and a row's own narrow run — because every clip, the
    /// reorder overrun and the overscroll slide all key on `y` alone. One
    /// pipeline rather than two that have to be kept in step.
    private struct RowRun {
        var y: Int
        var x: Int
        var width: Int
        var frames: [String]
        /// The rate the run asked for, and the clock it asked on.
        ///
        /// Carried rather than assumed. Rebuilding a child's run with the
        /// defaults silently retimed it: a `.dots` spinner asks for 0.110 s a
        /// frame and got the clock's own 0.05 s, so a spinner inside a List ran
        /// 2.2x too fast — and looked, in a screenshot, exactly right.
        var frameDuration: Double
        var clock: AnimationClock

        /// The same run on line `y`. Every clip and slide moves runs vertically
        /// and nothing else, so this is the only motion any of them needs.
        func moved(to y: Int) -> Self {
            var copy = self
            copy.y = y
            return copy
        }
    }

    /// The background a row shows for its type and visual state — a fixed
    /// colour, or (for the cursor row of a focused list) a whole pulse.
    private func rowBackground(
        rowType: ListRowType<SelectionValue>,
        isFocused: Bool,
        isSelected: Bool,
        sectionContentIndex: Int,
        style: any ListStyle,
        context: RenderContext,
        palette: any Palette
    ) -> RowBackground {
        switch rowType {
        case .header, .footer, .unselectable:
            return .none

        case .content:
            if isFocused && isSelected {
                // The cursor row on a focused list breathes. As a CYCLE, not a
                // live phase: the phase read marks the frame as having consulted
                // the clock, so the whole page was re-rendered on every tick to
                // recolour one row. The caller turns the cycle into
                // ``AnimatedCellRun``s over the row's own lines.
                return .focusedSelection(in: context, palette: palette)
            } else if isFocused {
                return .fixed(palette.focusBackground)
            } else if isSelected {
                // Selected row while the list itself doesn't have
                // focus. Controlled by the
                // `unfocusedSelectionVisibility` environment value
                // (default `.automatic` → visible). Setting
                // `.hidden` suppresses the desaturated highlight
                // and falls through to the alternating-row /
                // no-background path — useful for transient lists
                // (pop-up pickers, quick-pick palettes) where the
                // ambient highlight is more noise than signal.
                if context.environment.unfocusedSelectionVisibility == .hidden {
                    return .init(alternatingBackgroundIfAny(
                        sectionContentIndex: sectionContentIndex,
                        style: style,
                        palette: palette))
                }
                return .fixed(
                    palette.accent.opacity(ViewConstants.selectedBackground, over: palette.background))
            } else {
                return .init(alternatingBackgroundIfAny(
                    sectionContentIndex: sectionContentIndex,
                    style: style,
                    palette: palette))
            }
        }
    }

    /// Returns the alternating-row tint when this row qualifies
    /// for it, or nil otherwise. Extracted so the unfocused-
    /// selection-hidden path and the unselected-row path can both
    /// fall back to it without duplicating the condition.
    private func alternatingBackgroundIfAny(
        sectionContentIndex: Int,
        style: any ListStyle,
        palette: any Palette
    ) -> Color? {
        if style.alternatingRowColors && sectionContentIndex.isMultiple(of: 2) {
            return palette.accent.opacity(ViewConstants.alternatingRowBackground, over: palette.background)
        }
        return nil
    }

    /// Renders a line with a right-aligned badge.
    /// Layout: [1 pad][content][fill padding][badge][1 pad]
    private func renderLineWithBadge(
        line: String,
        badge: BadgeValue,
        rowWidth: Int,
        backgroundColor: Color?,
        palette: any Palette,
        gutter: String
    ) -> String {
        let badgeText = badge.displayText
        let styledBadge = ANSIRenderer.colorize(badgeText, foreground: palette.foregroundTertiary)
        let badgeWidth = badgeText.strippedLength

        // When the row is too narrow for both, the CONTENT truncates and the
        // badge survives (as in SwiftUI, where the label truncates first) —
        // overflowing instead put the badge in the cells the container
        // clips, silently hiding it.
        let contentBudget = rowWidth - badgeWidth - 3
        let fittedLine =
            line.strippedLength > contentBudget
            ? line.truncatedToWidth(max(1, contentBudget)) : line

        let usedWidth = 1 + fittedLine.strippedLength + badgeWidth + 1
        let fillPadding = max(1, rowWidth - usedWidth)
        let paddedLine =
            gutter + fittedLine + String(repeating: " ", count: fillPadding) + styledBadge + " "

        return terminatedBackground(paddedLine, backgroundColor)
    }

    /// Renders a plain line without badge.
    /// Layout: [1 pad][content][right padding]
    private func renderPlainLine(
        line: String,
        rowWidth: Int,
        backgroundColor: Color?,
        gutter: String
    ) -> String {
        let lineLength = line.strippedLength
        let usedWidth = 1 + lineLength
        let rightPadding = max(1, rowWidth - usedWidth)
        let paddedLine = gutter + line + String(repeating: " ", count: rightPadding)

        return terminatedBackground(paddedLine, backgroundColor)
    }

    /// Applies `backgroundColor` as a persistent row background and TERMINATES
    /// it with a reset at the row's right edge.
    ///
    /// The reset matters: `withPersistentBackground` leaves the background
    /// active at the end of the string, and a borderless list has no right
    /// border to cap it — so a selected row's highlight bled rightward into
    /// whatever was composited beside the list (in the styles demo, across
    /// the whole screen / into the neighbouring list's border). A bordered
    /// list's own right border happened to reset it, masking the bug there.
    /// Matches the self-contained pattern `BackgroundModifier` already uses.
    private func terminatedBackground(_ line: String, _ backgroundColor: Color?) -> String {
        guard backgroundColor != nil else { return line }
        return line.withPersistentBackground(backgroundColor) + ANSIRenderer.reset
    }
}

// MARK: - List Content View

/// Simple view that renders pre-computed lines.
struct _ListContentView: View, Renderable {
    let lines: [String]

    /// The breathing rows' cells, already positioned among `lines` — the
    /// container shifts them past its border along with the lines themselves.
    var runs: [AnimatedCellRun] = []

    var body: Never {
        fatalError("_ListContentView renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(lines: lines)
        // A measure pass draws nothing, so a run left on it would describe
        // cells that were never on screen — and keep the clock alive from a
        // pass that produced no frame.
        if !context.isMeasuring { buffer.animatedCells = runs }
        return buffer
    }
}

// MARK: - Disabled state

extension _ListCore {
    /// Whether this list is disabled, counting an ancestor's `.disabled(true)`.
    ///
    /// `List` has a concrete `disabled(_:) -> Self` overload, which wins
    /// overload resolution over `View.disabled(_:)` — so `List { … }
    /// .disabled(true)` sets ``isDisabled`` and never builds a
    /// `DisabledModifier`. That is fine on its own; what it hid is the OTHER
    /// direction. `VStack { List { … } }.disabled(true)` does build one, and
    /// nothing here read the `\.isEnabled` it publishes, so the list stayed
    /// focusable, scrollable and clickable inside a disabled subtree.
    ///
    /// SwiftUI: "The higher views in a view hierarchy can override the value
    /// you set on this view." Every other control in the framework already
    /// combines the two this way — `Button`, `TextField`, `_ToggleCore`,
    /// `Slider`, `Stepper`, `RadioButton`, `DatePicker`, `SecureField`,
    /// `TextEditor` and `_PickerMenuCore` all read
    /// `self.isDisabled || !context.environment.isEnabled`.
    func isDisabled(in context: RenderContext) -> Bool {
        isDisabled || !context.environment.isEnabled
    }
}
