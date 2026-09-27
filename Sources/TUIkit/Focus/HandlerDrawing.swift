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
/// nothing containing it is stored. It is not fine for an input that reaches a
/// control WITHOUT focusing it — a drag from elsewhere hovering a `List` —
/// because a control that does not hold the focus makes only replayable
/// registrations, and the `ForEach` row or `.equatable()` view around it is
/// stored like any other. It was then served as it was stored: the gap under
/// the pointer never opened.
///
/// So such an input reports the control through this. Only the control's own
/// buffers and those containing it are dropped, and its sizes are kept: what
/// such an input moves — a drop gap — is drawn by the control itself over rows
/// that have not changed, and does not move the control's size. That is the
/// scope a focus move onto a `ScrollView` uses (`FocusDrawnOnlyAtItself`), and
/// for the same reason: the rows below are served from their own memos.
///
/// Applied at once rather than queued, as a focus move is: the input arrives
/// on the main actor, between frames, and already asks for the frame that
/// draws it (the drag's events are consumed). Held weakly, since a stored
/// buffer's journal keeps the closures that hold this, and the cache keeps the
/// buffer.
struct HandlerDrawing {
    private weak var cache: RenderCache?
    private let identity: ViewIdentity

    /// The pictures of the control `context` is rendering.
    init(_ context: RenderContext) {
        cache = context.renderCache
        identity = context.identity
    }

    /// Drops the control's own cached buffers and those containing it.
    func changed() {
        cache?.clearAffected(by: identity, keepingSizes: true, includingDescendants: false)
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
