//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// The persistent focus identifier of the focusable view that
    /// emitted this region, when applicable.
    ///
    /// Optional and `nil` for non-focusable regions (a List's
    /// container-wide click region, a ScrollView's wheel region,
    /// `.onMouseEvent` modifiers, etc.). When set, ScrollView
    /// (and any other consumer that wants to know "where in the
    /// content does focus live?") can scan the carrying
    /// buffer's regions for one whose `focusID` matches
    /// `FocusManager.focusedID` and read its bounds directly,
    /// without any side-channel mapping.
    public let focusID: String?

    /// Rows of chrome an ANCESTOR drew immediately above this region — a
    /// border rule, typically — that belong to the control for the purpose of
    /// revealing it.
    ///
    /// Purely geometric, and read by ``FrameBuffer/revealTarget(focusID:wholeControl:)``
    /// alone: hit-testing ignores it, so a border stays inert to clicks while a
    /// reveal can still bring it on screen. A control that draws its own border
    /// has no need of this; it exists because `.border()` and friends wrap a
    /// child in a container that SHIFTS the child's regions without growing
    /// them, leaving the rule one row outside everything the reveal can see.
    public var revealOutsetTop: Int = 0

    /// Rows of ancestor-drawn chrome immediately below this region. See
    /// ``revealOutsetTop``.
    public var revealOutsetBottom: Int = 0

    /// Rows clipped off this region's top by an ancestor's viewport — a
    /// `ScrollView` the region has been scrolled up inside of.
    ///
    /// Hit-testing wants the CLIPPED rectangle: a control half-scrolled off the
    /// top must not be clickable on the rows it no longer occupies. But a
    /// coordinate space begins where the region begins, clipped or not, and one
    /// field cannot be both. So ``offsetY`` stays the clipped top — every
    /// existing consumer keeps the rectangle it expects — and this records how
    /// far above it the region really starts.
    ///
    /// Read through ``localOriginY``, which is what turns an absolute point
    /// into a region-local one. Without it a drop destination that wraps a
    /// scrolled page reported points short by the scroll offset, and anything
    /// drawn at them landed that far up the screen.
    public var topClip: Int = 0

    /// Columns clipped off this region's left edge by an ancestor's viewport —
    /// a horizontal `ScrollView` the region has been scrolled left inside of.
    /// The X half of ``topClip``, with the same one-field-cannot-be-both
    /// reasoning: ``offsetX`` stays the clipped left edge, this records how
    /// far left of it the region really starts, and ``localOriginX`` is what
    /// turns an absolute column into a region-local one.
    public var leftClip: Int = 0

    /// The absolute screen row this region's local coordinate space starts at:
    /// its (possibly clipped) top, moved back up past whatever an ancestor
    /// viewport cut away.
    ///
    /// Every conversion of an absolute point into a region-local one — which is
    /// the form handlers are given — measures from here, because a control's
    /// rows are numbered from the control, not from the fold it happens to be
    /// scrolled under. Asking instead *where on screen the region is* — hit
    /// testing (``contains(x:y:)``), edge proximity, overlap — wants the clipped
    /// rectangle, so those keep reading ``offsetY`` directly.
    ///
    /// The two coincide for everything an ancestor viewport has not clipped,
    /// which is why mixing them up stays invisible until something is scrolled:
    /// a Table on a scrolled page reported clicks one row too high per clipped
    /// row, so a click on row 20 selected row 15.
    public var localOriginY: Int { offsetY - topClip }

    /// The absolute screen column this region's local coordinate space starts
    /// at. See ``localOriginY`` — same distinction, other axis.
    public var localOriginX: Int { offsetX - leftClip }

    /// Creates a hit-test region.
    public init(
        offsetX: Int,
        offsetY: Int,
        width: Int,
        height: Int,
        handlerID: HandlerID,
        focusID: String? = nil
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.height = height
        self.handlerID = handlerID
        self.focusID = focusID
    }

    /// Whether the region contains the given absolute screen position.
    public func contains(x: Int, y: Int) -> Bool {
        x >= offsetX && x < offsetX + width && y >= offsetY && y < offsetY + height
    }

    /// The part of this region inside `columns` × `rows`, or `nil` when none
    /// of it is.
    ///
    /// The trim a CLIPPING CONTAINER performs, which is why it accumulates
    /// ``topClip`` / ``leftClip`` rather than merely moving the rectangle:
    /// hit-testing wants the visible rectangle, but a handler is handed points
    /// measured from where the region really BEGINS, and a region trimmed
    /// without recording what was cut reports every point short by exactly
    /// that much.
    ///
    /// The ranges are in the carrying buffer's own coordinates and nothing is
    /// re-based, so a caller clipping to a box that does not start at the
    /// origin passes that box's ranges and shifts afterwards.
    ///
    /// - Parameters:
    ///   - columns: The surviving column range.
    ///   - rows: The surviving row range.
    /// - Returns: The trimmed region, `self` when it was already inside, or
    ///   `nil` when nothing of it survives.
    public func clipped(toColumns columns: Range<Int>, rows: Range<Int>) -> Self? {
        let left = Swift.max(offsetX, columns.lowerBound)
        let right = Swift.min(offsetX + width, columns.upperBound)
        let top = Swift.max(offsetY, rows.lowerBound)
        let bottom = Swift.min(offsetY + height, rows.upperBound)
        guard right > left, bottom > top else { return nil }
        guard left != offsetX || top != offsetY || right != offsetX + width
            || bottom != offsetY + height
        else { return self }
        var trimmed = Self(
            offsetX: left, offsetY: top, width: right - left, height: bottom - top,
            handlerID: handlerID, focusID: focusID)
        trimmed.revealOutsetTop = revealOutsetTop
        trimmed.revealOutsetBottom = revealOutsetBottom
        trimmed.topClip = topClip + (top - offsetY)
        trimmed.leftClip = leftClip + (left - offsetX)
        return trimmed
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
