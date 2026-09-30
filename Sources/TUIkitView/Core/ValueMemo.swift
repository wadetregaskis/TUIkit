//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueMemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The value memo, once

//  Two wrappers memoize a subtree by the value of something: `EquatableView` by
//  the whole view value, `_MemoizedRow` by a `ForEach` row's data element. What
//  they DO with that value is identical — probe the cache, keep the cached
//  subtree's state alive on a hit, otherwise render under a volatile-read
//  tracker and store only what is safe to serve again — and it was written twice.
//
//  Written twice, it drifted, and the drift is on the record inside
//  `_MemoizedRow` itself: the `hasUncomparableEnvironmentValue` clause "was
//  missed when the buffer half was unified", so a Form row under an injected
//  uncomparable value measured once and served that size forever. That is the
//  argument for one copy — not tidiness, but that the next clause added to one
//  half would have gone the same way.
//
//  The memo BUILDS what it draws. A caller hands it two closures, `build`, which
//  makes the row's view, and `render` (or `measure`), which draws a built view,
//  and the memo calls `build` at most once per call, only on a path that draws
//  or measures the row, and hands what it built to the draw. So the one place
//  that needs the built value — a serve that has to compare the value it would
//  draw before it serves, and draws that same value when the comparison fails —
//  already holds it, and the row is never built twice in one call. The built
//  row lives for the call and no longer: nothing here keeps it.
//
//  Generic functions taking the key by value, rather than a protocol with a
//  `var memoKey` requirement. A get-only property requirement returns `@out`,
//  and the production key on the row path is the row's element as its own type
//  — found at run time, so address-only here — so every probe would
//  materialise a copy and a destroy of it where a generic parameter is
//  `@in_guaranteed` and borrows the caller's field. Both callers are in this
//  module and built whole-module, so each gets a specialization in which the
//  closures inline and nothing is allocated.

/// The buffer half: serves `key`'s cached buffer, or renders and stores it.
///
/// A stored subtree may carry registrations (`EffectJournal`): the per-frame
/// registrations its render recorded, which a hit makes again at this position
/// in the walk, so the key dispatcher and the other per-walk registries see
/// the same thing whether the subtree rendered or was served.
///
/// - Parameters:
///   - key: The value the memo is keyed by. A hit means this compared equal;
///     whether that implies an equal rendering is the CALLER's claim, and the two
///     callers claim it on different grounds — see their own doc comments.
///   - viewType: The type named in a verifier mismatch report. An autoclosure
///     over a metatype, so neither the metadata read nor `String(describing:)` is
///     paid on the paths that never report — which is all of them, almost always.
///   - context: The render context.
///   - build: Builds the memoized content's view. Called at most once per call,
///     and only where it is drawn — on a miss, or for the verifier's fresh
///     render — which is what lets `_MemoizedRow` defer building the row view
///     at all.
///   - render: Renders a built view. Called on the same paths, with what
///     `build` returned.
///
/// `@inline(__always)`: both callers are in this module, and the MISS path calls
/// `render` once per row per pass. Left out of line it cost **+3.3% on the
/// `menus` stress scenario** — the shape with the highest miss ratio, since an
/// interactive row can never be stored and so takes the miss path every frame.
/// For the same reason everything a hit or a store does with registrations is
/// out of line below, behind a count check.
@inline(__always)
@MainActor
func renderValueMemoized<Key: Equatable, Row>(
    key: Key,
    viewType: @autoclosure () -> Any.Type,
    context: RenderContext,
    build: () -> Row,
    render: (Row, RenderContext) -> FrameBuffer
) -> FrameBuffer {
    // No cache: standalone rendering, outside a render loop. Render straight
    // through rather than trapping — `EquatableView.renderToBuffer` used to force
    // unwrap here while its own `sizeThatFits` guarded, so the type contradicted
    // itself; the guard is the half that is right.
    guard let cache = context.renderCache else { return render(build(), context) }
    let identity = context.identity
    cache.markActive(identity)

    if let entry = cache.lookupEntry(
        identity: identity, view: key,
        contextWidth: context.availableWidth, contextHeight: context.availableHeight,
        gradientFrame: context.gradientFrame,
        surfaceBackground: context.environment.surfaceBackground,
        effectScope: context.effectScope,
        // A measure draws nothing, and a run's frames are all one width.
        animationMustBeCurrent: !context.isMeasuring)
    {
        // Keep the cached subtree's state alive for GC — the WHOLE subtree, not
        // just this identity: nothing below is visited on a hit, so a `@State`
        // deeper than a direct child would otherwise be pruned this pass and
        // reset on the next real render.
        context.stateStorage?.markActive(identity)
        context.stateStorage?.retainSubtree(identity)
        // The same declaration to the render cache, for the same reason one layer
        // over. `markActive(identity)` above covers THIS wrapper only; a nested
        // one below it — the ordinary nested-`ForEach` shape, since `ForEach`
        // wraps every Equatable element row in one of these — is never visited on
        // a hit, so `removeInactive()` collected its entry while it was still
        // live, and `sizeThatFits` deliberately marks nothing, so the measure walk
        // could not rescue it either. The steady state was one entry where there
        // should have been two, and the first frame the OUTER value changed, every
        // inner row re-rendered from scratch though none of them had.
        cache.retainSubtree(identity)
        // Both callers verify. This used to be a `verifies` parameter that
        // `_MemoizedRow` passed `false`, so under `TUIKIT_VERIFY_RENDER_MEMO`
        // the standing CI net checked no row serve at all — and rows are what
        // the net mostly has to check, since `ForEach` wraps every Equatable
        // element in a `_MemoizedRow` and nothing in `Stress` uses
        // `.equatable()`.
        // One row of `megalist` against one row of `table`, in a number: a
        // served subtree is a row a control did not have to compose.
        cache.rowWork.served += 1
        if RenderCache.verifiesRenderMemo {
            return verifyServe(
                entry, viewType: viewType, context: context, cache: cache, render: { render(build(), $0) })
        } else if !entry.effects.isEmpty, !context.isMeasuring {
            // A measure pass registers nothing when it renders, so it replays
            // nothing when it is served.
            replayEffects(entry.effects, context: context, cache: cache)
        }
        return entry.buffer
    }

    // Miss: render under a volatile-read tracker (reusing an ancestor's, so
    // nesting bubbles up) and store only buffers that are safe to serve again:
    //   • never a measure-pass buffer (incomplete — interactive controls suppress
    //     their hit-test regions while measuring — and it would clobber the
    //     render-pass entry at a different size every frame);
    //   • never a subtree carrying an overlay (a layer this buffer has not
    //     composited yet, settled by the frame rather than by the subtree). A
    //     hit-test REGION no longer stops it: its id is the control's own, and
    //     the handler behind it is registered again from the journal below;
    //   • never a time-varying subtree (a pulse-phase read or an animation
    //     request means the next frame differs even though the value compares
    //     equal — a cached Spinner would freeze, issue #1). A subtree whose
    //     motion is all in animated cell runs IS stored: the loop moves the runs
    //     on without it. Its buffer shows each run at the instant it was drawn,
    //     though, so the lookup above misses once any run shows something else;
    //   • never a subtree that made a per-frame registration this memo cannot
    //     make again. One it CAN (`recordReplayableEffect`) was recorded in the
    //     effect journal while this render ran, and is stored with the buffer.
    // The other half of the pair above: a subtree that had to be composed.
    cache.rowWork.rendered += 1
    let existingTracker = context.environment.volatileReadTracker
    let tracker = existingTracker ?? VolatileReadTracker()
    let renderContext =
        existingTracker == nil
        ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
        : context
    // `unreplayableCount`, not `cacheUnsafeCount`: this is the one gate that
    // replays. Every other gate on the tracker keeps counting replayable
    // registrations, because it has no way to make them again.
    let unsafeBefore = tracker.unreplayableCount
    // Snapshot the invalidation generation too: a `clearAffected` DURING this
    // render — an environment or colour-environment change, a `ScrollViewReader`
    // publish; those are its synchronous callers — fires before we store, and
    // storing afterwards would resurrect the pre-clear buffer and serve it until
    // the key next changes. NOT a `@State` write: since `44660d87` those are
    // queued (on the cache's `link`) and drained at the next `beginRenderPass`,
    // so this counter does not move for them and the store goes ahead — which is
    // right, because the drain clears the entry before it can be served. That
    // rests on the drain dropping the entries at, above AND below each queued
    // identity: a write this render makes to state the buffer read is to state
    // held at this memo, inside it or above it, and each of those drops this
    // entry. A drain that keeps what is below a writer (Option C's soft drain)
    // keeps this entry after a write above it, and the store is then right
    // only if what that drain keeps is re-checked before it is served.
    let clearsBefore = cache.stats.subtreeClears
    let journal = cache.effectJournal
    let journalStart = journal.beginRecording()

    // The scopes this render arms are kept alive by the entry it stores, for as
    // long as that is kept — and, stored or not, by what encloses this memo
    // (see `ObservationLeases`).
    let leaseMark = cache.leases.beginComputation()
    let buffer = observingKeptResult(of: Key.self, kind: .keptRender, context: context) {
        render(build(), renderContext)
    }
    let lease = cache.leases.endComputation(leaseMark)

    if RenderCache.isStorable(
        buffer: buffer, context: context,
        readVolatile: tracker.unreplayableCount > unsafeBefore,
        invalidatedDuringRender: cache.stats.subtreeClears > clearsBefore)
    {
        let effects = journal.count > journalStart ? ownChannelEffects(journal, since: journalStart, context: context) : []
        cache.store(
            identity: identity, view: key, buffer: buffer,
            contextWidth: context.availableWidth, contextHeight: context.availableHeight,
            gradientFrame: context.gradientFrame,
            surfaceBackground: context.environment.surfaceBackground,
            recorded: (effects, effects.isEmpty ? .none : context.effectScope, lease))
    }
    // Empties the journal when this was the outermost recording memo. An inner
    // one leaves its entries in place for the memo enclosing it.
    journal.endRecording()
    return buffer
}

extension RenderContext {
    /// Where registrations made here are recorded — see
    /// `RenderCache.EffectScope`.
    fileprivate var effectScope: RenderCache.EffectScope {
        RenderCache.EffectScope(
            section: environment.activeFocusSectionID, isBackdrop: environment.drawsBackdrop)
    }
}

/// The recorded registrations since `start` that went into `context`'s own key
/// channels.
///
/// The others went into throwaways swapped in somewhere below — `.dimmed()`,
/// the page under a modal, a focus-reach probe — and were discarded with them.
/// Replayed from here they would land in the channels in force at this memo,
/// which for a live memo are the LIVE ones. Comparing `ObjectIdentifier`s is
/// sound here because this context holds its dispatcher for the whole render
/// that appended them.
@MainActor
private func ownChannelEffects(
    _ journal: EffectJournal, since start: Int, context: RenderContext
) -> [EffectJournal.Entry] {
    let token = context.environment.keyChannelToken
    return journal.entries(since: start).filter { $0.channelToken == token }
}

/// Makes a served subtree's registrations again, into `context`'s channels.
///
/// Also declares them as a replayable effect, so every gate enclosing this memo
/// sees the same count as if the subtree had rendered, and re-records them for
/// an enclosing memo that is recording, tagged with THIS context's channels:
/// the entry was stored under whatever channels were in force when it rendered,
/// and the ones in force now may be a different throwaway.
@MainActor
private func replayEffects(_ effects: [EffectJournal.Entry], context: RenderContext, cache: RenderCache) {
    for effect in effects { effect.apply(context) }
    context.environment.volatileReadTracker?.recordReplayableEffect()
    let journal = cache.effectJournal
    guard journal.isRecording else { return }
    let token = context.environment.keyChannelToken
    for effect in effects { journal.append(effect.retagged(token)) }
}

/// A hit under `TUIKIT_VERIFY_RENDER_MEMO`: renders the subtree fresh,
/// compares it with what was stored, and returns the FRESH render.
///
/// The fresh render registers for real, so the stored registrations are NOT
/// replayed here, or every handler would be there twice. Instead the fresh
/// render's registrations are recorded and compared with the stored ones by kind
/// and count, the only comparison opaque closures allow.
///
/// Returning the fresh render makes the verifier a debugging aid you can SEE:
/// under it the screen is what a frame drawn without the cache would show, so a
/// view that fails to update and starts updating under the verifier was being
/// served stale, and the report names it. It is not a way to make anything
/// work — it re-renders every serve, which costs more than the cache saves,
/// and every difference it draws, it also reports.
///
/// The fresh render observes nothing past the check: it runs in a detached
/// computation (``ObservationLeases/beginDetachedComputation()``), whose scopes
/// are cancelled as it ends. Observed under the frame, it would watch every
/// reader the entry holds — including one whose lease a kept result forgot
/// to hold — until the next frame, and a write in between would clear the
/// entry the verifier exists to catch serving stale.
@MainActor
private func verifyServe(
    _ entry: RenderCache.CacheEntry, viewType: () -> Any.Type, context: RenderContext,
    cache: RenderCache, render: (RenderContext) -> FrameBuffer
) -> FrameBuffer {
    let journal = cache.effectJournal
    let start = journal.beginRecording()
    defer { journal.endRecording() }
    let tracker = context.environment.volatileReadTracker
    let unreplayableBefore = tracker?.unreplayableCount ?? 0
    let checkMark = cache.leases.beginDetachedComputation()
    let fresh = render(context)
    _ = cache.leases.endComputation(checkMark)
    if fresh.lines != entry.buffer.lines {
        cache.noteRenderMemoMismatch(
            viewType: String(describing: viewType()), served: entry.buffer,
            fresh: fresh, identity: context.identity.path)
    }
    guard !context.isMeasuring else { return fresh }
    // A fresh render that declined — it made a registration that cannot be
    // replayed — leaves no journal to compare with: the declined registrations
    // were made, just not recorded. That is the focus-reach probe, which renders
    // rows beside the focused one under a manager that declines them all, and is
    // served what the live page stored; the replay registers the same controls
    // the fresh render would. The picture is still compared above, and would
    // catch the case that matters here, a control that now holds the focus
    // drawn as it looked without it.
    guard (tracker?.unreplayableCount ?? 0) == unreplayableBefore else { return fresh }
    let freshKinds = ownChannelEffects(journal, since: start, context: context).map(\.kind)
    let servedKinds = entry.effects.map(\.kind)
    if freshKinds != servedKinds {
        cache.noteRenderMemoEffectMismatch(
            viewType: String(describing: viewType()), served: servedKinds,
            fresh: freshKinds, identity: context.identity.path)
    }
    return fresh
}

/// Re-measures what a served cross-frame size stands for, reports a
/// disagreement — ``RenderCache/verifiesMeasureMemo``'s check, for this table —
/// and returns the FRESH size, as the render verifier returns the fresh render.
///
/// The per-pass memo's serves were checked and these were not: a size served
/// here was returned as it stood, so an entry that outlived what it measured
/// could be caught only by the pixels it happened to move. On a throwaway
/// tracker, so what the check reads cannot decide what the live pass stores;
/// and in a detached observation computation, so it observes nothing past the
/// check either (see `verifyServe`). Out of line, to keep the serve itself
/// small.
///
/// - Parameters:
///   - served: What the memo handed back.
///   - label: What the size is of, for the report; "(cross-frame)" is added.
///     Built only when there is something to report.
///   - proposal: The proposal the size answers, for the report.
///   - context: Where the size was asked.
///   - measure: Measures it afresh.
@inline(never)
@MainActor
package func verifyServedSize(
    _ served: ViewSize, label: @autoclosure () -> String, proposal: ProposedSize, context: RenderContext,
    measure: (RenderContext) -> ViewSize
) -> ViewSize {
    let checkMark = context.renderCache?.leases.beginDetachedComputation()
    let fresh = context.withVolatileReadTracker(VolatileReadTracker()) { measure($0) }
    _ = context.renderCache?.leases.endComputation(checkMark)
    guard fresh != served else { return fresh }
    context.renderCache?.noteMeasureMemoMismatch(
        viewType: "\(label()) (cross-frame)", served: served, fresh: fresh, proposal: proposal,
        availableWidth: context.availableWidth, availableHeight: context.availableHeight,
        identity: context.identity.path)
    return fresh
}

/// The size half: the same memo keyed by proposal as well as value.
///
/// Deliberately marks NOTHING active. Marking every measured identity is
/// O(tree) per frame on a giant eager tree (`fanout` at scale 100 measures
/// ~200k memoized rows — the Set inserts and identity hashing alone regressed it
/// 13%). A measure-only entry that must survive the pass is the WINDOWED band's
/// concern, and the band paths mark the specific rows they measure, bounded by
/// the window rather than the tree.
///
/// - Parameters:
///   - key: As the buffer half's.
///   - proposal: The proposed size, which is part of the key here.
///   - context: The render context.
///   - build: As the buffer half's: called at most once per call, and only
///     where the content is measured — on a miss, or for the verifier.
///   - measure: Measures a built view.
@inline(__always)
@MainActor
func measureValueMemoized<Key: Equatable, Row>(
    key: Key,
    proposal: ProposedSize,
    context: RenderContext,
    build: () -> Row,
    measure: (Row, RenderContext) -> ViewSize
) -> ViewSize {
    guard let cache = context.renderCache else { return measure(build(), context) }
    // The generation is in the key for the same reason `measureChild`'s is (see
    // `measureIdentityHash`), and it has to be in BOTH or the pair is worse than
    // useless. A container that changed an environment value its subtree's size
    // depends on says so with `invalidatingMeasureMemo()`; the outer key then
    // misses and this wrapper is re-entered — and without the generation here
    // this probe answered the post-change ask with the pre-change size and never
    // measured the subtree at all. From the CROSS-frame table, so it stood until
    // the memoized value itself changed.
    let sizeKey = RenderCache.SizeKey(
        identityHash: context.identity.structuralHash,
        proposalWidth: proposal.width, proposalHeight: proposal.height,
        availableWidth: context.availableWidth, availableHeight: context.availableHeight,
        hasExplicitWidth: context.hasExplicitWidth, hasExplicitHeight: context.hasExplicitHeight,
        measureGeneration: context.measureGeneration)
    if let cached = cache.lookupSize(key: sizeKey, view: key) {
        if RenderCache.verifiesMeasureMemo {
            return verifyServedSize(
                cached, label: "\(Key.self)", proposal: proposal, context: context, measure: { measure(build(), $0) })
        }
        return cached
    }

    // The same gate as the buffer half: a subtree that declares a render side
    // effect (`.onRenderPass`) or reads a per-frame-volatile value must not have
    // its measurement memoised away — a served size would silently hide real
    // layout participation, breaking the `OnRenderPassModifier` contract
    // ("observation must not be memoised away"). Store-gating suffices: such a
    // subtree never stores, so it never hits either. `cacheUnsafeCount`, which
    // counts replayable registrations too: this half replays nothing.
    let existingTracker = context.environment.volatileReadTracker
    let tracker = existingTracker ?? VolatileReadTracker()
    let measureContext =
        existingTracker == nil
        ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
        : context
    let unsafeBefore = tracker.cacheUnsafeCount
    // The scopes this measure arms are kept alive by the size it stores — see
    // the buffer half.
    let leaseMark = cache.leases.beginComputation()
    let size = observingKeptResult(of: Key.self, kind: .keptMeasure, context: context) {
        measure(build(), measureContext)
    }
    let lease = cache.leases.endComputation(leaseMark)
    // The uncomparable-environment clause. A non-Equatable environment value in
    // force cannot be seen by the key, so a change to it could never invalidate a
    // stored size. This half is why the two memos are now one: the clause was
    // added to `EquatableView`'s size memo and MISSED on `_MemoizedRow`'s "when
    // the buffer half was unified", and a Form row under an injected uncomparable
    // value measured once and served that size forever.
    if tracker.cacheUnsafeCount == unsafeBefore,
        !context.environment.hasUncomparableEnvironmentValue
    {
        cache.storeSize(key: sizeKey, identity: context.identity, view: key, size: size, lease: lease)
    }
    return size
}
