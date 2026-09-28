//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Link.swift
//
//  The way back to a render cache for whatever keeps one past the render that
//  made it, without a weak reference to the cache.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension RenderCache {
    /// The way back to a render cache for something that keeps it past the
    /// render that made it — a `@State` box, an observation registration, a
    /// control's handler, the focus manager — without a weak reference to the
    /// cache.
    ///
    /// A weak reference is not free for the object it names. The first one
    /// moves the object's reference count into a side table for the rest of
    /// the object's life, and from then on every retain and release of it takes
    /// the runtime's slow path through that table. This cache is retained and
    /// released with every context a render copies, and an app's cache was
    /// referenced weakly from its first frame: its `StateStorage`, every
    /// `@State` box's sink (stamped again at every hydration), the focus
    /// manager and every observed body's registration held it so. Counted with
    /// an interposed retain counter (2026-09-27), 27,688 of its retains and
    /// releases a frame went through the side table on the `chat` session,
    /// 16,053 on `notes`, 8,789 on `settings`.
    ///
    /// So such a holder keeps this instead, strongly. It is made with the cache
    /// and belongs to it, and it holds nothing that holds the cache, so keeping
    /// it keeps nothing alive and makes no cycle: a buffer's journal, which the
    /// cache keeps, can hold it.
    ///
    /// Two ways in, for two kinds of holder:
    ///
    /// - **From any thread**, ``invalidateRender(for:)``: the queue of
    ///   invalidations a `@State` write or an `@Observable` change makes, which
    ///   the cache drains on the main actor at ``RenderCache/beginRenderPass()``.
    ///   It lives here, not on the cache, so a write on another thread never
    ///   touches the cache at all. Once the cache has gone the queue is closed:
    ///   a report does nothing, and asks for no frame.
    /// - **On the main actor**, ``cache``: for a holder that has to act on the
    ///   cache's tables at once (a focus move, a control's drawing report). It
    ///   names the cache `unowned`, which keeps no strong count and, unlike a
    ///   weak reference, moves nothing to a side table: the unowned count is
    ///   kept inline beside the strong one. The cache's `deinit` clears it
    ///   first thing, so a holder that outlives the cache reads `nil`, as
    ///   through a weak reference. Read only on the main actor, where caches
    ///   are released — by the context that renders into them — so it cannot
    ///   be cleared while it is being read. `unowned`, not `unowned(unsafe)`:
    ///   a holder that broke that rule and read a cache already deinitializing
    ///   on another thread traps, rather than reading freed memory.
    package final class Link: RenderInvalidationSink, @unchecked Sendable {
        /// What the link's lock guards: the queue, whether the cache is still
        /// there to drain it, and the diagnostic a write reports to.
        private struct Queue: Sendable {
            /// `false` once the cache has gone: nothing is queued, no frame is
            /// asked for.
            var attached = true
            /// `true` once a whole-cache clear is requested; supersedes
            /// `identities`.
            var clearAll = false
            /// Subtrees whose cached buffers must be dropped (unless
            /// `clearAll`).
            var identities: Set<ViewIdentity> = []
            /// The cache's ``RenderCache/bodyMutationDiagnostic``, mirrored
            /// here so a write on another thread reads it without reading the
            /// cache.
            var diagnostic: BodyMutationDiagnostic?
        }

        /// What a drain takes: the invalidations queued since the last one.
        package struct Pending: Sendable {
            /// Whether a whole-cache clear was asked for.
            package let clearAll: Bool
            /// The identities queued, when `clearAll` is not set.
            package let identities: Set<ViewIdentity>
        }

        private let queue = Lock(initialState: Queue())

        /// The cache, or `nil` once it has gone. Main actor only — see the type.
        package private(set) unowned var cache: RenderCache?

        init() {}

        /// Called by the cache's `init`.
        func attach(_ cache: RenderCache) {
            self.cache = cache
        }

        /// Called first thing in the cache's `deinit`: from here on a holder
        /// reads `nil`, and a report goes nowhere.
        func detach() {
            cache = nil
            queue.withLock { queue in
                queue.attached = false
                queue.clearAll = false
                queue.identities.removeAll()
                queue.diagnostic = nil
            }
        }

        /// Mirrors the cache's diagnostic, which a write reports to.
        func setDiagnostic(_ diagnostic: BodyMutationDiagnostic?) {
            queue.withLock { $0.diagnostic = diagnostic }
        }

        /// Queues an invalidation and asks for a frame — what a `@State` write
        /// and an `@Observable` change do. Thread-safe; the cache's tables are
        /// changed later, on the main actor, by the drain. Does nothing once the
        /// cache has gone.
        ///
        /// - Parameter identity: The subtree whose cached buffers are now stale,
        ///   or `nil` to drop the whole cache.
        package func invalidateRender(for identity: ViewIdentity?) {
            let (queued, diagnostic) = queue.withLock { queue -> (Bool, BodyMutationDiagnostic?) in
                guard queue.attached else { return (false, nil) }
                if let identity {
                    if !queue.clearAll { queue.identities.insert(identity) }
                } else {
                    queue.clearAll = true
                    queue.identities.removeAll(keepingCapacity: true)
                }
                return (true, queue.diagnostic)
            }
            guard queued else { return }
            // Opt-in, and free when off: one optional test. See
            // `BodyMutationDiagnostic` for why a write during the walk is worth
            // naming — this is the single funnel every `@State` write reaches,
            // so it is the only place that needs to ask. Outside the lock: it
            // may print.
            diagnostic?.note(identity)
            AppState.shared.setNeedsRender()
        }

        /// Takes what has been queued since the last drain, leaving the queue
        /// empty. Called by the cache, on the main actor.
        func drain() -> Pending {
            queue.withLock { queue in
                let pending = Pending(clearAll: queue.clearAll, identities: queue.identities)
                queue.clearAll = false
                queue.identities.removeAll(keepingCapacity: true)
                return pending
            }
        }
    }
}
