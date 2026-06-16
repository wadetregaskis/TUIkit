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
        let stripHeight = stripRowCount(style: style, available: ctx.availableWidth)
        let stripWidth = stripWrappedWidth(style: style, available: ctx.availableWidth)

        let contentSize = ChildView(tabs[selectedIndex].content).measure(
            proposal: ProposedSize(width: ctx.availableWidth, height: nil),
            context: contentContext(ctx, stripHeight: stripHeight))

        return ViewSize(
            width: max(stripWidth, contentSize.width),
            height: stripHeight + contentSize.height,
            isWidthFlexible: contentSize.isWidthFlexible,
            isHeightFlexible: false)
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
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Strip.
        let selected = selectedIndex
        var strip = renderStrip(
            style: style, selectedIndex: selected, isFocused: isFocused && !isDisabled,
            palette: palette, context: context)

        // Selected content, isolated per tab. Its background matches the active
        // tab's, so the active tab (whose row sits at the bottom of the strip)
        // flows into the content as one surface.
        let activeBg = Self.activeTabBackground(palette: palette, isFocused: isFocused && !isDisabled)
        let stripHeight = strip.height
        let content = TUIkit.renderToBuffer(
            tabs[selected].content.background(activeBg),
            context: contentContext(context, stripHeight: stripHeight))

        strip.appendVertically(content)
        return strip.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// The active tab's background — the accent, dimmed when the strip isn't
    /// focused. Shared by the active chip and the content area so they match.
    static func activeTabBackground(palette: any Palette, isFocused: Bool) -> Color {
        let accent = palette.accent.resolve(with: palette)
        return isFocused ? accent : accent.opacity(ViewConstants.focusBorderDim)
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

    /// The rows + rule the strip occupies for the given available width.
    private func stripRowCount(style: TabViewStyle, available: Int) -> Int {
        stripRowGroups(style: style, available: available).count + (style == .bordered ? 1 : 0)
    }

    /// The widest laid-out row, for sizing the panel to the wrapped strip.
    private func stripWrappedWidth(style: TabViewStyle, available: Int) -> Int {
        let sep = tabSeparatorWidth(style: style)
        return stripRowGroups(style: style, available: available).map { row in
            row.reduce(0) { $0 + tabWidth($1, style: style) }
                + max(0, row.count - 1) * sep + (style == .bordered ? 1 : 0)
        }.max() ?? 0
    }

    private func renderStrip(
        style: TabViewStyle, selectedIndex: Int, isFocused: Bool,
        palette: any Palette, context: RenderContext
    ) -> FrameBuffer {
        let activeBg = Self.activeTabBackground(palette: palette, isFocused: isFocused)
        let inactiveBg = palette.border.resolve(with: palette)
        let activeFg = Self.contrastingForeground(for: activeBg, palette: palette)
        let inactiveFg = Self.contrastingForeground(for: inactiveBg, palette: palette)

        // The active tab's whole row moves to the bottom of the stack so it sits
        // directly above the content (matching backgrounds, they read as one).
        var groups = stripRowGroups(style: style, available: context.availableWidth)
        if let activeRow = groups.firstIndex(where: { $0.contains(selectedIndex) }),
            activeRow != groups.count - 1 {
            groups.append(groups.remove(at: activeRow))
        }
        var lines: [String] = []
        var regions: [(x: Int, y: Int, width: Int, index: Int)] = []
        var maxWidth = 0

        for (y, row) in groups.enumerated() {
            var line = style == .bordered ? ANSIRenderer.colorize("│", foreground: palette.border) : ""
            var x = style == .bordered ? 1 : 0
            for (j, i) in row.enumerated() {
                let active = i == selectedIndex
                let body = " \(tabs[i].title) "
                if style == .compact {
                    // A coloured chip: active and inactive tabs use distinct
                    // backgrounds. The caps are half-blocks drawn in the chip's
                    // colour over the surrounding default — ▐ fills the right half
                    // of the leading cell and ▌ the left half of the trailing one,
                    // so the chip's fill extends half a cell each side with a
                    // clean, solid edge. (The corner-triangle glyphs ◢ ◣ render
                    // far smaller than a cell in Terminal.app, so they don't.)
                    let chip = active ? activeBg : inactiveBg
                    let chipFg = active ? activeFg : inactiveFg
                    line += ANSIRenderer.colorize("▐", foreground: chip)
                    line += ANSIRenderer.colorize(body, foreground: chipFg, background: chip, bold: active)
                    line += ANSIRenderer.colorize("▌", foreground: chip)
                    regions.append((x: x, y: y, width: body.count + 2, index: i))
                    x += body.count + 2
                } else {
                    let seg = active
                        ? ANSIRenderer.colorize(body, foreground: activeFg, background: activeBg, bold: true)
                        : ANSIRenderer.colorize(body, foreground: palette.foregroundSecondary)
                    regions.append((x: x, y: y, width: body.count, index: i))
                    line += seg
                    x += body.count
                    if j < row.count - 1 || style == .bordered {
                        line += ANSIRenderer.colorize("│", foreground: palette.border)
                        x += 1
                    }
                }
            }
            maxWidth = max(maxWidth, x)
            lines.append(line)
        }
        if style == .bordered {
            // A rule beneath the tabs that ties the strip to the content.
            lines.append(ANSIRenderer.colorize(
                String(repeating: "─", count: maxWidth), foreground: palette.border))
        }
        var buffer = FrameBuffer(lines: lines)

        // Mouse: clicking a tab selects it (row index → the region's y offset).
        if !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher {
            let focusManager = context.environment.focusManager
            let captureFocusID = persistedFocusIDForClicks(context)
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
        return buffer
    }

    private func persistedFocusIDForClicks(_ context: RenderContext) -> String {
        FocusRegistration.persistFocusID(
            context: context, explicitFocusID: nil, defaultPrefix: "tabview",
            propertyIndex: StateIndex.focusID)
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
