//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionDisabledModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that disables selection for a view within a List.
///
/// When applied to a list row, `.selectionDisabled()` refuses to let that row
/// become the `List`'s selection: Enter/Space and a click on it do nothing
/// (``ItemListHandler/toggleSelectionAtFocusedIndex()``), and it renders with
/// a dimmed foreground to show it.
///
/// Reported to the enclosing `List` the same way `.deleteDisabled()` /
/// `.moveDisabled()` are — as the row renders, via ``RowEditRestrictions``,
/// rather than by inspecting the row's structure, so a modifier written
/// outside this one (`.selectionDisabled(_:).padding()`) still counts. That
/// also means the restriction is only known for a row that has actually
/// drawn: Up/Down and Page Up/Page Down route around a `.selectionDisabled()`
/// row once it has rendered at least once (``ItemListHandler/moveFocus(by:wrap:)``),
/// the same on-screen-only guarantee `.deleteDisabled()` documents — Home and
/// End jump straight to a boundary and do not yet consult it.
///
/// ## Usage
///
/// ```swift
/// List(selection: $selection) {
///     ForEach(items) { item in
///         Text(item.name)
///             .selectionDisabled(item.isLocked)
///     }
/// }
/// ```
public struct SelectionDisabledModifier<Content: View>: View {
    /// The content to apply selection disabled to.
    let content: Content

    /// Whether selection is disabled.
    let isDisabled: Bool

    public var body: Never {
        fatalError("SelectionDisabledModifier renders via Renderable")
    }
}

// MARK: - Equatable

extension SelectionDisabledModifier: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: SelectionDisabledModifier<Content>, rhs: SelectionDisabledModifier<Content>) -> Bool {
        lhs.content == rhs.content && lhs.isDisabled == rhs.isDisabled
    }
}

// MARK: - Renderable

extension SelectionDisabledModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        report(context)
        let buffer = TUIkit.renderToBuffer(content, context: context)
        guard isDisabled else { return buffer }
        // The doc's "dimmed foreground" promise — the same persistent-faint
        // primitive the List's own held-row preview uses, which restates
        // itself after every reset a multi-run row's content already
        // contains (see `ANSIRenderer.applyPersistentDim`). Everything else
        // about the buffer (hit regions, badges, opacity claims) is carried
        // through unchanged; only the drawn colour changes.
        var dimmed = buffer
        dimmed.lines = buffer.lines.map(ANSIRenderer.applyPersistentDim)
        return dimmed
    }

    /// Tells the enclosing `List` this row refuses to be selected.
    ///
    /// The same per-frame collector, and the same side-effect-declaring
    /// asymmetry, `.deleteDisabled()` / `.moveDisabled()` use (see
    /// `_RowEditRestrictionView.report(_:)`): only when actually disabled does
    /// this opt the row out of the render memo, so a row that never uses this
    /// modifier — or uses it with `false` — pays nothing and memoizes exactly
    /// as before. A refusal that stayed memo-eligible would be reported once
    /// and then silently forgotten on every frame the cache served instead of
    /// re-rendering.
    private func report(_ context: RenderContext) {
        guard isDisabled, !context.isMeasuring,
            let restrictions = context.environment.listRowEditRestrictions,
            let row = restrictions.currentRowIndex
        else { return }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        restrictions.disableSelection(row: row)
    }
}

// MARK: - Layoutable

extension SelectionDisabledModifier: Layoutable {
    /// Measures `content` unchanged: dimming a row's colour does not change
    /// its size, and measurement never reports a restriction (`report(_:)`
    /// guards `!context.isMeasuring`, matching `.deleteDisabled()`).
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
