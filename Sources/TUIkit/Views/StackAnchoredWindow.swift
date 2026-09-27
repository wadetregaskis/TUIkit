//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackAnchoredWindow.swift
//
//  The variable-height anchor walk of "Locating things without drawing
//  them" (§5e, §6a): when rows are NOT uniform, the scroll position is a
//  persisted anchor — a row ordinal plus the cells of it hidden above the
//  viewport top — and scroll input is applied as a DELTA walked in row
//  space: one line up looks at one row. The frame then fills outward from
//  the anchor, measuring only the rows it draws. Estimated extents cover
//  only what is never measured — the blank suffix that feeds the scrollbar
//  and the seek target of a big jump — so an estimate being wrong can move
//  the thumb, never the content: the anchor row is pinned to the offset the
//  clip will show, by construction.
//
//  Small stacks keep the exact full walk (their O(N) is trivial and their
//  absolute space stays exact); this path takes over above
//  `anchoredWindowThreshold` rows, where O(N)-per-frame is the bug.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Per-frame measurer

/// One anchored frame's measuring state: memoises each touched row's pitch
/// (height + the spacing charged before a non-first row), keeps the built
/// child for the render step, and feeds every measurement into the running
/// estimate. One measure per touched row per frame.
@MainActor
private final class AnchoredWindowFrame {
    let children: ChildViewCollection
    let spacing: Int
    let state: StackWindowState
    let proposal: ProposedSize
    let context: RenderContext

    private(set) var sawSpacer = false
    private var pitchCache: [Int: Int] = [:]
    private var widthCache: [Int: Int] = [:]
    private var built: [Int: ChildView] = [:]

    init(
        children: ChildViewCollection, spacing: Int, state: StackWindowState,
        proposal: ProposedSize, context: RenderContext
    ) {
        self.children = children
        self.spacing = spacing
        self.state = state
        self.proposal = proposal
        self.context = context
    }

    func pitch(of ordinal: Int) -> Int {
        if let cached = pitchCache[ordinal] { return cached }
        let child = children[ordinal]
        if child.isSpacer { sawSpacer = true }
        let measured = child.measure(proposal: proposal, context: context)
        // Keep a measure-only row's memo entries alive across the pass GC:
        // an off-window row touched only by this pitch walk never renders,
        // so nothing else marks it — and unmarked entries are pruned at the
        // end of every pass, forcing a full re-measure every frame. Bounded
        // by the rows this frame touches, unlike marking inside the memo
        // itself (which is O(tree) on eager stacks).
        context.renderCache?.markActive(child.identity(under: context))
        // AFTER-spacing semantics: a row's pitch is its height plus the gap
        // BELOW it (every row but the last has one). `fill` advances by the
        // pitch of the row it just placed, so the gap must ride the row
        // ABOVE it — the before-spacing convention dropped exactly the
        // row 0 → row 1 gap (row 0's pitch carried no spacing) and shifted
        // the whole tail up one line per spacing unit.
        let value = max(1, measured.height) + (ordinal < children.count - 1 ? spacing : 0)
        pitchCache[ordinal] = value
        widthCache[ordinal] = measured.width
        built[ordinal] = child
        state.recordMeasuredPitch(value)
        return value
    }

    func child(at ordinal: Int) -> ChildView {
        built[ordinal] ?? children[ordinal]
    }

    /// The measured width of a row the pitch walk has already touched.
    ///
    /// What a `.gradientExtent(.subtree)` ramp aligns a row by: the RENDERED
    /// width does not exist until after the render the ramp has to colour, and
    /// the pitch walk measured this one anyway. `nil` for a row this frame
    /// never measured — an off-band graft, whose cells are not drawn.
    func measuredWidth(of ordinal: Int) -> Int? {
        widthCache[ordinal]
    }

    /// Re-binds the persisted anchor ordinal to its stable key (§5f). The
    /// fast path — the key still lives at the remembered ordinal — is one
    /// key build. On a miss, the key is searched nearby first (data shifts
    /// are usually small), then everywhere (the documented Ω(n) id→ordinal
    /// cost, touching keys only). A key that left the data entirely falls
    /// to the LADDER: last frame's rendered rows, nearest survivor first,
    /// preserving `anchorOffsetWithin`. A dead ladder (the list was
    /// replaced) leaves the clamped index fallback — approximate, and
    /// correct at the ends (§5f).
    func rebindAnchor(mode: ScrollAnchorMode) {
        let count = children.count
        guard count > 0 else { return }
        state.anchorOrdinal = min(max(0, state.anchorOrdinal), count - 1)
        // WINDOW mode (the spec's default) is *no* anchor: the position stays
        // where it is in line coordinates, so the ordinal is kept as-is and an
        // insert above shifts the content down. Only the row-holding modes
        // re-bind the ordinal to its key below. See
        // `Documentation/Scroll-anchoring.md` §1.1 / §2.
        guard mode.holdsRowIdentity else { return }
        guard let anchorKey = state.anchorKey else { return }
        guard children.key(at: state.anchorOrdinal) != anchorKey else { return }

        if let found = locate(key: anchorKey) {
            state.anchorOrdinal = found
            return
        }
        // Nearest first, and of the two equally near — the rows either side of
        // a deleted one — the one below, which the delete moved into its place:
        // nothing else moves. Ordered by distance alone, the pair came in the
        // memo's order, which the process's hash seed sets, and which row took
        // the anchor, and so the frame, changed from one run to the next.
        let neighbours = state.rowOrdinalMemo.sorted {
            let distances = (abs($0.value - state.anchorOrdinal), abs($1.value - state.anchorOrdinal))
            return distances.0 != distances.1 ? distances.0 < distances.1 : $0.value > $1.value
        }
        for (key, _) in neighbours where key != anchorKey {
            if let found = locate(key: key) {
                state.anchorOrdinal = found
                state.anchorKey = key
                return
            }
        }
    }

    /// The ordinal holding `key`: nearby ring search first, then the full
    /// key scan. Never builds a row view.
    private func locate(key: String) -> Int? {
        let count = children.count
        let origin = state.anchorOrdinal
        for distance in 0...64 {
            for candidate in [origin - distance, origin + distance]
            where candidate >= 0 && candidate < count {
                if children.key(at: candidate) == key { return candidate }
            }
        }
        return children.firstOrdinal(forKey: key)
    }

    /// Applies a scroll offset to the persisted anchor. A big jump seeks by
    /// estimate (O(1), approximate — what a scrollbar drag means); a small
    /// delta walks rows until it is consumed (one line up looks at one row).
    ///
    /// `linesBelow` is what the scroll content draws below this stack — a
    /// section's footer (``ScrollContentWindow/linesBelow``) — which ends the
    /// content where this stack does not.
    func advanceAnchor(to offset: Int, viewportHeight: Int, linesBelow: Int) {
        let count = children.count
        var anchor = min(state.anchorOrdinal, count - 1)
        var within = state.anchorOffsetWithin
        let delta = offset - state.lastDerivedOffset
        if abs(delta) > viewportHeight * 4, let reported = state.lastReportedTotal,
            offset + viewportHeight >= reported
        {
            // A jump to the very bottom of what this stack last reported — End,
            // a tail glue re-asserted after the total refined, a scrollbar
            // dragged down — means the LAST rows, whatever the running pitch
            // says. Mapped through the average instead, a tail of rows taller
            // than the rest (groups that grow down the list) lands short: the
            // average the tail itself raised divides the offset into an ordinal
            // far above it, and End showed the last row for a frame and then
            // settled mid-list. So the bottom is placed exactly, from the last
            // row up — the estimate is exact at the endpoints.
            //
            // At this stack's end, which is the viewport's bottom only when
            // nothing is drawn below the stack. A footer fills the viewport's
            // lines past the end: placed at the viewport's bottom, the last row
            // pushed the footer below it, and a jump to the content's end that
            // is not glued (`scrollTo(y:)` past it) stayed there, the footer
            // never shown.
            let pastEnd = min(offset + viewportHeight - reported, linesBelow)
            (anchor, within) = tailAnchor(endingAt: viewportHeight - pastEnd)
        } else if abs(delta) > viewportHeight * 4 {
            let estimate = state.estimatedPitch(spacing: spacing)
            anchor = min(count - 1, max(0, offset / estimate))
            within = max(0, offset - anchor * estimate)
        } else if delta != 0 {
            within += delta
            while within < 0, anchor > 0 {
                anchor -= 1
                within += pitch(of: anchor)
            }
            if within < 0 { within = 0 }
            while anchor < count - 1, within >= pitch(of: anchor) {
                within -= pitch(of: anchor)
                anchor += 1
            }
        }
        // Clamp against the CURRENT pitch unconditionally — not just on the
        // frames that scrolled. A width change re-wraps rows and shrinks
        // pitches under a stale `within` (a viewport top that was a wrap
        // continuation line no longer exists), and without this the anchor
        // row silently drifts above the viewport on a resize frame whose
        // offset didn't move (§5e: the anchor row is pinned by construction).
        //
        // The last row alone may sit wholly above the viewport, when what is
        // drawn below this stack is taller than the viewport: at the content's
        // end the viewport's top is `linesBelow - viewportHeight` lines past
        // the stack's end. Held to the viewport, the last row's last line rode
        // down with every line scrolled, the footer under it, whose end was
        // never reached.
        let pastEnd = anchor == count - 1 ? max(0, linesBelow - viewportHeight + 1) : 0
        within = min(within, max(0, pitch(of: anchor) - 1 + pastEnd))
        // A negative offset is a viewport whose top shows what the scroll
        // content draws above this stack — a section's header
        // (`ScrollContentWindow/linesAbove`) — so the first row sits that many
        // lines down it. Every branch above floors `within` at 0, which would
        // have drawn row 0 at the viewport's top, over the header's lines.
        if offset < 0 {
            anchor = 0
            within = offset
        }
        state.anchorOrdinal = anchor
        state.anchorOffsetWithin = within
        state.lastDerivedOffset = offset
    }

    /// The anchor that puts the last row's bottom `line` lines below the
    /// viewport's top — at its bottom, or above a footer — walking up from the
    /// last row by exact pitches until those lines are covered: the row
    /// reached and how many of its lines sit above the viewport's top. At or
    /// above the top (`line <= 0`, a footer taller than the viewport) that is
    /// the last row, wholly above it. O(the rows one viewport shows).
    func tailAnchor(endingAt line: Int) -> (ordinal: Int, within: Int) {
        var ordinal = children.count - 1
        var covered = pitch(of: ordinal)
        while covered < line, ordinal > 0 {
            ordinal -= 1
            covered += pitch(of: ordinal)
        }
        return (ordinal, max(0, covered - line))
    }

    /// Fills outward from the anchor: the anchor row sits exactly at
    /// (offset − offsetWithin); rows below fill until the viewport plus one
    /// margin row is covered; one margin row above (when it fits the
    /// absolute space). Returns the placements plus the deepest ordinal
    /// reached and the y just below it (the estimated-suffix base).
    func fill(window: ScrollContentWindow) -> (placed: [(ordinal: Int, y: Int)], last: Int, bottomY: Int) {
        let count = children.count
        let anchor = state.anchorOrdinal
        let anchorY = window.offset - state.anchorOffsetWithin
        var placed: [(ordinal: Int, y: Int)] = []
        var y = anchorY
        var ordinal = anchor
        let windowBottom = window.offset + window.viewportHeight
        while ordinal < count, y < windowBottom {
            placed.append((ordinal, y))
            y += pitch(of: ordinal)
            ordinal += 1
        }
        if ordinal < count {
            placed.append((ordinal, y))  // bottom margin row
            y += pitch(of: ordinal)
        }
        let last = placed.last?.ordinal ?? anchor
        // Fill upward from the anchor, covering the viewport top plus one
        // margin row for scroll-up reveal. With the implicit top anchor
        // (`anchorOffsetWithin >= 0`, so `anchorY <= offset`) the anchor is
        // already the top-visible row, and this places exactly ONE row — the
        // margin above it — as the single-margin version did. A DESIGNATED row
        // held BELOW the top (`anchorOffsetWithin < 0`, `anchorY > offset`)
        // also draws the now-visible rows between the top and the anchor.
        var upperY = anchorY
        var above = anchor - 1
        var reachedTop = anchorY <= window.offset
        while above >= 0 {
            let aboveY = upperY - pitch(of: above)
            if aboveY < 0 { break }  // absolute-space floor (full-height buffer)
            placed.append((above, aboveY))
            upperY = aboveY
            if reachedTop { break }  // just placed the one margin row above the top
            if aboveY <= window.offset { reachedTop = true }  // this row IS the top-visible one
            above -= 1
        }
        return (placed, last, y)
    }
}

// MARK: - The anchored render

extension _VStackCore {
    /// Row counts above this use the anchored walk once uniform arithmetic
    /// is unavailable; at or below it, the exact full walk is cheap and
    /// keeps small stacks byte-exact in absolute space.
    static var anchoredWindowThreshold: Int { 256 }

    /// How many leading rows the anchored estimate measures for its pitch (and,
    /// within the budget's reach, its width). The uniform seek's width records
    /// seed from the same count, so the two paths answer alike.
    static var anchoredWidthSampleCount: Int { 16 }

    /// Applies a DESIGNATED row anchor (`.anchorPosition(.row(id))`), which
    /// replaces the implicit top-visible anchor, and returns its key (or `nil`
    /// when no designation is in force).
    ///
    /// The key is re-asserted every frame — that stickiness IS the hold, since
    /// `rebindAnchor` then finds wherever the row has moved to, so an insert or
    /// delete around it shifts the scroll position rather than the row. When
    /// the designation CHANGES the row is *adopted*: it keeps the screen line
    /// it currently occupies (`adoptDesignatedRow`), so designating — or, via
    /// the §1.2 shadow switch, selecting — a visible row does not jerk the
    /// viewport to the top.
    ///
    /// A row that is not in the data is not designated yet: nothing is held,
    /// the frame is drawn as with no designation, and the row is adopted on
    /// the frame it arrives, as the other two paths adopt it
    /// (`offsetHoldingDesignatedRow`) — and as a `scrollTo` of it moves
    /// nothing. Held from the start, the row at the anchor stood in for it at
    /// the viewport's top, and since a designation owns the anchor, the offset
    /// no longer moved it: a `.scrollPosition` scroll moved the scrollbar and
    /// not the rows. Once adopted, a row that leaves the data is held by its
    /// nearest neighbour (the ladder, `rebindAnchor`).
    private func applyDesignatedAnchor(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, context: RenderContext, mode: ScrollAnchorMode
    ) -> String? {
        guard mode == .row,
            let key = context.environment.anchorPosition?.wrappedValue?.rowKey
        else {
            state.designatedAnchorKey = nil
            return nil
        }
        if state.designatedAnchorKey != key {
            guard
                let designated = resolveOrdinal(
                    forKey: key, children: frame.children, state: state)
            else {
                state.designatedAnchorKey = nil
                return nil
            }
            state.designatedAnchorKey = key
            adoptDesignatedRow(frame: frame, state: state, window: window, designated: designated)
        }
        state.anchorKey = key
        return key
    }

    /// Adopts a newly designated row: it becomes the anchor at the screen line
    /// it currently occupies, encoded as a SIGNED `anchorOffsetWithin` —
    /// negative meaning the anchor sits that many lines BELOW the viewport top,
    /// which `fill` renders by walking upward from it. (The implicit top anchor
    /// keeps a non-negative `within`: cells hidden ABOVE the top.)
    private func adoptDesignatedRow(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, designated: Int
    ) {
        let line = adoptedHeldLine(
            frame: frame, state: state, window: window, designated: designated)
        state.anchorOrdinal = designated
        state.anchorOffsetWithin = -line
    }

    /// The screen line the designated row occupies right now, so adoption holds
    /// it there rather than at the top. Walked from the current anchor — bounded,
    /// since a visible row is at most a viewport of rows away. A row farther than
    /// that is off-screen: there is no line to preserve, so it is revealed at the
    /// top edge (minimal-movement reveal, as `scrollTo(_:anchor: nil)` does). The
    /// result is clamped into the viewport, reserving the indicator lines, so an
    /// off-by-a-little visible row still lands on a real line.
    private func adoptedHeldLine(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, designated: Int
    ) -> Int {
        let anchor = state.anchorOrdinal
        guard abs(designated - anchor) <= window.viewportHeight + 2 else {
            return window.edgeInset
        }
        var line = -state.anchorOffsetWithin
        if designated >= anchor {
            for ordinal in anchor..<designated { line += frame.pitch(of: ordinal) }
        } else {
            for ordinal in designated..<anchor { line -= frame.pitch(of: ordinal) }
        }
        let rowHeight =
            frame.pitch(of: designated) - (designated < frame.children.count - 1 ? spacing : 0)
        let lastLine = max(window.edgeInset, window.viewportHeight - rowHeight - window.edgeInset)
        return min(max(line, window.edgeInset), lastLine)
    }

    /// Sticky top for a below-top hold: a held row cannot sit lower on screen
    /// than the content above it can fill. Bounded by the held line (≤ one
    /// viewport).
    ///
    /// When the rows above it run out before its line, every one of them has
    /// been measured, so the row's place in the stack is exact — `available`
    /// lines down — and so is the offset that holds it on its line: that place
    /// less the line, as the other two paths hold a row
    /// (`offsetHoldingDesignatedRow`), but no higher than the content's top,
    /// the first line of what the scroll content draws above this stack — a
    /// section's header (`ScrollContentWindow/scrollableOffsets(stackHeight:)`).
    /// There the row rides up until the content's first line meets the
    /// viewport's, and is re-anchored where it lands. The offset is returned
    /// for the scroll view to adopt. Riding up at the offset it had, the row
    /// kept the rows above it on screen but not the offset: scrolled down when
    /// rows above it were deleted, the first row was drawn where the offset
    /// was — under "N more lines above", with nothing above it. And ridden up
    /// by the header's lines on screen at the offset it was handed, a row held
    /// under a header of two lines or more is drawn off its line — rows placed
    /// above the stack's top, which the fill drops — when a row is inserted
    /// above it or the header grows, and a scroll that takes a header line off
    /// screen rides the row up rather than leaving it on its line.
    ///
    /// When the rows above the held row fill its line, none of the header can
    /// be on screen, so a negative offset is raised — to where the topmost of
    /// those rows starts at the stack's top, the highest the fill places a
    /// row — and returned likewise. Left negative, the row sat the header's
    /// lines above its line, where that floor stopped the rows above it: a row
    /// designated off screen under a header showed on line 0, not under the
    /// "more above" line on line 1, and moved down to it on the first line
    /// scrolled.
    private func clampDesignatedHold(
        frame: AnchoredWindowFrame, state: StackWindowState, window: inout ScrollContentWindow
    ) -> Int? {
        let heldLine = -state.anchorOffsetWithin
        var available = 0
        var ordinal = state.anchorOrdinal - 1
        while ordinal >= 0, available < heldLine {
            available += frame.pitch(of: ordinal)
            ordinal -= 1
        }
        if available < heldLine {
            let offset = max(available - heldLine, -window.linesAbove)
            state.anchorOffsetWithin = offset - available
            guard offset != window.offset else { return nil }
            window.offset = offset
            return offset
        }
        guard window.offset < 0 else { return nil }
        window.offset = available - heldLine
        return window.offset
    }

    /// Resolves a pending `scrollTo` against the anchored geometry: pins the
    /// anchor to the TARGET (§5e — seek by anchor, not by absolute offset) and
    /// re-aims `window.offset`, returning the offset to report (or `nil` when
    /// there is no request or its key is absent). The estimated y positions
    /// only the scrollbar and the clamp; the target row itself lands exactly
    /// where the anchor walk puts it, estimates notwithstanding.
    private func resolveAnchoredSeek(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: inout ScrollContentWindow, children: ChildViewCollection
    ) -> Int? {
        guard let seek = window.seek else { return nil }
        window.seek = nil
        guard let ordinal = resolveOrdinal(forKey: seek.key, children: children, state: state)
        else { return nil }
        // Nil anchor near the window resolves in WALKED row space: an
        // already-visible target moves NOTHING, a nearby one moves minimally.
        // The estimate path below judges visibility by estimate-space y against
        // the walked offset — two coordinate spaces that drift apart — and
        // teleported the view (and the scrollbar) for a plainly on-screen row.
        if seek.anchor == nil,
            let nearOffset = nilAnchorSeekOffset(
                target: ordinal, frame: frame, state: state,
                window: window, seek: seek, count: children.count)
        {
            window.offset = nearOffset
            return nearOffset
        }
        let estimate = state.estimatedPitch(spacing: spacing)
        let estimatedY = ordinal * estimate
        let rowHeight = frame.pitch(of: ordinal) - (ordinal < children.count - 1 ? spacing : 0)
        let newOffset = window.offset(
            realising: seek, targetY: estimatedY, rowHeight: rowHeight,
            stackHeight: children.count * estimate - spacing)
        state.anchorOrdinal = ordinal
        state.anchorKey = children.key(at: ordinal)
        state.anchorOffsetWithin = 0
        state.lastDerivedOffset = estimatedY
        window.offset = newOffset
        return newOffset
    }

    /// Renders the window by anchored outward fill, or returns `nil` when a
    /// touched row is a spacer (spacer distribution needs the full walk).
    func renderAnchoredWindow(
        _ children: ChildViewCollection, window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer? {
        let state = uniformWindowState(context: context)
        guard !children.isEmpty else { return FrameBuffer() }

        // An explicit `.alignmentGuide` needs the whole run to place a row, and
        // materialising the whole run is exactly what this arithmetic path
        // exists to avoid. Decline instead, and let the exact slot walk — which
        // measures every row anyway — do the placement. Row 0 answers for all of
        // them: this path only runs over a uniformly keyed collection, whose
        // rows are built by one closure.
        guard !children[0].providesAlignmentGuide else { return nil }

        // Off-window rows leave the WINDOW, not the tree (§5h).
        context.stateStorage?.retainSubtree(context.identity)

        var childContext = context
        childContext.leaveScrollOrigin()
        let width = context.availableWidth
        let frame = AnchoredWindowFrame(
            children: children, spacing: spacing, state: state,
            proposal: ProposedSize(width: width, height: nil), context: childContext)

        let anchorMode = ScrollAnchorMode.effective(
            boundAnchor: context.environment.anchorPosition?.wrappedValue,
            defaultScrollAnchor: context.environment.defaultScrollAnchor)
        let designatedKey = applyDesignatedAnchor(
            frame: frame, state: state, window: window, context: context, mode: anchorMode)

        // A designation naming no row is none (`applyDesignatedAnchor`), and
        // the anchor is re-bound as with none: by the declared mode. Re-bound
        // as `.row`, the row at the top was held by its key in the missing
        // row's place, and an insert above it left the rows where they were,
        // where with no designation they move down.
        frame.rebindAnchor(
            mode: anchorMode == .row && designatedKey == nil
                ? ScrollAnchorMode.effective(
                    boundAnchor: nil, defaultScrollAnchor: context.environment.defaultScrollAnchor)
                : anchorMode)

        var window = window
        let resolvedSeek = resolveAnchoredSeek(
            frame: frame, state: state, window: &window, children: children)

        var heldOffset: Int?
        if designatedKey == nil {
            frame.advanceAnchor(
                to: window.offset, viewportHeight: window.viewportHeight,
                linesBelow: window.linesBelow)
            state.anchorKey = children.key(at: state.anchorOrdinal)
        } else {
            // A DESIGNATED row owns the anchor: the scroll position follows the
            // ROW, not the other way round. So neither walk the anchor by the
            // offset delta (that is how user scrolling moves it) nor re-derive
            // the key from whatever ordinal the offset implies — both would
            // drag the anchor off the designated row every frame, which is
            // exactly what made `.row` behave as "hold the top visible row".
            // A below-top hold rides up when the content above it shrinks past
            // its held line: once the rows above it run out, its place is exact
            // and the offset is the one that holds it, the row riding up only
            // past the content's top; while they fill its line, the header is
            // taken off screen. `lastDerivedOffset` is still synced so no
            // phantom delta accumulates if the designation is later cleared.
            heldOffset = clampDesignatedHold(frame: frame, state: state, window: &window)
            state.lastDerivedOffset = window.offset
        }
        var (placed, lastPlaced, bottomY) = frame.fill(window: window)
        // The rows the fill drew, before any focus target joins them.
        let drawn = ordinalSpan(of: placed.map(\.ordinal))

        // Focus / pending targets, wherever they are (§5d): estimated
        // positions relative to the anchor — the reveal snap converges on
        // them, and "already visible → do nothing" ends the chase. In band
        // mode (a reply channel) a far target must not stretch the band —
        // the gap would materialise as O(distance) blank lines — so it is
        // grafted out-of-band instead; classic mode keeps it inline in the
        // full-height canvas.
        var grafts: [(ordinal: Int, y: Int)] = []
        if let focusManager = context.environment.focusManager {
            let anchorY = window.offset - state.anchorOffsetWithin
            let estimate = state.estimatedPitch(spacing: spacing)
            let placedOrdinals = Set(placed.map(\.ordinal))
            for target in [focusManager.currentFocusedID, focusManager.pendingFocusID] {
                guard let focusID = target,
                    let key = Self.rowKey(inFocusID: focusID, belowStackPath: context.identity.path),
                    let ordinal = resolveOrdinal(forKey: key, children: children, state: state),
                    !placedOrdinals.contains(ordinal)
                else { continue }
                // Clamped, never dropped: an above-window target's estimate
                // routinely goes negative, and dropping it meant the row
                // never rendered, never registered, and upward reveal never
                // happened. At y 0 the region still tells the snap "scroll
                // up", which is all convergence needs.
                let estimatedY = anchorY + (ordinal - state.anchorOrdinal) * estimate
                if window.reply == nil {
                    placed.append((ordinal, max(0, estimatedY)))
                } else {
                    grafts.append((ordinal, max(0, estimatedY)))
                }
            }
        }
        // Ring continuation (see StackFocusReach.swift): the nearest
        // focusable row past a non-focusable run adjacent to focus must
        // render too, or Tab dead-ends at the run. Positioned like any
        // other off-window target: estimated y relative to the anchor.
        let focusedOrdinal = targetOrdinal(
            for: context.environment.focusManager?.currentFocusedID,
            children: children, state: state, context: context)
        if focusedOrdinal != nil {
            let anchorY = window.offset - state.anchorOffsetWithin
            let estimate = state.estimatedPitch(spacing: spacing)
            let covered = Set(placed.map(\.ordinal)).union(grafts.map(\.ordinal))
            for stop in focusRingContinuations(
                focusedOrdinal: focusedOrdinal, count: children.count,
                child: { frame.child(at: $0) }, width: width,
                viewportHeight: window.viewportHeight, context: childContext)
            where !covered.contains(stop) {
                let estimatedY = anchorY + (stop - state.anchorOrdinal) * estimate
                if window.reply == nil {
                    placed.append((stop, max(0, estimatedY)))
                } else {
                    grafts.append((stop, max(0, estimatedY)))
                }
            }
        }
        // Grafts render after the band; keep them in ascending row order so
        // the focus ring (registration order) stays in data order.
        grafts.sort { $0.ordinal < $1.ordinal }
        guard !frame.sawSpacer else { return nil }

        let buffer = assembleAnchoredBuffer(
            placed: placed, grafts: grafts, lastPlaced: lastPlaced, bottomY: bottomY,
            frame: frame, window: window, width: width, context: childContext)
        // Answer the seek only on success: a nil (spacer bail) falls to the
        // exact path, which re-resolves against its own geometry. A hold that
        // moved the offset after the seek has the last word.
        if buffer != nil, let offset = heldOffset ?? resolvedSeek {
            window.reply?.seekResolvedOffset = offset
        }
        if buffer != nil { state.drawnOrdinals = drawn }
        return buffer
    }

    /// Assembles the full-height buffer: rendered rows at their y, exact
    /// blank blocks between, and the estimated suffix (exact when the fill
    /// reached the tail) that feeds contentHeight and so the scrollbar.
    /// Estimated-position rows that would overlap real ones are pushed down
    /// — their exact place is unknowable without the prefix sum nobody
    /// computes (§3).
    private func assembleAnchoredBuffer(
        placed: [(ordinal: Int, y: Int)], grafts: [(ordinal: Int, y: Int)],
        lastPlaced: Int, bottomY: Int,
        frame: AnchoredWindowFrame, window: ScrollContentWindow, width: Int,
        context: RenderContext
    ) -> FrameBuffer? {
        let state = frame.state
        var sorted = placed
        sorted.sort { $0.y < $1.y }

        // With a reply channel (Stage 6) the buffer is the rendered band
        // only; prefix/suffix become metadata. See the uniform assembly.
        // A ramp spanning this stack runs across the whole CONTENT. Every
        // number on this path is an estimate — the rows' positions from the
        // anchor outward, the height from the running pitch average (§3) — so
        // the ramp is estimated with them, and converges as the walk learns
        // the real pitch. Exact would mean the full prefix sum this path
        // exists in order not to compute.
        let gradientFrame = context.gradientContentFrame(
            width: width,
            height: max(
                1,
                frame.children.count * state.estimatedPitch(spacing: spacing)
                    - (frame.children.count > 1 ? spacing : 0)))

        var result = FrameBuffer()
        let sliceOrigin = window.reply != nil ? (sorted.first?.y ?? 0) : 0
        var cursor = sliceOrigin
        var memo: [String: Int] = [:]
        // The line whose row is reported back, in this stack's coordinates,
        // and the row found there (see ``ScrollContentWindow/reportsIDAt``):
        // the first whose bottom lies past the line, as on the other two
        // paths. A line of a section's header above this stack (a negative
        // offset) reports the first row, as the exact paths do.
        let sampleY = window.sampleY(
            at: window.reportsIDAt ?? .top,
            contentBelow: lastPlaced < frame.children.count - 1
                || window.hasContentBelow(stackBottom: bottomY))
        var sampledOrdinal: Int?
        for (ordinal, y) in sorted {
            let rowHeight =
                frame.pitch(of: ordinal)
                - (ordinal < frame.children.count - 1 ? spacing : 0)
            let slotY = max(y, cursor)
            if slotY > cursor {
                result.appendVertically(FrameBuffer(emptyWithHeight: slotY - cursor), spacing: 0)
            }
            // At the height it was measured at, not the viewport's: the pitch
            // walk measured it at its ideal height, and a row taller than the
            // viewport drawn at the viewport's was cut to its first screenful
            // and padded out with blank lines — the rest of it never drawn,
            // however far the scroll view moved over it.
            var rendered = frame.child(at: ordinal).render(
                width: width, height: rowHeight,
                context: context.placingGradientChild(
                    gradientFrame,
                    x: Self.gradientX(
                        childWidth: frame.measuredWidth(of: ordinal) ?? width,
                        extent: width, alignment: alignment),
                    y: slotY))
            rendered = alignBuffer(rendered, toWidth: width, alignment: alignment)
            var slot = FrameBuffer()
            slot.appendVertically(rendered, spacing: 0)
            if slot.height < rowHeight {
                slot.appendVertically(
                    FrameBuffer(emptyWithHeight: rowHeight - slot.height), spacing: 0)
            } else if slot.height > rowHeight {
                slot = slot.clamped(toWidth: max(width, slot.width), height: rowHeight)
            }
            result.appendVertically(slot, spacing: 0)
            // Rows are variable-height here, so unlike the uniform path this
            // cannot be a division — but the spans are being walked anyway. A
            // line in the gap between two rows belongs to the row below it;
            // taken only inside a row, that line named no row at all.
            if window.reportsIDAt != nil, sampledOrdinal == nil, sampleY < slotY + rowHeight {
                sampledOrdinal = ordinal
            }
            cursor = slotY + rowHeight
            if let key = frame.children.key(at: ordinal) { memo[key] = ordinal }
        }
        guard !frame.sawSpacer else { return nil }
        // A line past every row drawn lies below the last row — the fill
        // covers the viewport while rows remain — over what the scroll content
        // draws below this stack: a section's footer. It reports the last row,
        // as the other two paths clamp their sample to it; it named none, and
        // the binding kept a stale id or none.
        if window.reportsIDAt != nil, sampledOrdinal == nil {
            sampledOrdinal = sorted.last?.ordinal
        }
        for (ordinal, y) in grafts {
            // The graft's y is an ESTIMATE (ordinal distance × running pitch
            // average), and on this path's whole domain — variable-height
            // rows — it can land INSIDE the rendered band, where the grafted
            // row's hit regions would overlay a visible row's and steal its
            // clicks. An off-band row is outside the band by definition, so
            // clamp a wayward estimate to the nearest edge OUTSIDE on its
            // true side (known from the ordinal): the reveal math keeps the
            // direction and the viewport clip drops the regions, exactly as
            // the accurate-estimate case always behaved.
            var bandLocalY = y - sliceOrigin
            let bandHeight = cursor - sliceOrigin
            if let firstPlaced = sorted.first?.0, ordinal < firstPlaced {
                // A full viewport height clear of the band top: the grafted
                // regions are at most viewportHeight tall (the row renders at
                // that height), so nothing can poke past 0 — a row-pitch
                // margin was not enough when the region outlived the pitch.
                bandLocalY = min(bandLocalY, -window.viewportHeight)
            } else {
                // Below — or BETWEEN placed runs, where the estimate is
                // ambiguous: out of the band is the contract either way.
                bandLocalY = max(bandLocalY, bandHeight)
            }
            graftOffBandRow(
                frame.child(at: ordinal), into: &result, bandLocalY: bandLocalY,
                width: width, viewportHeight: window.viewportHeight,
                context: context.placingGradientChild(
                    gradientFrame,
                    x: Self.gradientX(
                        childWidth: frame.measuredWidth(of: ordinal) ?? width,
                        extent: width, alignment: alignment),
                    y: y))
            if let key = frame.children.key(at: ordinal) { memo[key] = ordinal }
        }
        state.rowOrdinalMemo = memo

        let remaining = frame.children.count - 1 - lastPlaced
        let estimate = state.estimatedPitch(spacing: spacing)
        // The estimate prices each remaining row at height + below-gap; the
        // actual last row has no below-gap, so an estimated suffix carries
        // one spacing too many.
        let total =
            max(cursor, bottomY) + max(0, remaining) * estimate
            - (remaining > 0 ? spacing : 0)
        state.lastReportedTotal = total
        if let reply = window.reply {
            reply.sliceOriginY = sliceOrigin
            reply.sliceTotalHeight = total
            reply.sliceHoldsFirstRow = (sorted.first?.ordinal ?? 0) == 0
            reply.sliceHoldsLastRow = remaining <= 0
            // Anchored absolute space is estimate-derived: the unmeasured
            // remainder is priced at the running pitch average, and the band
            // origin itself drifts with past estimates. Even at the tail
            // (remaining == 0) the prefix above is estimated.
            reply.sliceTotalIsEstimate = true
            if let sampledOrdinal {
                reply.anchorID = frame.children.anyID(at: sampledOrdinal)
            }
        } else if total > cursor {
            result.appendVertically(FrameBuffer(emptyWithHeight: total - cursor), spacing: 0)
        }
        return result
    }

    /// Resolves a nil-anchor ("minimal movement") seek in WALKED row space,
    /// for targets near the current window: the exact pitch walk gives the
    /// target's true viewport-local position, so an already-visible target
    /// (within the indicator-clipped band, as the reveal snap defines it)
    /// moves nothing and a nearby one moves just enough. Far targets return
    /// `nil` — minimality is meaningless hundreds of rows away, and the
    /// estimate seek handles them.
    private func nilAnchorSeekOffset(
        target: Int, frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, seek: ScrollToRequest, count: Int
    ) -> Int? {
        let anchor = state.anchorOrdinal
        guard abs(target - anchor) <= window.viewportHeight * 2 + 4 else { return nil }
        var y = -state.anchorOffsetWithin
        if target >= anchor {
            for ordinal in anchor..<target { y += frame.pitch(of: ordinal) }
        } else {
            for ordinal in target..<anchor { y -= frame.pitch(of: ordinal) }
        }
        let rowHeight = frame.pitch(of: target) - (target < count - 1 ? spacing : 0)

        // The indicators are the scroll content's: a section's header above
        // this stack is content above, its footer content below
        // (`ScrollContentWindow/linesAbove`, `linesBelow`).
        let above = window.linesAbove
        let topShown = (seek.topInset > 0 && window.offset + above > 0) ? 1 : 0
        var lastVisible = anchor
        var walked = -state.anchorOffsetWithin
        while lastVisible < count - 1,
            walked + frame.pitch(of: lastVisible) < window.viewportHeight
        {
            walked += frame.pitch(of: lastVisible)
            lastVisible += 1
        }
        let lastHeight =
            frame.pitch(of: lastVisible) - (lastVisible < count - 1 ? spacing : 0)
        let contentBelow =
            lastVisible < count - 1
            || walked + lastHeight + window.linesBelow > window.viewportHeight
        let bottomShown = (seek.bottomInset > 0 && contentBelow) ? 1 : 0

        if y >= topShown, y + rowHeight <= window.viewportHeight - bottomShown {
            return window.offset  // fully visible: strict no-op
        }
        if y < topShown {
            // The first row's top is the stack's, 0, whatever the walk says:
            // walked from an anchor placed by an estimate, rows near the top
            // can sit a line or two off it. Under a section's header that line
            // was the header's — the seek scrolled to the first row and left
            // the header hidden, where the same seek in a column shows it.
            let destination = target == 0 ? 0 : window.offset + y
            let topPad = (seek.topInset > 0 && destination + above > 0) ? 1 : 0
            return max(-above, destination - topPad)
        }
        let bottomPad =
            (seek.bottomInset > 0 && (target < count - 1 || window.linesBelow > 0)) ? 1 : 0
        return max(-above, window.offset + y + rowHeight - window.viewportHeight + bottomPad)
    }

    /// Memo hit, else one key scan (never builds a row view). Shared by the
    /// anchored and uniform paths (focus targets and scrollTo seeks alike).
    func resolveOrdinal(
        forKey key: String, children: ChildViewCollection, state: StackWindowState
    ) -> Int? {
        if let memoised = state.rowOrdinalMemo[key],
            memoised < children.count, children.key(at: memoised) == key
        {
            return memoised
        }
        return children.firstOrdinal(forKey: key)
    }
}
