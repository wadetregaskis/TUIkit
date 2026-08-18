//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Tab

/// A tab in a ``TabView``: a title, a selection value, and the content shown
/// when that tab is active.
///
/// Mirrors SwiftUI's `Tab(_:value:content:)`. SwiftUI also takes a
/// `systemImage:` — omitted here, as a terminal has no SF Symbols.
///
/// ```swift
/// TabView(selection: $tab) {
///     Tab("Profile", value: 0) { ProfileView() }
///     Tab("Settings", value: 1) { SettingsView() }
/// }
/// ```
public struct Tab<Value: Hashable, Content: View>: View {
    let title: String
    let value: Value
    let content: Content

    /// Creates a tab with a localized title, selection value, and content.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the tab's label in the strip.
    ///   - value: The value this tab is selected by (matches the `TabView`'s
    ///     selection binding).
    ///   - content: The view shown while this tab is selected.
    public init(
        _ titleKey: LocalizedStringKey, value: Value, @ViewBuilder content: () -> Content
    ) {
        self.init(titleKey.localized, value: value, content: content)
    }

    /// Creates a tab whose title is displayed as written.
    ///
    /// - Parameters:
    ///   - title: The tab's label in the strip.
    ///   - value: The value this tab is selected by (matches the `TabView`'s
    ///     selection binding).
    ///   - content: The view shown while this tab is selected.
    @_disfavoredOverload
    public init(_ title: String, value: Value, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    // A standalone Tab (outside a TabView) just renders its content.
    public var body: some View { content }
}

extension Tab: TabContentProvider {
    func tabs() -> [_RawTab] {
        [_RawTab(value: AnyHashable(value), title: title, content: AnyView(content))]
    }
}

// MARK: - Style

/// The visual style of a ``TabView``'s tab strip.
public enum TabViewStyle: Sendable {
    /// The default — currently ``compact``.
    case automatic
    /// A single, border-free row; the active tab is marked by a background-colour
    /// fill rather than box-drawing chrome. The most space-efficient style.
    case compact
    /// A single row of box-drawing-separated tabs with a connecting rule beneath
    /// — more decorative, one row taller than ``compact``.
    case bordered

    var resolved: Self { self == .automatic ? .compact : self }
}

private struct TabViewStyleKey: EnvironmentKey {
    static let defaultValue: TabViewStyle = .automatic
}

extension EnvironmentValues {
    /// The tab-strip style for this environment.
    public var tabViewStyle: TabViewStyle {
        get { self[TabViewStyleKey.self] }
        set { self[TabViewStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the visual style of `TabView`s within this view.
    public func tabViewStyle(_ style: TabViewStyle) -> some View {
        environment(\.tabViewStyle, style)
    }
}

// The TUI-specific TabView environment modifiers (header alignment, header
// wrapping, content sizing, content padding) live in `TabViewModifiers.swift`.

// MARK: - TabView

/// A container that shows one of several tabs, with a strip for switching
/// between them.
///
/// Declare tabs with ``Tab`` and bind the active one to `selection`:
///
/// ```swift
/// @State private var tab = 0
///
/// TabView(selection: $tab) {
///     Tab("One", value: 0) { Text("First") }
///     Tab("Two", value: 1) { Text("Second") }
/// }
/// .tabViewStyle(.compact)
/// ```
///
/// The strip is keyboard-navigable (`←`/`→`) when focused and responds to mouse
/// clicks. Each tab's content keeps its own `@State` — switching tabs does not
/// disturb another tab's editing state.
public struct TabView<SelectionValue: Hashable, Content: View>: View {
    let selection: Binding<SelectionValue>
    let content: Content

    /// Creates a tab view with a selection binding.
    ///
    /// - Parameters:
    ///   - selection: A binding to the value identifying the active tab.
    ///   - content: A ``Tab`` for each page (directly, in a `ForEach`, etc.).
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }

    public var body: some View {
        _TabViewCore(
            selection: selection,
            tabs: (content as? TabContentProvider)?.tabs() ?? []
        )
    }
}

// MARK: - Core

private enum TabViewStateIndex {
    static let focusID = 0
    static let handler = 1
    /// Per-tab measured content sizes (``TabSizeCache``), so the panel can size
    /// to the widest *and* tallest tab without re-measuring every tab each pass.
    static let sizeCache = 2
}

/// Each tab's natural content size, per width measured at.
///
/// The width has to be part of the key because only the *selected* tab is
/// re-measured each pass. Keyed by tab value alone, every other tab kept
/// whatever size it had at the width it was first seen at, so after a resize the
/// panel was built from stale numbers — and since the panel sizes to the tallest
/// and widest of all tabs, it jumped the instant one of those tabs became
/// selected and got re-measured.
///
/// Several widths get measured within a single frame — a dialog probes its body
/// at more than one width before settling on one — so a cache that held only the
/// latest width would flush and re-seed every tab on each probe. Holding a
/// handful covers a probe sweep and a resize, and evicting the least recently
/// used keeps it bounded across a long resize drag.
/// `Equatable` so the caller can decline to write back a cache that did not
/// change. Writing a `StateBox` invalidates the render cache and requests
/// another render — and this one is written from the MEASURE pass, so an
/// unconditional store made every frame schedule the next one, forever. See
/// ``_TabViewCore/tabContentSizes(insets:available:context:)``.
private struct TabSizeCache: Equatable {
    private static let capacity = 8

    /// The widths held, least recently used first.
    private var order: [Int] = []
    private var sizes: [Int: [AnyHashable: ViewSize]] = [:]

    subscript(width: Int) -> [AnyHashable: ViewSize]? { sizes[width] }

    mutating func set(_ entry: [AnyHashable: ViewSize], for width: Int) {
        if let existing = order.firstIndex(of: width) { order.remove(at: existing) }
        order.append(width)
        sizes[width] = entry
        while order.count > Self.capacity { sizes.removeValue(forKey: order.removeFirst()) }
    }
}

/// Renders the tab strip plus the selected tab's content.
///
/// The selected content is rendered under a value-keyed *branch identity*, so
/// each tab's subtree (and its `@State`) is isolated — switching tabs can't
/// alias one tab's state onto another's.
struct _TabViewCore<SelectionValue: Hashable>: View, Renderable, Layoutable {
    let selection: Binding<SelectionValue>
    let tabs: [_RawTab]

    private typealias StateIndex = TabViewStateIndex

    var body: Never { fatalError("_TabViewCore renders via Renderable") }

    /// Index of the tab whose value matches the selection, or 0 (so something is
    /// always shown even if the binding holds a value with no matching tab).
    private var selectedIndex: Int {
        tabs.firstIndex { $0.value == AnyHashable(selection.wrappedValue) } ?? 0
    }

    /// The render context for the active tab's content: identity branched by the
    /// selected value, height reduced by the strip.
    private func contentContext(_ context: RenderContext, stripHeight: Int) -> RenderContext {
        var child = context.withBranchIdentity("tab-\(tabs[selectedIndex].value)")
        child.availableHeight = max(0, context.availableHeight - stripHeight)
        // The body is painted on the strip's surface, so anything inside that
        // draws a surface of its own has to step off THAT, not off the page.
        // Without this a `TextField` in a tab computed "a step above the page"
        // — which is the tab's own colour — and disappeared into it.
        child.environment.surfaceBackground = surfaceColor(child.environment.palette)
        return child
    }

    /// Each tab's natural (unconstrained) content size, memoised per tab.
    ///
    /// Only the *selected* tab is measured each pass; the others reuse their last
    /// measured size from a per-tab cache. Measuring every tab each pass would
    /// fully render the non-`Layoutable` tabs (channel editors, the 139/216/256-
    /// swatch grids) hundreds of cells at a time — pathologically slow. A tab not
    /// yet seen is measured once to seed its entry. So the selected tab tracks its
    /// own `@State` (e.g. the 256-grid's "show numbers"), and the panel holds the
    /// widest/tallest of all tabs without re-rendering them.
    ///
    /// The cache is a pure memo keyed by content identity **and the width it was
    /// measured at** (it can only ever equal what a measure would compute), so
    /// writing it during a measure pass is benign — it doesn't perturb layout,
    /// only avoids recomputation. A single `measureChild` already yields both
    /// axes, so caching the full ``ViewSize`` (rather than only the width) lets
    /// the panel size to the tallest tab too, at no extra measure cost.
    ///
    /// The width has to be part of the key precisely *because* only the selected
    /// tab is re-measured: with the sizes keyed by tab value alone, every other
    /// tab kept whatever it measured at the width it was first seen at. Once the
    /// terminal (or any enclosing layout) changed width, the panel — sized to
    /// the tallest and widest of all tabs — was built from stale numbers, and
    /// jumped the instant you switched to one of them. Re-seeding on a width
    /// change costs one full measure per resize and nothing in the steady state.
    private func tabContentSizes(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> [AnyHashable: ViewSize] {
        func measureTab(_ index: Int) -> ViewSize {
            var branch = context.withBranchIdentity("tab-\(tabs[index].value)")
            branch.availableWidth = available
            return measureChild(
                tabs[index].content.padding(insets),
                proposal: ProposedSize(width: nil, height: nil), context: branch)
        }
        guard let stateStorage = context.stateStorage else {
            return [AnyHashable(tabs[selectedIndex].value): measureTab(selectedIndex)]
        }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.sizeCache)
        let box: StateBox<TabSizeCache> = stateStorage.storage(for: key, default: TabSizeCache())
        var cache = box.value
        var entry = cache[available] ?? [:]
        entry[AnyHashable(tabs[selectedIndex].value)] = measureTab(selectedIndex)
        for (i, tab) in tabs.enumerated() where entry[AnyHashable(tab.value)] == nil {
            entry[AnyHashable(tab.value)] = measureTab(i)  // one-time seed per tab, per width
        }
        let present = Set(tabs.map { AnyHashable($0.value) })
        entry = entry.filter { present.contains($0.key) }  // drop removed tabs
        cache.set(entry, for: available)
        // Only when it actually changed. This runs during the MEASURE pass, and
        // writing a `StateBox` invalidates the render cache and asks for another
        // render — which measures again, which wrote again. An idle page with a
        // tab view rendered itself forever at whatever rate the loop would run,
        // producing byte-identical frames: 12% of a core on the Example's Tab
        // Views page, with nothing on screen changing. The cache is a memo, not
        // state; re-storing the same memo must not dirty anything.
        if cache != box.value { box.value = cache }
        return entry
    }

    /// The widest tab's natural (unconstrained) content width — the panel sizes to
    /// it (stable across tab switches) and the strip folds to it, rather than a
    /// wide strip ballooning the panel. Capped to what's available.
    private func widestContentWidth(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> Int {
        let cache = tabContentSizes(insets: insets, available: available, context: context)
        let widest = tabs.map { cache[AnyHashable($0.value)]?.width ?? 0 }.max() ?? 0
        return min(max(1, widest), max(1, available))
    }

    /// The tallest tab's natural (unconstrained) content height — the panel sizes
    /// to it so switching tabs doesn't change the panel height (mirroring how
    /// ``widestContentWidth`` keeps the width stable). Opt out per
    /// ``EnvironmentValues/tabViewContentSizing``: `.activeTab` returns the
    /// selected tab's height instead, so the panel tracks each tab's own height.
    ///
    /// Measuring the natural height at the same single per-tab measure the width
    /// uses makes this free. It is a safe panel height: the selected content is
    /// rendered at the (widest-tab) panel width, which is at least each tab's
    /// natural width, so it wraps no taller than its natural height.
    private func tallestContentHeight(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> Int {
        let cache = tabContentSizes(insets: insets, available: available, context: context)
        if context.environment.tabViewContentSizing == .activeTab {
            return max(0, cache[AnyHashable(tabs[selectedIndex].value)]?.height ?? 0)
        }
        return tabs.map { cache[AnyHashable($0.value)]?.height ?? 0 }.max() ?? 0
    }

    /// The selected tab's natural (unconstrained) content width — what its ink
    /// actually occupies. The content is *rendered* at the full panel width (so a
    /// `ViewThatFits` editor reliably picks its wide single-row candidate rather
    /// than tipping onto a stacked fallback at a tight width), then clamped to
    /// this natural width and block-centred. A tab narrower than the panel — e.g.
    /// a slim channel editor in a panel widened by the 256-swatch grid — is thus
    /// centred; a tab as wide as the panel clamps to the panel and fills it.
    private func naturalSelectedWidth(insets: EdgeInsets, available: Int, context: RenderContext) -> Int {
        var branch = context.withBranchIdentity("tab-\(tabs[selectedIndex].value)")
        branch.availableWidth = available
        return max(1, measureChild(
            tabs[selectedIndex].content.padding(insets),
            proposal: ProposedSize(width: nil, height: nil), context: branch).width)
    }

    /// The wrap budget for the header strip: the content width when folding
    /// (`toContentWidth`), otherwise the full available width (wrap only on
    /// overflow).
    private func stripWrapBudget(widest: Int, available: Int, context: RenderContext) -> Int {
        context.environment.tabViewHeaderWrap == .toContentWidth ? widest : max(1, available)
    }

    /// The strip's visual rows (tab indices, top-to-bottom with the active row
    /// floated to the bottom) and each tab's horizontal centre in panel-relative
    /// cells. Mirrors the render geometry so the `TabStripHandler`'s up/down keys
    /// move to the tab actually above/below the current one.
    private func navigationGeometry(context: RenderContext) -> (rows: [[Int]], centers: [Int: Int]) {
        let style = context.environment.tabViewStyle.resolved
        let alignment = context.environment.tabViewHeaderAlignment
        let insets = resolvedContentInsets(style: style, context: context)
        let bordered = style == .bordered
        let avail = bordered ? max(1, context.availableWidth - 2) : context.availableWidth
        let widest = widestContentWidth(insets: insets, available: avail, context: context)
        let rows = floatActiveRowToBottom(
            stripRowGroups(style: .compact, available: stripWrapBudget(widest: widest, available: avail, context: context)),
            selectedIndex: selectedIndex)
        let rowWidthOf: ([Int]) -> Int = bordered ? folderRowWidth : compactRowWidth
        let panelWidth = max(widest, rows.map(rowWidthOf).max() ?? 0)
        var centers: [Int: Int] = [:]
        for row in rows {
            var col = max(0, alignment.childOffset(childWidth: rowWidthOf(row), in: panelWidth))
            for i in row {
                let bodyWidth = tabWidth(i, style: bordered ? .bordered : .compact)
                let lead = bordered ? 1 : 0  // bordered: a wall precedes each tab body
                centers[i] = col + lead + bodyWidth / 2
                col += lead + bodyWidth
            }
        }
        return (rows, centers)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard !tabs.isEmpty else { return ViewSize.fixed(0, 0) }
        let style = context.environment.tabViewStyle.resolved
        var ctx = context
        ctx.availableWidth = proposal.width ?? context.availableWidth
        let insets = resolvedContentInsets(style: style, context: ctx)

        if style == .bordered {
            // Size to the widest tab; the strip wraps per the header-wrap mode.
            // Box chrome: each tab row is 2 lines (tops + labels) + the
            // content-border line + the bottom border, plus a 1-cell border side.
            let avail = max(1, ctx.availableWidth - 2)
            let widest = widestContentWidth(insets: insets, available: avail, context: ctx)
            let rows = stripRowGroups(
                style: .compact,
                available: stripWrapBudget(widest: widest, available: avail, context: ctx))
            let chrome = 2 * rows.count + 2
            // Size to the TALLEST tab (stable across switches), not just the
            // selected one — mirroring the widest-tab width.
            let contentHeight = tallestContentHeight(insets: insets, available: avail, context: ctx)
            let interior = max(widest, rows.map(folderRowWidth).max() ?? 0)
            return ViewSize(
                width: interior + 2, height: chrome + contentHeight,
                isWidthFlexible: false, isHeightFlexible: false)
        }

        // Compact: size to the widest tab; the strip wraps per the header-wrap
        // mode and the selected content is centred within it.
        let widest = widestContentWidth(insets: insets, available: ctx.availableWidth, context: ctx)
        let rows = stripRowGroups(
            style: style,
            available: stripWrapBudget(widest: widest, available: ctx.availableWidth, context: ctx))
        // Size to the TALLEST tab (stable across switches), not just the selected
        // one — mirroring the widest-tab width.
        let contentHeight = tallestContentHeight(
            insets: insets, available: ctx.availableWidth, context: ctx)
        let panelWidth = max(widest, rows.map(compactRowWidth).max() ?? 0)
        return ViewSize(
            width: panelWidth, height: rows.count + contentHeight,
            isWidthFlexible: false, isHeightFlexible: false)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !tabs.isEmpty else { return FrameBuffer() }
        let style = context.environment.tabViewStyle.resolved
        let palette = context.environment.palette
        let isDisabled = !context.environment.isEnabled

        // Focus handler (arrow-key tab switching).
        let stateStorage = context.stateStorage!
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "tabview",
            propertyIndex: StateIndex.focusID)
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let erased = Binding<AnyHashable>(
            get: { AnyHashable(selection.wrappedValue) },
            set: { if let v = $0.base as? SelectionValue { selection.wrappedValue = v } })
        let handlerBox: StateBox<TabStripHandler> = stateStorage.storage(
            for: handlerKey,
            default: TabStripHandler(
                focusID: persistedFocusID, selection: erased,
                values: tabs.map(\.value), canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.selection = erased
        handler.values = tabs.map(\.value)
        handler.canBeFocused = !isDisabled
        if !context.isMeasuring {
            let geometry = navigationGeometry(context: context)
            handler.rows = geometry.rows
            handler.centers = geometry.centers
            FocusRegistration.register(context: context, handler: handler)
        }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID) && !isDisabled
        let selected = selectedIndex

        var buffer =
            style == .bordered
            ? renderBordered(
                selectedIndex: selected, isFocused: isFocused, palette: palette, context: context)
            : renderCompact(
                selectedIndex: selected, isFocused: isFocused, palette: palette, context: context)
        attachRevealRegion(
            to: &buffer, persistedFocusID: persistedFocusID, context: context)
        return buffer
    }

    /// A whole-TabView region carrying the persisted focusID, so an
    /// ENCLOSING ScrollView can locate the focused TabView and scroll it
    /// into view (`snapViewportToFocusedControl` scans regions by focusID —
    /// the same rule Table, List, and ScrollView follow). Whole-control
    /// deliberately, not the strip: a TabView taller than the viewport then
    /// top-aligns (headers visible, content filling the rest), and a
    /// shorter one is revealed entirely. The handler is inert and the
    /// region sits at the BACK of the dispatch order, so the tab-strip
    /// click regions and interactive tab content keep winning every click.
    private func attachRevealRegion(
        to buffer: inout FrameBuffer, persistedFocusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring,
            let dispatcher = context.environment.mouseEventDispatcher
        else { return }
        let handlerID = dispatcher.register { _ in false }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID, focusID: persistedFocusID),
            at: 0
        )
    }

    private func persistedFocusIDForClicks(_ context: RenderContext) -> String {
        FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "tabview",
            propertyIndex: StateIndex.focusID)
    }

    /// Registers a click handler per tab region (selecting that tab).
    private func attachTabClicks(
        to buffer: inout FrameBuffer,
        regions: [(x: Int, y: Int, width: Int, index: Int)],
        context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher else { return }
        let captureFocusID = persistedFocusIDForClicks(context)
        let focusManager = context.environment.focusManager
        for region in regions {
            let value = tabs[region.index].value
            let capture = selection
            let handlerID = dispatcher.register { event in
                guard event.phase == .released, event.button == .left else {
                    return event.phase == .pressed && event.button == .left
                }
                focusManager?.focus(id: captureFocusID)
                if let v = value.base as? SelectionValue { capture.wrappedValue = v }
                return true
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: region.x, offsetY: region.y, width: region.width, height: 1,
                    handlerID: handlerID, focusID: nil))
        }
    }

    /// Renders the `.bordered` style: folder tabs sitting on a line-drawn content
    /// box. Inactive tabs sit on the box's top border (separated from the content
    /// by it); the active tab's row floats to the bottom and its underside opens
    /// into the content — the border curves around it (`╯ … ╰`) so the tab and
    /// the body read as one surface. The strip is aligned (leading / centre /
    /// trailing) over the box.
    ///
    /// For a single row this matches a classic notebook tab exactly. When the
    /// tabs wrap, upper rows stack as folder-tab strips above the active row; only
    /// the active (bottom) row connects into the content.
    private func renderBordered(
        selectedIndex: Int, isFocused: Bool, palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let surface = surfaceColor(palette)
        let border = palette.border
        let insets = resolvedContentInsets(style: .bordered, context: context)
        let alignment = context.environment.tabViewHeaderAlignment
        let chip = ActiveChipCycle(
            surface: surface, palette: palette, isFocused: isFocused, context: context)
        let (activeFg, inactiveFg, inactiveBg) = stripLabelColors(
            surface: surface, isFocused: isFocused, palette: palette)

        // Size to the widest tab; the strip wraps per the header-wrap mode.
        let avail = max(1, context.availableWidth - 2)
        let widest = widestContentWidth(insets: insets, available: avail, context: context)
        let rows = floatActiveRowToBottom(
            stripRowGroups(
                style: .compact,
                available: stripWrapBudget(widest: widest, available: avail, context: context)),
            selectedIndex: selectedIndex)
        guard !rows.isEmpty else { return FrameBuffer() }
        let chrome = 2 * rows.count + 2  // each row: tops + labels; plus content-border + bottom
        let interior = max(widest, rows.map(folderRowWidth).max() ?? 0)
        let boxWidth = interior + 2

        // Render the content at the full interior width (so a ViewThatFits editor
        // reliably picks its wide layout), then clamp it to its own natural width
        // so the per-line padding below centres it as a block; a tab as wide as
        // the interior clamps to it and fills. (See the compact path.)
        var contentCtx = contentContext(context, stripHeight: chrome)
        contentCtx.availableWidth = interior
        let natural = naturalSelectedWidth(insets: insets, available: avail, context: context)
        let full = TUIkit.renderToBuffer(
            tabs[selectedIndex].content.padding(insets).background(surface), context: contentCtx)
        let content = full.clamped(toWidth: min(natural, interior), height: full.height)

        func bc(_ s: String) -> String { ANSIRenderer.colorize(s, foreground: border) }
        func surf(_ n: Int) -> String {
            n > 0 ? ANSIRenderer.colorize(String(repeating: " ", count: n), background: surface) : ""
        }
        var (lines, regions, animatedCells) = folderStripRows(
            rows: rows, selectedIndex: selectedIndex, chip: chip,
            style: FolderStripStyle(
                activeFg: activeFg, inactiveFg: inactiveFg, inactiveBg: inactiveBg,
                border: border, surface: surface, interior: interior, boxWidth: boxWidth,
                alignment: alignment))

        // Content rows, centred within the interior as one block (a uniform
        // offset, so internal column alignment is preserved), then the bottom.
        //
        // The rows the content may occupy once the strip and borders take
        // theirs. The panel is hard-capped to `availableHeight` (the clamp at
        // the end), so any content beyond this budget could only survive by
        // displacing the bottom border — GitHub issue #13's missing `╰─╯`, with
        // stray interior rows where it should have been. Two ways past the
        // budget, both capped here: a height-flexible tab (a ScrollView, a
        // Spacer) measures its NATURAL height against the full available
        // height, chrome not yet subtracted, so `tallestContentHeight` padded
        // the panel one strip past what fits; and a tab genuinely taller than
        // the terminal. Either way the content clips INSIDE the border, like
        // any other bordered container.
        let contentPad = max(0, (interior - content.width) / 2)
        let contentStartY = lines.count
        let (visibleContent, panelContentHeight) = borderedPanelContent(
            content: content, insets: insets, avail: avail, chrome: chrome, context: context)
        for line in visibleContent.lines {
            let used = line.strippedLength
            lines.append(
                bc("│") + surf(contentPad) + line + surf(max(0, interior - contentPad - used)) + bc("│"))
        }
        // Size the box to the TALLEST tab so switching tabs doesn't change the
        // box height: pad the (selected) content down to that height with
        // surface-filled interior rows before the bottom border.
        while lines.count - contentStartY < panelContentHeight {
            lines.append(bc("│") + surf(interior) + bc("│"))
        }
        lines.append(bc("╰" + String(repeating: "─", count: interior) + "╯"))

        var buffer = FrameBuffer(lines: lines)
        // The strip's rows open the buffer, so the run's coordinates are the
        // buffer's already.
        buffer.animatedCells = context.isMeasuring ? [] : animatedCells
        // Re-attach the content's interactive regions/overlays (slider, toggle, …):
        // the content rows above were rebuilt as fresh strings, so the content
        // buffer's hit regions are not carried automatically. Shift them past the
        // left border + centring pad and down past the tab-strip rows. From the
        // budget-clipped content, so nothing hit-tests against rows not drawn.
        let contentShiftX = 1 + contentPad
        buffer.hitTestRegions.append(
            contentsOf: visibleContent.shiftedHitTestRegions(byX: contentShiftX, y: contentStartY))
        buffer.overlays.append(
            contentsOf: visibleContent.shiftedOverlays(byX: contentShiftX, y: contentStartY))
        // …and the runs, for the same reason and by the same shift: a focused
        // control inside the tab breathes only if its run reaches the root, and
        // the assignment above replaced the buffer's runs with the strip's.
        if !context.isMeasuring {
            buffer.animatedCells.append(
                contentsOf: visibleContent.shiftedAnimatedCells(
                    byX: contentShiftX, y: contentStartY))
        }
        attachTabClicks(to: &buffer, regions: regions, context: context)
        return buffer.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// The budget-clipped content rows and the interior height the panel pads
    /// to — both capped to what fits below the strip, so the bottom border
    /// always survives (GitHub issue #13; see the call site's rationale).
    private func borderedPanelContent(
        content: FrameBuffer, insets: EdgeInsets, avail: Int, chrome: Int, context: RenderContext
    ) -> (visible: FrameBuffer, panelHeight: Int) {
        let budget = max(0, context.availableHeight - chrome)
        let visible =
            content.height > budget
            ? content.clamped(toWidth: content.width, height: budget)
            : content
        let panelHeight = min(
            tallestContentHeight(insets: insets, available: avail, context: context), budget)
        return (visible, panelHeight)
    }

    // MARK: Surface, padding & geometry

    /// The shared surface — a very subtle lift above the base background (the
    /// app-header tone), used for the active tab and the content area so they
    /// read as one continuous surface without an accent fill washing out the
    /// content. Follows `appHeaderBackground` when the palette states one, and
    /// otherwise a derived step off the page — never the page colour itself.
    private func surfaceColor(_ palette: any Palette) -> Color {
        // `liftedBackground`, not `appHeaderBackground`: the latter defaults to
        // the page background, so on a palette that never overrode it the strip
        // painted the colour that was already there and the island vanished.
        palette.liftedBackground.resolve(with: palette)
    }

    /// The interior padding around each tab's content. An explicit
    /// `.tabViewContentPadding(_:)` wins; otherwise bordered gets a comfortable
    /// inset and compact none (the strip already abuts the content).
    private func resolvedContentInsets(style: TabViewStyle, context: RenderContext) -> EdgeInsets {
        if let explicit = context.environment.tabViewContentPadding { return explicit }
        return style == .bordered ? EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2) : EdgeInsets()
    }

    /// Reorders a wrapped strip so the active tab's row sits at the bottom (it
    /// abuts and connects to the content), *rotating* the others so they keep
    /// their cyclic order above it.
    ///
    /// Rotating — rather than just lifting the active row out and appending it —
    /// is what makes Up navigation reach every row. Up always selects the row
    /// directly above the active (bottom) one, which then rotates to the bottom;
    /// rotation feeds a *different* row into the second-from-bottom slot each
    /// time, so repeated Up walks the whole strip. Lifting-and-appending instead
    /// froze the upper rows, leaving Up oscillating between the bottom two.
    private func floatActiveRowToBottom(_ rows: [[Int]], selectedIndex: Int) -> [[Int]] {
        guard rows.count > 1,
            let activeRow = rows.firstIndex(where: { $0.contains(selectedIndex) })
        else { return rows }
        let pivot = (activeRow + 1) % rows.count  // rotate so the active row lands last
        return Array(rows[pivot...] + rows[..<pivot])
    }

    /// A bordered (folder-tab) row's width: each tab body is `" title "`, and the
    /// tabs share `count + 1` vertical walls.
    func folderRowWidth(_ row: [Int]) -> Int {
        row.reduce(0) { $0 + tabWidth($1, style: .bordered) } + (row.count + 1)
    }

    /// A compact row's width: the chips (each `▐ title ▌`) abut with no separator.
    func compactRowWidth(_ row: [Int]) -> Int {
        row.reduce(0) { $0 + tabWidth($1, style: .compact) }
    }

    // MARK: Strip rendering

    /// Per-tab visible width (cells), excluding inter-tab separators. Compact
    /// tabs carry two extra cells for the ◢ ◣ edge caps.
    ///
    /// The title is measured in CELLS, not Characters: a CJK or emoji title
    /// draws two cells per Character, and every width in the strip — row widths,
    /// the panel it sizes, the folder-tab walls, the click regions — is derived
    /// from this one number. Counting Characters here drew a strip wider than it
    /// measured, so the box came out ragged and the click regions slid left of
    /// the tabs they belong to.
    func tabWidth(_ index: Int, style: TabViewStyle) -> Int {
        let body = tabs[index].title.strippedLength + 2   // " title "
        return style == .compact ? body + 2 : body
    }

    /// Cells between adjacent tabs on a row (bordered uses a │; compact's caps
    /// abut, so none).
    private func tabSeparatorWidth(style: TabViewStyle) -> Int {
        style == .bordered ? 1 : 0
    }

    /// The visible width the strip occupies on a single row.
    private func stripVisibleWidth(style: TabViewStyle) -> Int {
        let body = tabs.indices.reduce(0) { $0 + tabWidth($1, style: style) }
        let separators = max(0, tabs.count - 1) * tabSeparatorWidth(style: style)
        return body + separators + (style == .bordered ? 1 : 0)  // bordered: leading │
    }

    /// Groups tab indices into rows that each fit within `available`. Wraps only
    /// when the single-row strip would overflow, then balances the tabs across
    /// the fewest rows so no row hogs the full width — with few tabs (the common
    /// case) this stays one row. A single tab is never split.
    private func stripRowGroups(style: TabViewStyle, available: Int) -> [[Int]] {
        let widths = tabs.indices.map { tabWidth($0, style: style) }
        let sep = tabSeparatorWidth(style: style)
        let total = stripVisibleWidth(style: style)
        let avail = max(1, available)
        let rowCount = max(1, (total + avail - 1) / avail)   // ceil(total / avail)

        // Greedily pack tabs into rows no wider than `cap` (a single tab is never
        // split).
        func pack(cap: Int) -> [[Int]] {
            var rows: [[Int]] = []
            var current: [Int] = []
            var width = 0
            for i in tabs.indices {
                let addend = (current.isEmpty ? 0 : sep) + widths[i]
                if !current.isEmpty && width + addend > cap {
                    rows.append(current)
                    current = []
                    width = 0
                }
                width += (current.isEmpty ? 0 : sep) + widths[i]
                current.append(i)
            }
            if !current.isEmpty { rows.append(current) }
            return rows
        }

        // Start from the balanced target row width, then widen the cap just enough
        // that greedy packing actually fits in `rowCount` rows. Greedy alone can
        // spill an extra (often single-tab) row — e.g. orphaning the last tab on
        // its own line — when the balanced target is a hair too tight.
        var cap = max((total + rowCount - 1) / rowCount, (widths.max() ?? 0) + sep)
        var rows = pack(cap: cap)
        while rows.count > rowCount && cap < avail {
            cap += 1
            rows = pack(cap: cap)
        }
        return rows
    }

    /// Compact: a border-free strip of chips, the active row floated to the
    /// bottom, above the content. The active chip and the content share the
    /// subtle surface, so they read as one island; inactive chips recede onto the
    /// base background.
    private func renderCompact(
        selectedIndex: Int, isFocused: Bool, palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let surface = surfaceColor(palette)
        let insets = resolvedContentInsets(style: .compact, context: context)
        let alignment = context.environment.tabViewHeaderAlignment
        let chip = ActiveChipCycle(
            surface: surface, palette: palette, isFocused: isFocused, context: context)

        // Size to the widest tab; the strip wraps per the header-wrap mode (folded
        // to the content width, or only on overflow).
        let widest = widestContentWidth(insets: insets, available: context.availableWidth, context: context)
        let rows = floatActiveRowToBottom(
            stripRowGroups(
                style: .compact,
                available: stripWrapBudget(widest: widest, available: context.availableWidth, context: context)),
            selectedIndex: selectedIndex)
        let panelWidth = max(widest, rows.map(compactRowWidth).max() ?? 0)

        // Render the content at the full panel width (so a ViewThatFits editor
        // reliably picks its wide single-row layout rather than tipping onto a
        // stacked fallback at a tight width), then clamp it to its own natural
        // width so the leftPad below centres it as a block. A tab as wide as the
        // panel clamps to the panel and fills it (leftPad 0). Clamp preserves the
        // content's hit regions, so its controls stay clickable once centred.
        var contentCtx = contentContext(context, stripHeight: rows.count)
        contentCtx.availableWidth = panelWidth
        let natural = naturalSelectedWidth(insets: insets, available: context.availableWidth, context: context)
        let full = TUIkit.renderToBuffer(
            tabs[selectedIndex].content.padding(insets).background(surface), context: contentCtx)
        let content = full.clamped(toWidth: min(natural, panelWidth), height: full.height)

        let strip = compactStripLines(
            rows: rows, selectedIndex: selectedIndex, isFocused: isFocused,
            surface: surface, chip: chip, palette: palette,
            width: panelWidth, alignment: alignment)
        let (stripLines, regions) = (strip.lines, strip.regions)

        // Centre the content block within the panel as one surface island,
        // shifting it (and its click regions) by a uniform offset so a narrower
        // tab's content is centred without disturbing its internal column
        // alignment (sliders / fields stay lined up).
        func surfFill(_ n: Int) -> String {
            n > 0 ? ANSIRenderer.colorize(String(repeating: " ", count: n), background: surface) : ""
        }
        let leftPad = max(0, (panelWidth - content.width) / 2)
        var centredLines = content.lines.map { line -> String in
            let used = line.strippedLength
            return surfFill(leftPad) + line + surfFill(max(0, panelWidth - leftPad - used))
        }
        // Size the panel to the TALLEST tab so switching tabs doesn't change the
        // panel height: pad the (selected) content down to that height with
        // surface-filled rows, so the shorter tabs read as the same island.
        let panelContentHeight = tallestContentHeight(
            insets: insets, available: context.availableWidth, context: context)
        while centredLines.count < panelContentHeight { centredLines.append(surfFill(panelWidth)) }
        let centredContent = content.replacingLines(centredLines, overlayShiftX: leftPad)

        var buffer = FrameBuffer(lines: stripLines)
        buffer.appendVertically(centredContent)
        // The strip is the top of the buffer, so its coordinates are already
        // the buffer's. (The clamp below drops the run if the chip is off-screen
        // — the run goes with the cells it describes.) Prepended rather than
        // assigned: `appendVertically` already carried the content's own runs
        // up, correctly shifted, and overwriting them froze every focused
        // control inside a tab.
        buffer.animatedCells =
            context.isMeasuring ? [] : strip.animatedCells + buffer.animatedCells
        attachTabClicks(to: &buffer, regions: regions, context: context)
        return buffer.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// Black or white, whichever reads better on `color`.
    static func contrastingForeground(for color: Color, palette: any Palette) -> Color {
        let c = color.resolve(with: palette).rgbComponents ?? (0, 0, 0)
        let luminance = 0.299 * Double(c.red) + 0.587 * Double(c.green) + 0.114 * Double(c.blue)
        return luminance > 140 ? .rgb(0, 0, 0) : .rgb(255, 255, 255)
    }
}

// `TabStripHandler` (the strip's focus/keyboard handler) lives in
// `TabStripHandler.swift`.
