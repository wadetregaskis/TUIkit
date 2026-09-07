//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StateStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - State Storage

/// Persistent store for `@State` values, indexed by `ViewIdentity`.
///
/// `StateStorage` is the backbone of TUIkit's state persistence across render
/// passes. It maps each `@State` property to a stable key derived from the
/// view's structural position in the tree (`ViewIdentity`) and the property's
/// declaration order within that view.
///
/// ## Lifecycle
///
/// - **Created** by `TUIContext` (one per application).
/// - **Populated** during rendering: when `renderToBuffer` hydrates a view's
///   `@State` properties, it looks up or creates `Storage` objects here.
/// - **Pruned** at the end of each render pass: identities not seen during
///   the current frame are removed. This runs *alongside* `LifecycleManager`'s
///   own sweep, not in coordination with it — the two key on different things
///   (`ViewIdentity` here, a lifecycle token string there) and
///   `RenderLoop.endRenderPass` simply calls them in sequence. Retaining a
///   subtree here therefore does **not** retain its `.task`s or its
///   `onDisappear`.
///
/// ## Thread Safety
///
/// The store itself is main-actor only, but a `StateBox`'s **setter** is not:
/// a `.task` or an input-thread mouse handler can write one. That path takes no
/// lock here — it hands off to `RenderCache.invalidateRender(for:)`, which does
/// (see its Thread Safety note).
public final class StateStorage: @unchecked Sendable {

    // MARK: - State Key

    /// A unique key for a single `@State` property on a specific view.
    ///
    /// ## The property-index namespace
    ///
    /// Indices `0...` belong to a composite view's own wrapped properties,
    /// bound by declaration order. Framework infrastructure that persists a
    /// box at the SAME identity as content it renders — a `Renderable`
    /// modifier or control that pushes no child identity — must use
    /// **negative** indices, or a wrapped composite view's first `@State`
    /// aliases the infrastructure's box: same type and the two share one
    /// value; different types and `storage(for:)` replaces the box each
    /// frame, resetting both sides to their defaults every render.
    ///
    /// Negative indices are reserved in RANGES, one per purpose, so wrappers
    /// stacked on one identity cannot collide with each other either. The
    /// allocation, in tens (a purpose grows downward within its ten):
    ///
    /// | range | owner |
    /// |---|---|
    /// | -10… | `FocusableModifier` |
    /// | -20… | `RefreshableModifier` |
    /// | -30… | `NavigationPresentationModifier` |
    /// | -40… | `_UserResizableCore` |
    /// | -50… | `_ToggleCore` |
    /// | -60… | `TaskModifier` |
    /// | -70… | `_VStackCore` (windowed lazy stacks) |
    ///
    /// Taking a new range: claim the next free ten here, in this table.
    /// (Leaf `Renderable` views whose slots can never share an identity with
    /// composite content keep their historical `0...` constants; anything
    /// that renders a caller-supplied `@ViewBuilder` at its own identity
    /// belongs in this table.)
    public struct StateKey: Hashable {
        /// The view's structural identity in the render tree.
        public let identity: ViewIdentity

        /// The property's declaration index within the view (0, 1, 2, ...),
        /// or a reserved NEGATIVE infrastructure index — see the
        /// property-index namespace note above.
        public let propertyIndex: Int

        /// Creates a new state key.
        public init(identity: ViewIdentity, propertyIndex: Int) {
            self.identity = identity
            self.propertyIndex = propertyIndex
        }
    }

    // MARK: - Storage

    /// All persisted state values, keyed by view identity + property index.
    private var values: [StateKey: AnyObject] = [:]

    /// Tracked values for `onChange(of:)`, keyed by view identity + property index.
    ///
    /// Unlike `values` (which stores `StateBox` objects that trigger re-renders),
    /// tracked values are plain values used only for change detection. Writing to
    /// them does not trigger a re-render.
    private var trackedValues: [StateKey: Any] = [:]

    /// Per-identity counters for `onChange(of:)` index assignment.
    ///
    /// Reset at the start of each render pass. Each `OnChangeModifier` claims the
    /// next index for its identity, ensuring chained `.onChange(of:)` modifiers at
    /// the same identity get unique keys.
    private var onChangeCounters: [ViewIdentity: Int] = [:]

    /// Identities seen during the current render pass (for garbage collection).
    private var activeIdentities: Set<ViewIdentity> = []

    /// Subtree roots whose descendants' state survives this pass's prune even
    /// when the descendant was not hydrated. Declared each frame by windowing
    /// containers (lazy stacks, `List`, `Table`): a row they skipped left the
    /// *window*, not the *tree* (§5h of "Locating things without drawing
    /// them"). Cleared by ``beginRenderPass``, so a container that stops
    /// rendering stops protecting and its subtree prunes on the next pass.
    /// Deliberately NOT pruned per-row on data deletion: knowing a row left
    /// the data would require the full id set every frame (the identity tax);
    /// a deleted row's state lingers until its container dies.
    private var retainedSubtreeRoots: [ViewIdentity] = []

    /// The render cache that state changes should invalidate — the cache of the
    /// `TUIContext` this storage belongs to. Wired by the context at creation and
    /// stamped onto each ``StateBox`` at hydration, so a state change clears only
    /// its own context's cache (no process-wide singleton → no cross-test bleed).
    public weak var renderCache: RenderCache?

    /// The last-rendered branch of each `ConditionalView`, keyed by the
    /// conditional's own identity (`true` ⇒ the `.trueContent` branch was last
    /// rendered, `false` ⇒ `.falseContent`).
    ///
    /// `ConditionalView.renderToBuffer` consults this to skip the inactive-branch
    /// `invalidateDescendants` (and the identity-node alloc it needs) on frames
    /// where the branch did **not** flip — the common case — only paying that cost
    /// on an actual flip. Written only on the render path (never while measuring,
    /// per the measure-side-effect rule) and pruned in ``endRenderPass`` alongside
    /// the rest of the per-identity state, so removed conditionals don't leak.
    private var lastConditionalCase: [ViewIdentity: Bool] = [:]

    /// What each animating value in the tree is doing.
    ///
    /// Held here rather than standing alone because its lifetime is exactly
    /// this one's: an animation belongs to a view identity, and dies with it.
    /// ``endRenderPass()``, ``invalidateDescendants(of:)`` and ``reset()``
    /// forward to it, so an animating view that leaves the tree — or a
    /// conditional branch that flips — takes its animations along.
    public let animations = AnimationStore()

    /// What each removed view left behind, so a removal transition has
    /// something to play out. See ``DepartureStore``.
    public let departures = DepartureStore()

    /// Creates an empty state storage.
    public init() {}

    /// The number of stored state entries (for testing/debugging).
    public var count: Int { values.count }
}

// MARK: - Internal API

extension StateStorage {
    /// Returns the persistent storage for a `@State` property, creating it if needed.
    ///
    /// If a storage object already exists for the given key, it is returned as-is
    /// (preserving the current value across render passes). Otherwise, a new storage
    /// is created with the provided default value.
    ///
    /// `defaultValue` is an `@autoclosure` because the common case is a HIT, and
    /// on a hit the default is built and thrown away. That is not free for every
    /// caller: a control's focus id is `"\(prefix)-\(context.identity.path)"`,
    /// and `path` walks the identity chain rendering a string of demangled
    /// generic type names — on every measure and every render of every focusable
    /// view, to be discarded on all but the frame that created the box.
    ///
    /// - Parameters:
    ///   - key: The state key (identity + property index).
    ///   - defaultValue: The initial value for newly created storage. Evaluated
    ///     only when there is no storage yet.
    /// - Returns: The persistent `Storage` object for this property.
    public func storage<Value>(
        for key: StateKey, default defaultValue: @autoclosure () -> Value
    ) -> StateBox<Value> {
        if let existing = values[key] as? StateBox<Value> {
            existing.identity = key.identity
            existing.invalidationSink = renderCache
            return existing
        }
        let fresh = StateBox(defaultValue())
        fresh.identity = key.identity
        fresh.invalidationSink = renderCache
        values[key] = fresh
        return fresh
    }

    /// The storage for a property **if one already exists**, never creating it.
    ///
    /// The measure pass's ``storage(for:default:)``. A measure runs
    /// speculatively and more than once per frame, so it must not create a box
    /// — that is a persistent mutation, at an identity that may never be
    /// rendered. But it does have to READ what the render put there, or a view
    /// that sizes itself from stored state measures one size and draws another.
    ///
    /// - Parameter key: The state key (identity + property index).
    /// - Returns: The existing box, or `nil` if nothing has been stored under
    ///   `key` (or something of another type has).
    public func existingStorage<Value>(for key: StateKey) -> StateBox<Value>? {
        values[key] as? StateBox<Value>
    }

    /// Marks an identity as active during the current render pass.
    ///
    /// Called by `renderToBuffer` when hydrating a view. Identities not marked
    /// active by the end of the render pass are candidates for garbage collection.
    ///
    /// - Parameter identity: The view identity to mark as active.
    public func markActive(_ identity: ViewIdentity) {
        activeIdentities.insert(identity)
    }

    /// Declares that every identity below `root` must survive this pass's
    /// prune, hydrated or not.
    ///
    /// Called on the render path by containers that *window* their children —
    /// render only the rows meeting the viewport — so the skipped rows' state
    /// (`@State`, `onChange` baselines, conditional-branch records) persists
    /// exactly as if they had rendered. Per-pass: declare on every frame the
    /// container renders; the declaration lapses (and the subtree becomes
    /// prunable) the first frame it doesn't.
    ///
    /// - Parameter root: The windowing container's own identity.
    public func retainSubtree(_ root: ViewIdentity) {
        retainedSubtreeRoots.append(root)
    }

    // MARK: - Conditional Branch Tracking

    /// Records which branch a `ConditionalView` rendered this frame, and reports
    /// whether that **flipped** since the last frame it was recorded.
    ///
    /// Called by ``ConditionalView`` on the render path (gated `!isMeasuring`).
    /// On the first record for an identity — or the first after the conditional
    /// reappeared (its entry having been pruned while absent) — there is no prior
    /// branch, so this returns `false`: the inactive branch has no persisted
    /// state yet (nothing was ever rendered there, or it was already pruned when
    /// the conditional left the tree), so its `invalidateDescendants` would be a
    /// no-op and can be skipped.
    ///
    /// The identity is marked active so its entry survives `endRenderPass`'s
    /// prune; entries for conditionals no longer in the tree are dropped there.
    ///
    /// - Parameters:
    ///   - identity: The conditional view's own identity.
    ///   - isTrueBranch: `true` if the `.trueContent` branch rendered this frame.
    /// - Returns: `true` if the branch differs from the last recorded one.
    public func recordConditionalBranch(_ identity: ViewIdentity, isTrueBranch: Bool) -> Bool {
        activeIdentities.insert(identity)
        let previous = lastConditionalCase[identity]
        lastConditionalCase[identity] = isTrueBranch
        guard let previous else { return false }
        return previous != isTrueBranch
    }

    // MARK: - onChange Tracking

    /// Claims the next `onChange` property index for the given identity.
    ///
    /// Each `OnChangeModifier` at a given identity calls this to get a unique
    /// index, ensuring chained `.onChange(of:)` modifiers don't collide.
    ///
    /// Claim it BEFORE rendering content. The index is positional, so one
    /// claimed afterwards is the count of claimants the CONTENT contributed at
    /// the same identity — and an `if` without `else` (or an `AnyView`) changes
    /// that from frame to frame, since both render at the parent identity. A
    /// claim made first depends only on the chain above, which is body order.
    ///
    /// - Parameter identity: The view identity requesting an index.
    /// - Returns: The next available index (starting at 0).
    public func nextOnChangeIndex(for identity: ViewIdentity) -> Int {
        let index = onChangeCounters[identity, default: 0]
        onChangeCounters[identity] = index + 1
        return index
    }

    /// Returns the previously tracked value for the given key, if any.
    ///
    /// - Parameter key: The state key (identity + property index).
    /// - Returns: The tracked value, or `nil` if no value was stored yet.
    public func trackedValue<V>(for key: StateKey) -> V? {
        trackedValues[key] as? V
    }

    /// Stores a tracked value for change detection across render passes.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The state key (identity + property index).
    public func setTrackedValue<V>(_ value: V, for key: StateKey) {
        trackedValues[key] = value
    }

    // MARK: - Render Pass Lifecycle

    /// Begins a new render pass by clearing the active identity set.
    public func beginRenderPass() {
        animations.beginRenderPass()
        departures.beginRenderPass()
        activeIdentities.removeAll(keepingCapacity: true)
        retainedSubtreeRoots.removeAll(keepingCapacity: true)
        beginSceneRender()
    }

    /// Begins one WALK of the view tree, of which a render pass may contain
    /// more than one (the app header's height-discovery and correction
    /// re-renders — see `RenderLoop.beginSceneRender()`).
    ///
    /// Deliberately narrower than ``beginRenderPass()``: it resets only the
    /// per-walk onChange counters, which are claimed POSITIONALLY, so a second
    /// walk that did not restart them would hand every `.onChange` /
    /// `.onPreferenceChange` a shifted index and read and write the wrong
    /// slots.
    ///
    /// It must NOT clear `activeIdentities`. By the time a walk begins, that
    /// set already carries the App's own root identity (marked when the app
    /// body was evaluated); clearing it mid-pass would leave the root unmarked
    /// and let ``endRenderPass()`` prune App-level `@State` on every frame that
    /// walks the tree twice.
    public func beginSceneRender() {
        onChangeCounters.removeAll(keepingCapacity: true)
    }

    /// Ends a render pass by removing state for views no longer in the tree.
    ///
    /// Any state whose identity was not marked active during this render pass
    /// — and is not under a ``retainSubtree(_:)`` root — is removed. This
    /// prevents memory leaks from views that have been permanently removed
    /// (e.g., by navigation or conditional branches) while keeping windowed-out
    /// rows' state alive.
    public func endRenderPass() {
        // Indexed once for the pass: the prune asks of every unmarked box,
        // and a climb per root per box was most of a frame's end on a page
        // of memoised cards (see `RetainedSubtreeIndex`).
        var retained = RetainedSubtreeIndex(roots: retainedSubtreeRoots)
        let staleKeys = values.keys.filter {
            !activeIdentities.contains($0.identity) && !retained.retains($0.identity)
        }
        for key in staleKeys {
            values.removeValue(forKey: key)
        }
        let staleTrackedKeys = trackedValues.keys.filter {
            !activeIdentities.contains($0.identity) && !retained.retains($0.identity)
        }
        for key in staleTrackedKeys {
            trackedValues.removeValue(forKey: key)
        }
        // Drop branch records for conditionals no longer in the tree, so a
        // conditional that left and later returns is treated as fresh (its
        // descendant state was already pruned above). Retained rows keep
        // theirs: if a retained row's conditional flips on re-entry, the
        // flip must be SEEN so the stale branch's state gets invalidated.
        let staleConditionals = lastConditionalCase.keys.filter {
            !activeIdentities.contains($0) && !retained.retains($0)
        }
        for identity in staleConditionals {
            lastConditionalCase.removeValue(forKey: identity)
        }
        animations.endRenderPass()
        departures.endRenderPass()
    }

    /// Removes all state for descendants of the given identity.
    ///
    /// Called by ``ConditionalView`` when switching branches to clean up
    /// state from the now-inactive branch.
    ///
    /// - Parameter ancestor: The branch identity whose descendants should be removed.
    public func invalidateDescendants(of ancestor: ViewIdentity) {
        let staleKeys = values.keys.filter { ancestor.isAncestor(of: $0.identity) }
        for key in staleKeys {
            values.removeValue(forKey: key)
        }
        let staleTrackedKeys = trackedValues.keys.filter { ancestor.isAncestor(of: $0.identity) }
        for key in staleTrackedKeys {
            trackedValues.removeValue(forKey: key)
        }
        animations.removeDescendants(of: ancestor)
    }

    /// Removes all stored state. Used during app cleanup.
    public func reset() {
        values.removeAll()
        trackedValues.removeAll()
        onChangeCounters.removeAll()
        activeIdentities.removeAll()
        lastConditionalCase.removeAll()
        animations.removeAll()
        departures.removeAll()
    }
}

// MARK: - State Box

/// Type-erased reference container for a single state value.
///
/// `StateBox` is the persistent storage backing a `@State` property.
/// It is a reference type so that mutations are visible across all copies
/// of the `@State` struct (which uses `nonmutating set`).
///
/// On value change, the box asks its ``RenderInvalidationSink`` to drop the
/// affected subtree's cached buffers and request a re-render. Invalidation is
/// identity-aware: only the affected subtree is cleared, not the whole cache.
public final class StateBox<Value>: @unchecked Sendable {
    /// The identity of the view that owns this state property.
    ///
    /// Set during hydration from ``StateStorage``. Passed to the sink so it can
    /// invalidate only the affected subtree.
    var identity: ViewIdentity?

    /// The sink that turns a value change into a (deferred, thread-safe) cache
    /// invalidation plus a re-render request — the box's owning context's
    /// ``RenderCache`` (wired during hydration from ``StateStorage``). Routing
    /// through the per-context sink keeps each context (the app's, and every
    /// test's) invalidating only its own cache, and — because the sink defers
    /// the mutation to the main-actor frame boundary — a `@State` written from a
    /// background `Task` never races the single-threaded cache. `nil` before the
    /// box is first hydrated, in which case nothing has been cached for it yet.
    weak var invalidationSink: (any RenderInvalidationSink)?

    /// The current value.
    public var value: Value {
        didSet {
            invalidationSink?.invalidateRender(for: identity)
        }
    }

    /// Creates a state box with an initial value.
    ///
    /// - Parameter value: The initial value.
    public init(_ value: Value) {
        self.value = value
    }
}
