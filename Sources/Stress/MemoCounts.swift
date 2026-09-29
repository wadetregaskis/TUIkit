//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoCounts.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// What the per-pass memos did over the frames a bench timed: the measure
/// memo's lookups, hits, misses and stores, and the child-views memo's hits
/// and misses — and, for each, the views it could not key at all, whose
/// value the hash cannot read (`ValueHashPlan.Shape.bypass`): measured or
/// resolved every time, neither looked up nor kept.
///
/// Counts rather than times, and that is the point: a change to how the memos
/// key a view is judged first by whether it serves the same answers as often
/// or more — which any machine can say, loaded or not — and only then by what
/// it costs, which only a quiet one can. Summed frame by frame, around each
/// render and outside the timed region, so a `--cold` run (a fresh cache each
/// frame) counts every frame too and the warm-up counts in neither.
struct MemoCounts {
    var measureHits = 0
    var measureMisses = 0
    var measureStores = 0
    var measureBypasses = 0
    var childViewsHits = 0
    var childViewsMisses = 0
    var childViewsBypasses = 0

    init() {}

    /// The totals `cache` has counted so far.
    @MainActor
    init(_ cache: RenderCache?) {
        guard let cache else { return }
        measureHits = cache.measureMemoTotals.hits
        measureMisses = cache.measureMemoTotals.misses
        measureStores = cache.measureMemoStores
        measureBypasses = cache.measureMemoBypasses
        childViewsHits = cache.childViewsMemoTotals.hits
        childViewsMisses = cache.childViewsMemoTotals.misses
        childViewsBypasses = cache.childViewsMemoBypasses
    }

    /// Adds what the counts moved by between `before` and `after`.
    mutating func add(from before: Self, to after: Self) {
        measureHits += after.measureHits - before.measureHits
        measureMisses += after.measureMisses - before.measureMisses
        measureStores += after.measureStores - before.measureStores
        measureBypasses += after.measureBypasses - before.measureBypasses
        childViewsHits += after.childViewsHits - before.childViewsHits
        childViewsMisses += after.childViewsMisses - before.childViewsMisses
        childViewsBypasses += after.childViewsBypasses - before.childViewsBypasses
    }

    /// Prints the value hash's census for `cache` — lookups by the shape of the
    /// plan that answered them, and the types that stepped or bypassed —
    /// warm-up included. Only in a build with `-DTUIKIT_VALUE_HASH_CENSUS`,
    /// which is the only build that counts it; otherwise nothing.
    @MainActor
    static func printValueHashCensus(of cache: RenderCache?) {
        #if TUIKIT_VALUE_HASH_CENSUS
        for line in cache?.valueHashPlans.census.report() ?? [] { print("  " + line) }
        #endif
    }

    /// One line, per frame over `frames`.
    func report(frames: Int) -> String {
        let divisor = Double(max(1, frames))
        let perFrame = { (count: Int) in String(format: "%.1f", Double(count) / divisor) }
        return "  memos/frame: measure \(perFrame(measureHits + measureMisses)) lookups, "
            + "\(perFrame(measureHits)) hits, \(perFrame(measureMisses)) misses, "
            + "\(perFrame(measureStores)) stores, \(perFrame(measureBypasses)) unkeyed; "
            + "child views \(perFrame(childViewsHits + childViewsMisses)) lookups, "
            + "\(perFrame(childViewsHits)) hits, \(perFrame(childViewsBypasses)) unkeyed"
    }
}
