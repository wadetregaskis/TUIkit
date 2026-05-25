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
    public init(
        offsetX: Int,
        offsetY: Int,
        content: FrameBuffer,
        level: OverlayLevel = .popover,
        zIndex: Double = 0,
        anchorHeight: Int = 0
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.content = content
        self.level = level
        self.zIndex = zIndex
        self.anchorHeight = anchorHeight
    }

    /// Returns a copy of this layer with its offset shifted by `(dx, dy)`.
    ///
    /// - Parameters:
    ///   - dx: The horizontal shift in columns.
    ///   - dy: The vertical shift in rows.
    /// - Returns: A shifted copy of the layer.
    public func shifted(byX dx: Int, y dy: Int) -> OverlayLayer {
        var copy = self
        copy.offsetX += dx
        copy.offsetY += dy
        return copy
    }
}
