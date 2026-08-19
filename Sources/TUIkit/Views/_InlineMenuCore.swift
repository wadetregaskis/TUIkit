//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _InlineMenuCore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The body of ``InlineMenuStyle``: the menu's label as a heading, a rule, and
/// the items expanded beneath it, all in the same bordered column a floating
/// menu uses.
///
/// `Renderable` rather than plain composition for one reason: the rows have to
/// be told the menu's width so their highlight reads as a bar across it, and
/// that width is only known after the column has been measured hugging its
/// content. ``renderMenuColumn(_:context:capHeight:)`` does exactly that, and
/// is shared with the floating presentations so every menu sits on one grid.
struct _InlineMenuCore: View, Renderable, Layoutable {
    let label: MenuStyleConfiguration.Label
    let content: MenuStyleConfiguration.Content

    var body: Never {
        fatalError("_InlineMenuCore renders via Renderable")
    }

    /// An inline menu hugs its widest row and is exactly as tall as it draws,
    /// so one render is its exact measure.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Capped at the height it was offered: a menu with more items than the
        // terminal has rows scrolls inside its border rather than running off
        // the bottom, and the focus reveal keeps the focused item in view as
        // the arrows walk past the edge.
        registerPagingKeys(context: context)
        return renderMenuColumn(column, context: context, capHeight: context.availableHeight)
    }

    @ViewBuilder
    private var column: some View {
        label
            .bold()
            .foregroundStyle(.palette.accent)
        Divider()
        content
    }

    /// Registers the menu's own paging keys: `Page Up`/`Page Down` move the
    /// cursor a screenful of rows, `Home`/`End` to the first and last.
    ///
    /// A menu is a list, and a list's paging keys move its cursor. Left to the
    /// focus ring these keys scroll the enclosing container and deliberately
    /// leave the focus behind — right for a page of prose with a button on it,
    /// wrong for a column that is nothing but rows: the highlight scrolled out
    /// of sight, and the next arrow key snapped the view back to where it had
    /// been left. Registered ahead of the ring (view handlers are layer 2, the
    /// focus system layer 3), and scoped to THIS menu's own rows by identity
    /// path so a menu beside other controls does not page through them.
    private func registerPagingKeys(context: RenderContext) {
        // Registered straight with the dispatcher rather than through
        // `.onKeyPress`: a modifier around the column would hide the rows from
        // `renderMenuColumn`, which walks the content to find them.
        guard !context.isMeasuring,
            let dispatcher = context.environment.keyEventDispatcher,
            let focusManager = context.environment.focusManager
        else { return }
        // The dispatcher clears its handlers every frame, so re-registering is
        // per-frame presence — declare it, or a memoised replay would drop it.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let path = context.identity.path
        // One screenful of rows: the height the menu was offered, less its own
        // chrome (two border rows, the label, and the rule under it).
        let page = max(1, context.availableHeight - 4)
        dispatcher.addHandler(sectionID: context.environment.activeFocusSectionID) { event in
            let jump: FocusManager.SubtreeFocusJump
            switch event.key {
            case .pageUp: jump = .backward(page)
            case .pageDown: jump = .forward(page)
            case .home: jump = .first
            case .end: jump = .last
            default: return false
            }
            return focusManager.moveFocus(inSubtreeAt: path, jump: jump)
        }
    }
}
