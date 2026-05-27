//  🖥️ TUIKit — Terminal UI Kit for Swift
//  HitTestRegion.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Hit-Test Region

/// A rectangular screen region that wants to receive mouse events.
///
/// Hit-test regions ride alongside ``FrameBuffer/overlays`` and follow
/// the exact same compositing dance: every combining operation
/// (``FrameBuffer/appendVertically(_:spacing:)``,
/// ``FrameBuffer/appendHorizontally(_:spacing:)``,
/// ``FrameBuffer/composited(with:at:)``, …) shifts the region's offset
/// by the same amount it shifts the buffer's lines.
///
/// By the time a buffer reaches the root the regions' ``offsetX`` /
/// ``offsetY`` are in absolute screen coordinates, so the
/// `MouseEventDispatcher` can hit-test the incoming mouse position
/// against them without any extra plumbing.
///
/// The dispatcher resolves overlapping regions in registration order:
/// the most recently emitted region wins. Container views naturally
/// emit their own region before their children's because the modifier
/// chain is evaluated outside-in, so a click that lands inside both a
/// child and its container is routed to the child first — same dispatch
/// semantics as a click in SwiftUI / AppKit.
public struct HitTestRegion: Sendable, Equatable {
    /// The column offset of the region's top-left corner, relative to
    /// the top-left of the carrying buffer.
    public var offsetX: Int

    /// The row offset of the region's top-left corner, relative to the
    /// top-left of the carrying buffer.
    public var offsetY: Int

    /// The region's width in terminal cells.
    public let width: Int

    /// The region's height in terminal rows.
    public let height: Int

    /// A token used to look up the registered handler on the
    /// `MouseEventDispatcher`. The dispatcher stores closures keyed by
    /// this id so the buffer can carry plain-value-type metadata and
    /// the dispatcher owns the closure lifetimes.
    public let handlerID: HandlerID

    /// Creates a hit-test region.
    public init(
        offsetX: Int,
        offsetY: Int,
        width: Int,
        height: Int,
        handlerID: HandlerID
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.height = height
        self.handlerID = handlerID
    }

    /// Whether the region contains the given absolute screen position.
    public func contains(x: Int, y: Int) -> Bool {
        x >= offsetX && x < offsetX + width && y >= offsetY && y < offsetY + height
    }
}

extension HitTestRegion {
    /// A stable id paired with a closure on the `MouseEventDispatcher`.
    ///
    /// The wrapped `Int` is unique only for the lifetime of one render
    /// pass — the dispatcher hands out fresh ids on every frame and
    /// drops them at the end. The id is also `Sendable` and `Equatable`
    /// so regions can be diffed cheaply.
    public struct HandlerID: Sendable, Hashable {
        /// The raw token value.
        public let raw: UInt64

        /// Creates a handler id wrapping a raw token.
        public init(_ raw: UInt64) {
            self.raw = raw
        }
    }
}
