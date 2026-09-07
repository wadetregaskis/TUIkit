//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheScratch.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The memory policy for one of ``RenderCache``'s per-pass scratch
/// dictionaries: clear it every pass, and every so often give its buffer back
/// when the pass that sized it is long gone.
///
/// `removeAll(keepingCapacity: true)` is the right instinct for a scratch space
/// — a dictionary refilled every frame should not reallocate every frame — but
/// it means the capacity is the largest frame the process has EVER had, and the
/// largest frame is almost always the first. Nothing is memoized on frame one,
/// so every row is measured and every measurement stored; from frame two the
/// buffer memo answers most of the tree and the measure memo holds a fraction of
/// what it did. Entries at the end of frame 1 against the steady state, over the
/// stress scenarios:
///
///     kitchensink  14,493 -> 26        modifiers  22,562 -> 809
///     fanout       28,009 -> 4,009     anyview     8,508 -> 1,009
///
/// So `kitchensink` held a dictionary sized for fourteen thousand entries in
/// order to store twenty-six, for the life of the process. `deep` and
/// `gradients`, whose frames really are all the same size, keep their capacity
/// and pay nothing for this.
struct ScratchTrimmer {
    /// The most the dictionary has held since the last time the policy looked.
    private var peak = 0

    /// Passes remaining before it looks again.
    private var passesUntilTrim = Self.interval

    /// How often the dictionary is checked against what it is actually holding
    /// — a couple of seconds of frames, so a page that settles gives its first
    /// frame's buffer back promptly and one that keeps needing the room
    /// re-grows at most this often.
    private static let interval = 120

    /// How much a shrink has to be worth before it is taken.
    ///
    /// Not a micro-optimisation — it is the correction to a first cut that did
    /// not have one. Shrinking a SMALL dictionary and regrowing it leaves a hole
    /// the allocator cannot put the next buffer in, and `textwall` and
    /// `animating`, whose scratch is a few hundred entries, came back **8-9%
    /// BIGGER**. With the floor they are flat, and the scenarios that hold
    /// megabytes still give them back.
    private static let floor = 256 * 1024

    /// Ends a render pass: note what the dictionary held, hand its buffer back
    /// if it is holding far more room than it needs, and empty it.
    mutating func endOfPass<Key, Value>(_ dictionary: inout [Key: Value]) {
        peak = max(peak, dictionary.count)
        passesUntilTrim -= 1
        if passesUntilTrim <= 0 {
            passesUntilTrim = Self.interval
            shrink(&dictionary)
            peak = 0
        }
        dictionary.removeAll(keepingCapacity: true)
    }

    /// Replaces the buffer with one sized for the recent peak, when it is
    /// holding room for several times that AND the difference is worth a
    /// megabyte-scale allocation.
    ///
    /// A fresh empty dictionary is how a buffer is released:
    /// `removeAll(keepingCapacity: false)` keeps the storage object, and
    /// `reserveCapacity` only ever grows.
    ///
    /// Reserving half again as much as the peak rather than exactly it, so a
    /// pass that grows a little does not have to reallocate. Half and not
    /// double, because a `Dictionary` rounds its bucket count up to a power of
    /// two at a 75% load factor: `fanout`'s 4,009-entry peak asks for 8,192
    /// buckets at either 1x or 1.5x and for 16,384 at 2x, so doubling bought no
    /// extra headroom at all and cost **1.74 MB against 868 KB**.
    private func shrink<Key, Value>(_ dictionary: inout [Key: Value]) {
        let wanted = max(16, peak)
        guard dictionary.capacity > 4 * wanted else { return }
        let reserve = wanted + wanted / 2
        let perBucket = MemoryLayout<Key>.stride + MemoryLayout<Value>.stride
        guard (dictionary.capacity - reserve) * perBucket >= Self.floor else { return }
        dictionary = Dictionary(minimumCapacity: reserve)
    }
}
