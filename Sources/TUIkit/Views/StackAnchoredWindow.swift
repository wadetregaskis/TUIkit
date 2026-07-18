//  🖥️ TUIKit — Terminal UI Kit for Swift
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
        let value = max(1, measured.height) + (ordinal > 0 ? spacing : 0)
        pitchCache[ordinal] = value
        built[ordinal] = child
        state.recordMeasuredPitch(value)
        return value
    }

    func child(at ordinal: Int) -> ChildView {
        built[ordinal] ?? children[ordinal]
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
    func rebindAnchor() {
        let count = children.count
        guard count > 0 else { return }
        state.anchorOrdinal = min(max(0, state.anchorOrdinal), count - 1)
        guard let anchorKey = state.anchorKey else { return }
        guard children.key(at: state.anchorOrdinal) != anchorKey else { return }

        if let found = locate(key: anchorKey) {
            state.anchorOrdinal = found
            return
        }
        let neighbours = state.rowOrdinalMemo.sorted {
            abs($0.value - state.anchorOrdinal) < abs($1.value - state.anchorOrdinal)
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
    func advanceAnchor(to offset: Int, viewportHeight: Int) {
        let count = children.count
        var anchor = min(state.anchorOrdinal, count - 1)
        var within = state.anchorOffsetWithin
        let delta = offset - state.lastDerivedOffset
        if abs(delta) > viewportHeight * 4 {
            let estimate = state.estimatedPitch(spacing: spacing)
            anchor = min(count - 1, max(0, offset / estimate))
            within = max(0, offset - anchor * estimate)
            within = min(within, max(0, pitch(of: anchor) - 1))
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
            within = min(within, max(0, pitch(of: anchor) - 1))
        }
        state.anchorOrdinal = anchor
        state.anchorOffsetWithin = within
        state.lastDerivedOffset = offset
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
        if anchor > 0 {
            let above = anchor - 1
            let aboveY = anchorY - pitch(of: above)
            if aboveY >= 0 { placed.append((above, aboveY)) }  // top margin row
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

    /// Renders the window by anchored outward fill, or returns `nil` when a
    /// touched row is a spacer (spacer distribution needs the full walk).
    func renderAnchoredWindow(
        _ children: ChildViewCollection, window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer? {
        let state = uniformWindowState(context: context)
        guard !children.isEmpty else { return FrameBuffer() }

        // Off-window rows leave the WINDOW, not the tree (§5h).
        context.environment.stateStorage?.retainSubtree(context.identity)

        var childContext = context
        childContext.environment.scrollContentWindow = nil
        let width = context.availableWidth
        let frame = AnchoredWindowFrame(
            children: children, spacing: spacing, state: state,
            proposal: ProposedSize(width: width, height: nil), context: childContext)

        frame.rebindAnchor()

        // A pending scrollTo: pin the anchor to the TARGET (§5e — seek by
        // anchor, not by absolute offset). The estimated y positions only
        // the scrollbar and the clamp; the target row itself lands exactly
        // where the anchor walk below puts it, estimates notwithstanding.
        // `advanceAnchor` then walks the (≤ viewport-sized) delta between
        // the target's top and the anchor-adjusted offset in row space, so
        // centre/bottom alignment measures real rows, not estimates.
        var window = window
        var resolvedSeek: Int?
        if let seek = window.seek {
            window.seek = nil
            if let ordinal = resolveOrdinal(forKey: seek.key, children: children, state: state) {
                let estimate = state.estimatedPitch(spacing: spacing)
                let estimatedY = ordinal * estimate
                let rowHeight = frame.pitch(of: ordinal) - (ordinal > 0 ? spacing : 0)
                let newOffset = seek.windowOffset(
                    targetY: estimatedY, rowHeight: rowHeight, currentOffset: window.offset,
                    viewportHeight: window.viewportHeight,
                    totalHeight: children.count * estimate - spacing)
                state.anchorOrdinal = ordinal
                state.anchorKey = children.key(at: ordinal)
                state.anchorOffsetWithin = 0
                state.lastDerivedOffset = estimatedY
                window.offset = newOffset
                resolvedSeek = newOffset
            }
        }

        frame.advanceAnchor(to: window.offset, viewportHeight: window.viewportHeight)
        state.anchorKey = children.key(at: state.anchorOrdinal)
        var (placed, lastPlaced, bottomY) = frame.fill(window: window)

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
        guard !frame.sawSpacer else { return nil }

        let buffer = assembleAnchoredBuffer(
            placed: placed, grafts: grafts, lastPlaced: lastPlaced, bottomY: bottomY,
            frame: frame, window: window, width: width, context: childContext)
        // Answer the seek only on success: a nil (spacer bail) falls to the
        // exact path, which re-resolves against its own geometry.
        if buffer != nil, let resolvedSeek {
            window.reply?.seekResolvedOffset = resolvedSeek
        }
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
        var result = FrameBuffer()
        let sliceOrigin = window.reply != nil ? (sorted.first?.y ?? 0) : 0
        var cursor = sliceOrigin
        var memo: [String: Int] = [:]
        for (ordinal, y) in sorted {
            let rowHeight = frame.pitch(of: ordinal) - (ordinal > 0 ? spacing : 0)
            let slotY = max(y, cursor)
            if slotY > cursor {
                result.appendVertically(FrameBuffer(emptyWithHeight: slotY - cursor), spacing: 0)
            }
            var rendered = frame.child(at: ordinal).render(
                width: width, height: window.viewportHeight, context: context)
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
            cursor = slotY + rowHeight
            if let key = frame.children.key(at: ordinal) { memo[key] = ordinal }
        }
        guard !frame.sawSpacer else { return nil }
        for (ordinal, y) in grafts {
            graftOffBandRow(
                frame.child(at: ordinal), into: &result, bandLocalY: y - sliceOrigin,
                width: width, viewportHeight: window.viewportHeight, context: context)
            if let key = frame.children.key(at: ordinal) { memo[key] = ordinal }
        }
        state.rowOrdinalMemo = memo

        let remaining = frame.children.count - 1 - lastPlaced
        let estimate = state.estimatedPitch(spacing: spacing)
        let total = max(cursor, bottomY) + max(0, remaining) * estimate
        if let reply = window.reply {
            reply.sliceOriginY = sliceOrigin
            reply.sliceTotalHeight = total
            // Anchored absolute space is estimate-derived: the unmeasured
            // remainder is priced at the running pitch average, and the band
            // origin itself drifts with past estimates. Even at the tail
            // (remaining == 0) the prefix above is estimated.
            reply.sliceTotalIsEstimate = true
        } else if total > cursor {
            result.appendVertically(FrameBuffer(emptyWithHeight: total - cursor), spacing: 0)
        }
        return result
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

    /// `windowSizeThatFits` for anchored (large, variable) content: the
    /// total is the running estimate, exact at the endpoints; width and
    /// flexibility come from a bounded sample. Estimation here is honest —
    /// the absolute total feeds only the scrollbar and the clip bound, both
    /// of which the design declares estimated (§3).
    func anchoredSizeThatFits(
        _ children: ChildViewCollection, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize? {
        let state = uniformWindowState(context: context)
        let count = children.count
        guard count > 0 else { return ViewSize.fixed(0, 0) }

        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.environment.scrollContentWindow = nil
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight
        let sampleProposal = ProposedSize(width: widthLimit, height: nil)

        var estimate = state.estimatedPitch(spacing: spacing)
        var maxWidth = 0
        var widthFlexible = false
        var heightFlexible = false
        var sampleTotal = 0
        let sampleSize = min(count, 16)
        for ordinal in 0..<sampleSize {
            let child = children[ordinal]
            guard !child.isSpacer else { return nil }
            let size = child.measure(proposal: sampleProposal, context: measureContext)
            sampleTotal += max(1, size.height) + (ordinal > 0 ? spacing : 0)
            maxWidth = max(maxWidth, min(size.width, widthLimit))
            if size.isWidthFlexible { widthFlexible = true }
            if size.isHeightFlexible { heightFlexible = true }
        }
        if state.measuredPitchCount < 1, sampleSize > 0 {
            estimate = max(1, sampleTotal / sampleSize)
        }

        let total = count * estimate - spacing
        return ViewSize(
            width: maxWidth, height: min(total, max(0, heightLimit)),
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }
}
