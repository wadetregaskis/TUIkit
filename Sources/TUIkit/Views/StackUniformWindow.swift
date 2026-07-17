//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StackUniformWindow.swift
//
//  The uniform-extent fast path of "Locating things without drawing them"
//  (§5i, worked example §6e): when a windowed lazy stack's rows provably
//  share one extent, every placement is arithmetic — the visible ordinals
//  come from a division, the prefix and suffix are single blank blocks of
//  exact height, and a frame touches O(window) rows instead of measuring
//  all N. The extent is a HYPOTHESIS: seeded from row 0, verified against
//  every row this path actually measures, and falsified same-frame — a row
//  of a different height flips the stack to the exact full walk before
//  anything wrong is drawn, permanently (the flag persists).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Persistent hypothesis state

/// `StateStorage` property indices for `_VStackCore` (file-scope: a generic
/// type cannot hold static storage).
private enum VStackStateIndex {
    /// The `UniformWindowState` hypothesis box.
    static let uniformWindow = 0
}

/// The windowed stack's persisted window state: the uniformity
/// hypothesis, and — for variable-height content — the scroll anchor
/// (§5e: `ScrollAnchor { item, offsetWithin }`, held here in ordinal
/// form beside the running extent estimate). File-scope (not nested in
/// `_VStackCore`) so non-generic helpers can hold it.
final class StackWindowState {
        /// Every row is exactly this tall, as far as this path has measured.
        /// `nil` until seeded (from row 0, on the render path only — the
        /// measure-side-effect rule forbids seeding while measuring).
        var hypothesisExtent: Int?

        /// A measured row disagreed: uniform arithmetic is dead, permanently
        /// — this stack uses the anchored walk (large N) or the exact full
        /// walk (small N) from then on.
        var broken = false

        /// Ordinals of recently rendered rows by their stable key, so the
        /// focused row (which moved off-window and must keep registering)
        /// resolves O(1) instead of re-scanning all keys. Rebuilt each fast
        /// frame from the rows it rendered; a miss falls back to the key
        /// scan — the documented Ω(n) id→ordinal cost, paid only on a cold
        /// jump and memoised while focus stays put.
        var rowOrdinalMemo: [String: Int] = [:]

        // MARK: Anchor (variable-height content, §5e/§6a)

        /// The row the viewport is anchored on.
        var anchorOrdinal = 0

        /// The anchored row's stable `ForEach` key (§5f): the anchor names a
        /// ROW, not a position. Data edits shift ordinals; each frame the
        /// ordinal is re-bound to this key before scroll input applies, so
        /// an insertion above the anchor moves nothing on screen (§6d) and a
        /// deleted anchor falls to its nearest surviving neighbour.
        var anchorKey: String?

        /// How many cells of the anchor row sit above the viewport top.
        var anchorOffsetWithin = 0

        /// The absolute offset the anchor was last derived against. Scroll
        /// input arrives as a new absolute offset; the DIFFERENCE is walked
        /// in row space (one line up looks at one row, §3), so estimates
        /// never move what's on screen — only the scrollbar.
        var lastDerivedOffset = 0

        /// Running average of measured row pitches (row + spacing), the
        /// extent estimate for rows never measured. Refined as rows are
        /// touched; drives the scrollbar and big-jump seeks only.
        var measuredPitchTotal = 0
        var measuredPitchCount = 0

        func recordMeasuredPitch(_ pitch: Int) {
            measuredPitchTotal += pitch
            measuredPitchCount += 1
        }

        /// The estimated pitch: measured average (rounded, not truncated —
        /// truncation systematically over-shoots seeks), else the uniform
        /// seed, else one line. Never below 1 (division safety).
        func estimatedPitch(spacing: Int) -> Int {
            if measuredPitchCount > 0 {
                let rounded = (measuredPitchTotal + measuredPitchCount / 2) / measuredPitchCount
                return max(1, rounded)
            }
            if let hypothesisExtent { return max(1, hypothesisExtent + spacing) }
            return 1
        }
}

extension _VStackCore {
    func uniformWindowState(context: RenderContext) -> StackWindowState {
        let stateStorage = context.environment.stateStorage!
        let key = StateStorage.StateKey(
            identity: context.identity, propertyIndex: VStackStateIndex.uniformWindow)
        let box: StateBox<StackWindowState> = stateStorage.storage(
            for: key, default: StackWindowState())
        // The box lives at the stack's OWN identity, which nothing else marks
        // active: _VStackCore is Renderable (no body-hydration markActive) and
        // registers no focusable, and retainSubtree protects strict
        // DESCENDANTS only. Without this, endRenderPass pruned the anchor
        // and hypothesis every frame — each "anchored" frame silently
        // re-derived from scratch (deterministic, so single-data tests
        // couldn't see it; the §5f insert-above test caught it).
        stateStorage.markActive(context.identity)
        return box.value
    }
}

// MARK: - Focus-target key extraction

extension _VStackCore {
    /// The `ForEach` key of the row a (default, path-derived) focus ID
    /// addresses below this stack, parsed straight out of the ID — the row's
    /// path component is `TypeName[key]` immediately after the stack's path.
    /// Explicit `.focusID("…")` strings embed no path and return `nil`.
    static func rowKey(inFocusID id: String, belowStackPath stackPath: String) -> String? {
        guard !stackPath.isEmpty, let range = id.range(of: stackPath) else { return nil }
        let rest = id[range.upperBound...]
        guard rest.first == "/" else { return nil }
        guard let open = rest.firstIndex(of: "["),
            !rest[rest.startIndex..<open].dropFirst().contains("/"),
            let close = rest[rest.index(after: open)...].firstIndex(of: "]")
        else { return nil }
        return String(rest[rest.index(after: open)..<close])
    }
}

// MARK: - The seek render

extension _VStackCore {
    /// Renders the window by arithmetic seek, or returns `nil` when the
    /// uniform hypothesis is unusable (unseeded on a measure-only frame,
    /// previously broken, or falsified by a row measured right now) — the
    /// caller then takes the exact full-walk path in the same frame.
    func renderUniformSeekWindow(
        _ children: ChildViewCollection, window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer? {
        let state = uniformWindowState(context: context)
        guard !state.broken else { return nil }
        guard !children.isEmpty else { return FrameBuffer() }

        // Off-window rows leave the WINDOW, not the tree (§5h).
        context.environment.stateStorage?.retainSubtree(context.identity)

        var childContext = context
        childContext.environment.scrollContentWindow = nil
        let width = context.availableWidth

        // Seed the hypothesis from row 0 (render path: mutation is legal).
        let extent: Int
        if let known = state.hypothesisExtent {
            extent = known
        } else {
            let seed = children[0].measure(
                proposal: ProposedSize(width: width, height: nil), context: childContext)
            guard seed.height > 0 else {
                state.broken = true
                return nil
            }
            state.hypothesisExtent = seed.height
            extent = seed.height
        }
        let pitch = extent + spacing
        guard pitch > 0 else {
            state.broken = true
            return nil
        }
        let count = children.count
        let totalHeight = count * pitch - spacing

        let candidates = candidateOrdinals(
            children: children, window: window, pitch: pitch, state: state, context: context)

        // Build + verify each candidate. A disagreeing height falsifies the
        // hypothesis for good; the caller re-walks exactly, this same frame.
        let proposal = ProposedSize(width: width, height: nil)
        var rows: [(ordinal: Int, child: ChildView)] = []
        rows.reserveCapacity(candidates.count)
        for ordinal in candidates.sorted() {
            let child = children[ordinal]
            let measured = child.measure(proposal: proposal, context: childContext)
            guard measured.height == extent, !child.isSpacer else {
                state.broken = true
                return nil
            }
            rows.append((ordinal, child))
        }

        // Assemble: exact blank blocks between the rendered rows. With a
        // reply channel (Stage 6), the buffer is just the rendered band —
        // the prefix/suffix become metadata instead of blank lines and the
        // ScrollView clips the band directly. Without one (tests, direct
        // injection), the classic full-height buffer is emitted.
        var result = FrameBuffer()
        let sliceOrigin = window.reply != nil ? (rows.first.map { $0.ordinal * pitch } ?? 0) : 0
        var cursor = sliceOrigin
        var memo: [String: Int] = [:]
        for (ordinal, child) in rows {
            let rowY = ordinal * pitch
            if rowY > cursor {
                result.appendVertically(FrameBuffer(emptyWithHeight: rowY - cursor), spacing: 0)
            }
            var rendered = child.render(
                width: width, height: window.viewportHeight, context: childContext)
            rendered = alignBuffer(rendered, toWidth: width, alignment: alignment)
            var slot = FrameBuffer()
            slot.appendVertically(rendered, spacing: 0)
            if slot.height < extent {
                slot.appendVertically(FrameBuffer(emptyWithHeight: extent - slot.height), spacing: 0)
            } else if slot.height > extent {
                slot = slot.clamped(toWidth: max(width, slot.width), height: extent)
            }
            result.appendVertically(slot, spacing: 0)
            cursor = rowY + extent
            if let key = children.key(at: ordinal) { memo[key] = ordinal }
        }
        if let reply = window.reply {
            reply.sliceOriginY = sliceOrigin
            reply.sliceTotalHeight = totalHeight
        } else if cursor < totalHeight {
            result.appendVertically(FrameBuffer(emptyWithHeight: totalHeight - cursor), spacing: 0)
        }
        state.rowOrdinalMemo = memo
        return result
    }

    /// The ordinals this frame renders: rows meeting the window, one margin
    /// row past each edge, and the focused row / pending focus target with
    /// their neighbours (§5d — they must render to keep registering).
    private func candidateOrdinals(
        children: ChildViewCollection, window: ScrollContentWindow, pitch: Int,
        state: StackWindowState, context: RenderContext
    ) -> Set<Int> {
        let count = children.count
        var candidates: Set<Int> = []
        let firstVisible = max(0, window.offset / pitch)
        let lastVisible = min(
            count - 1, max(firstVisible, (window.offset + window.viewportHeight - 1) / pitch))
        if firstVisible < count {
            for ordinal in max(0, firstVisible - 1)...min(count - 1, lastVisible + 1) {
                candidates.insert(ordinal)
            }
        }
        if let focusManager = context.environment.focusManager {
            for target in [focusManager.currentFocusedID, focusManager.pendingFocusID] {
                guard let ordinal = targetOrdinal(
                    for: target, children: children, state: state, context: context)
                else { continue }
                for neighbour in max(0, ordinal - 1)...min(count - 1, ordinal + 1) {
                    candidates.insert(neighbour)
                }
            }
        }
        return candidates
    }

    /// The ordinal of the row a focus ID addresses: memo hit, else one key
    /// scan (never builds a row view).
    private func targetOrdinal(
        for focusID: String?, children: ChildViewCollection,
        state: StackWindowState, context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        guard let key = Self.rowKey(inFocusID: focusID, belowStackPath: context.identity.path)
        else { return nil }
        if let memoised = state.rowOrdinalMemo[key],
            memoised < children.count, children.key(at: memoised) == key
        {
            return memoised
        }
        return children.firstOrdinal(forKey: key)
    }
}

// MARK: - The seek measure

extension _VStackCore {
    /// `windowSizeThatFits` by arithmetic, or `nil` when the hypothesis is
    /// unavailable (never seeded — seeding is a render-path mutation) or
    /// broken. Mirrors append-while-fits exactly for uniform rows: the fit
    /// count is a division, the height is exact. Width and flexibility come
    /// from a bounded sample of the fitting rows (the full walk measured
    /// them all; uniform-height content overwhelmingly has uniform width
    /// and inert flags, and the render path's verification remains the
    /// falsification net for the height itself).
    func uniformSeekSizeThatFits(
        _ children: ChildViewCollection, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize? {
        guard let extent = uniformWindowState(context: context).hypothesisExtent,
            !uniformWindowState(context: context).broken,
            extent > 0
        else { return nil }

        let count = children.count
        guard count > 0 else { return ViewSize.fixed(0, 0) }
        let pitch = extent + spacing
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight

        // Append-while-fits: k rows fit when k*pitch - spacing <= limit.
        let fitCount = max(0, min(count, (heightLimit + spacing) / pitch))
        let height = fitCount > 0 ? fitCount * pitch - spacing : 0

        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.environment.scrollContentWindow = nil
        let sampleProposal = ProposedSize(width: widthLimit, height: nil)
        var maxWidth = 0
        var widthFlexible = false
        var heightFlexible = false
        for ordinal in 0..<min(fitCount, 64) {
            let size = children[ordinal].measure(proposal: sampleProposal, context: measureContext)
            guard size.height == extent else { return nil }  // falsified: exact walk
            maxWidth = max(maxWidth, min(size.width, widthLimit))
            if size.isWidthFlexible { widthFlexible = true }
            if size.isHeightFlexible { heightFlexible = true }
        }
        return ViewSize(
            width: maxWidth, height: height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }
}
