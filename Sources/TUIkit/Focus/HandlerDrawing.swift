//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HandlerDrawing.swift
//
//  What a control draws of ITSELF from the handler object it keeps between
//  frames, and the report that drops those pictures from the render cache when
//  an input moves that state between frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

/// The cached pictures of a control that draws part of itself from its handler
/// object, captured where the control registers the input that moves that
/// state.
///
/// A handler is a class held in the control's `@State`, so writing one of its
/// properties is not a `@State` write: the box never sees it, and the render
/// cache hears nothing. That was always fine for a control that holds the
/// focus, because a focused control's registration cannot be replayed and
/// nothing containing it is stored. It is not fine for the inputs that reach a
/// control WITHOUT focusing it — a drag from elsewhere hovering a `List`, the
/// wheel over a `ScrollView`, the pointer passing over its scrollbar or over a
/// resizable view's edge, a drag held at its edge — because a control that
/// does not hold the focus makes only replayable registrations, and the
/// `ForEach` row or `.equatable()` view around it is stored like any other.
/// It was then served as it was stored: the gap under the pointer never
/// opened, and the content never moved under the wheel.
///
/// So such an input reports the control through this. Only the control's own
/// buffers and those containing it are dropped, and its sizes are kept: what
/// these inputs move — a drop gap, a scroll position, a lit scrollbar cell — is
/// drawn by the control itself over content that has not changed, and none of
/// it moves the control's size. That is the scope a focus move onto a
/// `ScrollView` uses (`FocusDrawnOnlyAtItself`), and for the same reason: the
/// rows below are served from their own memos, exactly as they are when the
/// same control is scrolled from the keyboard.
///
/// Applied at once rather than queued, as a focus move is: the inputs arrive
/// on the main actor, between frames or at the top of one, and each already
/// asks for the frame that draws it (a consumed event, a drag that is still
/// driving). The one report made DURING a render — a `List` re-aiming its drop
/// gap after drawing (``ItemListHandler/drawing``) — relies on the same
/// immediacy: a memo still rendering around the list sees the clear and
/// declines to store.
///
/// The cache is reached through its ``RenderCache/Link``, not a reference of
/// its own. Not a strong one, since a stored buffer's journal keeps the
/// closures that hold this, and the cache keeps the buffer. And not a weak one:
/// a `List` or `Table` stamps its handler with this on every render, and the
/// first weak reference to the cache puts every retain and release of it, for
/// the rest of its life, through the runtime's slow path — 20,111 a frame on
/// the `app-shapes` sidebar, where nothing else referenced it weakly
/// (counted 2026-09-27).
struct HandlerDrawing {
    private let link: RenderCache.Link?
    private let identity: ViewIdentity

    /// The pictures of the control `context` is rendering.
    init(_ context: RenderContext) {
        link = context.renderCache?.link
        identity = context.identity
    }

    /// Drops the control's own cached buffers and those containing it.
    func changed() {
        link?.cache?.clearAffected(by: identity, keepingSizes: true, includingDescendants: false)
    }

    /// Runs `body`, and reports a change when `state` reads differently after
    /// it than before.
    ///
    /// A comparison rather than a report on every call, because the inputs
    /// that reach here mostly move nothing: a drag hovering a list crosses a
    /// row boundary a few times in the dozens of reports it makes, and each
    /// report is a walk of the whole cache.
    func reportingChanges<State: Equatable, Result>(
        to state: () -> State, around body: () -> Result
    ) -> Result {
        let before = state()
        let result = body()
        if state() != before { changed() }
        return result
    }
}

// MARK: - Scrollables

/// What an input can move of a scrollable's own picture without focusing it:
/// where the content sits, by row and by line within one, how far past an edge
/// it has been pulled, and which scrollbar cell is lit under the pointer.
///
/// The wheel scrolls whatever it is over, focused or not; the pointer lifts a
/// scrollbar's cells as it passes; a click on a "N more" line pages. Each is
/// compared through this, so an event that moved none of it — the pointer
/// resting on the same cell, a click on a row — reports nothing. See
/// ``HandlerDrawing``.
struct DrawnScrollPosition: Equatable {
    let offset: Int
    let subRowLines: Int
    let excursion: Int
    let hoveredBarCell: Int?

    /// `state`'s position, with `subRowLines` for a scrollable that can stop
    /// partway through a row — a `List` or `Table` with rows taller than a
    /// line.
    init(_ state: some ScrollableOffsetState, subRowLines: Int = 0) {
        offset = state.scrollOffset
        self.subRowLines = subRowLines
        excursion = state.overscrollState.excursion
        hoveredBarCell = state.hoveredBarCell
    }
}

extension ItemListHandler {
    /// This list's or table's ``DrawnScrollPosition``, the lines scrolled off
    /// its top row included.
    var drawnPosition: DrawnScrollPosition {
        DrawnScrollPosition(self, subRowLines: scrollTopClipLines)
    }
}

extension ScrollViewHandler {
    /// This scroll view's ``DrawnScrollPosition`` on each axis, vertical first.
    var drawnPositions: [DrawnScrollPosition] {
        [DrawnScrollPosition(self), DrawnScrollPosition(horizontal)]
    }
}
