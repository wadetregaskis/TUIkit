//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitStyling

// MARK: - Render Cache

/// Caches rendered ``FrameBuffer`` results for views that opt into subtree memoization.
///
/// `RenderCache` is Phase 5 of TUIkit's render pipeline optimization. It stores
/// the output of the two wrappers that memoize a subtree by the value of
/// something — ``EquatableView`` by the whole view value, `_MemoizedRow` by a
/// `ForEach` row's data element — keyed by their `ViewIdentity`'s structural hash, allowing
/// unchanged subtrees to skip rendering entirely.
///
/// ## How It Works
///
/// When an `EquatableView<V>` renders, it:
/// 1. Looks up a cached entry by the current `ViewIdentity`'s structural hash
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
/// An `@Observable` mutation is scoped the same way, and has been since
/// commit 96c12acb (2026-09-05): every composite body is evaluated under
/// `withObservationTracking` at its own identity, so the `onChange` calls
/// ``invalidateRender(for:)`` with that identity — the same sink and the same
/// scope as a `@State` write. It used to arrive with no identity, via
/// `setNeedsRenderWithCacheClear`, and a model that changed every frame — a
/// clock, a progress counter, a download's byte count — therefore made every
/// frame a cold render of the whole tree, and nothing the memo held was ever
/// served while it did.
///
/// The whole cache is dropped only by: a palette / appearance / locale /
/// toggle-glyph change, a change to the width claim the memoized sizes were
/// measured under (checked once per ``beginRenderPass()``), an explicit `nil`
/// invalidation, or the `setNeedsRenderWithCacheClear` fallback that a render
/// with no `RenderCache` in its context still takes.
///
/// Two consequences worth knowing before relying on this:
///
/// - Because the **ancestors** go too, a state change deep inside a memoized
///   subtree evicts every memoized entry on the spine above it. Nesting
///   `.equatable()` buys less than it looks under churn.
/// - Only ``EquatableView`` and `_MemoizedRow` consult the **buffer** memo —
///   `renderChild` does not, so a tree with neither is re-rendered in full
///   every frame, cache or no cache. That exclusivity is the buffer's alone;
///   the other three tables are not so narrow. Every measured child goes
///   through the measure memo (`measureChild`, since `ec91cabe`, 2026-08-12)
///   and every provider's child list through the child-views memo
///   (`resolveChildViews`, since `90a608df`, 2026-09-05) — both per-pass
///   scratch, emptied by ``beginRenderPass()``, so what they spare is the
///   SECOND walk of a subtree inside one frame, never the first. The size memo
///   is cross-frame like the buffer's, and since `32b87838` (2026-09-05) it has
///   a caller that is not a memo wrapper at all: a hugging `List` keeps its
///   widest row there, asked by its rows' DATA rather than by a view value.
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

    /// A cached rendering result for a single view identity.
    /// - Note: A `final class`, not a struct. Every ``lookup(identity:view:contextWidth:contextHeight:gradientFrame:surfaceBackground:)``
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

        /// Where this view sat in a `.gradientExtent(.subtree)` ramp when the
        /// buffer was rendered — `nil` when no ramp spanned it, which is almost
        /// always.
        ///
        /// Part of the key because the colour is baked into the buffer's escape
        /// codes. A row keyed only on its value and size served the ink it had
        /// at its OLD position after something above it changed height:
        /// inserting a row at the top of a four-row ramp left the rows below it
        /// wearing the three-row ramp's colours.
        public let gradientFrame: GradientFrame?

        /// The surface the subtree was painted OVER.
        ///
        /// Translucent ink is composited against `enclosingSurface` at render
        /// time, so a buffer holds a blend that is only right over the surface
        /// it was made on. Here for the same reason ``gradientFrame`` is: a
        /// cached child that MOVED within a ramp had to re-render, and a cached
        /// child that is now over a different colour has to as well.
        ///
        /// The raw `surfaceBackground` rather than the resolved
        /// `enclosingSurface`: resolving consults the palette on every lookup,
        /// and a palette change already invalidates through its own modifier.
        /// The value that gets past that is a container assigning
        /// `environment.surfaceBackground` directly (`TabView` does), which
        /// bypasses `noteAppliedEnvironment` and so leaves nothing else to
        /// notice it.
        public let surfaceBackground: Color?

        /// Creates a new cache entry.
        /// Where this view sat.
        ///
        /// Read by ``removeInactive()`` and ``clearAffected(by:keepingSizes:includingDescendants:)``
        /// and by nothing else — which is the whole reason it is kept: the table's
        /// key is now only the identity's structural hash, and
        /// `RetainedSubtreeIndex.retains` climbs a chain, so there is nowhere else
        /// for those two to get one. Overwritten by each store, so it is the most
        /// recent structurally-equal chain rather than the first the bucket ever
        /// saw; both prunes compare identities structurally, so that is the same
        /// answer to the same question. The arrangement `SizeEntry` has had
        /// since `7db94fe9`.
        public let identity: ViewIdentity

        /// The replayable registrations the subtree made while it rendered,
        /// into its own key channels, which a hit makes again in order — see
        /// `EffectJournal`. Empty for almost every entry.
        package let effects: [EffectJournal.Entry]

        /// Where `effects` were recorded — `.none` when there are none. A
        /// lookup from anywhere else misses.
        package let effectScope: EffectScope

        public convenience init(
            identity: ViewIdentity,
            viewSnapshot: Any, buffer: FrameBuffer, contextWidth: Int, contextHeight: Int,
            gradientFrame: GradientFrame? = nil,
            surfaceBackground: Color? = nil
        ) {
            self.init(
                identity: identity, viewSnapshot: viewSnapshot, buffer: buffer,
                contextWidth: contextWidth, contextHeight: contextHeight,
                gradientFrame: gradientFrame, surfaceBackground: surfaceBackground,
                effects: [], effectScope: .none)
        }

        /// Creates an entry that carries recorded registrations.
        package init(
            identity: ViewIdentity,
            viewSnapshot: Any, buffer: FrameBuffer, contextWidth: Int, contextHeight: Int,
            gradientFrame: GradientFrame?, surfaceBackground: Color?,
            effects: [EffectJournal.Entry], effectScope: EffectScope
        ) {
            self.identity = identity
            self.viewSnapshot = viewSnapshot
            self.buffer = buffer
            self.contextWidth = contextWidth
            self.contextHeight = contextHeight
            self.gradientFrame = gradientFrame
            self.surfaceBackground = surfaceBackground
            self.effects = effects
            self.effectScope = effectScope
        }
    }

    /// Where a subtree's registrations were recorded, which is where a hit
    /// replaying them has to be too — or the served buffer and the replayed
    /// registrations describe a render that did not happen there.
    ///
    /// Neither half is in the memo's key, because both are written straight
    /// into the environment and nothing notices them change. So they are
    /// compared here, for an entry that has registrations, and only there: a
    /// subtree that registers nothing draws no control and no focus.
    package struct EffectScope: Equatable {
        /// The focus section the registrations were filed in.
        package var section: String?

        /// Whether the subtree was drawn as a backdrop
        /// (`EnvironmentValues.drawsBackdrop`). Its controls registered with a
        /// manager that focuses nothing, so the buffer shows none of them
        /// focused. Served to the live page after a sheet with no focusables of
        /// its own was dismissed, it would show the control the focus returned
        /// to as unfocused: no focused id moved, so nothing would invalidate
        /// it. That used to be prevented by never storing a backdrop render at
        /// all, and so everything behind a modal, or under a navigation stack's
        /// pushed screen, was drawn afresh on every frame it was up.
        package var isBackdrop: Bool

        /// No registrations, or a lookup made without a scope.
        package static let none = Self(section: nil, isBackdrop: false)

        package init(section: String?, isBackdrop: Bool) {
            self.section = section
            self.isBackdrop = isBackdrop
        }
    }

    /// Cached entries keyed by the view identity's STRUCTURAL HASH.
    ///
    /// The hash, not the identity — the bargain ``MeasureKey`` documents and
    /// `SizeKey`/`ChildViewsKey` took in `7db94fe9`, made here last because here
    /// it is both the most valuable and the most consequential. A `ViewIdentity`
    /// is a chain of class nodes: every probe copies it (retain/release) and every
    /// HIT compares two *equal* chains step for step, because
    /// `IdentityNode.structurallyEqual`'s `===` shortcut cannot fire — the walk
    /// that stored the entry built its chain on an earlier frame and the walk
    /// probing it built a fresh one. For a `ForEach` row the step is `.keyed`, so
    /// that per-level compare includes a `String ==`.
    ///
    /// The collision argument is `SizeKey`'s in shape, and NOT inherited from
    /// `MeasureKey`'s "nothing here outlives the pass" — this table is
    /// cross-frame. A false hit needs two distinct identity chains to collide on a
    /// full 64-bit `Hasher.finalize()` AND the stored snapshot to accept the
    /// probing type AND both context extents, the surface and the gradient frame
    /// to match AND two *different* view values to compare equal.
    ///
    /// What differs from `SizeKey`, and it is worth saying plainly: a collision
    /// here serves the OTHER subtree's cells — wrong pixels — where `SizeKey`'s
    /// serves a wrong number. `TUIKIT_VERIFY_RENDER_MEMO` re-renders every serve
    /// and compares the cells, which is the standing check on exactly that; it
    /// cannot see a 64-bit collision, but it is the net for a fumbled guard.
    ///
    /// A confirmation on the hit path is deliberately NOT added: comparing
    /// `entry.identity == identity` re-introduces the walk this removes, and
    /// comparing only `depth` adds no bits, because `structurallyEqual` already
    /// fast-rejects on depth. Take the bargain or don't.
    private var entries: [Int: CacheEntry] = [:]

    /// A memoized measurement: the view value at cache time, its size, and the
    /// identity ``SizeKey`` stopped carrying.
    ///
    /// - Note: A `final class`, not a struct, for the reason ``CacheEntry`` is one
    ///   and now with the same two refcounted fields: ``lookupSize(key:view:)``
    ///   pulls an entry out of the dictionary on the REJECT path as well as the
    ///   hit, and both prunes copy one per entry they walk, so a struct copy
    ///   would retain the snapshot existential AND the identity chain every
    ///   time. One reference instead. Every property is `let`, so sharing the
    ///   instance cannot alias a mutation.
    private final class SizeEntry {
        let viewSnapshot: Any
        let size: ViewSize
        /// Where the measured view sat — read by ``removeInactive()`` and
        /// ``clearAffected(by:keepingSizes:includingDescendants:)``, which is the only reason it is
        /// kept. Overwritten by each store, so it is the most recent
        /// structurally-equal chain rather than the first one the key ever saw;
        /// both prunes compare identities structurally, so that is the same
        /// answer to the same question.
        let identity: ViewIdentity
        init(viewSnapshot: Any, size: ViewSize, identity: ViewIdentity) {
            self.viewSnapshot = viewSnapshot
            self.size = size
            self.identity = identity
        }
    }

    /// Memoized value-keyed measurements (see ``lookupSize`` / ``storeSize``).
    private var sizeEntries: [SizeKey: SizeEntry] = [:]

    /// How many times this cache has been dropped WHOLE.
    ///
    /// A counter rather than a notification because the thing that needs it is
    /// not in the cache: `_VStackCore`'s content-width record lives in `@State`
    /// precisely so that a `@State` write cannot sweep it (see
    /// `StackContentWidth.swift`), which also means the cache's own
    /// invalidation never reaches it. The two events that clear everything —
    /// a moved `EnvironmentSnapshot` and a moved width or colour generation —
    /// are exactly the ones such a record cannot detect for itself, so it
    /// carries this number and compares it.
    public private(set) var clearGeneration = 0

    /// How many subtree clears have dropped memoized SIZES — every
    /// ``clearAffected(by:keepingSizes:includingDescendants:)`` that does not keep them. That is the
    /// `@State` and `@Observable` writes drained at frame start, and also the
    /// focus moves and scoped environment changes applied mid-pass, so it can
    /// move between two measures of one frame. A clear that keeps sizes (a
    /// paint, a tint) does not count: it promises that no cell moved.
    ///
    /// Beside ``clearGeneration`` for the same reason: something that keeps a
    /// size OUTSIDE this cache, and needs to hear when one in it would have
    /// been dropped, carries this number and compares it.
    public private(set) var sizeClearGeneration = 0

    /// Forgets every size memoized AT `identity` — in the cross-frame table,
    /// and in this pass's under `measureGeneration` — and nothing else: no
    /// buffer, no ancestor, no descendant, no generation moves. What is next
    /// asked there is measured rather than served; a memo deeper inside the
    /// view, keyed on something the change did not touch, is not reached.
    ///
    /// For a caller that has been told an answer may have moved and has to find
    /// out. A value memo compares only the value it was keyed on, and a view
    /// that reads anything else — a `ForEach` row reading data its element does
    /// not carry, or an `@Observable` read while it was measured but not drawn,
    /// which nothing tracks — goes on being served its old answer until
    /// something clears it. Forgetting it first is the only way to ask it
    /// again: a bumped ``RenderContext/measureGeneration`` is not one, because
    /// what is measured under the bump is stored under the bump, and the next
    /// bump of the same generation is served it. Nor is a lookup that misses on
    /// request, which puts a branch in every lookup in every app for the sake
    /// of this one — an earlier form of this did, and measured +0.5% to +0.8%
    /// on the memo-heavy scenarios.
    ///
    /// Matched by hash, which is all the keys hold: the identity's own for the
    /// cross-frame table, and for this pass's the one `measureChild` folds the
    /// generation into. A collision forgets an
    /// unrelated entry, which costs a measure and nothing else. A scan of both
    /// size tables, so for a single identity on an uncommon event.
    package func forgetSizes(of identity: ViewIdentity, measureGeneration: UInt8) {
        let hash = identity.structuralHash
        var staleSizes: [SizeKey] = []
        for key in sizeEntries.keys where key.identityHash == hash { staleSizes.append(key) }
        for key in staleSizes { sizeEntries.removeValue(forKey: key) }
        let folded = measureIdentityHash(identity, generation: measureGeneration)
        var staleMeasures: [MeasureKey] = []
        for key in measureEntries.keys where key.identityHash == folded { staleMeasures.append(key) }
        for key in staleMeasures { measureEntries.removeValue(forKey: key) }
    }

    /// One measurement under one vertical budget: what ``MeasureKey`` leaves out.
    ///
    /// A key holds at most one of these. The pattern the memo exists for is a
    /// pair of walks over the same subtree — the enclosing stack's natural-size
    /// ask at (`proposal.width` nil, `availableHeight` the viewport) and the
    /// ScrollView's content-extent walk at (the width proposed, `availableHeight`
    /// the measuring canvas) — and one slot serves it: the first walk stores, the
    /// second reads. A key queried under a third budget replaces the slot rather
    /// than growing a list, except that a natural answer is never displaced by a
    /// budget-shaped one (it is the entry that can still serve a later query).
    struct MeasureEntry {
        /// Whether the width arrived as `proposal.width` rather than inherited
        /// from `context.availableWidth`. Only distinguishable when the two are
        /// equal — which is exactly the pair of walks above.
        let proposalWidthWasSpecified: Bool
        let proposalHeight: Int?
        let availableHeight: Int
        let size: ViewSize
    }

    /// Memoized `measureChild` results — see ``lookupMeasure`` / ``storeMeasure``.
    ///
    /// PER-PASS, unlike ``sizeEntries``: cleared by every ``beginRenderPass()``,
    /// so nothing here outlives the frame that measured it. That is what makes
    /// an unkeyed-by-value memo defensible where the cross-frame one was not —
    /// within one pass the tree, the state and the environment are fixed, so a
    /// repeat measurement of the same view at the same proposal is a repeat of
    /// work already done, not a guess about a different frame.
    private var measureEntries: [MeasureKey: MeasureEntry] = [:]

    /// The memory policy for the two per-pass scratch dictionaries above — one
    /// each, because they are sized by different things. See ``ScratchTrimmer``.
    private var measureScratch = ScratchTrimmer()
    private var childViewScratch = ScratchTrimmer()

    /// What ``verifiesMeasureMemo`` found: one line per served size that a fresh
    /// measurement disagreed with. Capped, because a broken memo produces them by
    /// the thousand and the first few say everything.
    public private(set) var measureMemoMismatches: [String] = []

    /// What ``verifiesRenderMemo`` found: one line per served buffer a fresh
    /// render disagreed with. Capped, for the reason the measure twin is.
    public private(set) var renderMemoMismatches: [String] = []

    /// This pass's resolved children, per stack — scratch, like
    /// ``measureEntries``; emptied by ``beginRenderPass()``.
    private var childViewEntries: [ChildViewsKey: [ChildView]] = [:]
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

    /// This pass's ``VolatileReadTracker``, mirrored here from the environment by
    /// ``EnvironmentValues/installVolatileReadTracker(_:)``.
    ///
    /// NOT the owner, and NOT one this cache mints. The environment's tracker is
    /// the single per-frame instance every `recordVolatileRead()` /
    /// `recordRenderSideEffect()` site writes to, and this has to be that same
    /// object: the measure memo's store gate reads a delta off it, so a
    /// different instance would read counters nothing moves and store every
    /// unsafe measurement as safe. Minting one in ``beginRenderPass()`` would do
    /// exactly that on every path that installs no tracker (`ViewRenderer`'s
    /// snapshot render, most test fixtures) — which is the measurement the gate
    /// exists to refuse.
    ///
    /// It exists because `measureChild` consulted the memo through
    /// `context.environment.volatileReadTracker`: an `ObjectIdentifier` hash, an
    /// `[ObjectIdentifier: Any]` probe, a `swift_dynamicCast` and a retain, paid
    /// ~14,400 times on a `fanout` frame (`Performance-profile-2026-08.md`
    /// §3's measures/frame table). `RenderContext` already mirrors this cache as
    /// a stored field for the same reason, so from there this is one more load.
    ///
    /// Strong, not weak like ``StateStorage/renderCache``: a weak read is a
    /// side-table check, and this is read once per measured node. The object is
    /// two counters, and the render loop replaces it every frame.
    ///
    /// Deliberately NOT cleared by ``beginRenderPass()``. `RenderLoop` installs
    /// a fresh tracker every frame, but `Stress`'s bench and the profiling
    /// harness install one per context and then open a pass per frame — clearing
    /// would switch the memo off there from frame two onwards, which is how this
    /// memo shipped inert once already (§27).
    public internal(set) var volatileReadTracker: VolatileReadTracker?

    /// The width-traits generation this cache's contents were measured under.
    ///
    /// The claim is part of what a measurement means, so memos taken under one
    /// host's traits are wrong under another's. See
    /// ``TerminalWidthTraits/generation`` and ``beginRenderPass()``.
    private var measuredUnderWidthGeneration = TerminalWidthTraits.generation

    /// The terminal-colours generation this cache's contents were rendered under.
    ///
    /// A buffer spells some colours from what the terminal reported: a colour
    /// that is the terminal's own, drawn in the other slot, is its reported RGB,
    /// and a blend with one mixes that RGB. So buffers rendered under one report
    /// are wrong under the next. Checked in ``beginRenderPass()``.
    ///
    /// Internal, not private, so a test can age it. Moving the process-wide
    /// generation instead would clear every cache in the test process.
    var renderedUnderTerminalColorsGeneration = TerminalColors.generation

    /// Identities seen during the current render pass (for garbage collection).
    private var activeIdentities: Set<ViewIdentity> = []

    /// What the last ``removeInactive()`` walked and dropped — the
    /// `TUIKIT_DEBUG_RENDER` frame line prints it, since the retained-subtree
    /// walk is per entry NOT marked active and its cost is the count of those.
    private var lastPrune = (renderEntries: 0, sizeEntries: 0, retainedChecks: 0, prunedRender: 0, prunedSizes: 0)

    /// What the last ``removeInactive()`` walked and dropped, for a harness
    /// that reports it beside its timings (`Stress --bench` does).
    public var lastPruneSummary: String {
        "render: \(lastPrune.renderEntries) sizes: \(lastPrune.sizeEntries) "
            + "retainedChecks: \(lastPrune.retainedChecks) "
            + "dropped: \(lastPrune.prunedRender)+\(lastPrune.prunedSizes)"
    }

    /// Subtree roots whose descendants must survive this pass's collection even
    /// though nothing below them was visited. See ``retainSubtree(_:)``.
    private var retainedSubtreeRoots: [ViewIdentity] = []

    /// The value each environment slot applied, so a change can be detected.
    /// Internal, not private, only so `RenderCache+EnvironmentSlots.swift` can
    /// reach it: nothing but ``noteAppliedEnvironment(_:identity:keyPath:depth:)``
    /// and the prune may touch it.
    var appliedEnvironment: [EnvironmentSlot: AppliedEnvironment] = [:]

    /// The content type each `AnyView` drew last, keyed by its identity's hash
    /// folded with its depth — see ``noteErasedContent(_:identity:depth:)``.
    /// Internal for the same reason as ``appliedEnvironment``.
    var erasedContent: [Int: ErasedContent] = [:]

    /// Bumped once per pass, for pruning ``appliedEnvironment``.
    private(set) var frameCounter: UInt64 = 0

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

    /// Cumulative row-shaped work, for the controls that draw rows.
    ///
    /// Lives beside ``stats`` and is deliberately NOT part of it: these count
    /// what the RENDER did, not what the cache did. They are here because this
    /// is the object a row memo would live on and the one a harness already
    /// holds per context — a control reads it from the environment exactly as
    /// it reads the cache.
    public var rowWork = RowWork()

    /// Reports `@State` written mid-walk, when `TUIKIT_DIAGNOSE_BODY_MUTATION=1`
    /// asked for it. `nil` otherwise, which is the whole of its cost.
    public var bodyMutationDiagnostic: BodyMutationDiagnostic? =
        BodyMutationDiagnostic.isEnabled ? BodyMutationDiagnostic() : nil

    /// Stats snapshot taken at the start of each render pass (for per-frame deltas).
    private var statsAtFrameStart = Stats()

    /// The registrations the value memos record while they render, so a cache
    /// hit can make them again — see `EffectJournal`.
    package let effectJournal = EffectJournal()

    /// Ids interned per view identity that have to live exactly as long as the
    /// entries here do — in practice the mouse dispatcher's handler ids, which
    /// a stored buffer carries baked into its hit-test regions. Pruned in
    /// ``removeInactive()`` by this cache's own retention rule; see
    /// ``InternedIDTable``.
    ///
    /// Weak, and wired by the `TUIContext` that owns both sides, so a cache
    /// outliving nothing keeps nothing alive.
    package weak var internedIDTable: (any InternedIDTable)?

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
    ///   - gradientFrame: Where this view sits in a spanning gradient now.
    ///     `nil` — the default, and the overwhelmingly common case — means no
    ///     `.gradientExtent(.subtree)` is in force.
    ///   - surfaceBackground: The surface this view's translucent ink would be
    ///     composited against now. A cached buffer holds ink already blended,
    ///     so an entry made over a different surface has to miss.
    /// - Returns: The cached ``FrameBuffer`` if valid, or `nil` on miss.
    ///
    /// An entry that stored registrations is looked up as if no focus section
    /// were in force; the value memo asks `lookupEntry`, which is told the
    /// section.
    public func lookup<V: Equatable>(
        identity: ViewIdentity,
        view: V,
        contextWidth: Int,
        contextHeight: Int,
        gradientFrame: GradientFrame? = nil,
        surfaceBackground: Color? = nil
    ) -> FrameBuffer? {
        lookupEntry(
            identity: identity, view: view, contextWidth: contextWidth, contextHeight: contextHeight,
            gradientFrame: gradientFrame, surfaceBackground: surfaceBackground, effectScope: .none
        )?.buffer
    }

    /// The whole entry for a view, under the same rules as
    /// ``lookup(identity:view:contextWidth:contextHeight:gradientFrame:surfaceBackground:)``,
    /// plus one: an entry that stored registrations misses when `effectScope`
    /// is not where they were recorded — another focus section, or a backdrop
    /// where they were live, or the reverse (see ``EffectScope``).
    ///
    /// The scope is not in the key because it is assigned straight into the
    /// environment (`.focusSection` and six other sites, `isolatedForBackground`),
    /// so nothing notices it change. An autoclosure, read only for an entry that
    /// has registrations.
    ///
    /// One caller, the value memo.
    package func lookupEntry<V: Equatable>(
        identity: ViewIdentity,
        view: V,
        contextWidth: Int,
        contextHeight: Int,
        gradientFrame: GradientFrame?,
        surfaceBackground: Color?,
        effectScope: @autoclosure () -> EffectScope
    ) -> CacheEntry? {
        // Read at most once, and only for an entry that has registrations.
        var scopeRead: EffectScope?
        func scope() -> EffectScope {
            if let scopeRead { return scopeRead }
            let read = effectScope()
            scopeRead = read
            return read
        }
        guard let entry = scopedEntry(for: identity, effectScope: scope) else {
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
        // Translucent ink is composited at render time, so a buffer holds a
        // blend that is only right over the surface it was painted on.
        guard entry.surfaceBackground == surfaceBackground else {
            stats.misses += 1
            logDebug("MISS (surface changed) \(identity.path)")
            return nil
        }
        // The ramp's colours are baked into the buffer, so a view that has
        // MOVED within one must re-render even though nothing about it changed.
        guard entry.gradientFrame == gradientFrame else {
            stats.misses += 1
            logDebug("MISS (gradient moved) \(identity.path)")
            return nil
        }
        guard oldView == view else {
            stats.misses += 1
            logDebug("MISS (view changed) \(identity.path)")
            return nil
        }
        // Replaying would file the registrations in the section they were
        // recorded in, not the one in force here — and a backdrop's picture
        // shows its controls unfocused, which the live page's may not.
        guard entry.effects.isEmpty || entry.effectScope == scope() else {
            stats.misses += 1
            logDebug("MISS (focus section or backdrop changed) \(identity.path)")
            return nil
        }
        stats.hits += 1
        logDebug("HIT \(identity.path)")
        return entry
    }

    /// The entry a lookup under `effectScope` should compare: the one in the
    /// identity's own slot, or — for a backdrop, when that slot holds the live
    /// page's registrations — the one a backdrop keeps beside it.
    ///
    /// A picture drawn as a backdrop and one drawn live are never served for
    /// each other (see ``EffectScope``), and with one slot per identity each
    /// replaced the other: presenting a sheet overwrote every row the page had
    /// stored, and dismissing it drew them all again. So an entry that recorded
    /// registrations while drawn as a backdrop is stored under a second key
    /// (``backdropKey(_:)``), and the live one stays where it was, served again
    /// the moment the sheet goes. Everything else — no registrations, so the
    /// same picture either way — keeps the one slot.
    ///
    /// The scope is read only when the own slot is empty or holds registrations,
    /// as the check after it always was: the common entry costs no environment
    /// read.
    private func scopedEntry(for identity: ViewIdentity, effectScope: () -> EffectScope) -> CacheEntry? {
        let own = entries[identity.structuralHash]
        if let own, own.effects.isEmpty { return own }
        guard effectScope().isBackdrop else { return own }
        return entries[Self.backdropKey(identity.structuralHash)] ?? own
    }

    /// Where an entry drawn as a backdrop with registrations is kept: beside
    /// the identity's own slot, not in it — see
    /// ``scopedEntry(for:effectScope:)``. A mix of the structural hash, under
    /// the bargain the plain key already strikes: a false hit needs this word
    /// to equal another identity's hash AND the view values to compare equal.
    private static func backdropKey(_ hash: Int) -> Int {
        hash &* 0x5851_F42D_4C95_7F2D &+ 0x1405_7B7E_F767_814F
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
    ///   - gradientFrame: Where the view sat in a spanning gradient while it
    ///     rendered, so a later lookup from a different place misses.
    ///   - surfaceBackground: The surface the view was painted OVER while it
    ///     rendered, for the same reason: its translucent ink is already
    ///     blended against this colour, so a later lookup over another one
    ///     misses (commit 54977d08, 2026-09-06).
    public func store<V: Equatable>(
        identity: ViewIdentity,
        view: V,
        buffer: FrameBuffer,
        contextWidth: Int,
        contextHeight: Int,
        gradientFrame: GradientFrame? = nil,
        surfaceBackground: Color? = nil
    ) {
        store(
            identity: identity, view: view, buffer: buffer,
            contextWidth: contextWidth, contextHeight: contextHeight,
            gradientFrame: gradientFrame, surfaceBackground: surfaceBackground,
            recorded: (effects: [], scope: .none))
    }

    /// Stores a rendered buffer with the registrations to make again on a hit.
    ///
    /// - Parameter recorded: The replayable registrations the render made into
    ///   its own key channels, in order, and where they were made (`.none`
    ///   when there are none). One parameter, as the pair is only ever
    ///   meaningful together.
    package func store<V: Equatable>(
        identity: ViewIdentity,
        view: V,
        buffer: FrameBuffer,
        contextWidth: Int,
        contextHeight: Int,
        gradientFrame: GradientFrame?,
        surfaceBackground: Color?,
        recorded: (effects: [EffectJournal.Entry], scope: EffectScope)
    ) {
        stats.stores += 1
        let key =
            !recorded.effects.isEmpty && recorded.scope.isBackdrop
            ? Self.backdropKey(identity.structuralHash) : identity.structuralHash
        entries[key] = CacheEntry(
            identity: identity,
            viewSnapshot: view,
            buffer: buffer,
            contextWidth: contextWidth,
            contextHeight: contextHeight,
            gradientFrame: gradientFrame,
            surfaceBackground: surfaceBackground,
            effects: recorded.effects,
            effectScope: recorded.scope
        )
        logDebug("STORE \(identity.path)")
    }

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
    /// - **An overlay** is a layer this buffer has not composited yet: what it
    ///   draws, and where, is settled by the frame rather than by this subtree.
    ///   Hit-test **regions** were refused here too, for a reason that no
    ///   longer holds — a region names its handler by an id, that id is the
    ///   control's own (`MouseHandlerIDTable`), and the closure behind it is
    ///   registered again on every hit from the effect journal.
    /// - **A volatile read** means the next frame differs even though the value
    ///   compares equal — a cached `Spinner` would freeze.
    /// - **An invalidation during the render** — an environment change or a
    ///   `ScrollViewReader` publish calling `clearAffected` synchronously; NOT
    ///   a `@State` write, which is queued and drained at the next pass —
    ///   already cleared this entry; storing now would resurrect the
    ///   pre-clear buffer.
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
            && buffer.overlays.isEmpty
            && !readVolatile
            && !invalidatedDuringRender
            && !context.environment.hasUncomparableEnvironmentValue
    }

    /// The memoized measurement for `key`, or `nil` when there is none or the
    /// view value has changed.
    ///
    /// One caller: `measureValueMemoized`, which both ``EquatableView`` and
    /// `_MemoizedRow` reach — they were the same code written twice.
    ///
    /// The measure-side counterpart to ``lookup(identity:view:contextWidth:contextHeight:gradientFrame:surfaceBackground:)``.
    /// Both the key and the value are checked: `key` covers the identity and
    /// the proposal, and `view` — compared with `==` against the snapshot
    /// taken when the size was stored — covers the content, so a row whose
    /// data changed re-measures even though it sits at the same identity under
    /// the same proposal.
    ///
    /// Unlike the buffer cache this is safe to populate from a measure pass:
    /// entries are keyed by proposal, so a measure cannot overwrite what a
    /// render stored (see ``store(identity:view:buffer:contextWidth:contextHeight:gradientFrame:surfaceBackground:)``,
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

    /// Stores a memoized measurement — see ``lookupSize(key:view:)`` for who asks.
    public func storeSize<V: Equatable>(key: SizeKey, identity: ViewIdentity, view: V, size: ViewSize) {
        stats.stores += 1
        sizeEntries[key] = SizeEntry(viewSnapshot: view, size: size, identity: identity)
    }

    /// Whether every memo hit is checked against a fresh measurement.
    ///
    /// Off by default and never on in an app: it measures the subtree the memo
    /// just saved, so it costs more than the memo saves. It exists because the
    /// memo's claim — that a size taken under one vertical budget answers a
    /// query made under another — is a claim about every `sizeThatFits` beneath
    /// it, and the only direct check of it is to make both measurements and
    /// compare. Set by `TUIKIT_VERIFY_MEASURE_MEMO`, or assigned directly by a
    /// test; ``measureMemoMismatches`` collects what it finds.
    ///
    /// A pixel-level guard alone is not enough, which is the reason this exists
    /// as well as `MeasureMemoEquivalenceTests`: an unsound serve only changes
    /// the picture when the wrong size reaches a place that draws differently
    /// for it, so a corpus can miss a real one. This catches the serve itself.
    @MainActor public static var verifiesMeasureMemo =
        ProcessInfo.processInfo.environment["TUIKIT_VERIFY_MEASURE_MEMO"] != nil

    /// What ``verifiesMeasureMemo`` found: one line per served size that a fresh
    /// measurement disagreed with. Capped, because a broken memo produces them
    /// by the thousand and the first few say everything.

    /// Where ``verifiesMeasureMemo`` writes what it finds, when the environment
    /// variable names a path rather than just switching the mode on.
    ///
    /// An app draws a screen; it has nowhere to print a diagnostic that would
    /// not corrupt the very frame under test. So a live run — the Example app
    /// walked through a PTY, which is the only place a real app's tree is
    /// measured — says where to put the report instead.
    @MainActor static let measureMemoMismatchLog: String? = {
        guard let value = ProcessInfo.processInfo.environment["TUIKIT_VERIFY_MEASURE_MEMO"],
            value.contains("/")
        else { return nil }
        return value
    }()

    /// Whether every BUFFER memo hit is checked against a fresh render.
    ///
    /// The twin of ``verifiesMeasureMemo``, and it exists because a served
    /// buffer can be wrong in a way nothing else notices. The memo's claim is
    /// that a subtree whose view value compares equal, at the same size, draws
    /// the same cells — and that claim quietly depends on everything ELSE the
    /// subtree read while drawing. An environment value applied through a
    /// modifier is compared (``noteAppliedEnvironment(_:identity:keyPath:depth:)``), but one **assigned
    /// directly** — `context.environment.foo = x`, which several containers do
    /// — is not, and the entry it invalidates is nobody's.
    ///
    /// That is not hypothetical: it is how a buffer painted over one
    /// `surfaceBackground` came to be served over another, blend and all, until
    /// the surface joined the key. The direct check is to render the subtree the
    /// memo just saved and compare the cells, which costs more than the memo
    /// saves and so is never on in an app.
    ///
    /// Set by `TUIKIT_VERIFY_RENDER_MEMO`, or assigned directly by a test.
    /// ``renderMemoMismatches`` collects what it finds.
    @MainActor public static var verifiesRenderMemo =
        ProcessInfo.processInfo.environment["TUIKIT_VERIFY_RENDER_MEMO"] != nil

    /// Where ``verifiesRenderMemo`` writes what it finds, when the environment
    /// variable names a path rather than just switching the mode on — an app has
    /// nowhere to print a diagnostic that would not corrupt the frame under test.
    @MainActor static let renderMemoMismatchLog: String? = {
        guard let value = ProcessInfo.processInfo.environment["TUIKIT_VERIFY_RENDER_MEMO"],
            value.contains("/")
        else { return nil }
        return value
    }()

    /// Records a served buffer that a fresh render did not reproduce.
    ///
    /// - Parameters:
    ///   - viewType: The memoized view's type, for the report.
    ///   - served: What the memo handed back.
    ///   - fresh: What rendering it again produced.
    ///   - identity: Where in the tree it sat.
    @MainActor public func noteRenderMemoMismatch(
        viewType: String, served: FrameBuffer, fresh: FrameBuffer, identity: String = ""
    ) {
        guard renderMemoMismatches.count < 20 else { return }
        let shared = min(served.lines.count, fresh.lines.count)
        let differing = (0..<shared).first { served.lines[$0] != fresh.lines[$0] }
        let firstDiff =
            differing.map {
                "line \($0): served \(served.lines[$0].debugDescription) "
                    + "but a fresh render says \(fresh.lines[$0].debugDescription)"
            }
            ?? "served \(served.lines.count) lines, a fresh render gives \(fresh.lines.count)"
        recordRenderMemoMismatch("\(viewType): \(firstDiff)" + (identity.isEmpty ? "" : " at \(identity)"))
    }

    /// Records a served entry whose replayed registrations a fresh render did
    /// not make: a different kind, order or count.
    ///
    /// Compared by kind because the recorded closures are opaque. What it
    /// catches is a key that compares equal over a subtree that registers
    /// differently, which a served buffer would silently get wrong.
    @MainActor package func noteRenderMemoEffectMismatch(
        viewType: String, served: [EffectJournal.Kind], fresh: [EffectJournal.Kind], identity: String = ""
    ) {
        guard renderMemoMismatches.count < 20 else { return }
        let names = { (kinds: [EffectJournal.Kind]) in kinds.map(\.name).joined(separator: ", ") }
        recordRenderMemoMismatch(
            "\(viewType): served registrations [\(names(served))] but a fresh render makes [\(names(fresh))]"
                + (identity.isEmpty ? "" : " at \(identity)"))
    }

    /// Appends one finding to ``renderMemoMismatches``, and to the log file
    /// when the environment variable names one.
    @MainActor private func recordRenderMemoMismatch(_ line: String) {
        renderMemoMismatches.append(line)
        if let path = Self.renderMemoMismatchLog, let data = (line + "\n").data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// Records a served size a fresh measurement did not agree with.
    @MainActor public func noteMeasureMemoMismatch(
        viewType: String, served: ViewSize, fresh: ViewSize, proposal: ProposedSize,
        availableWidth: Int, availableHeight: Int, identity: String = ""
    ) {
        guard measureMemoMismatches.count < 20 else { return }
        measureMemoMismatches.append(
            "\(viewType): served \(served.width)x\(served.height)"
                + "\(served.isNaturalSize ? " (natural)" : "")"
                + " but a fresh measure at proposal "
                + "(\(proposal.width.map(String.init) ?? "nil"), \(proposal.height.map(String.init) ?? "nil"))"
                + " in \(availableWidth)x\(availableHeight) says \(fresh.width)x\(fresh.height)"
                + (identity.isEmpty ? "" : " at \(identity)"))
        if let path = Self.measureMemoMismatchLog, let last = measureMemoMismatches.last,
            let data = (last + "\n").data(using: .utf8)
        {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// Looks up this pass's memoized `measureChild` result.
    ///
    /// Two ways to hit. The same question asked twice — same width form, same
    /// vertical budget — is the memo's original job. The second is the point of
    /// ``ViewSize/isNaturalSize``: a stored answer that no budget shaped may
    /// answer a query under a *different* budget, provided that budget is at
    /// least as tall as the answer, since a clamp that did not bite at the
    /// stored height cannot bite at a budget above it either.
    ///
    /// - Parameters:
    ///   - key: What is being measured, and at what width.
    ///   - proposalWidthWasSpecified: Whether this query proposed the width.
    ///   - proposalHeight: This query's proposed height, if any.
    ///   - availableHeight: This query's available height.
    ///   - verticalBudget: `min(proposalHeight ?? .max, availableHeight)` — the
    ///     tallest answer this query could accept unclamped.
    public func lookupMeasure(
        key: MeasureKey,
        proposalWidthWasSpecified: Bool,
        proposalHeight: Int?,
        availableHeight: Int,
        verticalBudget: Int
    ) -> ViewSize? {
        if let entry = measureEntries[key],
            (entry.size.isNaturalSize && entry.size.height <= verticalBudget)
                || (entry.proposalWidthWasSpecified == proposalWidthWasSpecified
                    && entry.proposalHeight == proposalHeight
                    && entry.availableHeight == availableHeight)
        {
            measureHits += 1
            measureMemoTotals.hits += 1
            return entry.size
        }
        measureMisses += 1
        measureMemoTotals.misses += 1
        return nil
    }

    /// Stores a `measureChild` result for the rest of this pass.
    ///
    /// A natural answer outranks a budget-shaped one for the slot: the shaped
    /// one can only ever serve its own budget back, while the natural one still
    /// serves every budget above its height. (Both are correct; this is about
    /// which is worth keeping.)
    public func storeMeasure(
        key: MeasureKey,
        proposalWidthWasSpecified: Bool,
        proposalHeight: Int?,
        availableHeight: Int,
        size: ViewSize
    ) {
        let entry = MeasureEntry(
            proposalWidthWasSpecified: proposalWidthWasSpecified,
            proposalHeight: proposalHeight,
            availableHeight: availableHeight,
            size: size)
        // `updateValue` so the common case is ONE dictionary access: the key
        // carries a `ViewIdentity`, whose hashing and structural comparison are
        // the most expensive thing here, and a read-then-write to decide the
        // rare demotion below paid for them twice on every measured view.
        if let previous = measureEntries.updateValue(entry, forKey: key),
            previous.size.isNaturalSize, !size.isNaturalSize
        {
            measureEntries[key] = previous
        }
    }

    /// The children a stack resolved earlier this pass for the same content
    /// value, or `nil`. See `resolveChildViews(from:context:)`.
    public func lookupChildViews(key: ChildViewsKey) -> [ChildView]? {
        childViewEntries[key]
    }

    /// Remembers a stack's resolved children for the rest of the pass.
    public func storeChildViews(key: ChildViewsKey, children: [ChildView]) {
        childViewEntries[key] = children
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

    /// The pass's retained roots, indexed for the prune — built once per
    /// ``removeInactive()``, which asks of every unmarked entry.
    private func retainedIndex() -> RetainedSubtreeIndex {
        RetainedSubtreeIndex(roots: retainedSubtreeRoots)
    }

    /// Begins a new render pass by draining any deferred `@State` invalidations,
    /// clearing the active identity set, and snapshotting the current stats for
    /// per-frame delta calculation.
    public func beginRenderPass() {
        // The claim moved — a different host is being rendered as — so every
        // memoized size was measured against a width that no longer applies.
        // Or the terminal reported different colours, so every buffer that
        // spelled or blended the ones before is stale. Its sizes are not, but
        // both events are rare enough that one clear of everything is simplest.
        // Checked once per pass rather than per lookup: the width moves only in
        // the diagnostic app that switches hosts at runtime, and the colours
        // only when the terminal reports them.
        let widthMoved = measuredUnderWidthGeneration != TerminalWidthTraits.generation
        let coloursMoved = renderedUnderTerminalColorsGeneration != TerminalColors.generation
        if widthMoved || coloursMoved {
            measuredUnderWidthGeneration = TerminalWidthTraits.generation
            renderedUnderTerminalColorsGeneration = TerminalColors.generation
            clearAll()
        }

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
        measureScratch.endOfPass(&measureEntries)
        childViewScratch.endOfPass(&childViewEntries)
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
        var retainedChecks = 0
        var retained = retainedIndex()
        func isLive(_ identity: ViewIdentity) -> Bool {
            if activeIdentities.contains(identity) { return true }
            retainedChecks += 1
            return retained.retains(identity)
        }
        // Over the PAIRS, not the keys: a key is now just a hash, and `isLive`
        // needs the chain `retained.retains` climbs, which lives in the entry.
        // Collect-then-remove is kept, so nothing mutates the dictionary mid-walk.
        var staleKeys: [Int] = []
        for (key, entry) in entries where !isLive(entry.identity) { staleKeys.append(key) }
        for key in staleKeys { entries.removeValue(forKey: key) }
        // Collect-then-remove, the spelling `AnimationStore.endRenderPass()`
        // uses and for its reason: removing inside `for … in sizeEntries`
        // COW-copies the whole table on the first removal, and this table is
        // hundreds of entries on a live page and thousands on `fanout`.
        var staleSizeKeys: [SizeKey] = []
        for (key, entry) in sizeEntries where !isLive(entry.identity) { staleSizeKeys.append(key) }
        for key in staleSizeKeys { sizeEntries.removeValue(forKey: key) }
        // Ids interned per identity go the same way, and by the same rule: a
        // handler id baked into a stored buffer's regions must still name its
        // control for as long as that buffer can be served, so retention — not
        // merely "something asked for it this pass" — is what keeps one.
        internedIDTable?.pruneInternedIDs { retained.retains($0) }
        lastPrune = (
            renderEntries: entries.count + staleKeys.count, sizeEntries: sizeEntries.count + staleSizeKeys.count,
            retainedChecks: retainedChecks, prunedRender: staleKeys.count, prunedSizes: staleSizeKeys.count)
        // Environment slots are pruned by pass number, not by `activeIdentities`
        // — only memoizing views mark themselves active, and an environment
        // modifier is not one, so an identity check would drop every slot on
        // every frame and the comparison above could never fire.
        //
        // But NOT a slot inside a subtree a memo served this pass. Nothing
        // below a hit is visited, so its slots go unseen while the entries they
        // guard are retained (`retainSubtree`). Pruned, such a slot came back as
        // `.first` the next time the subtree rendered — and `.first` clears
        // nothing, so an inner memo served what it had drawn under the OLD
        // value: an outer row re-rendered for a new tint, its inner rows still
        // in the old one. So a slot is kept for as long as anything cached below
        // it is live.
        //
        // And only every `slotSweepInterval` passes, because the liveness check
        // is the price: every slot inside a served row is unseen on every frame
        // it is served, and asking each whether it is retained, every frame,
        // was +10.9% on `menus`. Keeping a dead slot a while is safe — at worst
        // it answers `.changed` for a subtree that returns, one conservative
        // clear — where dropping a live one is not. Sweeping periodically also
        // spares the frames between sweeps the walk over the whole table that
        // pruning by pass number made on every one of them.
        guard frameCounter.isMultiple(of: Self.slotSweepInterval) else { return }
        var staleSlots: [EnvironmentSlot] = []
        for (slot, applied) in appliedEnvironment
        where applied.lastSeenFrame < frameCounter && !isLive(slot.identity) {
            staleSlots.append(slot)
        }
        for slot in staleSlots { appliedEnvironment.removeValue(forKey: slot) }
        var staleErasures: [Int] = []
        for (key, erased) in erasedContent
        where erased.lastSeenFrame < frameCounter && !isLive(erased.identity) {
            staleErasures.append(key)
        }
        for key in staleErasures { erasedContent.removeValue(forKey: key) }
    }

    /// How many passes apart ``removeInactive()`` sweeps the environment slots
    /// — see there.
    package static var slotSweepInterval: UInt64 { 64 }

    /// Clears all cached entries.
    ///
    /// Called by `RenderLoop` when global environment values change
    /// (theme, appearance) that affect all views simultaneously.
    /// For state changes that only affect a subtree, prefer
    /// ``clearAffected(by:keepingSizes:includingDescendants:)``.
    public func clearAll() {
        clearGeneration &+= 1
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
    ///
    /// - Parameters:
    ///   - identity: The identity whose ancestors, descendants and self are
    ///     affected.
    ///   - keepingSizes: `true` when the change cannot have moved a cell — a
    ///     paint, a tint — so the memoized SIZES stay and only the buffers go.
    ///     A ramp that rotates every frame re-inks four hundred rows, which is
    ///     the render walk's business; it used to cost the four measure walks
    ///     as well, re-measuring rows a colour cannot resize. `false` for
    ///     anything that can affect layout, which is every other environment
    ///     value and every `@State` write.
    ///   - includingDescendants: `false` when nothing below `identity` can draw
    ///     differently for the change: then only `identity` and the buffers
    ///     that CONTAIN it go. A focus move onto a scroll view, whose content
    ///     learns nothing of its focus, used to drop every row the content had
    ///     measured and drawn, and the next frame rebuilt them all.
    public func clearAffected(
        by identity: ViewIdentity, keepingSizes: Bool = false, includingDescendants: Bool = true
    ) {
        if !keepingSizes { sizeClearGeneration &+= 1 }
        stats.subtreeClears += 1
        // The hashes of `identity` and every ancestor of it, so "is the cached
        // identity `identity` or above it" is a set lookup per entry (confirmed
        // structurally on a hit) rather than a climb of `identity`'s chain per
        // entry. "Is it below" still climbs the cached chain to `identity`'s
        // depth, which is one hop per level of difference and a hash compare.
        var chain = Set<Int>()
        var cursor: ViewIdentity? = identity
        while let node = cursor {
            chain.insert(node.structuralHash)
            cursor = node.parent
        }
        func affects(_ cached: ViewIdentity) -> Bool {
            // Raw-rooted identities (tests, the empty default root) have no
            // chain to index: ancestry is a path prefix, and only the walk
            // sees it.
            if identity.isRawRooted || cached.isRawRooted {
                return cached == identity
                    || cached.isAncestor(of: identity)
                    || (includingDescendants && identity.isAncestor(of: cached))
            }
            if cached.depth <= identity.depth {
                return chain.contains(cached.structuralHash)
                    && (cached == identity || cached.isAncestor(of: identity))
            }
            return includingDescendants && identity.isAncestor(of: cached)
        }
        // `affects` reads `depth`, `isRawRooted`, `structuralHash`, `==` and
        // `isAncestor(of:)` — all structural, none of it available from a hash.
        var staleKeys: [Int] = []
        for (key, entry) in entries where affects(entry.identity) { staleKeys.append(key) }
        for key in staleKeys { entries.removeValue(forKey: key) }
        if !keepingSizes {
            var staleSizeKeys: [SizeKey] = []
            for (key, entry) in sizeEntries where affects(entry.identity) { staleSizeKeys.append(key) }
            for key in staleSizeKeys { sizeEntries.removeValue(forKey: key) }
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
        erasedContent.removeAll()
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
                + "entries: \(measureEntries.count) | "
                + "PRUNE render: \(lastPrune.renderEntries) sizes: \(lastPrune.sizeEntries) "
                + "retainedChecks: \(lastPrune.retainedChecks) "
                + "dropped: \(lastPrune.prunedRender)+\(lastPrune.prunedSizes)"
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
