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
//  A measure is SPECULATIVE: it may run several times a frame, at sizes nothing
//  is drawn at, for a subtree that is never rendered. The rule it works under is
//  the one a CPU's speculative execution works under — it may do anything it
//  likes, including fill caches, so long as nothing the user is meant to be able
//  to rely on differs when the speculation turns out not to be needed. Latency
//  and allocation are not that; the committed frame is.
//
//  So a derived cache written from a measure is fine, and this one qualifies:
//  the record is a maximum over rows, recomputed from the rows themselves, so a
//  measure that never renders leaves behind a correct answer rather than a
//  decision. The box it lives in may itself be CREATED by a measure —
//  `uniformWindowState` hydrates it with `storage(for:default:)` at the top of
//  `anchoredSizeThatFits` — which `StateStorage.existingStorage` warns a measure
//  off, rightly, for a user's `@State`, whose first value is something an app
//  sees. Nothing in this box is: every field in it is derived, so creating it
//  speculatively is the case the rule above permits, and a stack that stops
//  being measured has it pruned like any other. The render cache's size memo
//  says the same of its own store, in as many words
//  (`RenderCache.lookupSize(key:view:)`): "Unlike the buffer cache this is safe
//  to populate from a measure pass".
//
//  `RowWidthRecords`' stricter local rule — "seeding is a render-path mutation"
//  — is still right for IT, and the difference is worth naming, because it is
//  the line: **a complete aggregate is path-independent; a sample is not.** A
//  maximum over every row is the same number whoever computes it, in whatever
//  order. A sixteen-row seed is not — WHICH rows were sampled shapes every later
//  answer, so a measure that sampled differently from the render would make the
//  stack's width depend on which passes happened to run, and that is a visible
//  effect of speculation.
//
//  What this is NOT free of is invalidation duty, and the duty is larger than a
//  render-cache entry's, because this record survives what those do not — see
//  ``ContentWidthRecord`` for the three events that make it stale, and
//  `challenge` for the fourth, which it can only ask about.
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
/// the cache's for free. Three events make a record stale outright, none of
/// which this stack could observe for itself:
///
/// * ``TerminalWidthTraits/generation`` — the terminal's reported glyph widths
///   moved, so every cell count taken before it is a different number now. The
///   render cache answers this with a `clearAll()` in `beginRenderPass`.
/// * ``RenderContext/measureGeneration`` — a container declared that measures
///   below it must not be reused.
/// * ``RenderCache/clearGeneration`` — the cache was dropped whole: a moved
///   `EnvironmentSnapshot`, a moved colour claim.
///
/// A fourth is carried and does NOT make it stale: a subtree clear that drops
/// sizes (``RenderCache/sizeClearGeneration``), which every `@State` write is.
/// The record is keyed on the rows' DATA, and a row draws more than its data —
/// a units toggle, a "show details" — which is the `ForEach` captured-data hole
/// every memo in the framework has. This record is exposed to it differently
/// from its siblings, and worse: `Table.fitWidth` and `_ListCore.widestRowWidth`
/// sit in the render cache, so a write sweeps them, and this record survives a
/// write BY DESIGN, because surviving one is why it is in `@State`. Treating
/// the write as staleness is exact and costs +3,590% on a document written to
/// every frame, so it gates a CHALLENGE instead — see
/// `_VStackCore.challenge(_:children:context:)`.
struct ContentWidthRecord {
    /// The rows the maximum was taken over — the whole collection at the time.
    let rows: AnyEquatableBox
    /// How many leading rows `widest` is the maximum over.
    let covered: Int
    /// The widest row among them that has a width of its own. A row that
    /// fills whatever it is offered has none to contribute; it contributes
    /// `isFlexible` (``wholeContentWidth(of:limit:)``).
    /// Moved in place when a challenge finds that row wider than it was, or
    /// narrower but still at least ``runnerUp`` — or a row the last frame
    /// drew wider than both.
    var widest: Int
    /// Which row that was — the one `challenge` re-measures after a write,
    /// with the rows the last frame drew. `nil` when no row had a width of
    /// its own: no row's width decided the answer, and a write that gives an
    /// undrawn row one is inside the residue `challenge` states.
    var widestOrdinal: Int?
    /// The proposal width that row was measured under, which `challenge`
    /// measures it under again: a width taken under one proposal is only
    /// comparable with one taken under the same proposal, because a row wider
    /// than a proposal WRAPS to it rather than reporting that it is wider.
    let measuredAt: Int
    /// The second-widest such row's width — a bound, not a row: every
    /// row but the widest is at most this wide, so a challenge that finds the
    /// widest row narrower but still at least this wide knows the new maximum
    /// exactly. `0` when there is no second row. Raised by a challenge that
    /// finds a drawn row wider than the widest, which leaves the old widest
    /// among the rest.
    var runnerUp: Int
    let isFlexible: Bool
    let widthGeneration: Int
    /// ``RenderContext/generationIgnoringIdealWidth``: a record filed under
    /// the probe's ideal-width mark is the same answer when a render asks.
    let measureGeneration: UInt8
    /// ``RenderCache/clearGeneration`` — how many times the cache had been
    /// dropped whole when this was taken. The two events that do that, a moved
    /// `EnvironmentSnapshot` and a moved colour claim, are the ones a record in
    /// `@State` cannot see for itself.
    let clearGeneration: Int
    /// ``RenderCache/sizeClearGeneration`` when this record was last known to
    /// hold. NOT part of ``isCurrent(in:)`` — a write does not mean these widths
    /// moved, and treating it as if it did costs 37× on a document written to
    /// every frame (measured). When it is behind, `challenge` runs before the
    /// record answers.
    var verifiedGeneration: Int

    /// Whether this record was taken under the same world as `context`.
    func isCurrent(in context: RenderContext) -> Bool {
        widthGeneration == TerminalWidthTraits.generation
            && measureGeneration == context.generationIgnoringIdealWidth
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
    ///   - ask: What this ask may do (`contentWidthAsk`). Only `.probe` — the
    ///     horizontal natural-extent probe itself, unbounded — may pay for a
    ///     walk and file what it finds. `.serve` may read a kept answer (a
    ///     render, the vertical probe, a `.frame(maxWidth:)` around the stack
    ///     should not be told the sample's width when the exact one is in hand)
    ///     but never starts one: the vertical probe asks over every row, and
    ///     walking there cost `log-viewer` 45× and `chat` 56× before this rule
    ///     existed; and an unbounded ask arriving at a terminal's width WRAPS a
    ///     sentence to a little under it, a width that looks honest and would
    ///     be filed as the content's.
    func contentWidthOverAllRows(
        _ children: ChildViewCollection, widthLimit: Int, ask: ContentWidthAsk,
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
        var widestOrdinal: Int?
        var measuredAt = widthLimit
        var runnerUp = 0
        var isFlexible = false
        // What an extension files as its verification: the prefix is exactly as
        // checked as the challenge left it, which is NOT checked when the
        // challenge's measure read something that moves on its own. `nil` for a
        // walk from nothing, which has just measured every row.
        var inheritedVerification: Int?
        if var record = state.contentWidth, record.isCurrent(in: context) {
            let whole = record.rows == signature && record.covered == count
            // Challenged only once it is known to be USABLE: a record for other
            // rows is about to be replaced by a walk, and re-measuring its
            // widest row would be a row measured for nothing.
            if whole || (record.covered <= count && signature.extends(record.rows)) {
                // The drawn rows only when the collection did not move: a write
                // that edits rows in place is where one drawn row outgrows the
                // rest — typing into a line — and a write that only grew the
                // collection has its new rows walked by the extension below. A
                // document appended to every frame would otherwise pay a band
                // of row measures every frame for rows it never touched:
                // measured, +21.3% on `app-shapes/code-editor-tailing`.
                let drawn = whole ? state.drawnOrdinals : 0..<0
                if challenge(&record, children: children, drawn: drawn, context: context) {
                    state.contentWidth = record
                    if whole {
                        return answer(
                            widest: record.widest, isFlexible: record.isFlexible,
                            limit: widthLimit)
                    }
                    from = record.covered
                    widest = record.widest
                    widestOrdinal = record.widestOrdinal
                    measuredAt = record.measuredAt
                    runnerUp = record.runnerUp
                    isFlexible = record.isFlexible
                    inheritedVerification = record.verifiedGeneration
                } else {
                    // Falsified, so gone: a record known to be wrong answers
                    // nothing, and kept it would only be challenged again.
                    state.contentWidth = nil
                }
            }
        }
        guard ask == .probe else { return nil }

        // RUNG 4 — the walk, and RUNG 1, the ceiling it stops at.
        let (measureContext, tracker) = rowWidthContext(context, width: widthLimit)
        let unsafeBefore = tracker.cacheUnsafeCount

        // Unproposed, under the mark: each row is asked its IDEAL width, which
        // is the question — a filling frame answers with its content rather
        // than the rung (``RenderContext/asksIdealWidth``).
        let proposal = ProposedSize(width: nil, height: nil)
        var walked = from
        // An inherited maximum can already be at this ask's ceiling — a wider
        // ask kept it — and then there is nothing left to walk for: the answer
        // is the ceiling, and new rows measured under it could only be filed
        // beside a maximum measured under a higher one.
        var clamped = widest >= widthLimit
        while !clamped, walked < count {
            let ordinal = walked
            let size = children[ordinal].measure(proposal: proposal, context: measureContext)
            walked += 1
            if size.isWidthFlexible { isFlexible = true }
            // A row with no width of its own contributes only its flexibility,
            // and is never the row a challenge re-measures — see
            // `wholeContentWidth(of:limit:)`.
            if hasNoWidthOfItsOwn(size, limit: widthLimit) { continue }
            if size.width >= widthLimit {
                widest = widthLimit
                widestOrdinal = ordinal
                clamped = true
                break
            }
            if widestOrdinal == nil {
                widest = size.width
                widestOrdinal = ordinal
                measuredAt = widthLimit
            } else if size.width > widest {
                runnerUp = widest
                widest = size.width
                widestOrdinal = ordinal
                measuredAt = widthLimit
            } else if size.width > runnerUp {
                runnerUp = size.width
            }
        }

        // A partial maximum must not be filed as if it were the whole one, and
        // a subtree that read a per-frame value or carries an environment that
        // cannot be compared must not be filed at all.
        if !clamped, tracker.cacheUnsafeCount == unsafeBefore,
            !measureContext.environment.hasUncomparableEnvironmentValue
        {
            state.contentWidth = ContentWidthRecord(
                rows: signature, covered: walked, widest: widest,
                widestOrdinal: widestOrdinal, measuredAt: measuredAt, runnerUp: runnerUp,
                isFlexible: isFlexible,
                widthGeneration: TerminalWidthTraits.generation,
                measureGeneration: context.generationIgnoringIdealWidth,
                clearGeneration: context.renderCache?.clearGeneration ?? 0,
                verifiedGeneration: inheritedVerification
                    ?? (context.renderCache?.sizeClearGeneration ?? 0))
        }
        return answer(widest: widest, isFlexible: isFlexible, limit: widthLimit)
    }

    /// The context a row is measured in for the content width, and the tracker
    /// that says whether what the measure read can be kept. One function for
    /// the walk and the challenge, because their answers are compared with each
    /// other and are only comparable if they were taken the same way.
    private func rowWidthContext(
        _ context: RenderContext, width: Int
    ) -> (context: RenderContext, tracker: VolatileReadTracker) {
        // Under the ideal-width mark always, whoever asks: the walk runs at the
        // probe, but the challenge can run at a render, and a row that answers
        // the probe's question differently from a render's must answer the
        // walk's question both times.
        var measureContext = context.askingIdealWidth()
        measureContext.isMeasuring = true
        measureContext.availableWidth = width
        // Children of a windowed stack are not at the scroll origin; the window
        // must not leak into their own measures (`windowSizeThatFits`).
        measureContext.leaveScrollOrigin()
        if let tracker = context.environment.volatileReadTracker {
            return (measureContext, tracker)
        }
        let tracker = VolatileReadTracker()
        return (
            measureContext.withEnvironment(
                measureContext.environment.setting(\.volatileReadTracker, to: tracker)),
            tracker
        )
    }

    /// Re-measures the one row a kept record names as its widest, and the rows
    /// the last frame drew, when a size clear has happened since the record was
    /// last known to hold, and reports whether it still does. `true` when there
    /// was nothing to challenge.
    ///
    /// The row is measured at the width it was measured at when it was filed
    /// (``ContentWidthRecord/measuredAt``), NOT at this ask's — so the verdict is
    /// the same whichever ask happens to run it, which is the line
    /// ``RenderContext/isMeasuring`` draws. The first version measured at the
    /// ask's own limit, and a narrow ask cannot tell a row's width from its
    /// wrap: a 120-cell sentence measures a few cells under a 40-cell
    /// proposal, exactly as a 38-cell row does. So a
    /// narrow ask that came first either failed a good record or raised it to
    /// the wrapped width and marked it checked, and which a frame got depended
    /// on the order its asks arrived in. What an ask is ANSWERED is still capped
    /// at its own limit; that is ``answer(widest:isFlexible:limit:)``'s job.
    ///
    /// By what the row measures now:
    ///
    /// * **The same or wider** — the record holds, raised to the row's new
    ///   width. That is exact on the challenge's own premise, that the other
    ///   rows did not move: the old maximum bounded them, and the new width is
    ///   at least the old maximum. It is also the case that matters most —
    ///   typing at the end of a document's longest line, which anything else
    ///   would answer by walking every row on every keystroke.
    /// * **Narrower, but still at least the runner-up** — the record holds,
    ///   lowered to the row's new width, exact on the same premise: every other
    ///   row is at most the runner-up. Holding Backspace at the end of the
    ///   longest line is this case until the line stops being the longest.
    /// * **Narrower than the runner-up** — it falls, because some other row is
    ///   the widest now and only a walk can say which.
    /// * **At or past the width it was measured at** — it falls: the row
    ///   outgrew the ceiling it was measured against, by an amount a measure
    ///   under that ceiling cannot say — or it fills whatever it is offered
    ///   now, and has no width to hold the maximum with, so which row does is
    ///   a walk's question too. A row that is flexible BELOW that width — a
    ///   filling frame, answering with its content — holds by its width like
    ///   any other.
    ///
    /// The rows the last frame DREW (``StackWindowState/drawnOrdinals``) are
    /// measured the same way, and the widest of everything measured is the
    /// maximum, exact on the same premise: the runner-up bounds every row not
    /// measured. A drawn row wider than the named one TAKES the record — and
    /// the named row joins the rest under the runner-up — so a line typed on
    /// until it is the longest reaches the extent on the frame of the keystroke
    /// that made it so. A drawn row past the ceiling falls it like the named
    /// row; one that fills whatever it is offered counts nothing, as in the
    /// walk. They cost a band of row measures on the frames a write moved the
    /// sizes, and nothing on the others.
    ///
    /// The row is MEASURED, not remembered: its own memoized sizes are
    /// forgotten first (``RenderCache/forgetSizes(of:measureGeneration:)``).
    /// That memo compares only the row's element, and survives any clear that
    /// is not about the row — a row measured but never drawn reads its
    /// `@Observable`s untracked, so a write to one clears the rows that WERE
    /// drawn and not this one. Served from it, the challenge would certify the
    /// width it exists to catch; and the sizes it holds under other proposals
    /// are wrong the same way, which the walk that follows a fall must not be
    /// served. A memo deeper INSIDE the row — an `.equatable()` view whose
    /// value compares equal while what its body reads has moved — is not
    /// forgotten, and need not be: the size memo drops, at the end of every
    /// frame, the entries of a row that frame did not draw, so what the
    /// challenge finds inside the widest row was measured this frame, after
    /// the write. An entry outlives its frame only under an `.equatable()`
    /// ancestor served from the buffer memo in that same frame
    /// (`RenderCache.retainSubtree(_:)`), and a frame that serves the stack
    /// that way does not measure it. `ContentWidthFreshChallengeTests` fails
    /// the day that stops being true. What is left sits upstream of every
    /// memo: a row measured but never drawn reads its `@Observable`s
    /// untracked, so a change to one moves nothing — no clear, so no
    /// challenge — and the extent learns it when the row is drawn, or when the
    /// next write challenges the record.
    ///
    /// A measure that read something that moves on its own — an animation in
    /// flight — still answers, but does not mark the record checked, so the next
    /// ask challenges again until the row settles. A walk that extends the
    /// record inherits that rather than stamping the prefix as checked.
    ///
    /// ## Why a challenge and not an invalidation
    ///
    /// A row's width is a function of its data — which the record keys on — and
    /// of whatever else the row's closure reads. That second half is the
    /// `ForEach` captured-data hole every memo in the framework has, but this
    /// record is exposed to it differently from its siblings: `Table.fitWidth`
    /// and `_ListCore.widestRowWidth` live in the render cache, so a `@State`
    /// write takes them with it, and this one lives in `@State` precisely so a
    /// write CANNOT. Without something here, a `.toggle()` that changes what a
    /// row draws — a units switch, a "show details" — would leave the content
    /// wider than the extent says and its tails unreachable: the defect
    /// `ScrollTwoAxisWindowTests` exists to forbid.
    ///
    /// Treating a write as an invalidation is the exact answer and is not
    /// affordable: measured at **+3,590%** on `app-shapes/code-editor-tailing`,
    /// where the write and the data change are the same event, because it turns
    /// every incremental walk back into a full one. So this challenges instead —
    /// one row, the one that decided the answer. A change that moves what rows
    /// draw moves that row too whenever it is uniform (a format, a locale, a
    /// units toggle), which is what such changes overwhelmingly are.
    ///
    /// **It is a sample — the named row and the drawn ones — and the residue
    /// is stated rather than hidden**: a change that widens some row the last
    /// frame did NOT draw past the runner-up, under an unchanged collection, is
    /// not caught until something starts a walk over — and growth does not,
    /// because a collection that only grew is extended. Past the maximum, the
    /// extent is short at once; past only the runner-up, it is short once the
    /// widest row narrows below that other row, since the bound it was lowered
    /// against was stale. Scrolled into view, such a row is drawn, and the next
    /// write measures it; with no write, nothing asks. And the drawn rows are
    /// measured only for a write that left the collection as it was (see the
    /// caller): one that ALSO grew it — a paste of several lines into a line —
    /// leaves the edited line to the next write that does not. The exact
    /// alternative —
    /// re-walking to verify, while holding the old maximum as a floor so
    /// nothing becomes unreachable meanwhile — is a design of its own and is
    /// noted rather than guessed at here.
    private func challenge(
        _ record: inout ContentWidthRecord, children: ChildViewCollection,
        drawn: Range<Int>, context: RenderContext
    ) -> Bool {
        guard record.verifiedGeneration != (context.renderCache?.sizeClearGeneration ?? 0)
        else { return true }
        let (measureContext, tracker) = rowWidthContext(context, width: record.measuredAt)
        let unsafeBefore = tracker.cacheUnsafeCount
        // Asked as the walk asks — unproposed, under the mark — or the answers
        // are not comparable with the record's.
        let unproposed = ProposedSize(width: nil, height: nil)

        // Every row measured here is known exactly; every other row is at most
        // the runner-up, on the challenge's premise that it did not move.
        var widest = 0
        var widestOrdinal: Int?
        var runnerUp = record.runnerUp
        if let ordinal = record.widestOrdinal {
            guard ordinal < children.count else { return false }
            let row = children[ordinal]
            // Its sizes forgotten FIRST, so it is measured rather than
            // remembered — and so the ones memoized under a proposal this does
            // not ask are gone too, and the walk that follows a fall, at
            // whichever rung it runs, is not served one of those.
            context.renderCache?.forgetSizes(
                of: row.identity(under: measureContext),
                measureGeneration: measureContext.measureGeneration)
            let size = row.measure(proposal: unproposed, context: measureContext)
            guard size.width < record.measuredAt else { return false }
            widest = size.width
            widestOrdinal = ordinal
        }

        // The rows the last frame DREW — see ``StackWindowState/drawnOrdinals``.
        // Not forgotten first: a drawn row was observed as it rendered, so the
        // write that moved it cleared its sizes already, which is exactly what
        // the widest row, measured but perhaps never drawn, cannot count on.
        // Rows past the record's prefix are the extension's, and walked by it.
        let reach = min(record.covered, children.count)
        for ordinal in drawn.clamped(to: 0..<reach) where ordinal != record.widestOrdinal {
            let size = children[ordinal].measure(proposal: unproposed, context: measureContext)
            if hasNoWidthOfItsOwn(size, limit: record.measuredAt) { continue }
            guard size.width < record.measuredAt else { return false }
            if size.width > widest {
                if widestOrdinal != nil { runnerUp = max(runnerUp, widest) }
                widest = size.width
                widestOrdinal = ordinal
            } else {
                runnerUp = max(runnerUp, size.width)
            }
        }

        // Narrower than the bound on the rows NOT measured: one of them may be
        // the widest now, and only a walk can say which.
        guard widestOrdinal == nil || widest >= record.runnerUp else { return false }
        record.widest = widest
        record.widestOrdinal = widestOrdinal
        record.runnerUp = runnerUp
        // Read AFTER the measures: a clear a measure itself caused — a row's
        // environment modifier noting a change — is one this answer reflects.
        if tracker.cacheUnsafeCount == unsafeBefore,
            !measureContext.environment.hasUncomparableEnvironmentValue
        {
            record.verifiedGeneration = context.renderCache?.sizeClearGeneration ?? 0
        }
        return true
    }

    /// What an ask is told: the maximum, capped at the ask's own limit.
    ///
    /// A CAPPED answer is never flexible. An inflexible row wider than the
    /// limit decided it, and a filler elsewhere cannot make it any wider — but
    /// `measureNaturalExtent` reads "flexible, and at the budget" as "fills
    /// whatever it is given" and stops climbing, at a rung that cannot hold the
    /// row. Worse, whether it said so depended on the path: a walk stops at the
    /// first row that reaches the ceiling and has seen only the fillers before
    /// it, while a kept record has seen every one. A two-axis view whose widest
    /// row was 6,000 cells and whose row 300 was a `Divider` measured 6,000 on
    /// its first frame and 4,096 on its second, with nothing changed.
    private func answer(widest: Int, isFlexible: Bool, limit: Int) -> ViewSize {
        ViewSize(
            width: min(widest, limit), height: 0,
            isWidthFlexible: wholeContentFlexibility(isFlexible, width: widest, limit: limit),
            isHeightFlexible: false)
    }
}

// MARK: - Counting rows

/// Whether a whole-content width answer is flexible: only when it is below
/// its limit. The rule `_VStackCore.answer(widest:isFlexible:limit:)` applies,
/// stated once, because every arm that answers the same natural-width ask — the
/// anchored sample, the uniform band and sample, the small-collection slot
/// walk — has to apply it too. An arm that said "flexible" for a capped
/// answer where the walk said not would decide, by being the one that
/// answered, whether `measureNaturalExtent` climbs past its first rung.
func wholeContentFlexibility(_ isFlexible: Bool, width: Int, limit: Int) -> Bool {
    isFlexible && width < limit
}

/// What one row adds to a whole-content width answer: its width, capped at
/// the limit — or nothing, when it came back flexible AT the limit. Such a
/// row reported what it was offered, and would report any other offer
/// just the same (a `TextEditor`, a nested `List`), so it has no width to
/// contribute and contributes its flexibility instead; counted, it put the
/// ladder's rung into the answer as if a row were that wide.
///
/// A flexible row BELOW the limit counts like any other. Under the
/// ideal-width ask that is what a `.frame(maxWidth: .infinity)` answers —
/// its content's width (``RenderContext/asksIdealWidth``) — and it was
/// once left out of the maximum with the true fillers, so a filler whose
/// text was the widest thing in the content was cut at the viewport.
///
/// The one rule for every arm that answers the natural-width ask, and for
/// the eager column (`clipSizeThatFits`), for the reason
/// ``wholeContentFlexibility(_:width:limit:)`` gives.
func wholeContentWidth(of size: ViewSize, limit: Int) -> Int {
    hasNoWidthOfItsOwn(size, limit: limit) ? 0 : min(size.width, limit)
}

/// Whether a row came back flexible at the limit — filling what it was
/// offered, with no width of its own. See
/// ``wholeContentWidth(of:limit:)``.
func hasNoWidthOfItsOwn(_ size: ViewSize, limit: Int) -> Bool {
    size.isWidthFlexible && size.width >= limit
}

/// The smallest range holding every ordinal in `ordinals` — the rows a band
/// render drew, for ``StackWindowState/drawnOrdinals``. Empty for none.
func ordinalSpan(of ordinals: [Int]) -> Range<Int> {
    guard let first = ordinals.min(), let last = ordinals.max() else { return 0..<0 }
    return first..<(last + 1)
}
