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
        var child = context.withBranchIdentity("tab-\(selection.wrappedValue)")
        child.availableHeight = max(0, context.availableHeight - stripHeight)
        return child
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard !tabs.isEmpty else { return ViewSize.fixed(0, 0) }
        let style = context.environment.tabViewStyle.resolved
        var ctx = context
        ctx.availableWidth = proposal.width ?? context.availableWidth
        let insets = resolvedContentInsets(style: style, context: ctx)

        if style == .bordered {
            // Box chrome: each tab row is 2 lines (tab tops + labels), plus the
            // content-border line and the bottom border; the box adds a 1-cell
            // border on each side.
            let rows = stripRowGroups(style: .compact, available: max(1, ctx.availableWidth - 2))
            let chrome = 2 * rows.count + 2
            let contentSize = ChildView(tabs[selectedIndex].content.padding(insets)).measure(
                proposal: ProposedSize(width: max(0, ctx.availableWidth - 2), height: nil),
                context: contentContext(ctx, stripHeight: chrome))
            let interior = max(contentSize.width, rows.map(folderRowWidth).max() ?? 0)
            return ViewSize(
                width: interior + 2, height: chrome + contentSize.height,
                isWidthFlexible: false, isHeightFlexible: false)
        }

        // Compact: one line per wrapped tab row, then the content.
        let rows = stripRowGroups(style: style, available: ctx.availableWidth)
        let contentSize = ChildView(tabs[selectedIndex].content.padding(insets)).measure(
            proposal: ProposedSize(width: ctx.availableWidth, height: nil),
            context: contentContext(ctx, stripHeight: rows.count))
        let panelWidth = max(contentSize.width, rows.map(compactRowWidth).max() ?? 0)
        return ViewSize(
            width: panelWidth, height: rows.count + contentSize.height,
            isWidthFlexible: contentSize.isWidthFlexible, isHeightFlexible: false)
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

    /// Moves the active tab's whole row to the bottom of a wrapped strip, so it
    /// sits directly above (and connects to) the content.
    private func floatActiveRowToBottom(_ rows: [[Int]], selectedIndex: Int) -> [[Int]] {
        var rows = rows
        if let activeRow = rows.firstIndex(where: { $0.contains(selectedIndex) }),
            activeRow != rows.count - 1 {
            rows.append(rows.remove(at: activeRow))
        }
        return rows
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
        let target = (total + rowCount - 1) / rowCount       // balance across rows
        let cap = max(target, (widths.max() ?? target) + sep)
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

        let rows = floatActiveRowToBottom(
            stripRowGroups(style: .compact, available: context.availableWidth),
            selectedIndex: selectedIndex)

        let content = TUIkit.renderToBuffer(
            tabs[selectedIndex].content.padding(insets).background(surface),
            context: contentContext(context, stripHeight: rows.count))

        let panelWidth = max(content.width, rows.map(compactRowWidth).max() ?? 0)
        let (stripLines, regions) = compactStripLines(
            rows: rows, selectedIndex: selectedIndex, isFocused: isFocused,
            surface: surface, activeBg: activeBg, palette: palette,
            width: panelWidth, alignment: alignment)

        // The content fills the full panel width as one surface island (so a
        // narrower content still backs the whole row beneath wider tabs).
        let paddedContent = content.replacingLines(content.lines.map { line in
            let used = line.strippedLength
            return used < panelWidth
                ? line + ANSIRenderer.colorize(
                    String(repeating: " ", count: panelWidth - used), background: surface)
                : line
        })

        var buffer = FrameBuffer(lines: stripLines)
        buffer.appendVertically(paddedContent)
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

        let rows = floatActiveRowToBottom(
            stripRowGroups(style: .compact, available: max(1, context.availableWidth - 2)),
            selectedIndex: selectedIndex)
        guard !rows.isEmpty else { return FrameBuffer() }
        let chrome = 2 * rows.count + 2  // each row: tops + labels; plus content-border + bottom

        let content = TUIkit.renderToBuffer(
            tabs[selectedIndex].content.padding(insets).background(surface),
            context: contentContext(context, stripHeight: chrome))

        let interior = max(content.width, rows.map(folderRowWidth).max() ?? 0)
        let boxWidth = interior + 2

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
                let rightActive = k < row.count && row[k] == selectedIndex
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

        // Content rows (filled to the interior with surface), then the bottom.
        for line in content.lines {
            let used = line.strippedLength
            lines.append(bc("│") + line + surf(interior - used) + bc("│"))
        }
        lines.append(bc("╰" + String(repeating: "─", count: interior) + "╯"))

        var buffer = FrameBuffer(lines: lines)
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

/// Switches the active tab with the left/right arrow keys when the strip is
/// focused.
final class TabStripHandler: Focusable {
    let focusID: String
    var canBeFocused: Bool
    var selection: Binding<AnyHashable>
    var values: [AnyHashable]

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

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .left: move(by: -1); return true
        case .right: move(by: 1); return true
        default: return false
        }
    }
}
