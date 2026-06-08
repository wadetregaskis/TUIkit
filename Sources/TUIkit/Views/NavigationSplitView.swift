//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitView.swift
//
//  Created by LAYERED.work
//  License: MIT

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
/// ## Focus Navigation
///
/// Each column registers as a separate focus section. Use Tab/Shift+Tab to
/// move between columns, and Up/Down arrows to navigate within each column.
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
private struct _NavigationSplitViewCore<Sidebar: View, Content: View, Detail: View>: View, Renderable, Layoutable {
    let sidebar: Sidebar
    let content: Content
    let detail: Detail
    let isThreeColumn: Bool
    let columnVisibility: Binding<NavigationSplitViewVisibility>?

    /// The minimum width for any column in characters.
    private let minimumColumnWidth = 10

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
        let visibility = resolveVisibility()

        // Calculate visible columns based on visibility
        let visibleColumns = calculateVisibleColumns(visibility: visibility)
        guard !visibleColumns.isEmpty else {
            return FrameBuffer()
        }

        // Resizable columns (the default) persist a user-chosen width per
        // non-trailing column and expose a draggable / focusable divider.
        let resizable =
            context.environment.navigationSplitViewResizable
            && context.environment.stateStorage != nil
        let widths: SplitViewWidths? = resizable
            ? context.environment.stateStorage!.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
                default: SplitViewWidths()
            ).value
            : nil
        if resizable {
            // Keep the persisted widths box AND the divider handlers (all keyed
            // by this identity) alive across the run loop's per-frame
            // StateStorage GC. `storage(for:)` does not mark the identity active,
            // and nothing else marks the split's own identity (the columns mark
            // their child identities, not the parent), so without this the box
            // is collected every frame and a drag / arrow resize never sticks.
            context.environment.stateStorage!.markActive(context.identity)
        }

        // Calculate column widths
        let columnWidths = calculateColumnWidths(
            visibleColumns: visibleColumns,
            style: style,
            availableWidth: context.availableWidth,
            widths: widths,
            writeBack: resizable && !context.isMeasuring
        )

        // Render each visible column
        var buffers: [FrameBuffer] = []
        // One entry per gap between columns; drives the divider's look and its
        // drag hit-test region (see `combineColumns`).
        var dividerInfos: [DividerRenderInfo] = []
        let focusManager = context.environment.focusManager

        for (index, column) in visibleColumns.enumerated() {
            let columnWidth = columnWidths[index]
            let columnContext = context.withAvailableSize(width: columnWidth, height: context.availableHeight)

            // Register focus section for this column (skip during measurement)
            let sectionID = focusSectionID(for: column)
            if !columnContext.isMeasuring {
                focusManager.registerSection(id: sectionID)
            }

            // Create a context with the active focus section
            var sectionContext = columnContext
            sectionContext.environment.activeFocusSectionID = sectionID

            // If this section is active, set the focus indicator color for borders (never active during measurement)
            if !columnContext.isMeasuring && focusManager.isActiveSection(sectionID) {
                let accentColor = context.environment.palette.accent
                let dimColor = accentColor.opacity(ViewConstants.focusBorderDim)
                sectionContext.environment.focusIndicatorColor = Color.lerp(dimColor, accentColor, phase: context.environment.pulsePhase)
            } else {
                sectionContext.environment.focusIndicatorColor = nil
            }

            var buffer = renderColumn(column, context: sectionContext)

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
                        captureManager.activateSection(id: captureSectionID)
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
                        index: index,
                        resizable: resizable,
                        widths: widths,
                        context: context,
                        focusManager: focusManager
                    )
                )
            }
        }

        // Read the pulse clock ONLY when a divider is focused/dragged or
        // hovered, so the demand-driven loop keeps the pulse animating just for
        // those cases (a static split with no active/hovered divider stays idle).
        let anyDividerPulsing = dividerInfos.contains { $0.isActive || $0.isHovered }
        let pulsePhase = anyDividerPulsing ? context.environment.pulsePhase : 0

        // Combine buffers horizontally, inserting the (possibly resizable)
        // dividers between them.
        return combineColumns(
            buffers: buffers,
            columnWidths: columnWidths,
            dividerInfos: dividerInfos,
            resizable: resizable,
            palette: context.environment.palette,
            pulsePhase: pulsePhase,
            availableHeight: context.availableHeight
        )
    }
}

// MARK: - Private Helpers

extension _NavigationSplitViewCore {
    /// Resolves the effective visibility from the binding or defaults to `.all`.
    fileprivate func resolveVisibility() -> NavigationSplitViewVisibility {
        if let binding = columnVisibility {
            let value = binding.wrappedValue
            // Resolve .automatic to .all
            if value == .automatic {
                return .all
            }
            return value
        }
        return .all
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

    /// Fixed column widths for sidebar and content (TUI-specific).
    /// Only the rightmost column adapts to terminal width changes.
    private var fixedSidebarWidth: Int { 25 }
    private var fixedContentWidth: Int { 30 }

    /// Calculates the width for each visible column.
    ///
    /// TUI-specific: every left column has a width, the rightmost column is
    /// flexible and absorbs the remainder. A left column's width is the user's
    /// stored width (from a drag / keyboard resize) when present, otherwise its
    /// default; either way it is clamped so the column keeps at least
    /// `minimumColumnWidth` and leaves at least that much for each column to its
    /// right. When `writeBack` is set (the real render of a resizable split),
    /// the clamped width is written back so the next arrow-key step starts from
    /// the true current width and a too-wide drag settles at the real maximum.
    fileprivate func calculateColumnWidths(
        visibleColumns: [NavigationSplitViewColumn],
        style: any NavigationSplitViewStyle,
        availableWidth: Int,
        widths: SplitViewWidths?,
        writeBack: Bool
    ) -> [Int] {
        let separatorCount = max(0, visibleColumns.count - 1)
        let usableWidth = availableWidth - separatorCount

        guard usableWidth > 0 else {
            return Array(repeating: 0, count: visibleColumns.count)
        }

        var result: [Int] = []
        var remainingWidth = usableWidth

        for (index, column) in visibleColumns.enumerated() {
            let isLastColumn = index == visibleColumns.count - 1

            if isLastColumn {
                // Last column gets all remaining width
                result.append(max(minimumColumnWidth, remainingWidth))
            } else {
                // Default width for left columns, overridden by a stored
                // user resize when present.
                let defaultWidth: Int
                switch column {
                case .sidebar:
                    defaultWidth = fixedSidebarWidth
                case .content:
                    defaultWidth = fixedContentWidth
                default:
                    defaultWidth = minimumColumnWidth
                }
                let desired = widths?.value(for: index) ?? defaultWidth
                // Reserve at least minimumColumnWidth for every column still to
                // the right, so a wide left column can't starve them.
                let columnsToTheRight = visibleColumns.count - index - 1
                let maxForColumn =
                    remainingWidth - minimumColumnWidth * columnsToTheRight
                let width = max(
                    minimumColumnWidth, min(desired, max(minimumColumnWidth, maxForColumn)))
                if writeBack {
                    widths?.set(width, for: index)
                }
                result.append(width)
                remainingWidth -= width
            }
        }

        return result
    }

    /// Returns the focus section ID for a column.
    fileprivate func focusSectionID(for column: NavigationSplitViewColumn) -> String {
        switch column {
        case .sidebar:
            return "nav-split-sidebar"
        case .content:
            return "nav-split-content"
        case .detail:
            return "nav-split-detail"
        default:
            return "nav-split-unknown"
        }
    }

    /// Renders a single column.
    fileprivate func renderColumn(_ column: NavigationSplitViewColumn, context: RenderContext) -> FrameBuffer {
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
        pulsePhase: Double,
        availableHeight: Int
    ) -> FrameBuffer {
        guard !buffers.isEmpty else { return FrameBuffer() }

        // Normalize all buffers to the same height
        let maxHeight = max(availableHeight, buffers.map(\.height).max() ?? 1)

        var result = FrameBuffer()

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
                    palette: palette, pulsePhase: pulsePhase)
                result.appendHorizontally(dividerBuffer, spacing: 0)
                result.appendHorizontally(paddedBuffer, spacing: 0)
            }
        }

        return result
    }

    /// Per-gap divider state passed from `renderToBuffer` to `combineColumns`.
    fileprivate struct DividerRenderInfo {
        /// Whether this divider's focus section is active (focused or being
        /// dragged) — its background pulses.
        let isActive: Bool
        /// Whether the cursor is over the divider — its grip dots pulse.
        let isHovered: Bool
        /// The mouse handler claiming drags on the divider, or `nil` when the
        /// split isn't resizable (or while measuring).
        let mouseHandlerID: HitTestRegion.HandlerID?
    }

    /// Sets up the divider that follows column `index`: registers its focus
    /// section + handler (so Tab reaches it and the arrow keys resize it), and
    /// registers the mouse handler that drags it. Returns the info
    /// `combineColumns` needs to draw and hit-test it. A no-op (returns an
    /// inert divider) while measuring or when the split isn't resizable.
    fileprivate func wireDivider(
        index: Int,
        resizable: Bool,
        widths: SplitViewWidths?,
        context: RenderContext,
        focusManager: FocusManager
    ) -> DividerRenderInfo {
        guard resizable, !context.isMeasuring, let widths,
            let stateStorage = context.environment.stateStorage
        else {
            return DividerRenderInfo(isActive: false, isHovered: false, mouseHandlerID: nil)
        }

        let sectionID = "nav-split-divider-\(index)"
        focusManager.registerSection(id: sectionID)

        // Persist one handler per divider so its drag anchor survives renders.
        let handler = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: 1 + index),
            default: _SplitDividerHandler(
                focusID: "\(sectionID)-\(context.identity.path)",
                columnIndex: index,
                widths: widths,
                minimumColumnWidth: minimumColumnWidth
            )
        ).value
        handler.canBeFocused = true
        focusManager.register(handler, inSection: sectionID)

        let isActive = focusManager.isActiveSection(sectionID)

        var mouseHandlerID: HitTestRegion.HandlerID?
        if let mouseDispatcher = context.environment.mouseEventDispatcher {
            // Enable motion reporting so the dispatcher can synthesise the
            // hover enter/exit transitions that pulse the grip dots.
            mouseDispatcher.requestFeature(.motion)
            let captureWidths = widths
            let captureHandler = handler
            let column = index
            let minWidth = minimumColumnWidth
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
                    // Anchor: the column's width when the drag began. Also
                    // focus the divider so a drag and the keyboard agree on
                    // which handle is active.
                    captureHandler.dragStartWidth =
                        captureWidths.value(for: column) ?? minWidth
                    captureFocus.activateSection(id: sectionID)
                    return true
                case .dragged, .released:
                    // `event.x` is localised to the divider's press position,
                    // so it is exactly the signed cell delta to apply.
                    if let start = captureHandler.dragStartWidth {
                        captureWidths.set(start + event.x, for: column)
                    }
                    if event.phase == .released {
                        captureHandler.dragStartWidth = nil
                    }
                    return true
                default:
                    return false
                }
            }
        }

        return DividerRenderInfo(
            isActive: isActive, isHovered: handler.isHovered, mouseHandlerID: mouseHandlerID)
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
    /// `pulsePhase` is non-zero only when some divider is active or hovered (see
    /// `renderToBuffer`), so an untouched split animates nothing. A
    /// non-resizable divider is a plain space column (the historical separator);
    /// its drag hit-test region spans the full height, so a drag works anywhere
    /// along it, not just on the dots.
    fileprivate func buildDividerColumn(
        info: DividerRenderInfo,
        height: Int,
        resizable: Bool,
        palette: any Palette,
        pulsePhase: Double
    ) -> FrameBuffer {
        let h = max(0, height)
        guard resizable, h > 0 else {
            return FrameBuffer(lines: Array(repeating: " ", count: h))
        }

        // Three grip dots centred vertically (fewer if the divider is short).
        let center = h / 2
        let gripRows = Set([center - 1, center, center + 1].filter { $0 >= 0 && $0 < h })

        // Grip foreground: a quiet dot, pulsing toward the accent while hovered.
        let dotColor = info.isHovered
            ? Color.lerp(
                palette.accent.opacity(ViewConstants.focusBorderDim),
                palette.accent, phase: pulsePhase)
            : palette.foregroundTertiary

        // Background: pulses across the whole divider while focused / dragging
        // (same min/max the List focus-pulse uses).
        let background: Color? = info.isActive
            ? Color.lerp(
                palette.accent.opacity(ViewConstants.focusPulseMin),
                palette.accent.opacity(ViewConstants.focusPulseMax), phase: pulsePhase)
            : nil

        let lines: [String] = (0..<h).map { row in
            let isGrip = gripRows.contains(row)
            // Render each cell as a self-contained styled string — it ends with
            // a reset — so the pulsing background stays scoped to the divider's
            // single column. `withPersistentBackground` deliberately does NOT
            // emit a trailing reset (it is built for full-width row fills), so
            // using it here let the background bleed into the next column to the
            // end of the line.
            return ANSIRenderer.colorize(
                isGrip ? "◦" : " ",
                foreground: isGrip ? dotColor : nil,
                background: background)
        }

        var buffer = FrameBuffer(lines: lines)
        if let id = info.mouseHandlerID {
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: 1, height: h, handlerID: id
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
