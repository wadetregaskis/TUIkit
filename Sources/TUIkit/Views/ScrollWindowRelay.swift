//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollWindowRelay.swift
//
//  A view that draws lines of its own above and below content it draws AT ITS
//  OWN IDENTITY — a `Section`'s header and footer around its content — sits
//  between the scroll view and a lazy stack that single-child steps still lead
//  to, so that stack still consumes the scroll window. This hands the stack
//  the window in the stack's own coordinates, and moves the stack's reply back
//  into the view's.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The scroll window, relayed through a view that draws `linesAbove` lines
/// above its content and some below it.
///
/// Withholding the window there instead — drawing the content whole, as a
/// lazy stack below a header in a `VStack` is — draws correctly and gives up
/// everything that rides the window: `scrollTo` and a `.scrollPosition` write
/// (seeks), `.scrollPosition` read-back, a held `.anchorPosition(.row)`, and
/// the band itself, so every row's `onAppear` fired on the first frame and an
/// `onAppear` pagination at the last row loaded until the data ran out.
struct ScrollWindowRelay {
    /// The reply the content answers into; `nil` when the view's window has
    /// none (tests, direct injection), and the content draws full height.
    private let contentReply: ScrollContentReply?
    /// The view's own reply, which this answers into.
    private let reply: ScrollContentReply?
    private let window: ScrollContentWindow
    private let linesAbove: Int

    /// The relay for a view drawing `linesAbove` lines above its content and
    /// `linesBelow` below it, or `nil` when there is nothing to relay: no
    /// window published, a measure (which is given none), a view that is not
    /// at the scroll content's origin, or no lines drawn around the content,
    /// which then sits at the view's origin and takes the window as it is.
    ///
    /// Not at the origin — a section among several in an eager column, which
    /// hands each of its children the window — no stack below can consume the
    /// window (``ScrollContentWindow/isAtOrigin(_:)``), and there is nothing to
    /// relay; relayed anyway, the footer was measured on every render for it.
    ///
    /// `linesBelow` is asked for only once there is a relay: the lines below
    /// are drawn after the content, in the order their controls join the focus
    /// ring, so it is the caller's measure of them. Only the stack's questions
    /// about the content below it read it (whether any lies below the
    /// viewport, and how far the content scrolls); the heights this reports
    /// are the drawn ones.
    init?(context: RenderContext, linesAbove: Int, linesBelow: () -> Int) {
        guard !context.isMeasuring, let window = context.environment.scrollContentWindow,
            window.isAtOrigin(context.identity)
        else { return nil }
        let linesBelow = linesBelow()
        guard linesAbove > 0 || linesBelow > 0 else { return nil }
        self.reply = window.reply
        self.contentReply = window.reply == nil ? nil : ScrollContentReply()
        self.window = window.beneath(
            linesAbove: linesAbove, linesBelow: linesBelow, reply: contentReply)
        self.linesAbove = linesAbove
    }

    /// The context the content is drawn in: the view's, with the window moved
    /// into the content's coordinates.
    func contentContext(_ context: RenderContext) -> RenderContext {
        var contentContext = context
        contentContext.environment.scrollContentWindow = window
        return contentContext
    }

    /// Where the view's own lines go, once its content has answered.
    struct Placement {
        /// Whether the lines above the content belong to the drawn buffer:
        /// always, unless the content drew a band that starts below its top.
        var drawsAbove = true
        /// Whether the lines below it do: unless the band stops short of the
        /// content's end.
        var drawsBelow = true
        /// Where the content's line 0 falls in the buffer the view assembles,
        /// and the content's whole height — for the view's lines the band
        /// leaves out, which go at `contentTop - linesAbove` (above) and
        /// `contentTop + contentHeight` (below). Those above are kept above
        /// the band by the caller: the anchored window's positions are
        /// estimates, and a row it holds at the viewport's top can put its
        /// line 0 inside the band. Those below need no such care, since a
        /// content's height never ends inside its own band.
        var contentTop = 0
        var contentHeight = 0
    }

    /// Moves the content's reply into the view's coordinates — its content
    /// starts `linesAbove` lines down and is followed by `linesBelow` drawn
    /// lines — and says which of the view's own lines the band holds.
    ///
    /// A band (Stage 6) is a slice of the content's lines; the view's buffer
    /// must be a contiguous slice of its own, so the lines above join it only
    /// when the band starts at the content's top, and those below only when it
    /// reaches the content's end. Left out, their controls are carried at
    /// their place outside the band (as a stack grafts an off-band row), so a
    /// focus move onto one still finds where to scroll.
    func answer(contentBuffer: FrameBuffer, linesBelow: Int) -> Placement {
        let whole = Placement(contentTop: linesAbove, contentHeight: contentBuffer.height)
        guard let reply, let contentReply else { return whole }
        if let id = contentReply.anchorID { reply.anchorID = id }
        if let offset = contentReply.seekResolvedOffset {
            reply.seekResolvedOffset = offset + linesAbove
        }
        if contentReply.measureWentStale { reply.measureWentStale = true }
        guard let origin = contentReply.sliceOriginY, let total = contentReply.sliceTotalHeight
        else {
            // A full-height buffer: the view's lines surround it whole.
            reply.drawnLines = contentReply.drawnLines.map { drawn in
                let lower = drawn.lowerBound <= 0 ? 0 : drawn.lowerBound + linesAbove
                let upper = drawn.upperBound == Int.max ? Int.max : drawn.upperBound + linesAbove
                return lower..<upper
            }
            return whole
        }
        // In the view's coordinates the content's line `y` is `y + linesAbove`,
        // and the lines above it start at the content's first row, not at the
        // content's 0, where the anchored window's first row need not sit.
        let drawsAbove = contentReply.sliceHoldsFirstRow
        let drawsBelow = contentReply.sliceHoldsLastRow
        reply.sliceOriginY = drawsAbove ? origin : origin + linesAbove
        reply.sliceTotalHeight = linesAbove + total + linesBelow
        reply.sliceTotalIsEstimate = contentReply.sliceTotalIsEstimate
        reply.sliceHoldsFirstRow = drawsAbove
        reply.sliceHoldsLastRow = drawsBelow
        return Placement(
            drawsAbove: drawsAbove, drawsBelow: drawsBelow,
            contentTop: (drawsAbove ? linesAbove : 0) - origin, contentHeight: total)
    }
}
