//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Entries.swift
//
//  What the render cache keeps for one memoized subtree: its buffer, what it
//  was drawn at and over, and the registrations it made.
//
//  Moved out of `RenderCache.swift`, which had reached the file-length
//  ceiling, unchanged.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension RenderCache {
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

        /// Where the animation clocks stood when the buffer was drawn, for a
        /// buffer that carries animated cell runs; `nil` for every other, and for
        /// one drawn where nothing said (``RenderCache/frameInstant``).
        ///
        /// A run's cells in the buffer show the frame of THIS instant, so a hit
        /// at a later one is right only while every run would show the same
        /// thing then — see ``showsItsAnimations(asAt:)``.
        package let drawnAt: AnimationInstant?

        /// The lease of the computation that drew `buffer`: what keeps the
        /// observation scopes that computation armed alive while the entry is
        /// kept (see ``ObservationLeases``). `nil` when nothing beneath it
        /// read.
        package let lease: ObservationLease?

        /// Whether the buffer shows each of its runs as the run would show at
        /// `instant` — trivially so for an entry with no runs, or when either
        /// instant is unknown, which is how an entry behaved before it kept one.
        package func showsItsAnimations(asAt instant: AnimationInstant?) -> Bool {
            guard let drawnAt, let instant, drawnAt != instant else { return true }
            return buffer.animatedCells.allSatisfy { $0.showsTheSame(at: instant, asAt: drawnAt) }
        }

        /// Creates a new cache entry.
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

        /// Creates an entry that carries recorded registrations, and the instant
        /// its animated cells were drawn at.
        package init(
            identity: ViewIdentity,
            viewSnapshot: Any, buffer: FrameBuffer, contextWidth: Int, contextHeight: Int,
            gradientFrame: GradientFrame?, surfaceBackground: Color?,
            effects: [EffectJournal.Entry], effectScope: EffectScope,
            drawnAt: AnimationInstant? = nil, lease: ObservationLease? = nil
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
            self.drawnAt = buffer.animatedCells.isEmpty ? nil : drawnAt
            self.lease = lease
        }
    }
}
