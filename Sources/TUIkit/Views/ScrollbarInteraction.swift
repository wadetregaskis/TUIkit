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

// MARK: - Hit testing

/// Which part of a scrollbar a coordinate falls on.
enum ScrollbarHit: Equatable {
    /// The start arrow (top of a vertical bar, left of a horizontal one).
    case arrowStart
    /// The end arrow (bottom / right).
    case arrowEnd
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
            if position < perEnd { return .arrowStart }
            if position >= length - perEnd { return .arrowEnd }
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
    /// Builds the mouse handler for a vertical scrollbar `length` cells tall that
    /// drives `state`: the arrows step by one, a track click pages or jumps per
    /// `behavior`, and a press on the thumb begins a drag that the dispatcher
    /// routes here until release. Returns `true` for any left-button event on the
    /// bar so it is consumed.
    ///
    /// Works in the bar's own units, which are `state`'s units for a `ScrollView`
    /// and a single-line `Table` (one line per row); for a `List` whose bar is
    /// measured in lines while its offset is in rows, dragging is proportional
    /// rather than exact, which is acceptable for the uncommon variable-height case.
    static func verticalMouseHandler(
        for state: ScrollableOffsetState, length: Int, arrows: ScrollbarArrows,
        proportional: Bool, behavior: ScrollbarClickBehavior
    ) -> (MouseEvent) -> Bool {
        { event in
            guard event.button == .left else { return false }
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
                    position: event.y, length: length, extent: extent, viewport: viewport,
                    offset: state.scrollOffset, arrows: arrows, proportional: proportional)
                switch hit {
                case .arrowStart:
                    state.scroll(by: -1)
                case .arrowEnd:
                    state.scroll(by: 1)
                case .trackBefore, .trackAfter:
                    if behavior == .jump {
                        let thumbCells = thumbCellCount(
                            trackLen: trackLen, extent: extent, viewport: viewport,
                            proportional: proportional)
                        jumpOrDrag(topCell: (event.y - perEnd) - thumbCells / 2)
                    } else if case .trackBefore = hit {
                        state.scroll(by: -max(1, viewport))
                    } else {
                        state.scroll(by: max(1, viewport))
                    }
                case .thumb(let grab):
                    state.scrollbarDragGrab = grab
                case .outside:
                    return false
                }
                return true
            case .dragged:
                guard let grab = state.scrollbarDragGrab else { return false }
                jumpOrDrag(topCell: (event.y - perEnd) - grab)
                return true
            case .released:
                state.scrollbarDragGrab = nil
                return true
            default:
                return false
            }
        }
    }
}
