//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// An inline menu hugs its widest row and is exactly as tall as it draws —
    /// which is what ``renderMenuColumn(_:context:capHeight:borderColor:)``
    /// works out before it draws anything, so
    /// ``measureMenuColumn(_:context:capHeight:borderColor:)`` asks for that
    /// plan and stops there.
    ///
    /// It used to be one render, discarded. That is the difference between four
    /// walks of a menu's tree per frame and three: the parent stack measures
    /// this view before it renders it, and both used to draw the whole column.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var measureContext = context
        measureContext.isMeasuring = true
        // The same preparation `measureFixedByRendering` did before rendering:
        // the proposal becomes the space, and no explicit width, so the rows
        // hug rather than fill.
        measureContext.hasExplicitWidth = false
        if let width = proposal.width { measureContext.availableWidth = width }
        if let height = proposal.height { measureContext.availableHeight = height }
        // `renderToBuffer` sets this for the rows before it calls through; the
        // measure has to agree, or a row reports a different verb's width.
        measureContext.environment.isInsideMenu = true
        return measureMenuColumn(
            column, context: measureContext, capHeight: measureContext.availableHeight)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Capped at the height it was offered: a menu with more items than the
        // terminal has rows scrolls inside its border rather than running off
        // the bottom, and the focus reveal keeps the focused item in view as
        // the arrows walk past the edge.
        registerPagingKeys(context: context)
        // The rows are page focus stops (that is what "inline" means), so
        // nothing else marks them as belonging to a menu — and a `Button` that
        // does not know it is in one says Return "activates" it rather than
        // chooses from the menu around it.
        var menuContext = context
        menuContext.environment.isInsideMenu = true
        return renderMenuColumn(
            column, context: menuContext, capHeight: context.availableHeight)
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
        guard !context.isMeasuring, context.environment.keyEventDispatcher != nil,
            context.environment.focusManager != nil
        else { return }
        // The dispatcher clears its handlers every frame, so re-registering is
        // per-frame presence. Declared as REPLAYABLE: a memo serving the menu
        // registers the keys again from the entry recorded below.
        context.environment.volatileReadTracker?.recordReplayableEffect()
        let path = context.identity.path
        // One screenful of rows: the height the menu was offered, less its own
        // chrome (two border rows, the label, and the rule under it).
        let page = max(1, context.availableHeight - 4)
        let sectionID = context.environment.activeFocusSectionID
        InlineMenuPagingRegistrar.register(path: path, page: page, sectionID: sectionID, context: context)
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: InlineMenuPagingRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    InlineMenuPagingRegistrar.register(
                        path: path, page: page, sectionID: sectionID, context: replay)
                })
        }
    }
}

// MARK: - Registration

/// The paging keys an inline menu registers, shared by the live render and by a
/// value memo replaying them — see `EffectJournal`.
enum InlineMenuPagingRegistrar {
    /// The journal kind of an inline menu's paging keys.
    static let kind = EffectJournal.Kind("inlineMenuPaging")

    /// Registers Page Up/Down, Home and End for the menu at `path`, moving the
    /// focus among its rows `page` at a time.
    ///
    /// The dispatcher AND the focus manager are looked up in `context`, not
    /// handed in: a replay belongs to a later walk, and the manager in force
    /// there is the one the rows registered with.
    @MainActor
    static func register(path: String, page: Int, sectionID: String?, context: RenderContext) {
        guard let dispatcher = context.environment.keyEventDispatcher,
            let focusManager = context.environment.focusManager
        else { return }
        dispatcher.addHandler(sectionID: sectionID) { event in
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
