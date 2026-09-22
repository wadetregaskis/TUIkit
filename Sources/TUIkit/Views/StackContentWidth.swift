//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackContentWidth.swift
//
//  How wide ALL of a windowed stack's rows are — the one question about a lazy
//  stack that cannot be answered from a sample, and the ladder that makes
//  answering it affordable.
//
//  Every other number a windowed stack reports is about the rows a budget
//  reaches: the height it occupies, the width it hugs to in eight lines, the
//  band it draws. Those are prefix questions and `StackUniformWindow` answers
//  them from a prefix — see `RowWidthRecords`, and the comment on
//  `anchoredSizeThatFits`'s `prefix`, which exists because answering them
//  globally made one stack report 24 wide and then 2.
//
//  A two-axis `ScrollView` asks a different one. Its horizontal extent comes
//  from `measureNaturalExtent(along: .horizontal)` — an UNBOUNDED width ask
//  under a height budget that reaches every row — and it means "how far right
//  can this content be scrolled". A sample cannot answer it. The sample is the
//  first sixteen rows for a collection over 256, always, wherever the viewport
//  is: a 120-cell row at ordinal 16 or 200 or 399 reports nothing, the content
//  measures and renders eight wide, no horizontal bar is drawn, and that row's
//  tail is unreachable at every offset — including when the row is ON SCREEN
//  and visibly truncated. The eager `VStack` of the same content answers 120,
//  so this was the twins disagreeing rather than a property of laziness.
//
//  The answer is Ω(rows) by information content and there is no way around
//  that. What there is a way around is paying it per frame, and that is what
//  the four rungs below are for. Measured on `app-shapes/code-editor` and
//  `app-shapes/code-editor-tailing` (2,000 syntax-coloured lines settled and
//  growing, release, 120x40, paired A/B):
//
//      walking every row, no ladder    +9.9%   and  +159.4%
//      this, mechanism only            +4.9%   and    +3.2%
//      this, at the real viewport      +5.1%   and   +12.1%
//
//  The last row is larger only because the answer is RIGHT: the content canvas
//  legitimately widens from 135 cells to 142, and a two-axis lazy stack's frame
//  is super-linear in canvas width (measured on the unfixed build: 135 → 142
//  costs it 20.8%). The middle row holds the canvas identical, so it is the
//  mechanism and nothing else.
//
//  ## The rungs
//
//  1. **The ceiling.** The walk stops the moment its running maximum reaches
//     the budget it is clamped to. Under `.frame(maxWidth: k)` — and under any
//     content whose rows are mostly longer than the space offered — that is an
//     exit after one or two rows rather than a walk. It is also what keeps the
//     natural-extent LADDER affordable: `measureNaturalExtent` re-measures the
//     whole content once per rung, so saturating content used to cost N rows
//     per rung, and now costs the handful of rows it takes to saturate.
//
//  2. **The kept answer**, which is rung 3's record when it covers the whole
//     collection — one record serves both, and it is deliberately NOT a second
//     entry in the render cache. That was written and removed: it bought
//     invalidation the record now carries itself and charged a `SizeKey` hash, a
//     dynamic compare and a `markActive` on every ask, which on a settled
//     editor — where the answer never changes and the walk runs once in the
//     process's life — was the whole of its cost. The question is asked three or
//     four times a frame, at two viewport widths and once per ladder rung, so
//     what this rung has to be is cheap rather than clever.
//
//  3. **The kept PREFIX** (``StackWindowState/contentWidth``). The answer is a
//     MAXIMUM, so a collection that only grew at the end is the old maximum
//     joined with the new rows — `AnyEquatableBox.extends(_:)` proves it, in
//     O(1) for a `Range` and by a leading-element compare otherwise. This is
//     the rung that matters for live content, and it is the reason it lives in
//     `@State` rather than in the render cache: an arriving row is a write, a
//     write clears the cache from the app root down, and a record that is gone
//     before it can be extended is no record at all.
//
//  4. **The walk**, which is where the first frame and a genuinely new
//     collection end up.
//
//  ## Why rung 3 may be written from a measure
//
//  `RenderContext.isMeasuring` says no side effects, and `RowWidthRecords`
//  states the local form of it: "seeding is a render-path mutation". This
//  breaks that, deliberately and narrowly, and the argument is that the two
//  reasons behind the rule do not reach here. `StateStorage`'s rule is about
//  CREATING a box at an identity that may never render — the box already
//  exists by the time this runs, hydrated by `uniformWindowState` at the top of
//  `anchoredSizeThatFits`. And the record is purely derived: it is a maximum
//  over rows, recomputed from the rows themselves, so a speculative measure
//  that never renders leaves behind a correct answer rather than a decision.
//  What it is NOT is free of invalidation duty — see ``ContentWidthRecord``,
//  which carries the two generations the render cache would have applied for
//  it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The kept prefix

/// A maximum over the first `covered` rows of `rows`, and what made it mean
/// that.
///
/// Held in ``StackWindowState`` — `@State`, so it outlives the render cache —
/// which means this type owns its own invalidation where a `SizeKey` entry gets
/// the cache's for free. Two generations are all that is needed and both are
/// process-wide counters rather than anything this stack can observe:
///
/// * ``TerminalWidthTraits/generation`` — the terminal's reported glyph widths
///   moved, so every cell count taken before it is a different number now. The
///   render cache answers this with a `clearAll()` in `beginRenderPass`.
/// * ``RenderContext/measureGeneration`` — a container declared that measures
///   below it must not be reused.
///
/// Everything else that could change a row's width changes the ROWS, and the
/// rows are the key. What is left uncovered is the `ForEach` captured-data hole
/// — a row built from data its element does not carry — which every memo in the
/// framework already has, and which this narrows rather than widens: an
/// incremental walk never re-measures its prefix, but the full walk it replaces
/// was being served stale per-row sizes out of `measureValueMemoized` anyway.
struct ContentWidthRecord {
    /// The rows the maximum was taken over — the whole collection at the time.
    let rows: AnyEquatableBox
    /// How many leading rows `widest` is the maximum over.
    let covered: Int
    /// The widest INFLEXIBLE row among them. A row that fills whatever it is
    /// offered has no natural width to contribute; it contributes `isFlexible`.
    let widest: Int
    let isFlexible: Bool
    let widthGeneration: Int
    let measureGeneration: UInt8
    /// ``RenderCache/clearGeneration`` — how many times the cache had been
    /// dropped whole when this was taken. The two events that do that, a moved
    /// `EnvironmentSnapshot` and a moved colour claim, are the ones a record in
    /// `@State` cannot see for itself.
    let clearGeneration: Int

    /// Whether this record was taken under the same world as `context`.
    func isCurrent(in context: RenderContext) -> Bool {
        widthGeneration == TerminalWidthTraits.generation
            && measureGeneration == context.measureGeneration
            && clearGeneration == (context.renderCache?.clearGeneration ?? 0)
    }
}

// MARK: - The ladder

extension _VStackCore {
    /// The width of the widest row over EVERY row, or `nil` when it cannot be
    /// answered or cannot be kept.
    ///
    /// `nil` rather than a walk when there is no data signature, which is the
    /// important half of the contract: an unmemoised walk of every row on every
    /// frame is 2.4× the frame on a two-thousand-row editor, so a stack whose
    /// content is not a single `ForEach` over comparable data keeps the sampled
    /// answer it has today rather than buying exactness at that price. That is
    /// the same line `_ListCore.widestRowWidth` draws — "Sources that cannot
    /// say what their data is … walk every time" — drawn the other way, because
    /// a List's walk measures rows it has already built and this one builds
    /// them.
    ///
    /// - Parameters:
    ///   - widthLimit: The budget the rows are measured against, and the
    ///     ceiling the walk stops at.
    ///   - mayWalk: Whether this ask is allowed to pay for a walk. `false` for
    ///     a BOUNDED ask (`proposal.width != nil`), which can read a kept
    ///     answer — a `.frame(maxWidth:)` around the stack should not be told
    ///     the sample's width when the exact one is already in hand — but must
    ///     never start one: the vertical natural-extent probe is a bounded ask
    ///     over every row, and walking there cost `log-viewer` 45× and `chat`
    ///     56× before this parameter existed.
    func contentWidthOverAllRows(
        _ children: ChildViewCollection, widthLimit: Int, mayWalk: Bool,
        state: StackWindowState, context: RenderContext
    ) -> ViewSize? {
        guard let signature = children.dataSignature else { return nil }
        let count = children.count
        guard count > 0 else { return nil }

        // RUNG 2 — the kept answer, and RUNG 3, the kept prefix: one record
        // answers both, because the record IS the answer when it covers the
        // whole collection. A second entry in the render cache was tried and
        // removed: it bought invalidation this record now carries itself
        // (``ContentWidthRecord``) and charged a `SizeKey` hash, a dynamic
        // `AnyEquatableBox` compare and a `markActive` on every ask, which on a
        // settled two-thousand-line editor — where the answer never changes and
        // the walk runs once in the process's life — was the whole of its cost.
        var from = 0
        var widest = 0
        var isFlexible = false
        if let record = state.contentWidth, record.isCurrent(in: context) {
            if record.rows == signature, record.covered == count {
                return answer(
                    widest: record.widest, isFlexible: record.isFlexible, limit: widthLimit)
            }
            if record.covered <= count, signature.extends(record.rows) {
                from = record.covered
                widest = record.widest
                isFlexible = record.isFlexible
            }
        }
        guard mayWalk else { return nil }

        // RUNG 4 — the walk, and RUNG 1, the ceiling it stops at.
        var measureContext = context
        measureContext.isMeasuring = true
        // Children of a windowed stack are not at the scroll origin; the window
        // must not leak into their own measures (`windowSizeThatFits`).
        measureContext.environment.scrollContentWindow = nil
        let existingTracker = context.environment.volatileReadTracker
        let tracker = existingTracker ?? VolatileReadTracker()
        if existingTracker == nil {
            measureContext = measureContext.withEnvironment(
                measureContext.environment.setting(\.volatileReadTracker, to: tracker))
        }
        let unsafeBefore = tracker.cacheUnsafeCount

        let proposal = ProposedSize(width: widthLimit, height: nil)
        var walked = from
        var clamped = false
        while walked < count {
            let size = children[walked].measure(proposal: proposal, context: measureContext)
            walked += 1
            // A row that fills whatever it is offered has no natural width:
            // folding its clamped measurement into the maximum would report the
            // ladder's budget as the content's width. It contributes its
            // flexibility instead, which is what ends the ladder.
            if size.isWidthFlexible {
                isFlexible = true
                continue
            }
            if size.width >= widthLimit {
                widest = widthLimit
                clamped = true
                break
            }
            widest = max(widest, size.width)
        }

        // A partial maximum must not be filed as if it were the whole one, and
        // a subtree that read a per-frame value or carries an environment that
        // cannot be compared must not be filed at all.
        if !clamped, tracker.cacheUnsafeCount == unsafeBefore,
            !measureContext.environment.hasUncomparableEnvironmentValue
        {
            state.contentWidth = ContentWidthRecord(
                rows: signature, covered: walked, widest: widest, isFlexible: isFlexible,
                widthGeneration: TerminalWidthTraits.generation,
                measureGeneration: context.measureGeneration,
                clearGeneration: context.renderCache?.clearGeneration ?? 0)
        }
        return answer(widest: widest, isFlexible: isFlexible, limit: widthLimit)
    }

    private func answer(widest: Int, isFlexible: Bool, limit: Int) -> ViewSize {
        ViewSize(
            width: min(widest, limit), height: 0,
            isWidthFlexible: isFlexible, isHeightFlexible: false)
    }
}
