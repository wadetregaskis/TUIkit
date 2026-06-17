//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabView.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Tab extraction

/// A tab recovered from the content closure before its value has been matched
/// to the `TabView`'s concrete selection-value type. Mirrors `_RawPickerOption`.
struct _RawTab {
    let value: AnyHashable
    let title: String
    let content: AnyView
    /// Measures the tab's content (padded by the given interior insets) at its
    /// *concrete* type. Captured in `Tab.tabs()` before the content is erased to
    /// `AnyView`, so a `Layoutable` child (e.g. a `ScrollView`) is sized via its
    /// `sizeThatFits` (its content's size) rather than `AnyView`'s
    /// render-to-measure fallback (which would render a flexible child to fill
    /// the viewport, defeating size-to-content).
    let measure: @MainActor (EdgeInsets, ProposedSize, RenderContext) -> ViewSize
}

/// A view that can contribute tabs to a ``TabView``.
///
/// Mirrors the `PickerOptionProvider` pattern: rather than reflecting over the
/// view tree, each view type that may appear in a tab-view content closure
/// declares how to surface its tabs. `TupleView` / `ForEach` recurse.
@MainActor
protocol TabContentProvider {
    func tabs() -> [_RawTab]
}

extension EmptyView: TabContentProvider {
    func tabs() -> [_RawTab] { [] }
}

extension TupleView: TabContentProvider {
    func tabs() -> [_RawTab] {
        var result: [_RawTab] = []
        func collect<Child: View>(_ view: Child) {
            if let provider = view as? TabContentProvider {
                result.append(contentsOf: provider.tabs())
            }
        }
        repeat collect(each children)
        return result
    }
}

extension ForEach: TabContentProvider {
    func tabs() -> [_RawTab] {
        data.flatMap { element -> [_RawTab] in
            (content(element) as? TabContentProvider)?.tabs() ?? []
        }
    }
}

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

    /// Creates a tab with a title, selection value, and content.
    ///
    /// - Parameters:
    ///   - title: The tab's label in the strip.
    ///   - value: The value this tab is selected by (matches the `TabView`'s
    ///     selection binding).
    ///   - content: The view shown while this tab is selected.
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
        let content = self.content  // concrete, captured before AnyView erasure
        return [
            _RawTab(
                value: AnyHashable(value), title: title, content: AnyView(content),
                measure: { insets, proposal, context in
                    ChildView(content.padding(insets)).measure(proposal: proposal, context: context)
                })
        ]
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

    var resolved: TabViewStyle { self == .automatic ? .compact : self }
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

// MARK: - Header alignment (TUI-specific)

private struct TabViewHeaderAlignmentKey: EnvironmentKey {
    static let defaultValue: HorizontalAlignment = .center
}

extension EnvironmentValues {
    /// How the tab strip is aligned across the width of a `TabView`.
    public var tabViewHeaderAlignment: HorizontalAlignment {
        get { self[TabViewHeaderAlignmentKey.self] }
        set { self[TabViewHeaderAlignmentKey.self] = newValue }
    }
}

extension View {
    /// Aligns the tab headers (leading, centre, or trailing) within `TabView`s
    /// in this view. Defaults to ``HorizontalAlignment/center``.
    ///
    /// TUI-specific: SwiftUI has no equivalent, so this is kept separate from the
    /// SwiftUI-parity ``tabViewStyle(_:)``.
    public func tabViewHeaderAlignment(_ alignment: HorizontalAlignment) -> some View {
        environment(\.tabViewHeaderAlignment, alignment)
    }
}

// MARK: - Header wrapping (TUI-specific)

/// How eagerly a `TabView` wraps its header strip onto multiple rows.
public enum TabViewHeaderWrap: Sendable {
    /// Keep the headers on as few rows as fit the available width — wrap only
    /// when a single row would overflow. The panel may be as wide as the
    /// one-row strip. The default.
    case minimal
    /// Fold the headers to the width of the widest tab's content, even when
    /// there's room for fewer rows — so a many-tabbed view (a colour picker)
    /// stays as narrow as its content instead of being stretched wide by a long
    /// header strip.
    case toContentWidth
}

private struct TabViewHeaderWrapKey: EnvironmentKey {
    static let defaultValue: TabViewHeaderWrap = .minimal
}

extension EnvironmentValues {
    /// How `TabView`s in this view wrap their header strip.
    public var tabViewHeaderWrap: TabViewHeaderWrap {
        get { self[TabViewHeaderWrapKey.self] }
        set { self[TabViewHeaderWrapKey.self] = newValue }
    }
}

extension View {
    /// Controls how eagerly `TabView`s in this view wrap their header strip.
    /// Defaults to ``TabViewHeaderWrap/minimal`` (wrap only on overflow).
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    public func tabViewHeaderWrap(_ wrap: TabViewHeaderWrap) -> some View {
        environment(\.tabViewHeaderWrap, wrap)
    }
}

// MARK: - Content padding (TUI-specific)

private struct TabViewContentPaddingKey: EnvironmentKey {
    /// `nil` means "use the per-style default" (none for ``TabViewStyle/compact``,
    /// a comfortable inset for ``TabViewStyle/bordered``).
    static let defaultValue: EdgeInsets? = nil
}

extension EnvironmentValues {
    /// The interior padding applied around every tab's content. `nil` resolves
    /// to the per-style default.
    public var tabViewContentPadding: EdgeInsets? {
        get { self[TabViewContentPaddingKey.self] }
        set { self[TabViewContentPaddingKey.self] = newValue }
    }
}

extension View {
    /// Sets the interior padding around the content of every tab in `TabView`s
    /// within this view. Applied to the full content subtree, so a single
    /// application on the `TabView` covers all of its tabs.
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    public func tabViewContentPadding(_ insets: EdgeInsets) -> some View {
        environment(\.tabViewContentPadding, insets)
    }

    /// Sets a uniform interior padding around every tab's content.
    public func tabViewContentPadding(_ length: Int) -> some View {
        environment(\.tabViewContentPadding, EdgeInsets(all: length))
    }
}

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
    /// Per-tab measured content widths (`[tab value: width]`), so the panel can
    /// size to the widest tab without re-measuring every tab each pass.
    static let widthCache = 2
}

/// Renders the tab strip plus the selected tab's content.
///
/// The selected content is rendered under a value-keyed *branch identity*, so
/// each tab's subtree (and its `@State`) is isolated — switching tabs can't
/// alias one tab's state onto another's.
private struct _TabViewCore<SelectionValue: Hashable>: View, Renderable, Layoutable {
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
        return child
    }

    /// The widest tab's natural (unconstrained) content width — the panel sizes to
    /// it (stable across tab switches) and the strip folds to it, rather than a
    /// wide strip ballooning the panel. Capped to what's available.
    ///
    /// Only the *selected* tab is measured each pass; the others reuse their last
    /// measured width from a per-tab cache. Measuring every tab each pass would
    /// fully render the non-`Layoutable` tabs (channel editors, the 139/216/256-
    /// swatch grids) hundreds of cells at a time — pathologically slow. A tab not
    /// yet seen is measured once to seed its entry. So the selected tab tracks its
    /// own `@State` (e.g. the 256-grid's "show numbers"), and the panel holds the
    /// widest of all tabs without re-rendering them.
    ///
    /// The cache is a pure memo keyed by content identity (it can only ever equal
    /// what a measure would compute), so writing it during a measure pass is
    /// benign — it doesn't perturb layout, only avoids recomputation.
    private func widestContentWidth(
        insets: EdgeInsets, available: Int, context: RenderContext
    ) -> Int {
        let cap = { (w: Int) in min(max(1, w), max(1, available)) }
        func measureTab(_ index: Int) -> Int {
            var branch = context.withBranchIdentity("tab-\(tabs[index].value)")
            branch.availableWidth = available
            return tabs[index].measure(insets, ProposedSize(width: nil, height: nil), branch).width
        }
        guard let stateStorage = context.environment.stateStorage else {
            return cap(measureTab(selectedIndex))
        }
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.widthCache)
        let box: StateBox<[AnyHashable: Int]> = stateStorage.storage(for: key, default: [:])
        var cache = box.value
        cache[AnyHashable(tabs[selectedIndex].value)] = measureTab(selectedIndex)
        for (i, tab) in tabs.enumerated() where cache[AnyHashable(tab.value)] == nil {
            cache[AnyHashable(tab.value)] = measureTab(i)  // one-time seed per tab
        }
        let present = Set(tabs.map { AnyHashable($0.value) })
        cache = cache.filter { present.contains($0.key) }  // drop removed tabs
        box.value = cache
        let widest = tabs.map { cache[AnyHashable($0.value)] ?? 0 }.max() ?? 0
        return cap(widest)
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
        return max(1, tabs[selectedIndex].measure(
            insets, ProposedSize(width: nil, height: nil), branch).width)
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
                let bodyWidth = bordered ? tabs[i].title.count + 2 : tabWidth(i, style: .compact)
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
            let contentSize = tabs[selectedIndex].measure(
                insets, ProposedSize(width: avail, height: nil),
                contentContext(ctx, stripHeight: chrome))
            let interior = max(widest, rows.map(folderRowWidth).max() ?? 0)
            return ViewSize(
                width: interior + 2, height: chrome + contentSize.height,
                isWidthFlexible: false, isHeightFlexible: false)
        }

        // Compact: size to the widest tab; the strip wraps per the header-wrap
        // mode and the selected content is centred within it.
        let widest = widestContentWidth(insets: insets, available: ctx.availableWidth, context: ctx)
        let rows = stripRowGroups(
            style: style,
            available: stripWrapBudget(widest: widest, available: ctx.availableWidth, context: ctx))
        let contentSize = tabs[selectedIndex].measure(
            insets, ProposedSize(width: ctx.availableWidth, height: nil),
            contentContext(ctx, stripHeight: rows.count))
        let panelWidth = max(widest, rows.map(compactRowWidth).max() ?? 0)
        return ViewSize(
            width: panelWidth, height: rows.count + contentSize.height,
            isWidthFlexible: false, isHeightFlexible: false)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !tabs.isEmpty else { return FrameBuffer() }
        let style = context.environment.tabViewStyle.resolved
        let palette = context.environment.palette
        let isDisabled = !context.environment.isEnabled

        // Focus handler (arrow-key tab switching).
        let stateStorage = context.environment.stateStorage!
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

        if style == .bordered {
            return renderBordered(
                selectedIndex: selected, isFocused: isFocused, palette: palette, context: context)
        }
        return renderCompact(
            selectedIndex: selected, isFocused: isFocused, palette: palette, context: context)
    }

    // MARK: Surface, padding & geometry

    /// The shared surface — a very subtle lift above the base background (the
    /// app-header tone), used for the active tab and the content area so they
    /// read as one continuous surface without an accent fill washing out the
    /// content. Behaves like `statusBarBackground` / `appHeaderBackground`: on a
    /// palette that doesn't tint those, it collapses to the base background.
    private func surfaceColor(_ palette: any Palette) -> Color {
        palette.appHeaderBackground.resolve(with: palette)
    }

    /// The active tab chip's background. When the strip is focused it breathes
    /// toward the accent on the pulse clock, so the active tab is easy to find on
    /// a busy screen; otherwise it's the quiet shared surface.
    ///
    /// `pulsePhase` is read from the environment only in the focused branch — that
    /// volatile read is what keeps the pulse timer (and the per-frame re-renders)
    /// running, so an unfocused tab view costs nothing.
    private func activeChipBackground(
        surface: Color, palette: any Palette, isFocused: Bool, context: RenderContext
    ) -> Color {
        guard isFocused else { return surface }
        return Color.lerp(
            surface, palette.accent.opacity(ViewConstants.buttonCapPulseBright),
            phase: context.environment.pulsePhase)
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
    private func folderRowWidth(_ row: [Int]) -> Int {
        row.reduce(0) { $0 + tabs[$1].title.count + 2 } + (row.count + 1)
    }

    /// A compact row's width: the chips (each `▐ title ▌`) abut with no separator.
    private func compactRowWidth(_ row: [Int]) -> Int {
        row.reduce(0) { $0 + tabWidth($1, style: .compact) }
    }

    // MARK: Strip rendering

    /// Per-tab visible width (cells), excluding inter-tab separators. Compact
    /// tabs carry two extra cells for the ◢ ◣ edge caps.
    private func tabWidth(_ index: Int, style: TabViewStyle) -> Int {
        let body = tabs[index].title.count + 2   // " title "
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
        let activeBg = activeChipBackground(
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

        let (stripLines, regions) = compactStripLines(
            rows: rows, selectedIndex: selectedIndex, isFocused: isFocused,
            surface: surface, activeBg: activeBg, palette: palette,
            width: panelWidth, alignment: alignment)

        // Centre the content block within the panel as one surface island,
        // shifting it (and its click regions) by a uniform offset so a narrower
        // tab's content is centred without disturbing its internal column
        // alignment (sliders / fields stay lined up).
        func surfFill(_ n: Int) -> String {
            n > 0 ? ANSIRenderer.colorize(String(repeating: " ", count: n), background: surface) : ""
        }
        let leftPad = max(0, (panelWidth - content.width) / 2)
        let centredContent = content.replacingLines(
            content.lines.map { line in
                let used = line.strippedLength
                return surfFill(leftPad) + line + surfFill(max(0, panelWidth - leftPad - used))
            }, overlayShiftX: leftPad)

        var buffer = FrameBuffer(lines: stripLines)
        buffer.appendVertically(centredContent)
        attachTabClicks(to: &buffer, regions: regions, context: context)
        return buffer.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// Lays out the wrapped, aligned compact chip rows. Returns the lines (each
    /// padded to `width`) and the per-tab click regions in strip coordinates.
    private func compactStripLines(
        rows: [[Int]], selectedIndex: Int, isFocused: Bool,
        surface: Color, activeBg: Color, palette: any Palette,
        width: Int, alignment: HorizontalAlignment
    ) -> (lines: [String], regions: [(x: Int, y: Int, width: Int, index: Int)]) {
        let activeFg = isFocused
            ? palette.accent.resolve(with: palette)
            : Self.contrastingForeground(for: surface, palette: palette)
        let inactiveFg = palette.foregroundSecondary
        let inactiveBg = palette.background.resolve(with: palette)
        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int, index: Int)] = []

        for (y, row) in rows.enumerated() {
            let offset = max(0, alignment.childOffset(childWidth: compactRowWidth(row), in: width))
            var line = String(repeating: " ", count: offset)
            var x = offset
            for i in row {
                let active = i == selectedIndex
                let body = " \(tabs[i].title) "
                // A coloured chip: the half-block caps (▐ … ▌) extend the chip's
                // fill half a cell each side with a clean edge. The active chip
                // takes the surface (breathing when focused) + bold; inactive
                // chips recede onto the base background.
                let chip = active ? activeBg : inactiveBg
                let chipFg = active ? activeFg : inactiveFg
                line += ANSIRenderer.colorize("▐", foreground: chip)
                line += ANSIRenderer.colorize(body, foreground: chipFg, background: chip, bold: active)
                line += ANSIRenderer.colorize("▌", foreground: chip)
                regions.append((x: x, y: y, width: body.count + 2, index: i))
                x += body.count + 2
            }
            if x < width { line += String(repeating: " ", count: width - x) }
            lines.append(line)
        }
        return (lines, regions)
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
                focusManager.focus(id: captureFocusID)
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
        let activeBg = activeChipBackground(
            surface: surface, palette: palette, isFocused: isFocused, context: context)
        let activeFg = isFocused
            ? palette.accent.resolve(with: palette)
            : Self.contrastingForeground(for: surface, palette: palette)
        let inactiveFg = palette.foregroundSecondary
        let inactiveBg = palette.background.resolve(with: palette)

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
        func base(_ n: Int) -> String { n > 0 ? String(repeating: " ", count: n) : "" }
        // The absolute box column of a row's left wall, per the strip alignment.
        func rowOffset(_ rowWidth: Int) -> Int {
            1 + max(0, alignment.childOffset(childWidth: rowWidth, in: interior))
        }

        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int, index: Int)] = []

        for (rowIndex, row) in rows.enumerated() {
            let isBottom = rowIndex == rows.count - 1
            let off = rowOffset(folderRowWidth(row))

            // Walls (count + 1) and bodies for this row, in absolute columns.
            var wallCols: [Int] = []
            var bodySpans: [(start: Int, len: Int, index: Int)] = []
            var col = off
            for i in row {
                wallCols.append(col)
                let bw = tabs[i].title.count + 2
                bodySpans.append((start: col + 1, len: bw, index: i))
                col += 1 + bw
            }
            wallCols.append(col)

            // Tab tops: the whole strip span is border-coloured, so emit it as one
            // run — `╭`/`╮` for active corners & strip ends, `┬` for shared walls.
            var top = ""
            for k in wallCols.indices {
                let leftActive = k > 0 && row[k - 1] == selectedIndex
                // The active tab's box closes with `╭ … ╮` so it reads as raised;
                // but a wall shared with an inactive neighbour can only carry one
                // glyph, so the active's right corner (`╮`) wins there while its
                // left corner falls back to a flush `┬` (a backwards `╭` on the
                // neighbour would look wrong). At a strip end the corner is clean.
                if k == 0 { top += "╭" }
                else if k == wallCols.count - 1 { top += "╮" }
                else if leftActive { top += "╮" }
                else { top += "┬" }
                if k < bodySpans.count { top += String(repeating: "─", count: bodySpans[k].len) }
            }
            lines.append(base(off) + bc(top) + base(boxWidth - off - top.count))

            // Tab labels: `│ title │ title │ …`, the active chip on the surface.
            let labelsY = lines.count
            var labels = base(off)
            for (k, i) in row.enumerated() {
                let active = i == selectedIndex
                labels += bc("│")
                labels += ANSIRenderer.colorize(
                    " \(tabs[i].title) ",
                    foreground: active ? activeFg : inactiveFg,
                    background: active ? activeBg : inactiveBg, bold: active)
                regions.append((x: bodySpans[k].start, y: labelsY, width: bodySpans[k].len, index: i))
            }
            labels += bc("│")
            lines.append(labels + base(boxWidth - off - folderRowWidth(row)))

            // Under the active (bottom) row: the content box's top border, curving
            // up to wrap the active tab and opening (surface gap) beneath it.
            if isBottom {
                let activeWall = wallCols.firstIndex { wc in
                    bodySpans.contains { $0.index == selectedIndex && $0.start == wc + 1 }
                } ?? 0
                let aLeft = wallCols[activeWall]
                let aBody = bodySpans.first { $0.index == selectedIndex }!
                let aRight = aBody.start + aBody.len
                let inactiveWalls = Set(wallCols).subtracting([aLeft, aRight])
                func borderGlyph(_ c: Int) -> String {
                    if c == 0 { return "╭" }
                    if c == boxWidth - 1 { return "╮" }
                    if c == aLeft { return "╯" }
                    if c == aRight { return "╰" }
                    return inactiveWalls.contains(c) ? "┴" : "─"
                }
                var left = ""
                for c in 0..<aBody.start { left += borderGlyph(c) }
                var right = ""
                for c in aRight..<boxWidth { right += borderGlyph(c) }
                lines.append(bc(left) + surf(aBody.len) + bc(right))
            }
        }

        // Content rows, centred within the interior as one block (a uniform
        // offset, so internal column alignment is preserved), then the bottom.
        let contentPad = max(0, (interior - content.width) / 2)
        let contentStartY = lines.count
        for line in content.lines {
            let used = line.strippedLength
            lines.append(
                bc("│") + surf(contentPad) + line + surf(max(0, interior - contentPad - used)) + bc("│"))
        }
        lines.append(bc("╰" + String(repeating: "─", count: interior) + "╯"))

        var buffer = FrameBuffer(lines: lines)
        // Re-attach the content's interactive regions/overlays (slider, toggle, …):
        // the content rows above were rebuilt as fresh strings, so the content
        // buffer's hit regions are not carried automatically. Shift them past the
        // left border + centring pad and down past the tab-strip rows.
        let contentShiftX = 1 + contentPad
        buffer.hitTestRegions.append(
            contentsOf: content.shiftedHitTestRegions(byX: contentShiftX, y: contentStartY))
        buffer.overlays.append(
            contentsOf: content.shiftedOverlays(byX: contentShiftX, y: contentStartY))
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

// MARK: - Focus handler

/// Switches the active tab with the arrow keys when the strip is focused:
/// left/right step through the tabs in order; up/down move between rows of a
/// wrapped strip, to the tab nearest above/below the current one's centre.
final class TabStripHandler: Focusable {
    let focusID: String
    var canBeFocused: Bool
    var selection: Binding<AnyHashable>
    var values: [AnyHashable]

    /// The visual rows (tab indices, top-to-bottom) and each tab's horizontal
    /// centre, refreshed each render so up/down navigation matches the layout.
    var rows: [[Int]] = []
    var centers: [Int: Int] = [:]

    init(focusID: String, selection: Binding<AnyHashable>, values: [AnyHashable], canBeFocused: Bool = true) {
        self.focusID = focusID
        self.selection = selection
        self.values = values
        self.canBeFocused = canBeFocused
    }

    private func move(by delta: Int) {
        guard !values.isEmpty else { return }
        let current = values.firstIndex(of: selection.wrappedValue) ?? 0
        let next = max(0, min(values.count - 1, current + delta))
        selection.wrappedValue = values[next]
    }

    /// Moves to the tab nearest (by centre) in the row `delta` rows away, or
    /// returns `false` when there is no such row — so the key bubbles up and
    /// focus can leave the strip (e.g. to the control above/below the TabView).
    private func moveVertically(_ delta: Int) -> Bool {
        let current = values.firstIndex(of: selection.wrappedValue) ?? 0
        guard let row = rows.firstIndex(where: { $0.contains(current) }) else { return false }
        let target = row + delta
        guard rows.indices.contains(target) else { return false }
        let cx = centers[current] ?? 0
        guard let nearest = rows[target].min(by: {
            abs((centers[$0] ?? 0) - cx) < abs((centers[$1] ?? 0) - cx)
        }) else { return false }
        selection.wrappedValue = values[nearest]
        return true
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .left: move(by: -1); return true
        case .right: move(by: 1); return true
        case .up: return moveVertically(-1)
        case .down: return moveVertically(1)
        default: return false
        }
    }
}
