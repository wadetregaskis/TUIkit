//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OverlayLayer.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Overlay Level

/// The semantic stacking level of an ``OverlayLayer``.
///
/// Layers composite onto the root buffer in ascending level order: a
/// `.popover` draws beneath a `.modal`, which draws beneath an `.alert`,
/// which draws beneath a `.notification`. Within a single level,
/// ``OverlayLayer/zIndex`` breaks ties.
///
/// An alert sits ABOVE a sheet deliberately, whichever presented first: an
/// alert is the topmost interruption in every windowing convention, and with
/// the old ordering an alert presented while a sibling sheet was up composited
/// beneath it — owning the keyboard while the sheet's dimming pass buried it,
/// an invisible dialog holding the app.
public enum OverlayLevel: Int, Sendable, Comparable, CaseIterable {
    /// A lightweight popover anchored to a control (e.g. a `Picker` drop-down).
    case popover

    /// A modal sheet or dialog.
    case modal

    /// A modal alert.
    case alert

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

    /// The ``zIndex`` for a layer that is a view's own displaced DRAWING —
    /// `.offset`, `.position`, a transition's overshoot — rather than a
    /// surface presented over the page.
    ///
    /// Being an overlay at all already puts such a layer above the in-flow
    /// content it escaped, and ``OverlayLevel`` already puts it below a dialog
    /// or an alert. What was left undecided is the order against the OTHER
    /// layers at `.popover`: an anchored drop-down or a context menu, which are
    /// windows and must not have a bouncing label drawn over them. Emission
    /// order decided that, which is to say the shape of the view tree did.
    ///
    /// So displaced drawing sits one notch below the level's floor. A negative
    /// value rather than pushing the presentations up: `zIndex` exists for
    /// exactly this and nothing in the framework sets it, so the room was
    /// already there and no case of the enum had to move. Nothing draws below
    /// this but the page.
    ///
    /// Note what this does NOT decide, because the compositor answers it
    /// without a number: a layer emitted INSIDE a presentation's content rides
    /// in that presentation's buffer and is drained in the pass after it, so a
    /// view bouncing inside a dialog draws above the dialog while one bouncing
    /// on the page behind it draws below. The ordering is relative because the
    /// nesting is.
    public static let displacedDrawingZIndex: Double = -1

    /// The height of the anchoring control sitting immediately above
    /// ``offsetY``.
    ///
    /// When the layer would overflow the bottom edge of the screen the
    /// compositor flips it to sit *above* the anchor instead. This value
    /// lets it compute the flipped position: the layer's bottom is placed
    /// flush with the top of the anchor.
    ///
    /// `0` does NOT disable flipping — it says there is nothing above
    /// ``offsetY`` to clear, so the layer's bottom lands flush with `offsetY`
    /// itself. That is right for a layer anchored AT a point (a context menu at
    /// the clicked cell) and wrong for one anchored BELOW a control, which
    /// would then be covered by its own menu. It also feeds `ScrollView`'s
    /// overlay culling, which measures a layer's extent from
    /// `offsetY - anchorHeight`, so a control on the last visible row must
    /// declare its height or its popover is discarded unseen.
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

    /// Whether this layer is a SCREEN-level panel rather than part of the
    /// drawing of the view that emitted it.
    ///
    /// The distinction three modifiers turn on, and it deserves a name because
    /// each of them got it wrong once by not having one:
    ///
    /// - ``View/hidden()`` drops a layer that is this view's own
    ///   drawing and isolates the subtree so a screen-level one is never
    ///   presented in the first place;
    /// - ``View/allowsHitTesting(_:)`` disarms an anchored pop-up,
    ///   because leaving one clickable under a view that just said it was not
    ///   is the bug it exists to prevent — and leaves a presented dialog's own
    ///   buttons alone, because that dialog is not this view's hit area;
    /// - ``View/opacity(_:)`` fades an anchored layer with the
    ///   subtree it belongs to, and does not fade a dialog the subtree merely
    ///   opened.
    ///
    /// It reads ``centered`` because the two coincide exactly today: a layer
    /// is centred precisely when it is a modal or an alert, which is precisely
    /// when it is a panel over the whole screen rather than a displaced piece
    /// of a view. `ScrollView`'s culling relies on the same coincidence from
    /// the other side — it keeps centred layers through a scroll because they
    /// are "screen-anchored, not content-anchored".
    ///
    /// A separate stored flag was considered and declined. It would answer a
    /// DIFFERENT question — "is this a presentation" — and a `.popover` is a
    /// presentation that all three modifiers should still treat as the view's
    /// own drawing, since it is anchored to it. Placement is the axis they
    /// actually want. If a centred non-presentation or an uncentred modal ever
    /// exists, this property is the one line to change, and the three modifiers
    /// stay correct by construction.
    public var isScreenLevel: Bool { centered }

    /// Whether this layer is a SURFACE — something that floats OVER the page and
    /// hides it — rather than a displaced piece of the view that emitted it.
    ///
    /// A menu, a dialog, a toast and a popover are windows: what is behind them
    /// is not meant to be legible through them. `.offset` and `.position` are
    /// not — they move a view's own drawing to another cell, and a `Text` moved
    /// four columns right must arrive as text, not as text in a box the width
    /// of its line.
    ///
    /// The compositor paints an opaque layer's cells over the surface colour
    /// before drawing it, wherever they name no background of their own. Until
    /// 590e71a4 that was unnecessary, because compositing replaced the base cell
    /// under every overlay cell, field included — so a surface that named no
    /// background still punched the page's away and every one of them was
    /// opaque by accident. Making a cell's glyph and its field two separate
    /// statements (so `ZStack { Color.red; Text("hi") }` draws the letters ON
    /// the red) is right, and it left the accident-dependent surfaces showing
    /// the page through their blanks.
    ///
    /// It defaults to `true` because a presentation is what an overlay layer
    /// almost always is, and because the two failures are not equally loud: a
    /// displaced label wrongly given a box is visible the moment anyone looks
    /// at it, while a menu leaking the page behind it depends on the palette
    /// and can survive a whole release unnoticed. The default that fails
    /// loudly is the safer one.
    public var isOpaque: Bool = true

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
    ///   - clampsToScreen: Whether an overhanging layer slides back on screen
    ///     rather than being clipped where it is (default: `true`) — see
    ///     ``clampsToScreen``.
    ///   - isOpaque: Whether the layer is a surface that hides what is behind
    ///     it (default: `true`) — see ``isOpaque``.
    public init(
        offsetX: Int,
        offsetY: Int,
        content: FrameBuffer,
        level: OverlayLevel = .popover,
        zIndex: Double = 0,
        anchorHeight: Int = 0,
        centered: Bool = false,
        dimsBackground: Bool = false,
        clampsToScreen: Bool = true,
        isOpaque: Bool = true
    ) {
        self.clampsToScreen = clampsToScreen
        self.isOpaque = isOpaque
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.content = content
        self.level = level
        self.zIndex = zIndex
        self.anchorHeight = anchorHeight
        self.centered = centered
        self.dimsBackground = dimsBackground
    }

    /// Whether an overhanging layer is moved back on screen (`true`, the
    /// pop-over policy) or CLIPPED where it is (`false`).
    ///
    /// Moving is right for a menu: a drop-down that would run off the right
    /// edge slides left and stays whole. It is exactly wrong for anything
    /// anchored to the pointer, which must stay where the pointer is even when
    /// part of it falls off the screen — a drag preview that slides back is a
    /// row that stops following the cursor, and the wider the preview the
    /// sooner it happens. (A full-width Table row detached after three cells.)
    public var clampsToScreen: Bool = true

    /// Resolves this layer's on-screen placement within a `maxWidth` × `maxHeight`
    /// content area: the (clamped) content plus the column and row to draw it at.
    ///
    /// The content is clamped to the screen first, so it can never exceed it — a
    /// too-tall popover keeps its top rows, so its text still shows even when it
    /// can't fit. If it would then overflow the bottom edge it is flipped to sit
    /// *above* its anchor (when ``anchorHeight`` allows); otherwise it is nudged
    /// back up. The same nudge keeps it within the right edge. Both are the
    /// ``clampsToScreen`` policy: a layer that declines it stays where it was
    /// put and loses the overhang out of its content instead (018429dd,
    /// 2026-07-30).
    public func placed(maxWidth: Int, maxHeight: Int) -> (content: FrameBuffer, x: Int, y: Int) {
        var clamped = content.clamped(toWidth: maxWidth, height: maxHeight)
        // `clamped(toWidth:height:)` deliberately keeps ALL hit-test regions —
        // in-flow clamping must never discard them, because the root compositor
        // re-places them. Here the clip is FINAL: rows/columns beyond it are
        // never drawn, so their regions must not stay clickable (a click below
        // a short terminal's too-tall dialog — e.g. on the status bar, whose
        // events arrive with y >= contentHeight — would activate an invisible
        // row). Trim every region to the clip, dropping the fully clipped.
        if content.height > maxHeight || content.width > maxWidth {
            clamped.hitTestRegions = clamped.hitTestRegions.compactMap { region -> HitTestRegion? in
                let right = min(region.offsetX + region.width, maxWidth)
                let bottom = min(region.offsetY + region.height, maxHeight)
                guard right > region.offsetX, bottom > region.offsetY else { return nil }
                if right == region.offsetX + region.width,
                    bottom == region.offsetY + region.height {
                    return region
                }
                return HitTestRegion(
                    offsetX: region.offsetX,
                    offsetY: region.offsetY,
                    width: right - region.offsetX,
                    height: bottom - region.offsetY,
                    handlerID: region.handlerID,
                    focusID: region.focusID)
            }
        }
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

        // Pointer-anchored: stay put and lose what falls off the edges. The
        // compositor grows its result to fit an overlay and cannot take a
        // negative column, so the overhang is cut from the CONTENT rather than
        // handed on as an out-of-range offset.
        if !clampsToScreen {
            let x = max(0, offsetX)
            let y = max(0, offsetY)
            let dropX = x - offsetX  // columns cut off the left edge
            let dropY = y - offsetY
            // Through `cutting`, not `visible.lines =`: the assignment moves the
            // CELLS and leaves every payload riding on the buffer — hit regions,
            // animated runs, opacity regions, nested layers — naming the cells
            // they used to sit on.
            let cut = Self.cutting(clamped, leadingColumns: dropX, rows: dropY)
            let visible = cut.clamped(toWidth: max(0, maxWidth - x), height: max(0, maxHeight - y))
            return (visible, x, y)
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

    /// `buffer` with its leading `dropColumns` columns and `dropRows` rows cut
    /// away, and everything riding on it moved by the same amount.
    ///
    /// The one place a layer loses its leading cells: the screen edge, in
    /// ``placed(maxWidth:maxHeight:)``'s pointer-anchored branch, and a
    /// clipping container, in ``clipped(toWidth:height:)``. It is a function
    /// because of its last statement rather than its first — `replacingLines`
    /// moves the hit regions, animated runs, opacity regions and nested layers
    /// with the cells they name, and assigning `lines` moves only the cells.
    /// The preview of a dragged card whose spinner stayed behind replays that
    /// spinner `dropColumns` cells right of the glyphs it draws, repainting the
    /// cells beside it while the visible spinner freezes at the frame the
    /// render drew, and the root fades a band `dropColumns` off the one asked
    /// for.
    ///
    /// No pre-clip against the surviving box is needed on the way: unlike
    /// `HitTestRegion`, a run and an opacity region record no clip counters, so
    /// translation and clipping commute, and payload left at a negative offset
    /// names cells that were cut away — dropped by
    /// `AnimatedCellRun.clipped(toCanvasColumns:rows:)` at the screen, and
    /// already read as `max(0, …)` by the opacity resolution.
    private static func cutting(
        _ buffer: FrameBuffer, leadingColumns dropColumns: Int, rows dropRows: Int
    ) -> FrameBuffer {
        guard dropColumns > 0 || dropRows > 0 else { return buffer }
        var lines = dropRows > 0 ? Array(buffer.lines.dropFirst(dropRows)) : buffer.lines
        if dropColumns > 0 { lines = cutting(lines, leadingColumns: dropColumns) }
        return buffer.replacingLines(
            lines, overlayShiftX: -dropColumns, overlayShiftY: -dropRows)
    }

    /// `lines` with `columns` cells cut from the left of each.
    ///
    /// The line half of `cutting(_:leadingColumns:rows:)`, which is now its
    /// only caller, because each of the three things it does is a bug someone
    /// shipped by doing the obvious thing instead.
    private static func cutting(_ lines: [String], leadingColumns columns: Int) -> [String] {
        lines.map { line in
            // `ansiAwareSlice`, not `ansiAwareSuffix`: the suffix throws away
            // every SGR that occurred before the cut, so a preview clipped at
            // the left edge arrived unstyled and rendered in the terminal's raw
            // defaults — which reads as "just the background". The slice
            // replays the style it cut through.
            let owed = max(0, line.strippedLength - columns)
            let slice = line.ansiAwareSlice(visibleStart: columns, visibleCount: owed)
            // A wide glyph straddling the cut cannot be half-drawn, so it is
            // dropped whole and the line comes back a cell short — which would
            // slide the whole preview one column left, off the cell the pointer
            // grabbed. Pad that shortfall, after the carried style so the gap
            // keeps the run's background.
            let shortfall = owed - slice.strippedLength
            guard shortfall > 0 else { return slice }
            // The scalar-exact split, not `leadingANSISequences()` +
            // `dropFirst(count)`: a combining mark opening the visible text
            // fuses with the last sequence's terminator into one `Character`,
            // and the character-counted drop severed it.
            let (carried, remainder) = slice.leadingANSISplit()
            return carried + String(repeating: " ", count: shortfall) + remainder
        }
    }

    /// The part of this layer that falls inside a `width` × `height`
    /// container, or `nil` when none of it does.
    ///
    /// What a CLIPPING container does to a layer carrying a piece of its own
    /// content's drawing — `.offset`, `.position`, a transition's overshoot.
    /// SwiftUI's `ScrollView` clips its content to its bounds (which is what
    /// `View.scrollClipDisabled(_:)` exists to turn off), and a layer that
    /// escapes one paints over whatever sits beside the viewport.
    ///
    /// It is emphatically NOT for a presentation. A menu, a drop-down, a
    /// dialog or a toast is a window over the page, and clipping one to the
    /// scroller its trigger happens to sit in is how a picker on the last row
    /// of a list loses every option. Callers choose by ``isOpaque``, which
    /// already draws exactly that line.
    ///
    /// The layer's offset is relative to the container, so a negative one
    /// means it starts outside: those columns and rows are cut from the
    /// CONTENT and the offset moves to the edge, since a composited buffer
    /// cannot be placed at a negative column. Hit-test regions are cut with
    /// the cells they name — a region left standing over clipped cells is a
    /// click target for a view that is not drawn there.
    ///
    /// - Parameters:
    ///   - width: The container's width in cells.
    ///   - height: The container's height in rows.
    /// - Returns: The clipped layer, `self` when it was already inside, or
    ///   `nil` when nothing of it survives.
    public func clipped(toWidth width: Int, height: Int) -> Self? {
        // Already inside: the overwhelmingly common case, and worth a test to
        // skip re-measuring every line of every layer on every frame.
        if offsetX >= 0, offsetY >= 0, offsetX + content.width <= width,
            offsetY + content.height <= height {
            return self
        }
        let x = max(0, offsetX)
        let y = max(0, offsetY)
        let boxWidth = width - x
        let boxHeight = height - y
        guard boxWidth > 0, boxHeight > 0 else { return nil }
        let dropX = x - offsetX
        let dropY = y - offsetY
        guard dropX < content.width || content.width == 0, dropY < content.height else {
            return nil
        }

        var cut = content
        if dropX > 0 || dropY > 0 {
            // Regions are clipped BEFORE the shift, against the surviving box
            // stated in the content's own coordinates, so every offset that
            // comes out of the shift is already inside it — and the box below
            // then has nothing left to do to them.
            //
            // This used to add that clipping after would go wrong because
            // `FrameBuffer.clamped(toWidth:height:)` mishandled negative
            // offsets. It did, and no longer does: all three copies of this
            // clip are now `HitTestRegion.clipped(toColumns:rows:)`, which
            // moves a straddling region to the surviving corner and records
            // what it cut. The order here is kept because it is the clearer
            // one, not because the alternative is broken.
            cut.hitTestRegions = content.hitTestRegions.compactMap {
                $0.clipped(
                    toColumns: dropX..<(dropX + boxWidth), rows: dropY..<(dropY + boxHeight))
            }
            cut = Self.cutting(cut, leadingColumns: dropX, rows: dropY)
        }
        let clipped = cut.clamped(toWidth: boxWidth, height: boxHeight)
        // A layer whose own drawing is gone may still carry a presentation
        // opened from inside it, which is not this container's to discard.
        //
        // It only saves a layer that is PARTLY outside: one that is wholly
        // outside is already gone at the `dropX`/`dropY` guard above, nested
        // presentation and all. Measured — a layer at `offsetX: -20` with
        // 5-wide content carrying a `.modal` returns nil there. That case is
        // narrow in practice (a `ScrollView` culls the vertical one before it
        // gets here) and is left rather than fixed blind, but the guard below
        // should not be read as covering it.
        guard !clipped.isEmpty || !clipped.overlays.isEmpty else { return nil }

        var copy = self
        copy.content = clipped
        copy.offsetX = x
        copy.offsetY = y
        return copy
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
