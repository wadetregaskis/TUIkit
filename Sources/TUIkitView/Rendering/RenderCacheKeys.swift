//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheKeys.swift
//
//  The keys ``RenderCache``'s four tables are probed by, and how each one
//  hashes. Split from the cache itself because they are a self-contained
//  subject — what identifies a cached answer, and what a collision would and
//  would not cost — and because every one of them now folds its fields before
//  `Hasher` sees any of them (see `CacheKeyHashing.swift`), which is a decision
//  a reader should be able to find in one place.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension RenderCache {

    /// Key for a memoized *measurement* (one identity can be measured at several
    /// proposals per frame, so — unlike the buffer cache — this is keyed by the
    /// proposal and available extent as well as the identity).
    public struct SizeKey: Hashable {
        /// The identity's structural hash, not the identity.
        ///
        /// The bargain ``RenderCache/MeasureKey`` documents, struck here for the
        /// same reason: a `ViewIdentity` is a chain of class nodes, so every copy
        /// of the key retains and releases it, and comparing two *equal* ones
        /// walks it step for step — the `===` shortcut inside
        /// `IdentityNode.structurallyEqual` cannot fire, because the walk that
        /// stored the key and the walk that probes it built their chains
        /// separately, and here they are a whole frame apart.
        ///
        /// The collision argument is NOT inherited from `MeasureKey`, whose own
        /// rests on "nothing here outlives the pass": this table is cross-frame.
        /// Made afresh, it is that a false hit needs two distinct identity paths
        /// to hash identically AND to carry the same proposal, the same two
        /// extents and the same two explicit flags, AND for the snapshot
        /// comparison in ``RenderCache/lookupSize(key:view:)`` to find the two
        /// views' values equal. It would show as one subtree sized from a twin
        /// until that value next changed — never as aliased state, since nothing
        /// is keyed from here but a size.
        ///
        /// The measure generation is deliberately NOT folded in, unlike the one
        /// `measureIdentityHash` folds into `MeasureKey`: this key ignores
        /// ``RenderContext/measureGeneration`` today, and folding it would change
        /// which menu rows re-measure — a behaviour change wearing a performance
        /// change's clothes. Set from `structuralHash` and nothing else, the word
        /// this hashes is bit-identical to the one the identity-carrying key
        /// hashed, so not one probe changes bucket.
        public let identityHash: Int
        public let proposalWidth: Int?
        public let proposalHeight: Int?
        public let availableWidth: Int
        public let availableHeight: Int
        public let hasExplicitWidth: Bool
        public let hasExplicitHeight: Bool
        /// The measure generation this size was taken in — see
        /// ``RenderContext/measureGeneration``.
        ///
        /// A STORED field, where ``RenderCache/MeasureKey`` folds its generation
        /// into the identity hash instead. That key cannot afford an eighth
        /// field; this one already carries seven and compares them all — and a
        /// generation that reached only the hash would be unsound here, because
        /// `Hashable`'s synthesised `==` is built from the stored properties and
        /// would still call two keys equal, which a `Dictionary`'s linear probe
        /// can act on when it meets the old entry on its way past its bucket.
        ///
        /// It costs nothing to carry: the two `Bool`s above end the struct at 58
        /// bytes of a 64-byte stride, so this lands in padding already there.
        ///
        /// Without it ``RenderContext/invalidatingMeasureMemo()`` did not mean
        /// what it says. `MeasureKey` misses on a bump, so a value-memoized
        /// wrapper IS re-entered — and then `measureValueMemoized`'s probe hit on
        /// the pre-change size and short-circuited before the subtree was
        /// measured at all. This table is the cross-frame one (only
        /// `clearAffected`/`clearAll` drop an entry), so the stale size stood
        /// until the memoized value itself changed.
        public let measureGeneration: UInt8

        public init(
            identityHash: Int,
            proposalWidth: Int?,
            proposalHeight: Int?,
            availableWidth: Int,
            availableHeight: Int,
            hasExplicitWidth: Bool,
            hasExplicitHeight: Bool,
            measureGeneration: UInt8
        ) {
            self.identityHash = identityHash
            self.proposalWidth = proposalWidth
            self.proposalHeight = proposalHeight
            self.availableWidth = availableWidth
            self.availableHeight = availableHeight
            self.hasExplicitWidth = hasExplicitWidth
            self.hasExplicitHeight = hasExplicitHeight
            self.measureGeneration = measureGeneration
        }

        /// The fields folded into one word before `Hasher` sees any of them —
        /// see ``mixHashWord(_:_:)``, and ``RenderCache/MeasureKey`` for why a
        /// process-local cache key does not need SipHash per field.
        public func hash(into hasher: inout Hasher) {
            var folded = mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(identityHash)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(proposalWidth ?? -1)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(proposalHeight ?? -1)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(availableWidth)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(availableHeight)))
            // The generation rides in the flags word rather than a seventh mix
            // round: it is one byte, the two flags occupy bits 0 and 1, so bits
            // 8…15 are free and folding it in costs a shift and an or.
            folded = mixHashWord(
                folded,
                (hasExplicitWidth ? 1 : 0) | (hasExplicitHeight ? 2 : 0)
                    | (UInt64(measureGeneration) << 8))
            hasher.combine(finalizeHashWord(folded))
        }
    }

    /// A `measureChild` memo key: what a measurement is *of*, with nothing in it
    /// about the space it was offered vertically.
    ///
    /// The type is what an identity-only key was missing. Transparent wrappers
    /// descend under their parent's identity, so several distinct views share
    /// one identity within a pass; keying on identity alone returned one view's
    /// size for another (the abandoned cross-frame cache — it got Panel/Card/
    /// Dialog wrong, and the equivalence harness caught it).
    ///
    /// The two widths are both here and both matter. `effectiveWidth` is
    /// `proposal.width ?? availableWidth`, the number a measure actually lays out
    /// against; `availableWidth` stays beside it because a container measures
    /// its children against the *available* extent while sizing itself against
    /// the proposal, so two calls that share one and not the other are two
    /// different questions. What is NOT here is the vertical budget or whether
    /// the width arrived as a proposal — those live in `RenderCache.MeasureEntry`, which is
    /// where a ``ViewSize/isNaturalSize`` answer gets to ignore them.
    public struct MeasureKey: Hashable {
        /// The identity's structural hash, not the identity.
        ///
        /// Two probes per measured view, and a `ViewIdentity` is a chain of
        /// class nodes: hashing walks it, comparing two *equal* ones walks it
        /// step for step (the `===` shortcut misses, because the two walks that
        /// meet here built their chains separately), and every copy of the key
        /// retains and releases it. Keyed by the chain's cached hash the whole
        /// key is plain data — no ARC, no walk — which is what makes a memo
        /// probed on every measured view affordable. (Measured: keying the
        /// identity itself cost `deep` +45%, all of it in `structurallyEqual`
        /// and retain/release.)
        ///
        /// This is the same bargain ``valueHash`` already strikes one field
        /// down, with the same shape of failure: a collision would need two
        /// distinct identity paths to hash identically *within one pass* AND to
        /// carry the same view type, the same value bytes and the same two
        /// widths — and it would show as one frame sized from a twin, never as
        /// aliased state, because nothing here outlives the pass.
        /// The identity's structural hash — with the measure generation folded
        /// in when there is one, which is almost never (see
        /// ``RenderContext/measureGeneration``).
        ///
        /// Folded rather than carried beside: this key is probed around two
        /// thousand times a frame and copied on every probe, and an eighth field
        /// grew it by a word — measured **+2.1% on the `anyview` stress
        /// scenario**, the shape with the most probes, for a field that is 0 for
        /// every view in almost every pass. Folded it costs one compare and one
        /// mix, at the one call site, only when a container has opted in.
        ///
        /// The bargain is the one this field already strikes: a wrong answer
        /// needs two distinct (identity, generation) pairs to hash identically
        /// WITHIN one pass and to carry the same view type, the same value bytes
        /// and the same two widths.
        let identityHash: Int
        let effectiveWidth: Int
        let availableWidth: Int
        let hasExplicitWidth: Bool
        let hasExplicitHeight: Bool
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

        /// The six fields folded into one word before `Hasher` sees any of them
        /// — see ``mixHashWord(_:_:)``. This key is probed around two thousand
        /// times a frame, and the synthesised conformance made that six SipHash
        /// rounds where one does.
        public func hash(into hasher: inout Hasher) {
            var folded = mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(identityHash)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(effectiveWidth)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(availableWidth)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(valueHash)))
            folded = mixHashWord(folded, UInt64(UInt(bitPattern: viewType)))
            folded = mixHashWord(
                folded, (hasExplicitWidth ? 1 : 0) | (hasExplicitHeight ? 2 : 0))
            hasher.combine(finalizeHashWord(folded))
        }

        public init(
            identityHash: Int,
            effectiveWidth: Int,
            availableWidth: Int,
            hasExplicitWidth: Bool,
            hasExplicitHeight: Bool,
            viewType: ObjectIdentifier,
            valueHash: Int
        ) {
            self.identityHash = identityHash
            self.effectiveWidth = effectiveWidth
            self.availableWidth = availableWidth
            self.hasExplicitWidth = hasExplicitWidth
            self.hasExplicitHeight = hasExplicitHeight
            self.viewType = viewType
            self.valueHash = valueHash
        }
    }

    /// A stack's resolved children for the pass — see
    /// `resolveChildViews(from:context:)`. The identity's hash plus the
    /// content's type and raw bytes, like ``MeasureKey`` without a proposal:
    /// which children a content value has does not depend on the space it is
    /// offered.
    public struct ChildViewsKey: Hashable {
        /// The identity's structural hash, not the identity — the trade
        /// ``RenderCache/MeasureKey`` documents, made here with the stronger of
        /// the two safety arguments: this table is per-pass scratch (emptied by
        /// every ``RenderCache/beginRenderPass()``), and nothing ever reads the
        /// identity back out of the key, so the chain of class nodes bought
        /// nothing but ARC on every copy and a step-for-step walk on every equal
        /// key (`IdentityNode.structurallyEqual`'s `===` shortcut cannot fire —
        /// the walk that stored the key and the walk that probes it built their
        /// chains separately).
        public let identityHash: Int
        public let viewType: ObjectIdentifier
        public let valueHash: Int

        public init(identityHash: Int, viewType: ObjectIdentifier, valueHash: Int) {
            self.identityHash = identityHash
            self.viewType = viewType
            self.valueHash = valueHash
        }

        /// The fields folded into one word before `Hasher` sees any of them —
        /// see ``mixHashWord(_:_:)``, and ``RenderCache/MeasureKey`` for why a
        /// process-local cache key does not need SipHash per field.
        public func hash(into hasher: inout Hasher) {
            var folded = mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(identityHash)))
            folded = mixHashWord(folded, UInt64(UInt(bitPattern: viewType)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(valueHash)))
            hasher.combine(finalizeHashWord(folded))
        }
    }

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

        /// The fields folded into one word before `Hasher` sees any of them —
        /// see ``mixHashWord(_:_:)``, and ``RenderCache/MeasureKey`` for why a
        /// process-local cache key does not need SipHash per field.
        public func hash(into hasher: inout Hasher) {
            var folded = mixHashWord(
                hashFoldSeed, UInt64(bitPattern: Int64(identity.structuralHash)))
            // The key path's own hash: it has to be the VALUE's, not the
            // object's, because two `\.foregroundStyle` literals from different
            // call sites are equal and must hash alike.
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(keyPath.hashValue)))
            folded = mixHashWord(folded, UInt64(bitPattern: Int64(depth)))
            hasher.combine(finalizeHashWord(folded))
        }
    }
}
