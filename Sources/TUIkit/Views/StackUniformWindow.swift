//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// The `UniformWindowState` hypothesis box. Negative: the box lives at the
    /// stack's OWN identity, and a lone non-`ChildViewProvider` child (one
    /// composite view, `someView.padding()`, an `if` without `else`, an
    /// `AnyView`) is TRANSPARENT — it pushes no child identity, so its first
    /// `@State` would bind that very key. Range -70, claimed in
    /// ``StateStorage/StateKey``'s table.
    static let uniformWindow = -70
}

/// A band row as the uniform render measured it: `fills` when it is
/// width-flexible, whose `width` is then only the width it was offered.
typealias UniformBandRow = (ordinal: Int, child: ChildView, width: Int, fills: Bool)

/// The widest rows a windowed stack has measured, kept as the running maxima
/// of every row any of its paths has seen: records in increasing ordinal order
/// whose widths strictly increase, so ``width(forFirst:)`` is the widest known
/// row among the first `k`.
///
/// The ordinal is the part that matters. A windowed stack answers measures from
/// three paths — the uniform arithmetic seek, the anchored estimate, the exact
/// walk — and each reports for a different PREFIX of the stack: the rows its
/// height budget has room for. A single global maximum answers the short
/// budgets with a row they would never reach, which is how a stack came to
/// measure one width on its first frame (an arm that walks the prefix) and
/// another on its second (the seek, answering from a global maximum).
struct RowWidthRecords {
    private var records: [(ordinal: Int, width: Int)] = []

    /// Whether any row has been recorded yet — distinct from "widest is zero".
    private(set) var isSeeded = false

    /// The widest row known among the first `count`, or 0 when none is.
    func width(forFirst count: Int) -> Int {
        var result = 0
        // Widths increase with ordinal, so the last record before the fold is
        // the maximum; the array holds only record-setting rows, so this is a
        // handful of steps even for a stack of millions.
        for record in records {
            guard record.ordinal < count else { break }
            result = record.width
        }
        return result
    }

    /// Marks the records seeded even when no row set one (an empty stack, or
    /// rows of zero width): "seeded" is about whether the sample has run.
    mutating func markSeeded() {
        isSeeded = true
    }

    /// Records a measured row, keeping only what changes an answer.
    mutating func note(ordinal: Int, width measured: Int) {
        guard measured > width(forFirst: ordinal + 1) else { return }
        let index = records.firstIndex { $0.ordinal >= ordinal } ?? records.count
        if index < records.count, records[index].ordinal == ordinal {
            records[index].width = measured
        } else {
            records.insert((ordinal, measured), at: index)
        }
        // A wider row earlier makes every narrower record after it unreachable.
        while index + 1 < records.count, records[index + 1].width <= measured {
            records.remove(at: index + 1)
        }
    }
}

/// The windowed stack's persisted window state: the uniformity
/// hypothesis, and — for variable-height content — the scroll anchor
/// (§5e: `ScrollAnchor { item, offsetWithin }`, held here in ordinal
/// form beside the running extent estimate). File-scope (not nested in
/// `_VStackCore`) so non-generic helpers can hold it.
final class StackWindowState {
        /// Every row is exactly this tall, as far as this path has measured.
        /// `nil` until seeded (from row 0, on the render path only).
        ///
        /// Render-path-only because this is a HYPOTHESIS taken from a sample —
        /// one row, taken under one proposal — and a sample's answer depends on
        /// how it was taken. Row 0 is always the row, but not always at the same
        /// width: a measure asks at whatever width its caller is trying (a
        /// dialog's trial widths, a ladder's rungs), where row 0 can wrap to a
        /// different height than the render draws it at, and kept, that height
        /// would be every row's pitch. So the stack's size would depend on which
        /// speculative passes happened to run, which is the one thing a measure
        /// may not do (see ``RenderContext/isMeasuring``). A complete aggregate
        /// taken the same way whoever takes it has no such dependence and may be
        /// written from a measure — `StackContentWidth.swift` is the worked
        /// example.
        var hypothesisExtent: Int?

        /// A measured row disagreed: uniform arithmetic is dead, permanently
        /// — this stack uses the anchored walk (large N) or the exact full
        /// walk (small N) from then on.
        var broken = false

        /// The widest rows the render paths have measured — a one-time seed
        /// sample plus every verified band row, grow-only — each remembered
        /// with the ordinal it came from. Empty until the first uniform render
        /// seeds it (seeding is a render-path mutation, like the extent).
        /// Lets `uniformSeekSizeThatFits` answer without measuring: before it,
        /// every measure re-sampled up to 64 rows for width/flexibility, which
        /// on any cache-invalidating frame (any `@State` write clears the memo)
        /// is the WHOLE stack for ≤64 rows — every frame.
        var rowWidths = RowWidthRecords()

        /// The widest row over every row, and the prefix it was taken
        /// over — the two-axis content-width answer. See
        /// `StackContentWidth.swift`, which owns every rule about it.
        var contentWidth: ContentWidthRecord?

        /// The widest row the LAST uniform render actually drew. The reported
        /// width is never below it: a stack must not tell its parent it is
        /// narrower than the band it is putting on screen, however few of the
        /// first rows that band contains (scrolled to row 300, the first nine
        /// rows are not what is drawn).
        var bandWidth = 0

        /// ``bandWidth`` without the rows that fill whatever they are offered.
        /// What floors a whole-content answer: a filler's measured width is the
        /// width it was given — last frame's canvas, in a two-axis view — so
        /// folding it in would hold the extent at last frame's forever, which
        /// is why the walk leaves fillers out of its maximum too.
        var inflexibleBandWidth = 0

        var hypothesisWidthFlexible = false
        var hypothesisHeightFlexible = false

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

        /// The row key a bound `.anchorPosition(.row(id))` last DESIGNATED, or
        /// `nil` when the anchor is the implicit top-visible row.
        ///
        /// Remembered so a designation is *adopted* once, when it changes: the
        /// key itself is re-asserted every frame (that is what holds the row),
        /// but re-seeding ``anchorOffsetWithin`` every frame would drag the row
        /// to the viewport top instead of leaving it where it sits.
        var designatedAnchorKey: String?

        /// The screen line the designated row is held on — its distance below
        /// the viewport top, adopted when the designation changes and held
        /// thereafter. Used by the paths that place rows at ABSOLUTE content y
        /// (uniform arithmetic, exact walk), where holding a row means moving
        /// the offset under it; see `StackDesignatedAnchor.swift`. The anchored
        /// walk holds its row through ``anchorOffsetWithin`` instead, being
        /// anchor-relative by construction.
        var anchorHeldScreenLine = 0

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
        let stateStorage = context.stateStorage!
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

        let (seeked, resolvedSeek) = resolvingUniformSeek(
            in: window, children: children, state: state,
            pitch: pitch, extent: extent, totalHeight: totalHeight)
        // A designated row overrides the offset: the position follows the ROW.
        // Exact here — a uniform row's absolute y is arithmetic.
        let (window, resolvedAnchor) = holdingDesignatedRow(
            in: seeked, children: children, state: state,
            rowY: { $0 * pitch }, rowHeight: extent,
            totalHeight: totalHeight, context: context)

        let candidates = candidateOrdinals(
            children: children, window: window, pitch: pitch, state: state, context: context)
        // The ring must continue past a non-focusable run adjacent to the
        // focused row (a disabled neighbour registers nothing and would end
        // the ring, trapping Tab inside the band) — probe for the nearest
        // focusable in each direction and render it too.
        let continuations = focusRingContinuations(
            focusedOrdinal: targetOrdinal(
                for: context.environment.focusManager?.currentFocusedID,
                children: children, state: state, context: context),
            count: count, child: { children[$0] },
            width: width, viewportHeight: window.viewportHeight, context: childContext)
        let offBand = Set(candidates.offBand)
            .union(continuations.filter { !candidates.band.contains($0) })
            .sorted()
        // Classic mode (no reply channel) keeps every row inline in the
        // full-height canvas, exactly at its y. Band mode must NOT stretch
        // the band to reach a far focus target: the gap would materialise as
        // O(distance) blank lines every frame — and the universal render
        // clamp then truncates the lines while keeping the regions, leaving
        // a corrupt band whose clip shows nothing. Off-band targets render
        // out-of-band instead (`graftOffBandRow`).
        let inline = window.reply == nil
            ? Set(candidates.band).union(offBand).sorted()
            : candidates.band
        let grafted = window.reply == nil ? [] : offBand

        // Build + verify each candidate. A disagreeing height falsifies the
        // hypothesis for good; the caller re-walks exactly, this same frame.
        let proposal = ProposedSize(width: width, height: nil)
        guard
            let rows = verifiedUniformRows(
                inline, children: children, extent: extent,
                state: state, proposal: proposal, context: childContext),
            let graftRows = verifiedUniformRows(
                grafted, children: children, extent: extent,
                state: state, proposal: proposal, context: childContext)
        else {
            state.broken = true
            return nil
        }
        recordWidths(
            band: rows, grafted: graftRows, children: children, state: state,
            proposal: proposal, context: childContext)

        // Assemble: exact blank blocks between the rendered rows. With a
        // reply channel (Stage 6), the buffer is just the rendered band —
        // the prefix/suffix become metadata instead of blank lines and the
        // ScrollView clips the band directly. Without one (tests, direct
        // injection), the classic full-height buffer is emitted.
        let rowContext = uniformRowPlacement(childContext, width: width, pitch: pitch, totalHeight: totalHeight)

        var result = FrameBuffer()
        let sliceOrigin = window.reply != nil ? (rows.first.map { $0.ordinal * pitch } ?? 0) : 0
        var (cursor, memo) = appendUniformRows(
            rows, into: &result, from: sliceOrigin, children: children,
            geometry: (extent, pitch, width, window.viewportHeight), rowContext: rowContext)
        if let reply = window.reply {
            reply.sliceOriginY = sliceOrigin
            reply.sliceTotalHeight = totalHeight
            reply.anchorID = sampledID(
                children, window: window, pitch: pitch, totalHeight: totalHeight)
        } else if cursor < totalHeight {
            result.appendVertically(FrameBuffer(emptyWithHeight: totalHeight - cursor), spacing: 0)
        }
        for (ordinal, child, rowWidth, _) in graftRows {
            graftOffBandRow(
                child, into: &result, bandLocalY: ordinal * pitch - sliceOrigin,
                width: width, viewportHeight: window.viewportHeight,
                context: rowContext(ordinal, rowWidth))
            if let key = children.key(at: ordinal) { memo[key] = ordinal }
        }
        state.rowOrdinalMemo = memo
        // The anchor correction wins over the seek: when both happen on one
        // frame the seek chose a row and the designation then held it, so the
        // corrected offset is the one actually rendered.
        if let resolved = resolvedAnchor ?? resolvedSeek {
            window.reply?.seekResolvedOffset = resolved
        }
        return result
    }

    /// Places a uniform row inside a ramp spanning the whole CONTENT, so a row
    /// keeps its colour as it scrolls past rather than the band re-inking under
    /// a ramp pinned to the viewport.
    ///
    /// Constant pitch makes every row's absolute y a multiplication, which is
    /// exactly what the ramp needs and what this path already has. The width is
    /// the row's MEASURED one, from the hypothesis verification — the rendered
    /// one does not exist until after the render this colours.
    ///
    /// - Returns: `(ordinal, rowWidth) -> RenderContext`, the identity when no
    ///   `.gradientExtent(.subtree)` spans this stack.
    private func uniformRowPlacement(
        _ context: RenderContext, width: Int, pitch: Int, totalHeight: Int
    ) -> (Int, Int) -> RenderContext {
        let frame = context.gradientContentFrame(width: width, height: totalHeight)
        return { ordinal, rowWidth in
            context.placingGradientChild(
                frame,
                x: Self.gradientX(childWidth: rowWidth, extent: width, alignment: alignment),
                y: ordinal * pitch)
        }
    }

    /// Renders one uniform row into a slot of exactly `extent` lines
    /// (padded or clamped), aligned to the stack's width.
    private func uniformRowSlot(
        _ child: ChildView, extent: Int, width: Int, viewportHeight: Int, context: RenderContext
    ) -> FrameBuffer {
        // Render at the slot's extent, not the viewport: a uniform row taller
        // than the viewport otherwise loses its tail to the render clamp
        // while the slot pads the loss with blanks (see the twin comment in
        // `_VStackCore.renderViewportWindow`).
        let rendered = alignBuffer(
            child.render(width: width, height: extent, context: context),
            toWidth: width, alignment: alignment)
        var slot = FrameBuffer()
        slot.appendVertically(rendered, spacing: 0)
        if slot.height < extent {
            slot.appendVertically(FrameBuffer(emptyWithHeight: extent - slot.height), spacing: 0)
        } else if slot.height > extent {
            slot = slot.clamped(toWidth: max(width, slot.width), height: extent)
        }
        return slot
    }

    /// Builds each ordinal's child, verifying the uniform hypothesis as it
    /// goes: a row measuring anything but `extent` — or a spacer — returns
    /// `nil` (falsified). Verified rows also SEED and GROW the width
    /// hypothesis (and its flexibility flags), render-path mutations both:
    /// the stack's O(1) measure answer tracks the widest row the render has
    /// ever seen, so scrolling a wider row into the band widens the report
    /// on the same frame — and no row beyond the ones the render already
    /// touches is ever measured for it (the O(window) build bound holds).
    /// Fidelity note: the answer is the max over VISITED rows, where the old
    /// per-measure sampling took the first 64 — both are heuristics for
    /// content the window has not reached, and the only consumer of a seeded
    /// stack's width (a vertical ScrollView's extents) discards it. Each width
    /// is filed under its ordinal so a measure asking about a short prefix is
    /// not answered with a row far below the fold.
    private func verifiedUniformRows(
        _ ordinals: [Int], children: ChildViewCollection, extent: Int,
        state: StackWindowState, proposal: ProposedSize, context: RenderContext
    ) -> [UniformBandRow]? {
        var result: [UniformBandRow] = []
        result.reserveCapacity(ordinals.count)
        for ordinal in ordinals {
            let child = children[ordinal]
            let measured = child.measure(proposal: proposal, context: context)
            guard measured.height == extent, !child.isSpacer else { return nil }
            state.rowWidths.note(ordinal: ordinal, width: measured.width)
            if measured.isWidthFlexible { state.hypothesisWidthFlexible = true }
            if measured.isHeightFlexible { state.hypothesisHeightFlexible = true }
            // The measured width is kept for the ramp: it is what the row will
            // be aligned by, and the rendered one does not exist yet.
            result.append((ordinal, child, measured.width, measured.isWidthFlexible))
        }
        return result
    }

    /// Lays the band's rows into `result` at their exact arithmetic positions,
    /// with a blank block for each gap, and returns where the walk left the
    /// cursor plus the key→ordinal memo it built on the way.
    private func appendUniformRows(
        _ rows: [UniformBandRow], into result: inout FrameBuffer,
        from sliceOrigin: Int, children: ChildViewCollection,
        geometry: (extent: Int, pitch: Int, width: Int, viewportHeight: Int),
        rowContext: (Int, Int) -> RenderContext
    ) -> (cursor: Int, memo: [String: Int]) {
        var cursor = sliceOrigin
        var memo: [String: Int] = [:]
        for (ordinal, child, rowWidth, _) in rows {
            let rowY = ordinal * geometry.pitch
            if rowY > cursor {
                result.appendVertically(FrameBuffer(emptyWithHeight: rowY - cursor), spacing: 0)
            }
            let slot = uniformRowSlot(
                child, extent: geometry.extent, width: geometry.width,
                viewportHeight: geometry.viewportHeight,
                context: rowContext(ordinal, rowWidth))
            result.appendVertically(slot, spacing: 0)
            cursor = rowY + geometry.extent
            if let key = children.key(at: ordinal) { memo[key] = ordinal }
        }
        return (cursor, memo)
    }

    /// The two render-path width mutations, together: what this frame's band
    /// is drawing (the floor the report may never fall below) and, once per
    /// stack, the sample a measure of it would have walked.
    private func recordWidths(
        band: [UniformBandRow],
        grafted: [UniformBandRow],
        children: ChildViewCollection, state: StackWindowState,
        proposal: ProposedSize, context: RenderContext
    ) {
        // Not `(band + grafted).reduce`: that concatenation would allocate a
        // fresh array of the band on every frame of every windowed stack.
        var bandWidth = 0
        var inflexibleBandWidth = 0
        for row in band {
            bandWidth = max(bandWidth, row.width)
            if !row.fills { inflexibleBandWidth = max(inflexibleBandWidth, row.width) }
        }
        for row in grafted {
            bandWidth = max(bandWidth, row.width)
            if !row.fills { inflexibleBandWidth = max(inflexibleBandWidth, row.width) }
        }
        state.bandWidth = bandWidth
        state.inflexibleBandWidth = inflexibleBandWidth
        seedWidthRecords(children, state: state, proposal: proposal, context: context)
    }

    /// Fills the width records from the same prefix a measure of this stack
    /// walks — every row for a small stack, the anchored estimate's sample for
    /// a large one — so the seek's later answers match the walk's.
    ///
    /// Without it the records hold the band alone, and the seek answered the
    /// whole-content question with the widest row on screen while the walk
    /// that had run moments earlier in the same pass had seen the whole
    /// prefix: a static tree measured 24 wide on its first frame and 2 on its
    /// second. Runs at most once per stack (`markSeeded` records that it has,
    /// even when no row set a record), and those same rows were measured by
    /// that walk in this pass, so the memo serves most of them; the steady
    /// state still measures nothing beyond the band.
    private func seedWidthRecords(
        _ children: ChildViewCollection, state: StackWindowState, proposal: ProposedSize,
        context: RenderContext
    ) {
        guard !state.rowWidths.isSeeded else { return }
        var measureContext = context
        measureContext.isMeasuring = true
        let count = children.count
        // The exact walk measures every row it can reach; the anchored
        // estimate samples sixteen. Mirror whichever would have answered, so
        // the seek reproduces it rather than a third heuristic.
        let sample = count > Self.anchoredWindowThreshold ? Self.anchoredWidthSampleCount : count
        for ordinal in 0..<max(0, min(count, sample)) {
            let child = children[ordinal]
            let size = child.measure(proposal: proposal, context: measureContext)
            // Measured but not drawn — keep the memo entry past the pass GC.
            measureContext.renderCache?.markActive(child.identity(under: measureContext))
            state.rowWidths.note(ordinal: ordinal, width: size.width)
        }
        state.rowWidths.markSeeded()
    }

    /// The id of the row under the sample line, when one was asked for.
    ///
    /// Constant pitch makes this a division rather than a walk: no row is
    /// built, and no key is compared.
    private func sampledID(
        _ children: ChildViewCollection, window: ScrollContentWindow, pitch: Int,
        totalHeight: Int
    ) -> AnyHashable? {
        guard let unit = window.reportsIDAt, pitch > 0, !children.isEmpty else { return nil }
        let sampled = window.sampleY(
            at: unit, contentBelow: window.offset + window.viewportHeight < totalHeight)
        let ordinal = min(max(0, sampled / pitch), children.count - 1)
        return children.anyID(at: ordinal)
    }

    /// Resolves a pending scrollTo against uniform geometry — EXACT, the
    /// target's y is arithmetic. Returns the window re-aimed at the
    /// request's offset (so the band renders there and the same frame shows
    /// the target) plus the offset to report, or the window unchanged when
    /// there is no request or the key is absent. The reply is written only
    /// when the caller completes: a falsified hypothesis falls through, and
    /// the next path re-resolves for itself.
    private func resolvingUniformSeek(
        in window: ScrollContentWindow, children: ChildViewCollection,
        state: StackWindowState, pitch: Int, extent: Int, totalHeight: Int
    ) -> (window: ScrollContentWindow, resolved: Int?) {
        var window = window
        guard let seek = window.seek else { return (window, nil) }
        window.seek = nil
        guard let ordinal = resolveOrdinal(forKey: seek.key, children: children, state: state)
        else { return (window, nil) }
        let newOffset = seek.windowOffset(
            targetY: ordinal * pitch, rowHeight: extent, currentOffset: window.offset,
            viewportHeight: window.viewportHeight, totalHeight: totalHeight)
        window.offset = newOffset
        return (window, newOffset)
    }

    /// The ordinals this frame renders: the contiguous window BAND (rows
    /// meeting the window plus one margin row past each edge), and the
    /// OFF-BAND focused row / pending focus target with their neighbours
    /// (§5d — they must render to keep registering, wherever they are).
    private func candidateOrdinals(
        children: ChildViewCollection, window: ScrollContentWindow, pitch: Int,
        state: StackWindowState, context: RenderContext
    ) -> (band: [Int], offBand: [Int]) {
        let count = children.count
        var band: [Int] = []
        let firstVisible = max(0, window.offset / pitch)
        let lastVisible = min(
            count - 1, max(firstVisible, (window.offset + window.viewportHeight - 1) / pitch))
        if firstVisible < count {
            band = Array(max(0, firstVisible - 1)...min(count - 1, lastVisible + 1))
        }
        var targets: Set<Int> = []
        if let focusManager = context.environment.focusManager {
            for target in [focusManager.currentFocusedID, focusManager.pendingFocusID] {
                guard let ordinal = targetOrdinal(
                    for: target, children: children, state: state, context: context)
                else { continue }
                for neighbour in max(0, ordinal - 1)...min(count - 1, ordinal + 1) {
                    targets.insert(neighbour)
                }
            }
        }
        return (band, targets.subtracting(band).sorted())
    }

    /// Renders an off-band focus/pending target row for its side effects —
    /// focus registration above all — and grafts its hit-test regions and
    /// overlays into the band buffer at the row's band-local y, WITHOUT
    /// adding any lines. Materialising the band→row gap as blank lines
    /// would cost O(distance) time and memory every frame the control stays
    /// focused off-window (and the universal render clamp then truncates
    /// the lines while keeping the regions, corrupting the band). Regions
    /// are pure rects, so they sit happily outside the band's line range —
    /// negative or far beyond — where the ScrollView's reveal math reads
    /// them and its viewport clip then drops the invisible ones.
    func graftOffBandRow(
        _ child: ChildView, into result: inout FrameBuffer, bandLocalY: Int,
        width: Int, viewportHeight: Int, context: RenderContext
    ) {
        let rendered = child.render(width: width, height: viewportHeight, context: context)
        let aligned = alignBuffer(rendered, toWidth: width, alignment: alignment)
        result.hitTestRegions.append(
            contentsOf: aligned.shiftedHitTestRegions(byX: 0, y: bandLocalY))
        result.overlays.append(contentsOf: aligned.shiftedOverlays(byX: 0, y: bandLocalY))
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
        let state = uniformWindowState(context: context)
        guard let extent = state.hypothesisExtent, !state.broken, extent > 0
        else { return nil }

        let count = children.count
        guard count > 0 else { return ViewSize.fixed(0, 0) }
        // Declined for the same reason the render declines it — the two must
        // agree on the width, and a guide can widen the stack past its widest
        // row.
        guard !children[0].providesAlignmentGuide else { return nil }
        let pitch = extent + spacing
        let widthLimit = proposal.width ?? context.availableWidth
        let heightLimit = proposal.height ?? context.availableHeight

        // Append-while-fits: k rows fit when k*pitch - spacing <= limit.
        let fitCount = max(0, min(count, (heightLimit + spacing) / pitch))
        let height = fitCount > 0 ? fitCount * pitch - spacing : 0
        guard fitCount > 0 else { return ViewSize.fixed(0, 0) }

        // O(1) once the render has seeded the width records: the answer is
        // pure arithmetic plus the widest row already known within this
        // budget's reach — no row measures at all, the steady state. (The
        // sample below is the fallback for a live hypothesis whose records are
        // not seeded — a state no render currently leaves, since the render
        // that seeds the one seeds the other — and it must not persist
        // anything: a sample's answer depends on which rows were in it, so a
        // measure that kept one would make the stack's width depend on which
        // speculative passes ran. ``RenderContext/isMeasuring`` has the rule
        // and the line it draws.)
        //
        // Floored by the band the last render drew: a prefix answer is the
        // right one for a parent asking "how wide are you in N lines", but a
        // scrolled stack is drawing rows the prefix does not contain, and it
        // must never report itself narrower than what it is putting on screen.
        // The exact answer, for the one ask that needs it — see
        // `StackContentWidth.swift`, and `anchoredSizeThatFits` for the twin of
        // this block. Both paths need it: which of them answers depends on
        // whether a render has seeded the uniformity hypothesis yet, so wiring
        // only one left a two-axis `ScrollView` correct on its first frame and
        // wrong from its second (measured — the bar appeared and then went).
        let exact =
            isNaturalExtentBudget(heightLimit) && proposal.height == nil
            ? contentWidthOverAllRows(
                children, widthLimit: widthLimit, mayWalk: proposal.width == nil,
                state: state, context: context)
            : nil

        if state.rowWidths.isSeeded {
            let walked = Self.walkedRowCount(
                budget: heightLimit, pitch: pitch, spacing: spacing, count: count)
            // The exact answer is already a maximum over every row, so the
            // records do not floor it: they only ever grow, and hold the widest
            // any row was when some path last saw it, so a row that NARROWED —
            // a line backspaced, a toggle turned off — would keep its old width
            // in the extent for as long as the stack lived. The band's
            // inflexible rows still floor it, because they are what is on
            // screen; its fillers do not, for the reason the walk leaves them
            // out. That is the band the LAST render drew, so a row on screen
            // that shrinks or widens reaches the extent at the next frame
            // rendered after it — which, in an app that renders on demand, is
            // the next thing that happens, not a frame scheduled for it.
            let seen = exact == nil ? state.rowWidths.width(forFirst: walked) : 0
            let drawn = exact == nil ? state.bandWidth : state.inflexibleBandWidth
            let prefix = min(max(seen, drawn), widthLimit)
            let width = max(prefix, exact?.width ?? 0)
            // The exact answer's flexibility is already over every row, so it
            // stands alone: the hypothesis's flag is sticky — set the first
            // time any band row filled, never cleared — and would go on saying
            // "flexible" after the last filler had left the data.
            let flexible: Bool
            if let exact {
                flexible = Self.wholeContentFlexibility(
                    exact.isWidthFlexible, width: width, limit: widthLimit)
            } else {
                flexible = state.hypothesisWidthFlexible
            }
            return ViewSize(
                width: width,
                height: height,
                isWidthFlexible: flexible,
                isHeightFlexible: state.hypothesisHeightFlexible)
        }

        var measureContext = context
        measureContext.isMeasuring = true
        measureContext.environment.scrollContentWindow = nil
        let sampleProposal = ProposedSize(width: widthLimit, height: nil)
        var maxWidth = 0
        var widthFlexible = false
        var heightFlexible = false
        for ordinal in 0..<min(fitCount, 64) {
            let child = children[ordinal]
            let size = child.measure(proposal: sampleProposal, context: measureContext)
            // Sample rows are measured but never rendered — keep their memo
            // entries alive across the pass GC (see AnchoredWindowFrame.pitch).
            measureContext.renderCache?.markActive(child.identity(under: measureContext))
            guard size.height == extent else { return nil }  // falsified: exact walk
            // With the exact answer in hand, a filler counts as the walk counts
            // it: its flexibility, not the width it was offered.
            if exact == nil || !size.isWidthFlexible {
                maxWidth = max(maxWidth, min(size.width, widthLimit))
            }
            if size.isWidthFlexible { widthFlexible = true }
            if size.isHeightFlexible { heightFlexible = true }
        }
        let width = max(maxWidth, exact?.width ?? 0)
        let flexible = widthFlexible || (exact?.isWidthFlexible ?? false)
        return ViewSize(
            width: width, height: height,
            isWidthFlexible: exact == nil
                ? flexible : Self.wholeContentFlexibility(flexible, width: width, limit: widthLimit),
            isHeightFlexible: heightFlexible)
    }
}
