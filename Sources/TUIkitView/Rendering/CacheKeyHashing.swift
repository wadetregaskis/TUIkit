//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CacheKeyHashing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Mixes one more word into a running hash.
///
/// FNV-style multiply-xor with a shift-fold, for building a composite cache
/// key's hash out of its fields before any of it reaches `Hasher`.
///
/// The point is what it saves rather than what it is. Swift's synthesised
/// `hash(into:)` feeds every stored property to the hasher in turn, and
/// `Hasher` is SipHash-1-3: it absorbs eight bytes per round, so a key of seven
/// fields costs seven rounds where one would do. These keys are probed a couple
/// of thousand times a frame — the measure memo alone runs ~2,000 lookups on a
/// `menus` frame — and none of them has an adversary: they are process-local
/// cache keys, not a hash table exposed to untrusted input. So the fields are
/// folded here and the result handed to `Hasher` as a single value, which keeps
/// the conformance honest (still seeded, still `Hashable`) at one round.
@inline(__always)
func mixHashWord(_ accumulated: UInt64, _ value: UInt64) -> UInt64 {
    var mixed = (accumulated ^ value) &* 0x0000_0100_0000_01b3
    mixed ^= mixed >> 29
    return mixed
}

/// The splitmix64 finalizer: avalanches the low bits, which is where a
/// `Dictionary` takes its bucket from.
@inline(__always)
func finalizeHashWord(_ value: UInt64) -> Int {
    var mixed = value
    mixed ^= mixed >> 30
    mixed = mixed &* 0xbf58_476d_1ce4_e5b9
    mixed ^= mixed >> 27
    mixed = mixed &* 0x94d0_49bb_1331_11eb
    mixed ^= mixed >> 31
    return Int(bitPattern: UInt(mixed))
}

/// The seed every fold starts from — FNV's offset basis.
let hashFoldSeed: UInt64 = 0xcbf2_9ce4_8422_2325
