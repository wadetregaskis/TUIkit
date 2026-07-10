//  🖥️ TUIKit — Terminal UI Kit for Swift
//  OverlayLayer.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Overlay Level

/// The semantic stacking level of an ``OverlayLayer``.
///
/// Layers composite onto the root buffer in ascending level order: a
/// `.popover` draws beneath an `.alert`, which draws beneath a `.modal`,
/// which draws beneath a `.notification`. Within a single level,
/// ``OverlayLayer/zIndex`` breaks ties.
public enum OverlayLevel: Int, Sendable, Comparable, CaseIterable {
    /// A lightweight popover anchored to a control (e.g. a `Picker` drop-down).
    case popover

    /// A modal alert.
    case alert

    /// A modal sheet or dialog.
    case modal

    /// A transient notification or toast.
    case notification

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Overlay Layer

/// A free-floating layer composited above the in-flow content at render time.
///
/// Overlay layers let a view draw outside its own bounds — a `Picker`
/// drop-down, a popover, a modal — without disturbing the layout of its
/// siblings. The layer rides along with the ``FrameBuffer`` it was emitted
/// into: every combining operation (`appendVertically`, `appendHorizontally`,
/// `composited`, …) shifts the layer's offset by the same amount it shifts the
/// buffer's lines. By the time the buffer reaches the root its ``offsetX`` /
/// ``offsetY`` are absolute, and `RenderLoop` composites every accumulated
/// layer in z-order.
///
/// - Important: This is framework infrastructure. Views emit overlay layers
///   by populating ``FrameBuffer/overlays``.
public struct OverlayLayer: Sendable, Equatable {
    /// The column offset of the layer's top-left corner, relative to the
    /// top-left of the ``FrameBuffer`` that carries it.
    public var offsetX: Int

    /// The row offset of the layer's top-left corner, relative to the
    /// top-left of the ``FrameBuffer`` that carries it.
    public var offsetY: Int

    /// The layer's rendered content.
    public var content: FrameBuffer

    /// The semantic stacking level.
    public var level: OverlayLevel

    /// The fine-grained stacking order within a ``level`` (higher draws later).
    public var zIndex: Double

    /// The height of the anchoring control sitting immediately above
    /// ``offsetY``.
    ///
    /// When the layer would overflow the bottom edge of the screen the
    /// compositor flips it to sit *above* the anchor instead. This value
    /// lets it compute the flipped position: the layer's bottom is placed
    /// flush with the top of the anchor. A value of `0` disables flipping
    /// (the layer is simply clamped on screen).
    public var anchorHeight: Int

    /// When `true`, the layer ignores ``offsetX`` / ``offsetY`` and is centred
    /// in the composite area instead (used by screen-level modals/alerts, which
    /// must centre on the whole screen regardless of where in the tree they were
    /// attached). Anchored overlays (popovers) leave this `false`.
    public var centered: Bool

    /// When `true`, the compositor dims everything beneath this layer before
    /// drawing it — a flat, inert backdrop so the layer reads as modal. Used by
    /// modals/alerts; popovers and notifications leave this `false`.
    public var dimsBackground: Bool

    /// Creates an overlay layer.
    ///
    /// - Parameters:
    ///   - offsetX: The column offset of the layer's top-left corner.
    ///   - offsetY: The row offset of the layer's top-left corner.
    ///   - content: The layer's rendered content.
    ///   - level: The semantic stacking level (default: `.popover`).
    ///   - zIndex: The fine-grained order within the level (default: `0`).
    ///   - anchorHeight: The height of the anchoring control above the layer,
    ///     used for flip-on-overflow placement (default: `0`).
    ///   - centered: Centre in the composite area, ignoring the offset (default: `false`).
    ///   - dimsBackground: Dim everything beneath before drawing (default: `false`).
    public init(
        offsetX: Int,
        offsetY: Int,
        content: FrameBuffer,
        level: OverlayLevel = .popover,
        zIndex: Double = 0,
        anchorHeight: Int = 0,
        centered: Bool = false,
        dimsBackground: Bool = false
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.content = content
        self.level = level
        self.zIndex = zIndex
        self.anchorHeight = anchorHeight
        self.centered = centered
        self.dimsBackground = dimsBackground
    }

    /// Resolves this layer's on-screen placement within a `maxWidth` × `maxHeight`
    /// content area: the (clamped) content plus the column and row to draw it at.
    ///
    /// The content is clamped to the screen first, so it can never exceed it — a
    /// too-tall popover keeps its top rows, so its text still shows even when it
    /// can't fit. If it would then overflow the bottom edge it is flipped to sit
    /// *above* its anchor (when ``anchorHeight`` allows); otherwise it is nudged
    /// back up. The same nudge keeps it within the right edge.
    public func placed(maxWidth: Int, maxHeight: Int) -> (content: FrameBuffer, x: Int, y: Int) {
        let clamped = content.clamped(toWidth: maxWidth, height: maxHeight)
        let height = clamped.height
        let width = clamped.width

        // Screen-level overlays (modals/alerts) centre on the whole composite
        // area. ``offsetX`` / ``offsetY`` are then a post-centre delta — zero for
        // an untouched dialog, non-zero once the user has dragged it — clamped so
        // the whole dialog always stays on screen (never partly off, unlike a
        // typical GUI).
        if centered {
            let centeredX = (maxWidth - width) / 2 + offsetX
            let centeredY = (maxHeight - height) / 2 + offsetY
            let x = min(max(0, centeredX), max(0, maxWidth - width))
            let y = min(max(0, centeredY), max(0, maxHeight - height))
            return (clamped, x, y)
        }

        var y = offsetY
        if y + height > maxHeight {
            // Try flipping above the anchoring control; else nudge back on screen.
            let flipped = offsetY - anchorHeight - height
            y = flipped >= 0 ? flipped : max(0, maxHeight - height)
        }
        y = max(0, y)

        var x = offsetX
        if x + width > maxWidth {
            x = max(0, maxWidth - width)
        }
        x = max(0, x)

        return (clamped, x, y)
    }

    /// Returns a copy of this layer with its offset shifted by `(dx, dy)`.
    ///
    /// ``centered`` layers are returned unchanged: they are anchored to the
    /// *screen* (centre + post-centre drag delta), not to the content that
    /// emitted them, so the positional shifts of buffer composition must not
    /// apply — folding an attachment point's position into the offset would
    /// displace the dialog off-centre (it presented correctly only when
    /// attached at the tree root).
    ///
    /// - Parameters:
    ///   - dx: The horizontal shift in columns.
    ///   - dy: The vertical shift in rows.
    /// - Returns: A shifted copy of the layer (or `self` when ``centered``).
    public func shifted(byX dx: Int, y dy: Int) -> Self {
        guard !centered else { return self }
        var copy = self
        copy.offsetX += dx
        copy.offsetY += dy
        return copy
    }
}
