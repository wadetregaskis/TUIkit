//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+ScrollPosition.swift
//
//  The `.scrollPosition` half of _ScrollViewCore: turning a bound ScrollPosition
//  into a scroll (which reuses the seek machinery `scrollTo` already drives)
//  and reporting back the row actually on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// The plumbing lives on the core, which is what renders — `ScrollView`
// itself is the public wrapper.
extension _ScrollViewCore {

    /// The seek a bound ``ScrollPosition`` is asking for this frame, or `nil`.
    ///
    /// Acted on once: the token (or, for the plain `id:` binding, the value
    /// differing from what was last reported) is what distinguishes a fresh
    /// request from the same one still sitting in the binding. Without that,
    /// scrolling away by hand would be undone on the very next frame.
    func positionSeek(handler: ScrollViewHandler, context: RenderContext) -> ScrollToRequest? {
        guard let box = context.environment.scrollPositionBinding else { return nil }
        let position = box.binding.wrappedValue
        guard let target = position.target else { return nil }

        switch target {
        case .id(let value, let anchor):
            let isFresh =
                position.requestToken == 0
                ? handler.lastReportedPositionID != value
                : handler.lastAppliedPositionToken != position.requestToken
            guard isFresh else { return nil }
            handler.lastAppliedPositionToken = position.requestToken
            handler.lastReportedPositionID = value
            // The same stringification `ForEach` derives its keys with, so the
            // comparison in the seek paths is exact.
            return ScrollToRequest(key: identityKey(value.base), anchor: anchor)
        case .edge, .offset:
            // Both are offsets, not rows, so they do not go through the key
            // seek — `applyPositionOffset` moves the scroll view directly.
            return nil
        }
    }

    /// Applies an offset-shaped ``ScrollPosition`` target (an edge or a row
    /// offset), which needs no key seek — the destination is arithmetic.
    func applyPositionOffset(handler: ScrollViewHandler, context: RenderContext) {
        guard let box = context.environment.scrollPositionBinding else { return }
        let position = box.binding.wrappedValue
        guard let target = position.target,
            handler.lastAppliedPositionToken != position.requestToken, position.requestToken > 0
        else { return }
        switch target {
        case .edge(let edge):
            handler.lastAppliedPositionToken = position.requestToken
            // Leading/trailing have no meaning on a vertical scroll; treating
            // them as top/bottom would be inventing behaviour, so they are
            // ignored rather than guessed at.
            switch edge {
            case .top: handler.scrollOffset = 0
            case .bottom:
                handler.scrollOffset = handler.maxOffset
                // The height this used is last frame's; the tail seek re-pins
                // against the height actually rendered.
                handler.seekingTail = true
            case .leading, .trailing: break
            }
        case .offset(let y):
            handler.lastAppliedPositionToken = position.requestToken
            handler.scrollOffset = max(0, min(y, handler.maxOffset))
        case .id:
            break  // Handled by the key seek — see `positionSeek`.
        }
    }

    /// Writes the row now under the anchor back to a bound ``ScrollPosition``.
    ///
    /// Only when it CHANGED. A render pass that wrote its binding every frame
    /// would invalidate its own subtree every frame and never settle — the
    /// same discipline `onPreferenceChange` follows, and for the same reason.
    func reportVisibleID(_ id: AnyHashable, handler: ScrollViewHandler, context: RenderContext) {
        guard let box = context.environment.scrollPositionBinding,
            handler.lastReportedPositionID != id
        else { return }
        handler.lastReportedPositionID = id
        var position = box.binding.wrappedValue
        position.reportVisible(id: id)
        box.binding.wrappedValue = position
    }
}
