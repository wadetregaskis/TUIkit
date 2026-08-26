//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Render Cache

/// Caches rendered ``FrameBuffer`` results for views that opt into subtree memoization.
///
/// `RenderCache` is Phase 5 of TUIkit's render pipeline optimization. It stores
/// the output of ``EquatableView`` instances keyed by their `ViewIdentity`,
/// allowing unchanged subtrees to skip rendering entirely.
///
/// ## How It Works
///
/// When an `EquatableView<V>` renders, it:
/// 1. Looks up a cached entry by the current `ViewIdentity`
/// 2. Compares the new view value with the stored snapshot (`Equatable.==`)
/// 3. Checks that the available size hasn't changed
/// 4. On hit: returns the cached ``FrameBuffer`` — **the entire subtree is skipped**
/// 5. On miss: renders normally and stores the result
///
/// ## Invalidation
///
/// A `@State` write does **not** clear the cache. `StateBox.value`'s `didSet`
/// calls ``invalidateRender(for:)`` with the box's own identity, which enqueues
/// it; the queue drains at the next ``beginRenderPass()`` into
/// `clearAffected(by:)`, dropping that identity, everything **below** it, and
/// everything **above** it on the ancestor spine. Siblings survive.
///
/// The whole cache is dropped only by: an `@Observable` mutation (which arrives
/// with no identity, via `setNeedsRenderWithCacheClear`), a palette / appearance
/// / locale / toggle-glyph change, or an explicit `nil` invalidation.
///
/// Two consequences worth knowing before relying on this:
///
/// - Because the **ancestors** go too, a state change deep inside a memoized
///   subtree evicts every memoized entry on the spine above it. Nesting
///   `.equatable()` buys less than it looks under churn.
/// - Only ``EquatableView`` and `_MemoizedRow` consult the cache at all —
///   `measureChild` / `renderChild` do not. A tree with neither is walked in
///   full every frame, cache or no cache.
///
/// ## Garbage Collection
///
/// Cache entries for `ViewIdentity` paths not seen during the current
/// render pass are removed in ``removeInactive()``, matching
/// `StateStorage`'s existing GC pattern.
///
/// ## Debug Logging
///
/// Set the environment variable `TUIKIT_DEBUG_RENDER=1` to enable per-frame
/// cache statistics logging to stderr. This logs hit/miss counts, cache size,
/// and individual identity lookups to help diagnose memoization effectiveness.
///
/// ## Thread Safety
///
/// The cache's tables are main-actor only, but ``invalidateRender(for:)`` is
/// **not**: a `@State` write can arrive from any thread (a `.task`, a mouse
/// handler on the input thread). That path therefore only takes a lock and
/// enqueues; every mutation of `entries` / `sizeEntries` happens on the main
/// actor when the queue drains.
public final class RenderCache: @unchecked Sendable {

    /// Aggregated cache performance statistics.
    ///
    /// Tracks hit/miss/store/clear counts. Use ``stats`` for cumulative
    /// totals, or `frameStats` (after ``logFrameStats()``) for the
    /// delta since the last ``beginRenderPass()``.
    public struct Stats: Equatable {
        /// Number of successful cache lookups (view and size matched).
        public var hits: Int = 0

        /// Number of failed cache lookups (identity missing, view changed, or size changed).
        public var misses: Int = 0

        /// Number of entries stored (including overwrites).
        public var stores: Int = 0

        /// Number of times ``clearAll()`` was called.
        public var clears: Int = 0

        /// Number of times ``clearAffected(by:)`` was called.
        public var subtreeClears: Int = 0

        /// Creates a new Stats instance with default values.
        public init(
            hits: Int = 0,
            misses: Int = 0,
            stores: Int = 0,
            clears: Int = 0,
            subtreeClears: Int = 0
        ) {
            self.hits = hits
            self.misses = misses
            self.stores = stores
            self.clears = clears
            self.subtreeClears = subtreeClears
        }

        /// The total number of lookups (hits + misses).
        public var lookups: Int { hits + misses }

        /// The cache hit rate as a value between 0 and 1, or 0 if no lookups occurred.
        public var hitRate: Double {
            lookups > 0 ? Double(hits) / Double(lookups) : 0
        }

        /// Returns the per-element difference between this snapshot and an earlier one.
        public func delta(since earlier: Self) -> Self {
            Self(
                hits: hits - earlier.hits,
                misses: misses - earlier.misses,
                stores: stores - earlier.stores,
                clears: clears - earlier.clears,
                subtreeClears: subtreeClears - earlier.subtreeClears
            )
        }
    }

    /// A cached rendering result for a single view identity.
    /// - Note: A `final class`, not a struct. Every ``lookup(identity:view:contextWidth:contextHeight:)``
    ///   pulls an entry out of the dictionary — including the **reject** paths,
    ///   which discard it immediately — and a struct copy retains every
    ///   refcounted field: the snapshot existential plus the five arrays inside
    ///   the `FrameBuffer`. One reference instead. Every property is `let`, so
    ///   sharing the instance cannot alias a mutation.
    public final class CacheEntry {
        /// The type-erased view value at the time of caching.
        ///
        /// Cast back to the concrete `Equatable` type for comparison.
        public let viewSnapshot: Any

        /// The rendered output buffer.
        public let buffer: FrameBuffer

        /// The available width when this entry was cached.
        public let contextWidth: Int

        /// The available height when this entry was cached.
        public let contextHeight: Int

        /// Creates a new cache entry.
        public init(viewSnapshot: Any, buffer: FrameBuffer, contextWidth: Int, contextHeight: Int) {
            self.viewSnapshot = viewSnapshot
            self.buffer = buffer
            self.contextWidth = contextWidth
            self.contextHeight = contextHeight
        }
    }

    /// Cached entries keyed by view identity.
    private var entries: [ViewIdentity: CacheEntry] = [:]

    /// Key for a memoized *measurement* (one identity can be measured at several
    /// proposals per frame, so — unlike the buffer cache — this is keyed by the
    /// proposal and available extent as well as the identity).
    public struct SizeKey: Hashable {
        public let identity: ViewIdentity
        public let proposalWidth: Int?
        public let proposalHeight: Int?
        public let availableWidth: Int
        public let availableHeight: Int
        public let hasExplicitWidth: Bool
        public let hasExplicitHeight: Bool

        public init(
            identity: ViewIdentity,
            proposalWidth: Int?,
            proposalHeight: Int?,
            availableWidth: Int,
            availableHeight: Int,
            hasExplicitWidth: Bool,
            hasExplicitHeight: Bool
        ) {
            self.identity = identity
            self.proposalWidth = proposalWidth
            self.proposalHeight = proposalHeight
            self.availableWidth = availableWidth
            self.availableHeight = availableHeight
            self.hasExplicitWidth = hasExplicitWidth
            self.hasExplicitHeight = hasExplicitHeight
        }
    }

    /// A memoized measurement: the view value at cache time and its size.
    private struct SizeEntry {
        let viewSnapshot: Any
        let size: ViewSize
    }

    /// Memoized `EquatableView` measurements (see ``lookupSize`` / ``storeSize``).
    private var sizeEntries: [SizeKey: SizeEntry] = [:]

    /// A `measureChild` memo key: a ``SizeKey`` plus the view's TYPE.
    ///
    /// The type is what an identity-only key was missing. Transparent wrappers
    /// descend under their parent's identity, so several distinct views share
    /// one identity within a pass; keying on identity alone returned one view's
    /// size for another (the abandoned cross-frame cache — it got Panel/Card/
    /// Dialog wrong, and the equivalence harness caught it).
    public struct MeasureKey: Hashable {
        let size: SizeKey
        let viewType: ObjectIdentifier
        /// A hash of the view value's raw bytes — the discriminator that makes
        /// this memo sound.
        ///
        /// Identity + type + proposal is *not* enough: two different view
        /// values can share an identity within one pass (a transparent wrapper
        /// descends under its parent's identity), and without this the memo
        /// serves the first one's size for the second.
        ///
        /// Raw bytes work here for a reason that does **not** hold across
        /// frames. The cross-frame byte key was abandoned because `@State`,
        /// `@Environment`, `Binding` and existential boxes each embed a
        /// freshly-allocated pointer every frame, so nothing ever matched.
        /// Within a single pass those allocations are fixed: the same view
        /// value, copied down the tree, has byte-identical storage including
        /// its pointers. Two *different* values differ in the bytes that make
        /// them different.
        ///
        /// The failure mode is asymmetric, which is what makes it safe. Struct
        /// padding and enum payload slack are undefined bytes; when they differ
        /// the lookup **misses** and the view is measured again — correct, just
        /// not saved. A false *hit* would need two different values to hash
        /// identically, i.e. a 64-bit collision among the few hundred entries a
        /// pass stores.
        let valueHash: Int

        public init(size: SizeKey, viewType: ObjectIdentifier, valueHash: Int) {
            self.size = size
            self.viewType = viewType
            self.valueHash = valueHash
        }
    }

    /// Memoized `measureChild` results — see ``lookupMeasure`` / ``storeMeasure``.
    ///
    /// PER-PASS, unlike ``sizeEntries``: cleared by every ``beginRenderPass()``,
    /// so nothing here outlives the frame that measured it. That is what makes
    /// an unkeyed-by-value memo defensible where the cross-frame one was not —
    /// within one pass the tree, the state and the environment are fixed, so a
    /// repeat measurement of the same view at the same proposal is a repeat of
    /// work already done, not a guess about a different frame.
    private var measureEntries: [MeasureKey: ViewSize] = [:]
    /// Measure-memo hit/miss counts for this frame, reported by
    /// ``logFrameStats()``.
    ///
    /// Kept because a memo that silently never engages looks exactly like a
    /// memo that engages and does not help — this one shipped inert once
    /// already (the bench harness installed no ``VolatileReadTracker``, so the
    /// gate below never opened and the whole thing was dead code that still
    /// cost a call). The hit rate is the only thing that tells the difference.
    private var measureHits = 0
    private var measureMisses = 0

    /// Cumulative measure-memo counts across every pass this cache has served.
    ///
    /// Separate from the per-frame pair above, which ``beginRenderPass()``
    /// resets. A benchmark run wants the total over its iterations, not the
    /// last frame's — and wants it without `TUIKIT_DEBUG_RENDER`, because the
    /// number is the only way to tell a memo that never engaged from one that
    /// engaged and did not pay (this memo shipped inert once already).
    public private(set) var measureMemoTotals: (hits: Int, misses: Int) = (0, 0)

    /// Identities seen during the current render pass (for garbage collection).
    private var activeIdentities: Set<ViewIdentity> = []

    /// Subtree roots whose descendants must survive this pass's collection even
    /// though nothing below them was visited. See ``retainSubtree(_:)``.
    private var retainedSubtreeRoots: [ViewIdentity] = []

    /// One `.environment(keyPath, value)` application site in the tree.
    ///
    /// Keyed by key path as well as identity because nested environment
    /// modifiers can share one identity — and by application depth as well as
    /// key path, because two modifiers injecting the SAME key path can too
    /// (`.environment(\.x, a).environment(\.x, b)` with no identity node
    /// between). On a shared slot only the first-visited modifier was ever
    /// compared, so the inner one's changes went unseen.
    public struct EnvironmentSlot: Hashable {
        public let identity: ViewIdentity
        public let keyPath: AnyKeyPath
        public let depth: Int

        public init(identity: ViewIdentity, keyPath: AnyKeyPath, depth: Int) {
            self.identity = identity
            self.keyPath = keyPath
            self.depth = depth
        }
    }

    /// What ``noteAppliedEnvironment(_:identity:keyPath:)`` found.
    public enum EnvironmentChange {
        /// Nothing was applied here before — nothing below can be stale.
        case first
        /// The same value as last pass.
        case unchanged
        /// A different value: cached buffers below are stale.
        case changed
        /// The value is not `Equatable`, so change cannot be detected at all.
        case incomparable
    }

    private struct AppliedEnvironment {
        var value: Any
        var lastSeenFrame: UInt64
        var isComparable: Bool
    }

    /// The value each environment slot applied, so a change can be detected.
    private var appliedEnvironment: [EnvironmentSlot: AppliedEnvironment] = [:]

    /// Bumped once per pass, for pruning ``appliedEnvironment``.
    private var frameCounter: UInt64 = 0

    /// Invalidations enqueued by ``invalidateRender(for:)`` — a `@State` write —
    /// since the last frame, drained on the main actor at ``beginRenderPass()``.
    private struct PendingInvalidations: Sendable {
        /// `true` once a whole-cache clear is requested; supersedes `identities`.
        var clearAll = false
        /// Subtrees whose cached buffers must be dropped (unless `clearAll`).
        var identities: Set<ViewIdentity> = []
    }

    /// Guards ``PendingInvalidations`` so an off-main `@State` write can enqueue
    /// without racing the (otherwise single-threaded) `entries`/`sizeEntries`.
    private let pendingInvalidations = Lock(initialState: PendingInvalidations())

    /// Cumulative cache performance statistics.
    public private(set) var stats = Stats()

    /// Reports `@State` written mid-walk, when `TUIKIT_DIAGNOSE_BODY_MUTATION=1`
    /// asked for it. `nil` otherwise, which is the whole of its cost.
    public var bodyMutationDiagnostic: BodyMutationDiagnostic? =
        BodyMutationDiagnostic.isEnabled ? BodyMutationDiagnostic() : nil

    /// Stats snapshot taken at the start of each render pass (for per-frame deltas).
    private var statsAtFrameStart = Stats()

    /// Whether debug logging is enabled via the `TUIKIT_DEBUG_RENDER` environment variable.
    public static let debugEnabled: Bool = {
        ProcessInfo.processInfo.environment["TUIKIT_DEBUG_RENDER"] == "1"
    }()

    /// Creates an empty render cache.
    public init() {}

    /// The number of cached entries (for testing/debugging).
    public var count: Int { entries.count }

    /// Whether the cache is empty.
    public var isEmpty: Bool { entries.isEmpty }
}

// MARK: - Internal API

extension RenderCache {
    /// Looks up a cached buffer for a view, returning it if the view and context match.
    ///
    /// The caller provides the new view value and the current context size.
    /// If a cached entry exists with an equal view and matching size, the
    /// cached buffer is returned. Otherwise returns `nil`.
    ///
    /// - Parameters:
    ///   - identity: The view's structural identity.
    ///   - view: The current view value to compare against the snapshot.
    ///   - contextWidth: The current available width.
    ///   - contextHeight: The current available height.
    /// - Returns: The cached ``FrameBuffer`` if valid, or `nil` on miss.
    public func lookup<V: Equatable>(
        identity: ViewIdentity,
        view: V,
        contextWidth: Int,
        contextHeight: Int
    ) -> FrameBuffer? {
        guard let entry = entries[identity] else {
            stats.misses += 1
            logDebug("MISS (no entry) \(identity.path)")
            return nil
        }
        guard let oldView = entry.viewSnapshot as? V else {
            stats.misses += 1
            logDebug("MISS (type mismatch) \(identity.path)")
            return nil
        }
        guard entry.contextWidth == contextWidth,
            entry.contextHeight == contextHeight
        else {
            stats.misses += 1
            logDebug("MISS (size changed) \(identity.path)")
            return nil
        }
        guard oldView == view else {
            stats.misses += 1
            logDebug("MISS (view changed) \(identity.path)")
            return nil
        }
        stats.hits += 1
        logDebug("HIT \(identity.path)")
        return entry.buffer
    }

    /// Stores a rendered buffer for a view identity.
    ///
    /// Overwrites any existing entry for the same identity.
    ///
    /// - Parameters:
    ///   - identity: The view's structural identity.
    ///   - view: The view value to snapshot for future comparisons.
    ///   - buffer: The rendered output to cache.
    ///   - contextWidth: The available width during rendering.
    ///   - contextHeight: The available height during rendering.
    public func store<V: Equatable>(
        identity: ViewIdentity,
        view: V,
        buffer: FrameBuffer,
        contextWidth: Int,
        contextHeight: Int
    ) {
        stats.stores += 1
        entries[identity] = CacheEntry(
            viewSnapshot: view,
            buffer: buffer,
            contextWidth: contextWidth,
            contextHeight: contextHeight
        )
        logDebug("STORE \(identity.path)")
    }

    /// Looks up a memoized *measurement* for an `EquatableView`.
    ///
    /// The size twin of ``lookup(identity:view:contextWidth:contextHeight:)``:
    /// returns the cached ``ViewSize`` only when the view value compares equal
    /// and the proposal/available extent match. Value comparison is what makes
    /// this safe where an identity-only key is not — a hit means identical
    /// content, hence (between invalidations, which also bound environment
    /// changes) an identical size.
    /// Whether a rendered buffer may be stored — the conditions every memo has
    /// to satisfy before a frame it produced can be served again.
    ///
    /// One predicate because there were two, five conditions each, and they
    /// differed by one: `_MemoizedRow` was missing the uncomparable-environment
    /// clause `EquatableView` had, so a `ForEach` row under a non-`Equatable`
    /// environment injection cached a buffer that nothing could invalidate.
    ///
    /// - **A measure pass** produces an INCOMPLETE buffer — interactive
    ///   controls suppress their hit-test regions while measuring — and it
    ///   CLOBBERS, since a non-`Layoutable` ancestor renders its children once
    ///   per measure and again per render at a different size.
    /// - **Regions or overlays** mean an interactive subtree, whose buffer
    ///   captures per-frame handler state.
    /// - **A volatile read** means the next frame differs even though the value
    ///   compares equal — a cached `Spinner` would freeze.
    /// - **An invalidation during the render** (a `@State` write from an
    ///   `onAppear`) already cleared this entry; storing now would resurrect
    ///   the pre-write buffer.
    /// - **An uncomparable environment value** could change under the subtree
    ///   with nothing to notice, the cache key being free of the environment
    ///   precisely because the modifier compares.
    public static func isStorable(
        buffer: FrameBuffer,
        context: RenderContext,
        readVolatile: Bool,
        invalidatedDuringRender: Bool
    ) -> Bool {
        !context.isMeasuring
            && buffer.hitTestRegions.isEmpty
            && buffer.overlays.isEmpty
            && !readVolatile
            && !invalidatedDuringRender
            && !context.environment.hasUncomparableEnvironmentValue
    }

    /// The memoized measurement for `key`, or `nil` when there is none or the
    /// view value has changed.
    ///
    /// The measure-side counterpart to ``lookup(identity:view:contextWidth:contextHeight:)``.
    /// Both the key and the value are checked: `key` covers the identity and
    /// the proposal, and `view` — compared with `==` against the snapshot
    /// taken when the size was stored — covers the content, so a row whose
    /// data changed re-measures even though it sits at the same identity under
    /// the same proposal.
    ///
    /// Unlike the buffer cache this is safe to populate from a measure pass:
    /// entries are keyed by proposal, so a measure cannot overwrite what a
    /// render stored (see ``store(identity:view:buffer:contextWidth:contextHeight:)``,
    /// which must not be called while measuring).
    ///
    /// - Parameters:
    ///   - key: Identity plus the proposal the size was measured under.
    ///   - view: The current view value, compared against the stored snapshot.
    /// - Returns: The cached size, or `nil` on a miss.
    public func lookupSize<V: Equatable>(key: SizeKey, view: V) -> ViewSize? {
        guard let entry = sizeEntries[key], let old = entry.viewSnapshot as? V, old == view else {
            stats.misses += 1
            return nil
        }
        stats.hits += 1
        return entry.size
    }

    /// Stores a memoized measurement for an `EquatableView`.
    public func storeSize<V: Equatable>(key: SizeKey, view: V, size: ViewSize) {
        stats.stores += 1
        sizeEntries[key] = SizeEntry(viewSnapshot: view, size: size)
    }

    /// Looks up this pass's memoized `measureChild` result.
    public func lookupMeasure(key: MeasureKey) -> ViewSize? {
        if let hit = measureEntries[key] {
            measureHits += 1
            measureMemoTotals.hits += 1
            return hit
        }
        measureMisses += 1
        measureMemoTotals.misses += 1
        return nil
    }

    /// Stores a `measureChild` result for the rest of this pass.
    public func storeMeasure(key: MeasureKey, size: ViewSize) {
        measureEntries[key] = size
    }

    /// Marks an identity as active during the current render pass.
    ///
    /// Identities not marked active by the end of the render pass
    /// are candidates for garbage collection.
    ///
    /// - Parameter identity: The view identity to mark as active.
    public func markActive(_ identity: ViewIdentity) {
        activeIdentities.insert(identity)
    }

    /// Declares that everything cached *below* `root` is still live, without
    /// visiting it.
    ///
    /// A cache hit at an `.equatable()` view returns its stored buffer and skips
    /// the subtree entirely, so no view inside ever reaches ``markActive(_:)``.
    /// Without this the nested entries look absent from the tree and
    /// ``removeInactive()`` collects them — so the first frame the *outer* value
    /// changes, every inner entry has to be rendered from scratch even though
    /// none of them changed. The steady state was one entry where there should
    /// have been two.
    ///
    /// The twin of `StateStorage.retainSubtree(_:)`, which already protects the
    /// `@State` inside a cached subtree for exactly the same reason; per-pass in
    /// the same way, so a subtree that stops being declared becomes collectable
    /// on the next frame.
    ///
    /// - Parameter root: The cached view's own identity.
    public func retainSubtree(_ root: ViewIdentity) {
        retainedSubtreeRoots.append(root)
    }

    /// Records the environment value applied at a slot and reports whether it
    /// differs from the previous pass.
    ///
    /// This is what keeps a *scoped* style change from serving a stale buffer.
    /// The cache key is identity + view value + size, and deliberately carries
    /// no environment: a `.foregroundStyle` applied **above** an `.equatable()`
    /// boundary leaves the view value untouched, so without this the lookup hits
    /// and returns the buffer rendered under the old style. Detecting the change
    /// where it is applied — rather than fingerprinting the environment at every
    /// lookup — costs one comparison per environment modifier per pass instead
    /// of a dictionary walk per memoized view per pass.
    ///
    /// Called from both the measure and render walks. That is deliberate, and it
    /// is *not* the measure-side-effect bug: this table is the cache's own
    /// coherency record, not view state. The measure memo has the same blind
    /// spot as the buffer cache and measurement runs first, so a change noticed
    /// only on the render walk would already have served a stale size. Whichever
    /// walk sees it first clears; the other then reports `.unchanged`, so the
    /// clear happens once.
    ///
    /// - Returns: `.incomparable` when `value` is not `Equatable` — the caller
    ///   must then decline caching, because nothing here can tell whether it
    ///   changed.
    public func noteAppliedEnvironment(
        _ value: Any,
        identity: ViewIdentity,
        keyPath: AnyKeyPath,
        depth: Int
    ) -> EnvironmentChange {
        let slot = EnvironmentSlot(identity: identity, keyPath: keyPath, depth: depth)
        guard var previous = appliedEnvironment[slot] else {
            let comparable = value is any Equatable
            appliedEnvironment[slot] = AppliedEnvironment(
                value: value, lastSeenFrame: frameCounter, isComparable: comparable)
            return comparable ? .first : .incomparable
        }

        // Already answered this pass. Two-pass layout visits the same modifier
        // many times per frame and the value cannot change between those visits,
        // so everything below — two existential casts and a comparison, on a
        // path every environment modifier in the tree runs through — is done
        // once per pass rather than once per visit. Without this the whole
        // scheme costs ~17% of a frame; with it, nothing measurable.
        if previous.lastSeenFrame == frameCounter {
            return previous.isComparable ? .unchanged : .incomparable
        }

        guard previous.isComparable, let equatable = value as? any Equatable else {
            previous.lastSeenFrame = frameCounter
            previous.isComparable = false
            appliedEnvironment[slot] = previous
            return .incomparable
        }
        if equatable.isEqual(to: previous.value) {
            previous.lastSeenFrame = frameCounter
            appliedEnvironment[slot] = previous
            return .unchanged
        }
        appliedEnvironment[slot] = AppliedEnvironment(
            value: value, lastSeenFrame: frameCounter, isComparable: true)
        return .changed
    }

    /// Whether a retained subtree protects this identity from collection.
    ///
    /// O(roots × depth) via the structural ancestor walk, paid only for entries
    /// that were *not* visited this pass — the roots are the handful of
    /// `.equatable()` views that hit, so this stays cheap.
    private func isRetained(_ identity: ViewIdentity) -> Bool {
        retainedSubtreeRoots.contains { $0.isAncestor(of: identity) }
    }

    /// Begins a new render pass by draining any deferred `@State` invalidations,
    /// clearing the active identity set, and snapshotting the current stats for
    /// per-frame delta calculation.
    public func beginRenderPass() {
        // Snapshot stats *before* the drain so the deferred clears it applies
        // count toward this frame's delta (they are the first thing this frame
        // does). Then apply invalidations enqueued — possibly off the main actor
        // — by `@State` writes since the last frame, on the main actor, before
        // this frame reads the cache.
        statsAtFrameStart = stats
        // Before the drain: the drain's own invalidations belong to the frame
        // that requested them, not to this one.
        bodyMutationDiagnostic?.beginFrame()
        drainPendingInvalidations()
        activeIdentities.removeAll(keepingCapacity: true)
        retainedSubtreeRoots.removeAll(keepingCapacity: true)
        frameCounter &+= 1
        // The measure memo is this frame's scratch space and nothing more.
        measureEntries.removeAll(keepingCapacity: true)
        measureHits = 0
        measureMisses = 0
    }

    /// Applies the invalidations enqueued by ``invalidateRender(for:)`` since the
    /// last frame. Runs on the main actor (from ``beginRenderPass()``), where
    /// mutating `entries`/`sizeEntries` is safe.
    private func drainPendingInvalidations() {
        let pending = pendingInvalidations.withLock { state -> PendingInvalidations in
            let snapshot = state
            state.clearAll = false
            state.identities.removeAll(keepingCapacity: true)
            return snapshot
        }
        if pending.clearAll {
            clearAll()
        } else {
            for identity in pending.identities {
                clearAffected(by: identity)
            }
        }
    }

    /// Removes cache entries for views no longer in the tree.
    ///
    /// Any entry whose identity was not marked active during this render pass
    /// is removed. Prevents memory leaks from permanently removed views.
    public func removeInactive() {
        func isLive(_ identity: ViewIdentity) -> Bool {
            activeIdentities.contains(identity) || isRetained(identity)
        }
        let staleKeys = entries.keys.filter { !isLive($0) }
        for key in staleKeys {
            entries.removeValue(forKey: key)
        }
        for key in sizeEntries.keys where !isLive(key.identity) {
            sizeEntries.removeValue(forKey: key)
        }
        // Environment slots are pruned by pass number, not by `activeIdentities`
        // — only memoizing views mark themselves active, and an environment
        // modifier is not one, so an identity check would drop every slot on
        // every frame and the comparison above could never fire.
        for (slot, applied) in appliedEnvironment where applied.lastSeenFrame < frameCounter {
            appliedEnvironment.removeValue(forKey: slot)
        }
    }

    /// Clears all cached entries.
    ///
    /// Called by `RenderLoop` when global environment values change
    /// (theme, appearance) that affect all views simultaneously.
    /// For state changes that only affect a subtree, prefer
    /// ``clearAffected(by:)``.
    public func clearAll() {
        stats.clears += 1
        logDebug("CLEAR ALL (\(entries.count) entries)")
        entries.removeAll(keepingCapacity: true)
        sizeEntries.removeAll(keepingCapacity: true)
    }

    /// Clears cached entries affected by a state change at the given identity.
    ///
    /// Instead of clearing the entire cache, this removes only entries whose
    /// identity is an ancestor of, a descendant of, or equal to the changed
    /// identity. Sibling subtrees retain their cached buffers.
    ///
    /// - Parameter identity: The identity of the view whose state changed.
    public func clearAffected(by identity: ViewIdentity) {
        stats.subtreeClears += 1
        func affects(_ cached: ViewIdentity) -> Bool {
            cached == identity
                || cached.isAncestor(of: identity)
                || identity.isAncestor(of: cached)
        }
        let staleKeys = entries.keys.filter(affects)
        for key in staleKeys {
            entries.removeValue(forKey: key)
        }
        for key in sizeEntries.keys where affects(key.identity) {
            sizeEntries.removeValue(forKey: key)
        }
        logDebug("CLEAR AFFECTED by \(identity.path): \(staleKeys.count) of \(entries.count + staleKeys.count) entries")
    }

    /// Removes all cached entries, resets GC state, and clears statistics.
    public func reset() {
        entries.removeAll()
        sizeEntries.removeAll()
        activeIdentities.removeAll()
        retainedSubtreeRoots.removeAll()
        appliedEnvironment.removeAll()
        stats = Stats()
        statsAtFrameStart = Stats()
    }

    /// Resets the cumulative statistics counters to zero.
    public func resetStats() {
        stats = Stats()
    }

    /// Logs a per-frame summary to stderr if debug logging is enabled.
    ///
    /// Call this at the end of each render pass (after ``removeInactive()``)
    /// to emit a one-line summary showing **this frame's** cache activity
    /// (delta since ``beginRenderPass()``) plus the current entry count.
    public func logFrameStats() {
        guard Self.debugEnabled else { return }
        let frame = stats.delta(since: statsAtFrameStart)
        let rate =
            frame.lookups > 0
            ? String(format: "%.0f%%", frame.hitRate * 100)
            : "n/a"
        logDebug(
            "FRAME — hits: \(frame.hits), misses: \(frame.misses), "
                + "stores: \(frame.stores), clears: \(frame.clears), "
                + "subtreeClears: \(frame.subtreeClears), "
                + "entries: \(entries.count), hit rate: \(rate) | "
                + "MEASURE hits: \(measureHits) misses: \(measureMisses) "
                + "entries: \(measureEntries.count)"
        )
    }
}

// MARK: - Render Invalidation Sink

extension RenderCache: RenderInvalidationSink {
    /// Records a `@State`-driven invalidation and requests a re-render.
    ///
    /// This is the seam ``StateBox`` calls on every value change. It only
    /// *enqueues* the work behind `pendingInvalidations`' lock — the actual
    /// `entries`/`sizeEntries` mutation happens later, on the main actor, in
    /// `drainPendingInvalidations()` at frame start. That indirection is what
    /// makes a `@State` written from a background `Task` race-free: the cache is
    /// otherwise single-threaded, so it must never be mutated from the writer's
    /// thread. The re-render request goes through the retained `AppState`
    /// singleton (already thread-safe).
    ///
    /// - Parameter identity: the subtree whose cached buffers are now stale, or
    ///   `nil` to drop the whole cache.
    public func invalidateRender(for identity: ViewIdentity?) {
        // Opt-in, and free when off: one optional test. See
        // `BodyMutationDiagnostic` for why a write during the walk is worth
        // naming — this is the single funnel every `@State` write reaches, so
        // it is the only place that needs to ask.
        bodyMutationDiagnostic?.note(identity)
        pendingInvalidations.withLock { state in
            if let identity {
                if !state.clearAll { state.identities.insert(identity) }
            } else {
                state.clearAll = true
                state.identities.removeAll(keepingCapacity: true)
            }
        }
        AppState.shared.setNeedsRender()
    }
}

// MARK: - Private Helpers

extension RenderCache {
    /// Writes a debug message to stderr when `TUIKIT_DEBUG_RENDER=1` is set.
    ///
    /// Uses stderr so debug output never interferes with the terminal UI
    /// rendered on stdout. Redirect with `2>render.log` to capture.
    fileprivate func logDebug(_ message: @autoclosure () -> String) {
        guard Self.debugEnabled else { return }
        FileHandle.standardError.write(
            Data("[RenderCache] \(message())\n".utf8)
        )
    }
}

// MARK: - Existential Equality

extension Equatable {
    /// Compares against a type-erased value, `false` if it is a different type.
    ///
    /// The standard opening move for comparing two `any Equatable`s: open one
    /// existential so `Self` is concrete, then downcast the other to it.
    fileprivate func isEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}
