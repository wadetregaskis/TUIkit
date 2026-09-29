//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHash.swift
//
//  The per-pass memos' value hash: what tells two values of one view type
//  apart inside a render pass.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Hashes a view's value, to tell two values of one type apart inside a single
/// render pass — or `nil` when the value cannot be hashed, and the memo that
/// asked must measure it without looking it up or keeping it.
///
/// `measureChild` is generic over `V: View` and so cannot demand `Equatable`,
/// which is why the only value-keyed memo in the tree sits behind
/// `EquatableView`. The value's storage is the conformance-free substitute: no
/// reflection per value (which would cost what the memo saves), just the
/// struct's own bytes, which for a view is a handful of words.
///
/// **But only the bytes the value defines.** A struct's padding, the payload
/// an enum's other case left behind, the words of an existential's buffer its
/// payload does not fill, the half of an optional that its `nil` does not
/// write: none of those is written when the value is, so each holds whatever
/// the memory held before. Hashing them split equal values — differently on
/// each platform and run, so Linux missed where macOS hit — and reading them
/// at all is reading uninitialised memory. So each type is hashed by its
/// ``ValueHashPlan``, built once from the type alone: runs of bytes that every
/// value defines, and the parts only typed Swift can read (an optional's case,
/// a conditional's branch, an existential's payload), read by typed Swift.
/// A type with neither padding nor such a part — most views — is hashed as it
/// lies, word by word; a type holding something neither can read bypasses.
///
/// See ``RenderCache/MeasureKey/valueHash`` for why a value's defined bytes
/// are sound within a pass but were not across frames.
///
/// `Hasher` is the obvious spelling and the wrong one here. It is SipHash-1-3 —
/// keyed, randomised per process, and built to resist an adversary choosing
/// collisions. Nothing here has an adversary: this is a discriminator inside a
/// per-pass memo whose key ALSO carries the identity's hash, the view's type
/// and two widths. What it is, is hot — a whole-struct hash on every measured
/// child, **3.4% of a `menus` frame between this and the `withUnsafeBytes`
/// around it**. So: FNV-style mixing over whole words with a splitmix64
/// finalizer, which avalanches the low bits a `Dictionary` probes on. A side
/// effect worth having is that it is deterministic — `Hasher`'s seed is
/// randomised per process, so the memo's key stream (and any bug that depends
/// on it) differed run to run.
@MainActor
func viewValueHash<V: View>(_ view: V, plans: ValueHashPlans) -> Int? {
    // One lookup and one branch, and the dense loop inline: the shape of the
    // hash before plans, which was arrived at by measurement. `measureChild`
    // is generic and public, so a caller in another module does not
    // specialise it; `V.self == AnyView.self` in place of the witness this
    // lookup replaces cost `deep` +2.7% and `modifiers` +4.6%, and hoisting
    // the loop into a second function so the gate could `return` it cost
    // another point. Only a plan that is not dense leaves the function.
    let plan = plans.plan(for: V.self)
    if plan.pointee.shape != .dense { plans.armStackCheck() }
    let hash = valueHash(of: view, plan: plan, plans: plans)
    #if TUIKIT_VALUE_HASH_CENSUS
    plans.census.note(V.self, plan: plan, hashed: hash != nil)
    #endif
    return hash
}

/// The body of ``viewValueHash(_:plans:)``, in a function of its own only to
/// be NONISOLATED: written in the `@MainActor` function, the closure handed to
/// `withUnsafeBytes` would be isolated too, and Swift 6 checks the executor on
/// entry to such a closure — every hash of every measured view (see
/// ``ValueHashPlans``). Always inlined, so it is still the one function the
/// hot path's shape was measured as.
@inline(__always)
private func valueHash<V: View>(of view: V, plan: UnsafePointer<ValueHashPlan>, plans: ValueHashPlans) -> Int? {
    withUnsafeBytes(of: view) { bytes in
        guard plan.pointee.shape == .dense else {
            // Not dense, so not empty: the value has bytes, and an address.
            return plans.hashByPlan(bytes.baseAddress.unsafelyUnwrapped, plan)
        }
        return hashOfRawBytes(bytes)
    }
}

/// ``viewValueHash(_:plans:)`` of the value at `value`, read where it lies,
/// by `cache`'s plans.
///
/// A test's seam, and the reason it takes a pointer rather than a value: what
/// the hash must not read is the bytes a value's fields do not cover, and a
/// test can only put something there by writing into memory the value
/// occupies. A value passed by copy would arrive with whatever the copy wrote
/// in those bytes instead of what the test poked.
@MainActor
package func viewValueHash<V: View>(at value: UnsafePointer<V>, in cache: RenderCache) -> Int? {
    cache.valueHashPlans.valueHash(at: value)
}

/// The hash of `bytes`, word by word, with the tail packed into one last word
/// — every byte of a dense value.
///
/// Always inlined: the hot path's shape — the loop in the function that tests
/// the gate — was measured, and a call here would be the second function it
/// was measured against.
@inline(__always)
func hashOfRawBytes(_ bytes: UnsafeRawBufferPointer) -> Int {
    var hash = hashFoldSeed
    let count = bytes.count
    var index = 0
    while index + 8 <= count {
        hash = mixHashWord(hash, bytes.loadUnaligned(fromByteOffset: index, as: UInt64.self))
        index += 8
    }
    // The tail, packed into one word so a short struct still mixes every
    // byte it has. A view is a handful of words, so this runs at most once.
    if index < count {
        var tail: UInt64 = 0
        var shift: UInt64 = 0
        while index < count {
            tail |= UInt64(bytes[index]) &<< shift
            shift &+= 8
            index += 1
        }
        hash = mixHashWord(hash, tail)
    }
    return finalizeHashWord(hash)
}
