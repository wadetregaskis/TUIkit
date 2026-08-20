//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionEffects.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

extension AnyTransition.Effect {
    /// The buffer as it looks when the view is `phase` present — `1` fully
    /// there, `0` gone.
    ///
    /// Every effect keeps the buffer's SHAPE. A transition that changed its
    /// size would reflow the page on each frame, which is both expensive and
    /// the wrong picture: the slot is already the size it will end up, and what
    /// moves is what is drawn in it.
    @MainActor
    func apply(to buffer: FrameBuffer, phase: Double, context: RenderContext) -> FrameBuffer {
        let clamped = min(1, max(0, phase))
        guard clamped < 1 else { return buffer }
        switch self {
        case .identity:
            return buffer
        case .opacity:
            return Self.faded(buffer, by: clamped, context: context)
        case .move(let edge):
            let away = 1 - clamped
            switch edge {
            case .leading: return Self.translated(buffer, dx: -Self.scaled(buffer.width, away), dy: 0)
            case .trailing: return Self.translated(buffer, dx: Self.scaled(buffer.width, away), dy: 0)
            case .top: return Self.translated(buffer, dx: 0, dy: -Self.scaled(buffer.height, away))
            case .bottom: return Self.translated(buffer, dx: 0, dy: Self.scaled(buffer.height, away))
            }
        case .offset(let x, let y):
            let away = 1 - clamped
            return Self.translated(buffer, dx: Self.scaled(x, away), dy: Self.scaled(y, away))
        case .scale(let anchor):
            return Self.revealed(buffer, by: clamped, anchor: anchor)
        case .combined(let first, let second):
            return second.apply(
                to: first.apply(to: buffer, phase: phase, context: context),
                phase: phase, context: context)
        }
    }

    private static func scaled(_ extent: Int, _ fraction: Double) -> Int {
        Int((Double(extent) * fraction).rounded())
    }
}

// MARK: - The effects themselves

extension AnyTransition.Effect {
    /// Blends every colour the buffer names toward the background — the same
    /// fade ``View/opacity(_:)`` performs, and for the same reason: a terminal
    /// cell has no alpha, so the only thing that can dissolve is the colour.
    @MainActor
    private static func faded(
        _ buffer: FrameBuffer, by factor: Double, context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let defaultForeground = palette.foreground.resolve(with: palette)
        return buffer.replacingLines(
            buffer.lines.map {
                OpacityFade.fading(
                    $0, by: factor, over: surface, defaultForeground: defaultForeground)
            })
    }

    /// The buffer moved by whole cells within its own frame, with whatever
    /// slides past the edge clipped and the vacated cells blank.
    private static func translated(_ buffer: FrameBuffer, dx: Int, dy: Int) -> FrameBuffer {
        guard dx != 0 || dy != 0 else { return buffer }
        let width = buffer.width
        let blank = String(repeating: " ", count: max(0, width))
        var moved: [String] = []
        moved.reserveCapacity(buffer.lines.count)

        for row in buffer.lines.indices {
            let source = row - dy
            guard source >= 0, source < buffer.lines.count else {
                moved.append(blank)
                continue
            }
            let line = buffer.lines[source].padToVisibleWidth(width)
            moved.append(shifted(line, by: dx, within: width, blank: blank))
        }
        return buffer.replacingLines(moved)
    }

    /// One line moved sideways within `width`.
    private static func shifted(
        _ line: String, by dx: Int, within width: Int, blank: String
    ) -> String {
        guard dx != 0 else { return line }
        guard abs(dx) < width else { return blank }
        if dx > 0 {
            let kept = line.ansiAwareSlice(visibleStart: 0, visibleCount: width - dx)
            return (String(repeating: " ", count: dx) + kept).padToVisibleWidth(width)
        }
        let dropped = -dx
        return line.ansiAwareSlice(visibleStart: dropped, visibleCount: width - dropped)
            .padToVisibleWidth(width)
    }

    /// The buffer revealed from `anchor`, a whole cell at a time.
    ///
    /// SwiftUI scales; a terminal cannot. There is no sub-cell rendering to
    /// shrink, so what this does instead is uncover the view from its anchor —
    /// which reads as the same gesture and is exact rather than approximate.
    private static func revealed(
        _ buffer: FrameBuffer, by factor: Double, anchor: UnitPoint
    ) -> FrameBuffer {
        let width = buffer.width
        let height = buffer.lines.count
        let shownWidth = Int((Double(width) * factor).rounded())
        let shownHeight = Int((Double(height) * factor).rounded())
        let originX = Int((Double(width - shownWidth) * anchor.x).rounded())
        let originY = Int((Double(height - shownHeight) * anchor.y).rounded())
        let blank = String(repeating: " ", count: max(0, width))

        var revealed: [String] = []
        revealed.reserveCapacity(height)
        for row in 0..<height {
            guard row >= originY, row < originY + shownHeight, shownWidth > 0 else {
                revealed.append(blank)
                continue
            }
            let line = buffer.lines[row].padToVisibleWidth(width)
            let kept = line.ansiAwareSlice(visibleStart: originX, visibleCount: shownWidth)
            revealed.append(
                (String(repeating: " ", count: originX) + kept).padToVisibleWidth(width))
        }
        return buffer.replacingLines(revealed)
    }
}
