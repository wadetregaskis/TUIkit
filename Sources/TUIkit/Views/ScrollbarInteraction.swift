//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarInteraction.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Click behaviour

/// What happens when the *track* of a scrollbar (not the thumb or an arrow) is
/// clicked.
public enum ScrollbarClickBehavior: Sendable, Hashable, CaseIterable {
    /// Move one viewport towards the click (the classic scrollbar behaviour).
    case page
    /// Jump so the thumb centres on the clicked spot.
    case jump
}

private struct ScrollbarClickBehaviorKey: EnvironmentKey {
    static let defaultValue: ScrollbarClickBehavior = .page
}

extension EnvironmentValues {
    /// How a click on a scrollbar's track behaves. Defaults to
    /// ``ScrollbarClickBehavior/page``.
    public var scrollbarClickBehavior: ScrollbarClickBehavior {
        get { self[ScrollbarClickBehaviorKey.self] }
        set { self[ScrollbarClickBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Sets how a click on a scrollbar's track behaves within this view — paging
    /// towards the click (default) or jumping to it. The thumb is always
    /// draggable and the end arrows always step by one regardless.
    public func scrollbarClickBehavior(_ behavior: ScrollbarClickBehavior) -> some View {
        environment(\.scrollbarClickBehavior, behavior)
    }
}

// MARK: - Auto-repeat

/// A scroll action that repeats while a scrollbar arrow (or a `.page`-mode track)
/// is held down. Terminals send no key/button auto-repeat, so the bar's owner
/// drives it from the render loop (see ``ScrollbarRenderer/driveAutoRepeat``).
public struct ScrollbarRepeat: Sendable, Equatable {
    /// The offset delta applied on each repeat tick (±1 for an arrow, ±viewport
    /// for a page-track hold).
    public var delta: Int
    /// The absolute time of the next tick, in nanoseconds (`environment.frameNowNanos`
    /// scale). `0` means "not yet scheduled" — the driver seeds it with the initial
    /// delay the first frame it sees the hold.
    public var nextFireNanos: Int64

    public init(delta: Int, nextFireNanos: Int64 = 0) {
        self.delta = delta
        self.nextFireNanos = nextFireNanos
    }
}

extension ScrollbarRenderer {
    /// The pause before a held arrow/track starts repeating (like a key-repeat
    /// delay), then the gap between repeats.
    static let autoRepeatInitialDelayNanos: Int64 = 400_000_000
    static let autoRepeatIntervalNanos: Int64 = 60_000_000

    /// Drives a held scrollbar's auto-repeat. Call it each frame from the bar's
    /// owner (with a bar shown): while `state.scrollbarRepeat` is set it keeps the
    /// run loop waking and scrolls by the repeat delta once the initial delay has
    /// passed and then every interval. The hold's mouse handler sets the repeat on
    /// press and clears it on release.
    @MainActor
    static func driveAutoRepeat(
        state: ScrollableOffsetState, token: String, context: RenderContext
    ) {
        guard !context.isMeasuring, var repeating = state.scrollbarRepeat else { return }
        // Keep the loop ticking while held so the deadline below is checked.
        context.requestAnimation(token: token, frequency: 20)
        let now = context.environment.frameNowNanos
        if repeating.nextFireNanos == 0 {
            repeating.nextFireNanos = now + autoRepeatInitialDelayNanos
        } else if now >= repeating.nextFireNanos {
            state.scroll(by: repeating.delta)
            repeating.nextFireNanos = now + autoRepeatIntervalNanos
        }
        state.scrollbarRepeat = repeating
    }
}

// MARK: - Hit testing

/// Which part of a scrollbar a coordinate falls on.
enum ScrollbarHit: Equatable {
    /// An arrow button; `delta` is the direction it scrolls — `-1` toward the
    /// start (`▲` / `◀`), `+1` toward the end (`▼` / `▶`). With `.double` arrows
    /// both arrows appear at *each* end, so the direction is decided by which
    /// glyph was hit, not by which end of the bar it sits at.
    case arrow(delta: Int)
    /// The track before the thumb (above / left of it).
    case trackBefore
    /// The thumb; `grab` is the offset of the hit within the thumb, in cells.
    case thumb(grab: Int)
    /// The track after the thumb (below / right of it).
    case trackAfter
    /// Outside the bar entirely.
    case outside
}

extension ScrollbarRenderer {
    /// Classifies a bar-relative `position` (0 at the start of the bar) against a
    /// bar `length` cells long, using the same thumb geometry as ``trackCells``.
    static func hitTest(
        position: Int, length: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool
    ) -> ScrollbarHit {
        guard position >= 0, position < length else { return .outside }
        let perEnd = (length > arrowReserve(arrows) ? arrowReserve(arrows) : 0) / 2
        if perEnd > 0 {
            if position < perEnd {
                return .arrow(delta: arrowDelta(sub: position, perEnd: perEnd, atHead: true))
            }
            if position >= length - perEnd {
                return .arrow(delta: arrowDelta(sub: position - (length - perEnd), perEnd: perEnd, atHead: false))
            }
        }
        let trackLen = length - 2 * perEnd
        guard trackLen > 0 else { return .outside }
        let trackPos = position - perEnd
        let span = thumbSpan(
            count: trackLen, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional)
        let firstCell = span.start / 8
        let lastCell = (span.end - 1) / 8
        if trackPos < firstCell { return .trackBefore }
        if trackPos > lastCell { return .trackAfter }
        return .thumb(grab: trackPos - firstCell)
    }

    /// The scroll direction (−1 toward the start, +1 toward the end) for a click on
    /// an arrow cell `sub` cells into an end's `perEnd`-cell arrow region. With
    /// `.double` arrows (`perEnd == 2`) each end renders `[▲, ▼]` (`[◀, ▶]`), so the
    /// sub-position alone decides direction — the *same* at both ends, which is why
    /// the up-arrow at the bottom end must scroll up, not down. With `.single`
    /// (`perEnd == 1`) the head is `▲`/`◀` and the tail is `▼`/`▶`.
    private static func arrowDelta(sub: Int, perEnd: Int, atHead: Bool) -> Int {
        if perEnd >= 2 { return sub == 0 ? -1 : 1 }
        return atHead ? -1 : 1
    }

    /// The thumb length in whole cells for a `trackLen`-cell track (constant for a
    /// given extent/viewport, so the offset is immaterial).
    static func thumbCellCount(
        trackLen: Int, extent: Int, viewport: Int, proportional: Bool
    ) -> Int {
        let span = thumbSpan(
            count: trackLen, extent: extent, viewport: viewport, offset: 0, proportional: proportional)
        return max(1, (span.end - 1) / 8 - span.start / 8 + 1)
    }

    /// The scroll offset that places the thumb's top (left) edge at `topCell` of
    /// the track, clamped to the valid range.
    static func offset(
        forThumbTopCell topCell: Int, trackLen: Int, extent: Int, viewport: Int,
        proportional: Bool
    ) -> Int {
        let thumbCells = thumbCellCount(
            trackLen: trackLen, extent: extent, viewport: viewport, proportional: proportional)
        let travel = max(1, trackLen - thumbCells)
        let maxOffset = max(0, extent - viewport)
        let clamped = max(0, min(travel, topCell))
        return Int((Double(clamped) / Double(travel) * Double(maxOffset)).rounded())
    }
}

// MARK: - Mouse handler

extension ScrollbarRenderer {
    /// Builds the mouse handler for a scrollbar `length` cells long that drives
    /// `state`: the arrows step by one, a track click pages or jumps per `behavior`,
    /// and a press on the thumb begins a drag that the dispatcher routes here until
    /// release. `vertical` picks which localized coordinate is the bar position —
    /// `event.y` for a vertical bar, `event.x` for a horizontal one. Returns `true`
    /// for any left-button event on the bar so it is consumed.
    ///
    /// Works in the bar's own units, which are `state`'s units for a `ScrollView`
    /// (each axis) and a single-line `Table` (one line per row); for a `List` whose
    /// bar is measured in lines while its offset is in rows, dragging is
    /// proportional rather than exact, acceptable for the uncommon variable-height
    /// case.
    static func mouseHandler(
        for state: ScrollableOffsetState, length: Int, vertical: Bool,
        arrows: ScrollbarArrows, proportional: Bool, behavior: ScrollbarClickBehavior
    ) -> (MouseEvent) -> Bool {
        { event in
            guard event.button == .left else { return false }
            let position = vertical ? event.y : event.x
            let perEnd = (length > arrowReserve(arrows) ? arrowReserve(arrows) : 0) / 2
            let trackLen = max(1, length - 2 * perEnd)
            let extent = state.extent
            let viewport = state.viewportHeight

            func jumpOrDrag(topCell: Int) {
                state.scrollOffset = offset(
                    forThumbTopCell: topCell, trackLen: trackLen, extent: extent,
                    viewport: viewport, proportional: proportional)
            }

            switch event.phase {
            case .pressed:
                let hit = hitTest(
                    position: position, length: length, extent: extent, viewport: viewport,
                    offset: state.scrollOffset, arrows: arrows, proportional: proportional)
                switch hit {
                case .arrow(let delta):
                    // Step in the clicked arrow's own direction (with `.double`
                    // arrows the bottom end has an up-arrow too), then auto-repeat
                    // while held (see driveAutoRepeat).
                    state.scroll(by: delta)
                    state.scrollbarRepeat = ScrollbarRepeat(delta: delta)
                case .trackBefore, .trackAfter:
                    if behavior == .jump {
                        let thumbCells = thumbCellCount(
                            trackLen: trackLen, extent: extent, viewport: viewport,
                            proportional: proportional)
                        jumpOrDrag(topCell: (position - perEnd) - thumbCells / 2)
                        // Jump-to-spot implicitly grabs the thumb (centred under the
                        // cursor), so the press turns into a drag and the thumb
                        // follows the mouse until release — per macOS.
                        state.scrollbarDragGrab = thumbCells / 2
                    } else {
                        // Page towards the click now, then auto-repeat the paging
                        // while the track stays held.
                        let pageDelta = (hit == .trackBefore) ? -max(1, viewport) : max(1, viewport)
                        state.scroll(by: pageDelta)
                        state.scrollbarRepeat = ScrollbarRepeat(delta: pageDelta)
                    }
                case .thumb(let grab):
                    state.scrollbarDragGrab = grab
                case .outside:
                    return false
                }
                return true
            case .dragged:
                guard let grab = state.scrollbarDragGrab else { return false }
                jumpOrDrag(topCell: (position - perEnd) - grab)
                return true
            case .released:
                state.scrollbarDragGrab = nil
                state.scrollbarRepeat = nil
                return true
            default:
                return false
            }
        }
    }

    /// Vertical convenience wrapper over ``mouseHandler(for:length:vertical:arrows:proportional:behavior:)``
    /// — the bar position is `event.y`.
    static func verticalMouseHandler(
        for state: ScrollableOffsetState, length: Int, arrows: ScrollbarArrows,
        proportional: Bool, behavior: ScrollbarClickBehavior
    ) -> (MouseEvent) -> Bool {
        mouseHandler(
            for: state, length: length, vertical: true,
            arrows: arrows, proportional: proportional, behavior: behavior)
    }

    /// Horizontal convenience wrapper over ``mouseHandler(for:length:vertical:arrows:proportional:behavior:)``
    /// — the bar position is `event.x`.
    static func horizontalMouseHandler(
        for state: ScrollableOffsetState, length: Int, arrows: ScrollbarArrows,
        proportional: Bool, behavior: ScrollbarClickBehavior
    ) -> (MouseEvent) -> Bool {
        mouseHandler(
            for: state, length: length, vertical: false,
            arrows: arrows, proportional: proportional, behavior: behavior)
    }
}
