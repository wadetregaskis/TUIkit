//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitView.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - NavigationSplitView

/// A view that presents views in two or three columns, where selections in
/// leading columns control presentations in subsequent columns.
///
/// You create a navigation split view with two or three columns, and typically
/// use it as the root view in a ``Scene``. People choose one or more items in
/// a leading column to display details about those items in subsequent columns.
///
/// ## Two-Column Layout
///
/// To create a two-column navigation split view, use the
/// ``init(sidebar:detail:)`` initializer:
///
/// ```swift
/// @State private var selectedID: String?
///
/// var body: some View {
///     NavigationSplitView {
///         List("Items", selection: $selectedID) {
///             ForEach(items) { item in
///                 Text(item.name)
///             }
///         }
///     } detail: {
///         if let id = selectedID {
///             DetailView(itemID: id)
///         } else {
///             Text("Select an item")
///         }
///     }
/// }
/// ```
///
/// ## Three-Column Layout
///
/// To create a three-column view, use the ``init(sidebar:content:detail:)``
/// initializer:
///
/// ```swift
/// @State private var categoryID: String?
/// @State private var itemID: String?
///
/// var body: some View {
///     NavigationSplitView {
///         List("Categories", selection: $categoryID) { ... }
///     } content: {
///         List("Items", selection: $itemID) { ... }
///     } detail: {
///         DetailView(itemID: itemID)
///     }
/// }
/// ```
///
/// ## Column Visibility
///
/// You can programmatically control column visibility using a
/// ``NavigationSplitViewVisibility`` binding:
///
/// ```swift
/// @State private var visibility = NavigationSplitViewVisibility.all
///
/// NavigationSplitView(columnVisibility: $visibility) {
///     SidebarView()
/// } detail: {
///     DetailView()
/// }
/// ```
///
/// The user can hide and show columns too, and the split view writes what they
/// chose through the binding (or keeps it itself when there is none). The
/// leftmost divider's middle grip dot is a ◀: a still click on it, or Return or
/// Space with the divider focused, hides the column to its left — `.all` to
/// `.detailOnly` with two columns, `.all` to `.doubleColumn` to `.detailOnly`
/// with three. While a leading column is hidden, a one-cell edge column at the
/// left shows ▶, which brings back the nearest hidden column the same way, one
/// step at a time. The edge column is first in the Tab order. After either, the
/// keyboard moves to the handle that undoes it, so Return, Return goes there
/// and back. A split that cannot resize (``View/navigationSplitViewResizable(_:)``)
/// keeps the ◀ alone on its leftmost divider. `.toolbar(removing: .sidebarToggle)`
/// (``View/toolbar(removing:)``) takes both handles away.
///
/// ## Focus Navigation
///
/// Each column registers as a separate focus section. Use Tab/Shift+Tab to
/// move between columns, and Up/Down arrows to navigate within each column.
/// Hiding the column that holds the keyboard, from code or from the handles,
/// moves the keyboard to the leftmost column still showing, rather than out of
/// the split.
///
/// ## TUI-Specific Behavior
///
/// - Columns are separated by a vertical line character (`│`).
/// - The split view renders within the content area between AppHeader and StatusBar.
/// - Column widths are determined by the ``NavigationSplitViewStyle``.
/// - No automatic collapsing to stack (terminal width is typically sufficient).
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
    /// The sidebar column content.
    let sidebar: Sidebar

    /// The content column (only used in three-column layouts).
    let content: Content

    /// The detail column content.
    let detail: Detail

    /// Whether this is a three-column layout.
    let isThreeColumn: Bool

    /// Binding to column visibility (optional).
    let columnVisibility: Binding<NavigationSplitViewVisibility>?

    public var body: some View {
        _NavigationSplitViewCore(
            sidebar: sidebar,
            content: content,
            detail: detail,
            isThreeColumn: isThreeColumn,
            columnVisibility: columnVisibility
        )
    }
}

// MARK: - Two-Column Initializers

extension NavigationSplitView where Content == EmptyView {
    /// Creates a two-column navigation split view.
    ///
    /// - Parameters:
    ///   - sidebar: The view to show in the leading column.
    ///   - detail: The view to show in the detail area.
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = EmptyView()
        self.detail = detail()
        self.isThreeColumn = false
        self.columnVisibility = nil
    }

    /// Creates a two-column navigation split view with programmatic visibility control.
    ///
    /// - Parameters:
    ///   - columnVisibility: A binding to state that controls the visibility of the sidebar.
    ///   - sidebar: The view to show in the leading column.
    ///   - detail: The view to show in the detail area.
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = EmptyView()
        self.detail = detail()
        self.isThreeColumn = false
        self.columnVisibility = columnVisibility
    }
}

// MARK: - Three-Column Initializers

extension NavigationSplitView {
    /// Creates a three-column navigation split view.
    ///
    /// - Parameters:
    ///   - sidebar: The view to show in the leading column.
    ///   - content: The view to show in the middle column.
    ///   - detail: The view to show in the detail area.
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.isThreeColumn = true
        self.columnVisibility = nil
    }

    /// Creates a three-column navigation split view with programmatic visibility control.
    ///
    /// - Parameters:
    ///   - columnVisibility: A binding to state that controls the visibility of leading columns.
    ///   - sidebar: The view to show in the leading column.
    ///   - content: The view to show in the middle column.
    ///   - detail: The view to show in the detail area.
    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.isThreeColumn = true
        self.columnVisibility = columnVisibility
    }
}

// MARK: - Internal Core

/// Internal view that handles the actual rendering of NavigationSplitView.
///
/// Internal rather than `private` (the usual spelling for a `_*Core`) because
/// half of it lives in `NavigationSplitViewWidths.swift`, and a file-private
/// type cannot be extended from another file — the same reason
/// ``_ContainerViewCore`` is internal.
struct _NavigationSplitViewCore<Sidebar: View, Content: View, Detail: View>: View, Renderable, Layoutable {
    let sidebar: Sidebar
    let content: Content
    let detail: Detail
    let isThreeColumn: Bool
    let columnVisibility: Binding<NavigationSplitViewVisibility>?

    /// The minimum width for any column in characters.
    let minimumColumnWidth = 10

    /// The separator between columns (single space for TUI).
    /// TUI-specific: We use a space instead of a line to avoid double borders
    /// when columns contain bordered components like List.
    private let separator = " "

    var body: Never {
        fatalError("_NavigationSplitViewCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let minWidth = minimumColumnWidth * (isThreeColumn ? 3 : 2)
        return ViewSize(width: minWidth, height: 1, isWidthFlexible: true, isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let style = context.environment.navigationSplitViewStyle
        let toggleState = resolveToggleState(context: context)
        let visibility = resolveVisibility(toggleState: toggleState)

        // Calculate visible columns based on visibility
        let visibleColumns = calculateVisibleColumns(visibility: visibility)
        guard !visibleColumns.isEmpty else {
            return FrameBuffer()
        }
        let focusManager = context.environment.focusManager

        // A hidden leading column leaves a ▶ edge column at the left, registered
        // before the columns; they share what is left of the width.
        let (edge, columnsContext) = layOutEdge(
            visibleColumns: visibleColumns, context: context,
            focusManager: focusManager, toggleState: toggleState)

        // Resizable columns (the default) persist a user-chosen width per
        // non-trailing column and expose a draggable / focusable divider. This
        // works under a size-to-fit style too: the columns track their content
        // until the user drags/keys one, which pins it (``isUserSet``) so it
        // holds that width while the rest keep fitting —
        // `.navigationSplitViewColumnWidthReset(_:)` releases the pins.
        let resizable =
            context.environment.navigationSplitViewResizable
            && context.stateStorage != nil
        let widths = resizable ? resolvePersistedWidths(context: context) : nil

        // Calculate column widths — content-fit-from-left, or proportional,
        // honouring what each column asked for (NavigationSplitViewWidths.swift).
        // `self.` because the local shadows the method's own name.
        let columnWidths = self.columnWidths(
            visibleColumns: visibleColumns,
            style: style,
            context: columnsContext,
            widths: widths,
            writeBack: resizable && !context.isMeasuring
        )

        // Render each visible column
        var buffers: [FrameBuffer] = []
        // One entry per gap between columns; drives the divider's look and its
        // drag hit-test region (see `combineColumns`).
        var dividerInfos: [DividerRenderInfo] = []

        for (index, column) in visibleColumns.enumerated() {
            let columnWidth = columnWidths[index]
            let columnContext = context.withAvailableSize(width: columnWidth, height: context.availableHeight)

            // Register focus section for this column (skip during measurement)
            let sectionID = focusSectionID(for: column, context: context)
            if !columnContext.isMeasuring {
                focusManager?.registerSection(id: sectionID)
            }

            // Create a context with the active focus section
            var sectionContext = columnContext
            sectionContext.environment.activeFocusSectionID = sectionID

            // If this section is active, hand its borders the breathing ●
            // (never active during measurement).
            sectionContext.environment.focusIndicator = AnimatedColor.activeSection(
                !columnContext.isMeasuring && (focusManager?.isActiveSection(sectionID) ?? false),
                in: context.environment)

            var buffer = renderColumn(column, context: sectionContext, toggleState: toggleState)

            // Click anywhere on a column activates that column's focus
            // section. Registered last (= innermost), so any child
            // controls' own hit-test regions still take precedence; this
            // is the fall-through behaviour for clicking on the column's
            // empty space, separators, or non-interactive content.
            if !columnContext.isMeasuring,
                let mouseDispatcher = columnContext.environment.mouseEventDispatcher
            {
                let captureManager = focusManager
                let captureSectionID = sectionID
                let columnHandlerID = mouseDispatcher.register { event in
                    guard event.button == .left else { return false }
                    switch event.phase {
                    case .pressed: return true
                    case .released:
                        captureManager?.activateSection(id: captureSectionID)
                        return true
                    default: return false
                    }
                }
                // Place the region at the very back of the list so
                // children win the hit-test.
                buffer.hitTestRegions.insert(
                    HitTestRegion(
                        offsetX: 0, offsetY: 0,
                        width: buffer.width, height: buffer.height,
                        handlerID: columnHandlerID
                    ), at: 0
                )
            }
            buffers.append(buffer)

            // Wire the divider that follows this column (all but the last).
            // Registering its focus section here — right after this column's
            // section and before the next column's — interleaves it into the
            // Tab order (col0, divider0, col1, divider1, …) so Tab reaches the
            // handle, where the arrow keys resize it.
            if index < visibleColumns.count - 1 {
                dividerInfos.append(
                    wireDivider(
                        column: column,
                        togglesColumn: index == 0 && showsToggle(context: context, toggleState: toggleState),
                        toggleState: toggleState,
                        resizable: resizable,
                        widths: widths,
                        currentWidth: columnWidth,
                        context: context,
                        focusManager: focusManager
                    )
                )
            }
        }

        // The columns are one row, for the arrow keys: Left and Right move between
        // them. The dividers are not members — Tab and the mouse reach those.
        if !context.isMeasuring {
            focusManager?.registerSectionGroup(
                visibleColumns.map { focusSectionID(for: $0, context: context) },
                dividers: dividerInfos.map(\.focusID))
            // Every section this split owns is registered now, so a handle
            // pressed last frame can hand the keyboard to the one that undoes
            // it, and a column hidden with the keyboard in it can hand the
            // keyboard to the leftmost visible column.
            settleFocus(
                toggleState: toggleState, visibleColumns: visibleColumns,
                context: context, focusManager: focusManager)
        }

        // Ask for the cycle ONLY when a divider is focused/dragged or hovered,
        // so the demand-driven loop keeps the pulse animating just for those
        // cases (a static split with no active/hovered divider stays idle) —
        // and as a CYCLE rather than a live phase, so the divider's cells are
        // left as runs for the loop to advance instead of the whole split
        // re-rendering on every tick.
        let anyDividerPulsing = (dividerInfos + [edge?.info].compactMap { $0 })
            .contains { $0.isActive || $0.isHovered }
        let cycle = context.environment.selectionEmphasis.cycle(anyDividerPulsing)

        // Combine buffers horizontally, inserting the (possibly resizable)
        // dividers between them.
        let columns = combineColumns(
            buffers: buffers,
            columnWidths: columnWidths,
            dividerInfos: dividerInfos,
            resizable: resizable,
            palette: context.environment.palette,
            cycle: cycle,
            availableHeight: context.availableHeight
        )
        guard let edge else { return columns }
        return prependEdgeColumn(
            edge, to: columns, palette: context.environment.palette, cycle: cycle)
    }
}

// MARK: - Private Helpers

/// ``_NavigationSplitViewCore``'s `StateStorage` slots at its own identity. Its
/// columns render at child identities (`withChildIdentity`), so no caller
/// content shares these and they keep the leaf range `0...`. At file scope
/// because a generic type cannot hold static stored properties, and internal
/// because the sidebar toggle's half lives in NavigationSplitViewToggle.swift.
///
/// The divider handlers are stored per COLUMN, like the widths they write.
/// Stored by the divider's position on screen, the first divider kept the
/// handler it was built with in `.all`, which resizes the sidebar, and went on
/// resizing the hidden sidebar under `.doubleColumn`.
enum SplitViewStateIndex {
    /// The shared ``SplitViewWidths``.
    static let widths = 0
    /// The handler of the divider after the sidebar.
    static let sidebarDivider = 1
    /// The handler of the divider after the content column.
    static let contentDivider = 2
    /// The sidebar toggle's ``SplitViewToggleState``.
    static let toggle = 3
    /// The handler of the ▶ edge column shown while a leading column is hidden.
    static let edge = 4

    /// The slot of the divider that follows `column`, or `nil` for the detail
    /// column, which is always trailing and has no divider after it.
    static func divider(after column: NavigationSplitViewColumn) -> Int? {
        switch column {
        case .sidebar: sidebarDivider
        case .content: contentDivider
        default: nil
        }
    }
}

extension _NavigationSplitViewCore {
    /// Resolves the effective visibility from the binding, else from what the
    /// split's own handles last wrote (see ``SplitViewToggleState/visibility``),
    /// else `.all`.
    fileprivate func resolveVisibility(toggleState: SplitViewToggleState?) -> NavigationSplitViewVisibility {
        let value = columnVisibility?.wrappedValue ?? toggleState?.visibility ?? .all
        // Resolve .automatic to .all
        return value == .automatic ? .all : value
    }

    /// Calculates which columns should be visible based on visibility setting.
    fileprivate func calculateVisibleColumns(visibility: NavigationSplitViewVisibility) -> [NavigationSplitViewColumn] {
        if isThreeColumn {
            switch visibility {
            case .all, .automatic:
                return [.sidebar, .content, .detail]
            case .doubleColumn:
                return [.content, .detail]
            case .detailOnly:
                return [.detail]
            default:
                return [.sidebar, .content, .detail]
            }
        } else {
            // Two-column layout
            switch visibility {
            case .all, .automatic, .doubleColumn:
                return [.sidebar, .detail]
            case .detailOnly:
                return [.detail]
            default:
                return [.sidebar, .detail]
            }
        }
    }

    /// The persisted per-column width store for a resizable split, having marked
    /// its identity active (so the box and divider handlers survive the run
    /// loop's per-frame StateStorage GC — the columns mark their own child
    /// identities, not the parent's) and applied any width-reset token on a
    /// render pass (a changed `.navigationSplitViewColumnWidthReset(_:)` releases
    /// the user-pinned widths; a measure pass never mutates persisted state).
    fileprivate func resolvePersistedWidths(context: RenderContext) -> SplitViewWidths {
        let stateStorage = context.stateStorage!
        let widths = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: SplitViewStateIndex.widths),
            default: SplitViewWidths()
        ).value
        stateStorage.markActive(context.identity)
        if !context.isMeasuring {
            widths.applyResetToken(context.environment.navigationSplitViewColumnWidthResetToken)
        }
        return widths
    }

    /// Returns the focus section ID for a column.
    ///
    /// Namespaced by this split's identity, like its dividers' sections. Named
    /// by the column alone, two splits in one frame (side by side, or one in
    /// another's detail column) shared each column's section: Down walked from
    /// one split's sidebar into the other's, and Right from the second split's
    /// sidebar landed in the first split's detail column.
    func focusSectionID(
        for column: NavigationSplitViewColumn, context: RenderContext
    ) -> String {
        "nav-split-\(sectionName(of: column))-\(context.identity.path)"
    }

    /// The focus section ID of the divider that follows `column` — see
    /// `wireDivider` for why it is named by the column.
    func dividerSectionID(after column: NavigationSplitViewColumn, context: RenderContext) -> String {
        "nav-split-divider-\(sectionName(of: column))-\(context.identity.path)"
    }

    /// The column's name in the ids of the sections that belong to it.
    func sectionName(of column: NavigationSplitViewColumn) -> String {
        switch column {
        case .sidebar: "sidebar"
        case .content: "content"
        case .detail: "detail"
        default: "unknown"
        }
    }

    /// Renders a single column, noting whether it removed the toggle with
    /// `.toolbar(removing:)` (see ``SplitViewToggleState/removedByColumn``).
    fileprivate func renderColumn(
        _ column: NavigationSplitViewColumn, context: RenderContext, toggleState: SplitViewToggleState?
    ) -> FrameBuffer {
        guard let toggleState, !context.isMeasuring, let preferences = context.environment.preferenceStorage
        else { return renderColumnContent(column, context: context) }
        preferences.push()
        let buffer = renderColumnContent(column, context: context)
        recordToggleRemoval(of: column, from: preferences.pop(), toggleState: toggleState)
        return buffer
    }

    /// Renders a single column's content.
    fileprivate func renderColumnContent(_ column: NavigationSplitViewColumn, context: RenderContext) -> FrameBuffer {
        switch column {
        case .sidebar:
            return TUIkit.renderToBuffer(sidebar, context: context.withChildIdentity(type: type(of: sidebar)))
        case .content:
            return TUIkit.renderToBuffer(content, context: context.withChildIdentity(type: type(of: content)))
        case .detail:
            return TUIkit.renderToBuffer(detail, context: context.withChildIdentity(type: type(of: detail)))
        default:
            return FrameBuffer()
        }
    }

    /// Combines column buffers horizontally, inserting a one-column divider
    /// between each pair. The divider carries the resize handle and (when
    /// resizable) a full-height drag hit-test region.
    fileprivate func combineColumns(
        buffers: [FrameBuffer],
        columnWidths: [Int],
        dividerInfos: [DividerRenderInfo],
        resizable: Bool,
        palette: any Palette,
        cycle: SelectionEmphasisCycle,
        availableHeight: Int
    ) -> FrameBuffer {
        guard !buffers.isEmpty else { return FrameBuffer() }

        // Normalize all buffers to the same height
        let maxHeight = max(availableHeight, buffers.map(\.height).max() ?? 1)

        var result = FrameBuffer()

        // The ◀ toggle's row, so a still click there can be told from one on a dot.
        for info in dividerInfos where info.togglesColumn {
            info.handler?.arrowRow = maxHeight / 2
        }

        for (index, buffer) in buffers.enumerated() {
            // Pad buffer to full height and width
            let targetWidth = index < columnWidths.count ? columnWidths[index] : buffer.width
            let paddedBuffer = padToSize(buffer, width: targetWidth, height: maxHeight)

            if index == 0 {
                result = paddedBuffer
            } else {
                // The divider for the gap before this column.
                let info = index - 1 < dividerInfos.count
                    ? dividerInfos[index - 1]
                    : DividerRenderInfo(isActive: false, isHovered: false, mouseHandlerID: nil)
                let dividerBuffer = buildDividerColumn(
                    info: info, height: maxHeight, resizable: resizable,
                    palette: palette, cycle: cycle)
                result.appendHorizontally(dividerBuffer, spacing: 0)
                result.appendHorizontally(paddedBuffer, spacing: 0)
            }
        }

        return result
    }

    /// Per-gap divider state passed from `renderToBuffer` to `combineColumns`.
    struct DividerRenderInfo {
        /// Whether this divider's focus section is active (focused or being
        /// dragged) — its background pulses.
        let isActive: Bool
        /// Whether the cursor is over the divider — its grip dots pulse.
        let isHovered: Bool
        /// The mouse handler claiming drags on the divider, or `nil` when the
        /// split isn't resizable (or while measuring).
        let mouseHandlerID: HitTestRegion.HandlerID?
        /// Whether the divider is interactive at all — `false` under
        /// `.disabled()` or `.hidden()`, where the grip would advertise a
        /// handle that does nothing. A measuring pass stays `true`: the grip
        /// changes glyphs, never geometry, so measure parity holds either way.
        var isInteractive = true
        /// The divider's focus identity, stamped onto its hit region so an
        /// enclosing ScrollView can scroll a focused divider into view.
        var focusID: String?
        /// Whether this is the leftmost divider, whose centre row is the ◀ that
        /// hides the column to its left. Glyphs only, so a measuring pass sets
        /// it too.
        var togglesColumn = false
        /// The divider's handler, when it is wired.
        var handler: _SplitDividerHandler?
    }

    /// Sets up the divider that follows `column`: registers its focus
    /// section + handler (so Tab reaches it and the arrow keys resize it), and
    /// registers the mouse handler that drags it. Returns the info
    /// `combineColumns` needs to draw and hit-test it. A no-op (returns an
    /// inert divider) while measuring, and when the split isn't resizable
    /// unless this is the leftmost divider, which keeps its ◀ toggle.
    ///
    /// `currentWidth` is the width `column` is rendering at THIS frame,
    /// and is what every resize steps from (see
    /// ``_SplitDividerHandler/currentWidth``).
    fileprivate func wireDivider(
        column: NavigationSplitViewColumn,
        togglesColumn: Bool,
        toggleState: SplitViewToggleState?,
        resizable: Bool,
        widths: SplitViewWidths?,
        currentWidth: Int,
        context: RenderContext,
        focusManager: FocusManager?
    ) -> DividerRenderInfo {
        guard resizable || togglesColumn, !context.isMeasuring, let focusManager,
            let stateStorage = context.stateStorage, let toggleState,
            let handlerSlot = SplitViewStateIndex.divider(after: column)
        else {
            return DividerRenderInfo(
                isActive: false, isHovered: false, mouseHandlerID: nil, togglesColumn: togglesColumn)
        }

        // Namespaced by this split's identity, like every other per-instance
        // section (`modal-`, `alert-`, `contextmenu-`). Keyed on the index
        // alone, TWO resizable splits in one frame — a nested split in a detail
        // column, or two side by side — registered their dividers into ONE
        // shared section, so focusing either divider made both look focused and
        // the section's cycling walked another split's handle.
        //
        // Named by the column on its left, not by its position among the gaps.
        // Named by position, the content column's divider was the second gap in
        // `.all` and the first in `.doubleColumn`, so hiding the sidebar while
        // that divider held the focus removed its section, and the focus fell
        // back to the first section on the page.
        let sectionID = dividerSectionID(after: column, context: context)

        // The same gates every interactive view honours, which this direct
        // wiring bypassed: a `.disabled()` split's divider stayed a Tab stop
        // and stayed draggable, and a `.hidden()` one kept a Tab stop with no
        // picture for it to land on. Disabled views must not register with
        // the focus system; a suppressed subtree registers nothing at all.
        let isDisabled = !context.environment.isEnabled
        let isInteractive = !isDisabled && !context.environment.isFocusSuppressed
        guard isInteractive else {
            return DividerRenderInfo(
                isActive: false, isHovered: false, mouseHandlerID: nil, isInteractive: false,
                togglesColumn: togglesColumn)
        }
        focusManager.registerSection(id: sectionID)

        // Persist one handler per column so its drag anchor survives renders
        // (see `SplitViewStateIndex`).
        let handler = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: handlerSlot),
            default: _SplitDividerHandler(
                focusID: sectionID,
                column: column,
                widths: widths,
                minimumColumnWidth: minimumColumnWidth
            )
        ).value
        handler.canBeFocused = true
        handler.widths = widths
        handler.currentWidth = currentWidth
        // Only the leftmost divider hides a column; Return on the others falls
        // through, as it did before the toggle.
        handler.hide = togglesColumn ? hideAction(toggleState: toggleState) : nil
        if togglesColumn {
            FocusRegistration.publishActivationLabel(
                LocalizationService.shared.string(for: LocalizationKey.StatusBar.hideColumn),
                context: context, isFocused: focusManager.isFocused(id: sectionID))
        }
        focusManager.register(handler, inSection: sectionID)
        // The one focusable in the framework that does NOT go through
        // `FocusRegistration.register` — it registers into a section this view
        // owns, with a handler it persists itself — so anything hung off that
        // seam has to be repeated here or silently misses this control alone.
        // `help(_:)` is the first such thing: without this, `.help` on a split
        // divider works on hover and does nothing on the keyboard, which is the
        // failure mode `Documentation/Parity-decisions-pending.md` predicted for
        // exactly this site.
        FocusRegistration.publishHelpText(context: context, focusID: sectionID)

        let isActive = focusManager.isActiveSection(sectionID)

        var mouseHandlerID: HitTestRegion.HandlerID?
        if let mouseDispatcher = context.environment.mouseEventDispatcher {
            // Enable motion reporting so the dispatcher can synthesise the
            // hover enter/exit transitions that pulse the grip dots.
            mouseDispatcher.requestFeature(.motion)
            let captureWidths = widths
            let captureHandler = handler
            let captureFocus = focusManager
            mouseHandlerID = mouseDispatcher.register { event in
                // Hover transitions first — these arrive with a non-`.left`
                // button, so they'd be dropped by the button guard below.
                switch event.phase {
                case .entered:
                    captureHandler.isHovered = true
                    return true
                case .exited:
                    captureHandler.isHovered = false
                    return true
                default:
                    break
                }
                guard event.button == .left else { return false }
                switch event.phase {
                case .pressed:
                    // Anchor: the column's width when the drag began (see
                    // `_SplitDividerHandler.resizeBaseWidth` — under size-to-fit
                    // there is no stored width to read yet). Also focus the
                    // divider so a drag and the keyboard agree on which handle
                    // is active.
                    captureHandler.dragStartWidth = captureHandler.resizeBaseWidth
                    captureHandler.dragMoved = false
                    captureHandler.pressRow = event.y
                    captureFocus.activateSection(id: sectionID)
                    return true
                case .dragged, .released:
                    // `event.x` is localised to the divider's press position,
                    // so it is exactly the signed cell delta to apply. A press
                    // and release that never left the press column writes
                    // nothing at all: a bare click on the handle must leave the
                    // column exactly as it was, and must not pin a size-to-fit
                    // column (which would stop it tracking its content). The
                    // flag is sticky, so a drag that wanders away and returns
                    // still writes — restoring the start width — rather than
                    // stranding the column where it last moved.
                    captureHandler.dragMoved = captureHandler.dragMoved || event.x != 0
                    if captureHandler.dragMoved, let start = captureHandler.dragStartWidth {
                        captureWidths?.set(start + event.x, for: column)
                    }
                    if event.phase == .released {
                        // A still click on ◀ hides the column: pressed and
                        // released on the arrow's own cell with no movement in
                        // between. Anything else was a resize, or nothing.
                        if !captureHandler.dragMoved, let hide = captureHandler.hide,
                            let arrow = captureHandler.arrowRow,
                            captureHandler.pressRow == arrow, event.y == arrow
                        {
                            hide()
                        }
                        captureHandler.dragStartWidth = nil
                        captureHandler.dragMoved = false
                        captureHandler.pressRow = nil
                    }
                    return true
                default:
                    return false
                }
            }
        }

        return DividerRenderInfo(
            isActive: isActive, isHovered: handler.isHovered, mouseHandlerID: mouseHandlerID,
            focusID: handler.focusID, togglesColumn: togglesColumn, handler: handler)
    }

    /// Builds the one-column divider buffer for a gap.
    ///
    /// A resizable divider is a subtle grab handle — three `◦` dots stacked at
    /// its vertical centre — over an otherwise blank column, so it doesn't
    /// double up against the light `│` borders of the columns either side. Two
    /// independent cues animate it:
    ///
    /// - **Focused or dragging** (`isActive`): the whole divider *background*
    ///   pulses, a clear "this is the handle you're moving" signal.
    /// - **Hovered** (`isHovered`): just the grip dots pulse — a quiet hint
    ///   that's not distracting when the cursor merely passes over.
    ///
    /// `cycle` animates only when some divider is active or hovered (see
    /// `renderToBuffer`), so an untouched split animates nothing. A
    /// non-resizable divider is a plain space column (the historical separator);
    /// its drag hit-test region spans the full height, so a drag works anywhere
    /// along it, not just on the dots.
    fileprivate func buildDividerColumn(
        info: DividerRenderInfo,
        height: Int,
        resizable: Bool,
        palette: any Palette,
        cycle: SelectionEmphasisCycle
    ) -> FrameBuffer {
        let h = max(0, height)
        // A split that cannot resize keeps only the leftmost divider's ◀.
        guard resizable || info.togglesColumn, info.isInteractive, h > 0 else {
            return FrameBuffer(lines: Array(repeating: " ", count: h))
        }

        // Three grip dots centred vertically (fewer if the divider is short).
        let center = h / 2
        let gripRows = Set([center - 1, center, center + 1].filter { $0 >= 0 && $0 < h })
        return buildHandleColumn(info: info, height: h, palette: palette, cycle: cycle) { row in
            // The leftmost divider's middle dot is its ◀ toggle.
            if info.togglesColumn, row == center { return TerminalSymbols.leftArrow }
            return resizable && gripRows.contains(row) ? "◦" : nil
        }
    }

    /// Draws a one-cell handle column `height` rows tall: `glyph(row)` on the
    /// rows that have one, a blank cell on the rest, animated as
    /// ``buildDividerColumn(info:height:resizable:palette:cycle:)`` describes —
    /// the glyphs pulse while `info.isHovered`, the whole column's background
    /// while `info.isActive` — with `info.mouseHandlerID`'s hit region over
    /// the full height.
    func buildHandleColumn(
        info: DividerRenderInfo,
        height h: Int,
        palette: any Palette,
        cycle: SelectionEmphasisCycle,
        glyph: (Int) -> String?
    ) -> FrameBuffer {
        // Both ends of the hovered dot's breath come from `breathEnds`, so both spend
        // a faded accent. A dim end composited over the page beside a bright end
        // that kept the accent's alpha breathed between two alphas — §29's pair.
        let dot = palette.accent.breathEnds(
            dimmedTo: ViewConstants.focusBorderDim, over: palette.background)
        let pulse = palette.accentFillPulse()

        /// One divider cell as it looks at a given point in the pulse, with the
        /// claim its colours owe.
        ///
        /// A single closure rather than a colour computed up front, because a
        /// divider can pulse two things at once — the grip dots while hovered,
        /// the background while focused or dragging — and the runs below have
        /// to reproduce exactly what was drawn here, not an approximation of it.
        func cell(row: Int, at emphasis: SelectionEmphasis) -> ClaimingRow {
            let mark = glyph(row)
            // Grip foreground: a quiet dot, pulsing toward the accent while
            // hovered.
            let dotColor = info.isHovered
                ? emphasis.color(dim: dot.dim, bright: dot.bright)
                : palette.foregroundTertiary
            // Background: pulses across the whole divider while focused /
            // dragging (same min/max the List focus-pulse uses).
            let background: Color? = info.isActive
                ? emphasis.color(dim: pulse.dim, bright: pulse.bright)
                : nil
            // Each cell is a self-contained styled string — it ends with a
            // reset — so the pulsing background stays scoped to the divider's
            // single column. `withPersistentBackground` deliberately does NOT
            // emit a trailing reset (it is built for full-width row fills), so
            // using it here let the background bleed into the next column to the
            // end of the line. Through `ClaimingRow`, so the bytes state the
            // opaque spelling and the alpha travels as the claim.
            var drawn = ClaimingRow()
            drawn.append(mark ?? " ", cells: 1, ink: mark == nil ? nil : dotColor, field: background)
            return drawn
        }

        let now = cycle.frames[cycle.step % cycle.frames.count]
        let cells = (0..<h).map { cell(row: $0, at: now) }

        var buffer = FrameBuffer(lines: cells.map(\.text))
        // The drawn frame's claims are every frame's: the only colours that move are
        // the dot's breath and the background's, both spent at both ends, and a
        // resting dot is one colour in every frame (§63).
        buffer.opacityRegions = cells.enumerated().flatMap { row, cell in
            cell.claims.map { $0.shifted(byX: 0, y: row) }
        }
        // One run per row: a run covers one row, and the divider is one column
        // wide. Rows that look the same at every point in the cycle — the plain
        // spaces of a merely-hovered divider — produce a still run, which the
        // loop drops.
        buffer.animatedCells = (0..<h).compactMap { row in
            cycle.run(offsetX: 0, offsetY: row) { cell(row: row, at: $0).text }
        }.filter(\.isAnimating)
        if let id = info.mouseHandlerID {
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: 1, height: h, handlerID: id,
                    focusID: info.focusID
                )
            )
        }
        return buffer
    }

    /// Pads a buffer to the specified width and height.
    ///
    /// The padding doesn't shift the buffer's contents — characters
    /// stay at the same (x, y) coordinates — so the buffer's overlay
    /// layers and hit-test regions carry across unchanged. Building
    /// the result via `replacingLines` preserves both; the previous
    /// `FrameBuffer(lines: lines, width: width)` constructor dropped
    /// them, which broke per-column click-to-focus on NavigationSplitView.
    fileprivate func padToSize(_ buffer: FrameBuffer, width: Int, height: Int) -> FrameBuffer {
        var lines = buffer.lines

        // Pad each line to the target width
        let paddedLines = lines.map { line -> String in
            let lineWidth = line.strippedLength
            if lineWidth < width {
                return line + String(repeating: " ", count: width - lineWidth)
            }
            return line
        }
        lines = paddedLines

        // Pad to target height
        let emptyLine = String(repeating: " ", count: width)
        while lines.count < height {
            lines.append(emptyLine)
        }

        return buffer.replacingLines(lines)
    }
}

// MARK: - Equatable Conformance

extension NavigationSplitView: @preconcurrency Equatable where Sidebar: Equatable, Content: Equatable, Detail: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sidebar == rhs.sidebar && lhs.content == rhs.content && lhs.detail == rhs.detail && lhs.isThreeColumn == rhs.isThreeColumn
    }
}
