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
        renderMenuColumn(column, context: context, capHeight: context.availableHeight)
    }

    @ViewBuilder
    private var column: some View {
        label
            .bold()
            .foregroundStyle(.palette.accent)
        Divider()
        content
    }
}
