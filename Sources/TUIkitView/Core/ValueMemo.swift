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
//  Generic functions taking the key by value, rather than a protocol with a
//  `var memoKey` requirement. A get-only property requirement returns `@out`,
//  and the production key on the row path is `AnyEquatableBox`, which stores an
//  `any Equatable` and is therefore address-only — so every probe would
//  materialise a copy and a destroy of the existential where a generic parameter
//  is `@in_guaranteed` and borrows the caller's field. Both callers are in this
//  module and built whole-module, so each gets a specialization in which the
//  closures inline and nothing is allocated.

/// The buffer half: serves `key`'s cached buffer, or renders and stores it.
///
/// - Parameters:
///   - key: The value the memo is keyed by. A hit means this compared equal;
///     whether that implies an equal rendering is the CALLER's claim, and the two
///     callers claim it on different grounds — see their own doc comments.
///   - viewType: The type named in a verifier mismatch report. An autoclosure
///     over a metatype, so neither the metadata read nor `String(describing:)` is
///     paid on the paths that never report — which is all of them, almost always.
///   - context: The render context.
///   - render: Renders the memoized content. Called ONLY on a miss, which is
///     what lets `_MemoizedRow` defer building the row view at all.
///
/// `@inline(__always)`: both callers are in this module, and the MISS path calls
/// `render` once per row per pass. Left out of line it cost **+3.3% on the
/// `menus` stress scenario** — the shape with the highest miss ratio, since an
/// interactive row can never be stored and so takes the miss path every frame.
@inline(__always)
@MainActor
func renderValueMemoized<Key: Equatable>(
    key: Key,
    viewType: @autoclosure () -> Any.Type,
    context: RenderContext,
    render: (RenderContext) -> FrameBuffer
) -> FrameBuffer {
    // No cache: standalone rendering, outside a render loop. Render straight
    // through rather than trapping — `EquatableView.renderToBuffer` used to force
    // unwrap here while its own `sizeThatFits` guarded, so the type contradicted
    // itself; the guard is the half that is right.
    guard let cache = context.renderCache else { return render(context) }
    let identity = context.identity
    cache.markActive(identity)

    if let cached = cache.lookup(
        identity: identity, view: key,
        contextWidth: context.availableWidth, contextHeight: context.availableHeight,
        gradientFrame: context.gradientFrame,
        surfaceBackground: context.environment.surfaceBackground)
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
        if RenderCache.verifiesRenderMemo {
            let fresh = render(context)
            if fresh.lines != cached.lines {
                cache.noteRenderMemoMismatch(
                    viewType: String(describing: viewType()), served: cached,
                    fresh: fresh, identity: identity.path)
            }
        }
        return cached
    }

    // Miss: render under a volatile-read tracker (reusing an ancestor's, so
    // nesting bubbles up) and store only buffers that are safe to serve again:
    //   • never a measure-pass buffer (incomplete — interactive controls suppress
    //     their hit-test regions while measuring — and it would clobber the
    //     render-pass entry at a different size every frame);
    //   • never an interactive subtree (its regions and overlays capture
    //     per-frame handler state, and a focused control pulses);
    //   • never a time-varying subtree (a pulse-phase read or an animation
    //     request means the next frame differs even though the value compares
    //     equal — a cached Spinner would freeze, issue #1).
    let existingTracker = context.environment.volatileReadTracker
    let tracker = existingTracker ?? VolatileReadTracker()
    let renderContext =
        existingTracker == nil
        ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
        : context
    let unsafeBefore = tracker.cacheUnsafeCount
    // Snapshot the invalidation generation too: a `clearAffected` DURING this
    // render — an environment or colour-environment change, a `ScrollViewReader`
    // publish; those are its synchronous callers — fires before we store, and
    // storing afterwards would resurrect the pre-clear buffer and serve it until
    // the key next changes. NOT a `@State` write: since `44660d87` those are
    // queued (`pendingInvalidations`) and drained at the next `beginRenderPass`,
    // so this counter does not move for them and the store goes ahead — which is
    // right, because the drain clears the entry before it can be served.
    let clearsBefore = cache.stats.subtreeClears

    let buffer = render(renderContext)

    if RenderCache.isStorable(
        buffer: buffer, context: context,
        readVolatile: tracker.cacheUnsafeCount > unsafeBefore,
        invalidatedDuringRender: cache.stats.subtreeClears > clearsBefore)
    {
        cache.store(
            identity: identity, view: key, buffer: buffer,
            contextWidth: context.availableWidth, contextHeight: context.availableHeight,
            gradientFrame: context.gradientFrame,
            surfaceBackground: context.environment.surfaceBackground)
    }
    return buffer
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
///   - measure: Measures the memoized content. Called only on a miss.
@inline(__always)
@MainActor
func measureValueMemoized<Key: Equatable>(
    key: Key,
    proposal: ProposedSize,
    context: RenderContext,
    measure: (RenderContext) -> ViewSize
) -> ViewSize {
    guard let cache = context.renderCache else { return measure(context) }
    // The generation is in the key for the same reason `measureChild`'s is (see
    // `measureIdentityHash`), and it has to be in BOTH or the pair is worse than
    // useless. A container that changed an environment value its subtree's size
    // depends on says so with `invalidatingMeasureMemo()`; the outer key then
    // misses and this wrapper is re-entered — and without the generation here
    // this probe answered the post-change ask with the pre-change size and never
    // measured the subtree at all. From the CROSS-frame table, so it stood until
    // the memoized value itself changed.
    let sizeKey = RenderCache.SizeKey(
        identity: context.identity,
        proposalWidth: proposal.width, proposalHeight: proposal.height,
        availableWidth: context.availableWidth, availableHeight: context.availableHeight,
        hasExplicitWidth: context.hasExplicitWidth, hasExplicitHeight: context.hasExplicitHeight,
        measureGeneration: context.measureGeneration)
    if let cached = cache.lookupSize(key: sizeKey, view: key) { return cached }

    // The same gate as the buffer half: a subtree that declares a render side
    // effect (`.onRenderPass`) or reads a per-frame-volatile value must not have
    // its measurement memoised away — a served size would silently hide real
    // layout participation, breaking the `OnRenderPassModifier` contract
    // ("observation must not be memoised away"). Store-gating suffices: such a
    // subtree never stores, so it never hits either.
    let existingTracker = context.environment.volatileReadTracker
    let tracker = existingTracker ?? VolatileReadTracker()
    let measureContext =
        existingTracker == nil
        ? context.withEnvironment(context.environment.setting(\.volatileReadTracker, to: tracker))
        : context
    let unsafeBefore = tracker.cacheUnsafeCount
    let size = measure(measureContext)
    // The uncomparable-environment clause. A non-Equatable environment value in
    // force cannot be seen by the key, so a change to it could never invalidate a
    // stored size. This half is why the two memos are now one: the clause was
    // added to `EquatableView`'s size memo and MISSED on `_MemoizedRow`'s "when
    // the buffer half was unified", and a Form row under an injected uncomparable
    // value measured once and served that size forever.
    if tracker.cacheUnsafeCount == unsafeBefore,
        !context.environment.hasUncomparableEnvironmentValue
    {
        cache.storeSize(key: sizeKey, view: key, size: size)
    }
    return size
}
