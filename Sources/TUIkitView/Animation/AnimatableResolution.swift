//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableResolution.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Substitutes the animated value into an ``Animatable`` view before its body is
/// evaluated, so the subtree is built from where the picture *is* rather than
/// from where the tree says the value has got to.
///
/// This is the general case, and the expensive one: the body is re-evaluated on
/// every frame of the animation, because a terminal has no render server to
/// hand an interpolation to. That is affordable for the length of a change and
/// is not affordable forever — see <doc:AnimatingYourOwnView>.
///
/// - Parameters:
///   - view: The view about to be rendered or measured.
///   - context: Its render context.
///   - isMeasuring: Whether this is the measure walk, which must not write to
///     the store. Passed rather than read from `context.isMeasuring`, because
///     that flag means something narrower — a *render* performed only in order
///     to measure — and is false on the ordinary structural measure walk, where
///     writing would be just as wrong.
/// - Returns: `view` unchanged unless it is `Animatable` and something is
///   moving, in which case a copy at this frame's value.
@MainActor
func resolvingAnimation<V: View>(
    _ view: V, context: RenderContext, isMeasuring: Bool
) -> V {
    // The overwhelmingly common answer is "this type is not animatable", and it
    // is the same answer every time for a given type — so it is remembered,
    // exactly as `bindStateProperties` remembers which types have no `@State`.
    // Only an unseen type pays the conformance check.
    let typeID = ObjectIdentifier(V.self)
    if AnimatableTypeCache.isKnownInert(typeID) { return view }

    guard let animatable = view as? any Animatable else {
        AnimatableTypeCache.noteInert(typeID)
        return view
    }
    guard let storage = context.stateStorage else { return view }

    let key = AnimationStore.Key(identity: context.identity, owner: typeID)
    // Passing an `any Animatable` to a generic parameter opens the existential,
    // so the animatable data keeps its real type through the store.
    let resolved = substituting(
        animatable, key: key, storage: storage, context: context, isMeasuring: isMeasuring)
    return (resolved as? V) ?? view
}

/// Replaces `value`'s animatable data with what the store says to draw.
@MainActor
private func substituting<A: Animatable>(
    _ value: A, key: AnimationStore.Key, storage: StateStorage, context: RenderContext,
    isMeasuring: Bool
) -> A {
    let transaction = context.environment.transaction
    let animation = context.environment.canAnimate ? transaction.effectiveAnimation : nil
    let drawn = storage.animations.value(
        for: key,
        target: value.animatableData,
        animation: animation,
        nowNanos: context.environment.frameNowNanos,
        isMeasuring: isMeasuring)
    guard drawn != value.animatableData else { return value }

    // The subtree's appearance is now a function of time, which a value memo
    // cannot reproduce from a cached buffer — it would freeze the animation on
    // its first frame. Same declaration `requestAnimation` makes, for the same
    // reason.
    context.environment.volatileReadTracker?.recordRenderSideEffect()

    var copy = value
    copy.animatableData = drawn
    return copy
}

/// Which view types are known not to be ``Animatable``.
///
/// A negative cache, like `StateBindingCache.typesWithoutState`: the answer is a
/// property of the type, so it is asked once. Named for what it holds rather
/// than for what it is, because a hit means "nothing to do here".
///
/// Direct-mapped on the metadata pointer rather than a `Set`, because this is
/// consulted once per view per walk — the single most-executed lookup the
/// animation machinery adds — and a `Set` would hash the pointer through
/// SipHash to answer a question a load and a compare can answer. A paired A/B
/// measured the hashed version at **+0.6% [+0.1%, +1.0%] on `table`**, which is
/// small, real, and paid by every app whether or not it animates anything.
///
/// A collision costs a repeated conformance check, never a wrong answer: a slot
/// answers only for the exact pointer stored in it, and `0` is not a valid
/// metadata address so an empty slot always misses.
@MainActor
private enum AnimatableTypeCache {
    /// Power of two, so the index is a mask rather than a division. 512 slots
    /// is 4 KB and comfortably more than the distinct view types a frame
    /// touches, so in practice the table settles with no collisions at all.
    private static let slotCount = 512

    private static var slots = [UInt](repeating: 0, count: slotCount)

    /// Type metadata is at least 8-byte aligned, so the low three bits are
    /// always zero and carry nothing to index on.
    private static func slot(_ bits: UInt) -> Int { Int((bits >> 3) % UInt(slotCount)) }

    static func isKnownInert(_ typeID: ObjectIdentifier) -> Bool {
        slots[slot(typeID.rawBits)] == typeID.rawBits
    }

    static func noteInert(_ typeID: ObjectIdentifier) {
        slots[slot(typeID.rawBits)] = typeID.rawBits
    }
}

extension ObjectIdentifier {
    /// The raw address this identifier wraps.
    ///
    /// `ObjectIdentifier` exposes no bit pattern, and its `hashValue` is a
    /// SipHash of the address — the very cost being avoided. `unsafeBitCast` to
    /// `UInt` is exact: the type is a single pointer-sized field, and the
    /// standard library's own `init(bitPattern:)` on `UInt` (the reverse
    /// direction) documents that layout.
    fileprivate var rawBits: UInt { unsafeBitCast(self, to: UInt.self) }
}
