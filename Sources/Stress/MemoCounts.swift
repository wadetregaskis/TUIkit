//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MemoCounts.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// What the per-pass memos did over the frames a bench timed: the measure
/// memo's lookups, hits, misses and stores, and the child-views memo's hits
/// and misses.
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
    var childViewsHits = 0
    var childViewsMisses = 0

    init() {}

    /// The totals `cache` has counted so far.
    @MainActor
    init(_ cache: RenderCache?) {
        guard let cache else { return }
        measureHits = cache.measureMemoTotals.hits
        measureMisses = cache.measureMemoTotals.misses
        measureStores = cache.measureMemoStores
        childViewsHits = cache.childViewsMemoTotals.hits
        childViewsMisses = cache.childViewsMemoTotals.misses
    }

    /// Adds what the counts moved by between `before` and `after`.
    mutating func add(from before: Self, to after: Self) {
        measureHits += after.measureHits - before.measureHits
        measureMisses += after.measureMisses - before.measureMisses
        measureStores += after.measureStores - before.measureStores
        childViewsHits += after.childViewsHits - before.childViewsHits
        childViewsMisses += after.childViewsMisses - before.childViewsMisses
    }

    /// One line, per frame over `frames`.
    func report(frames: Int) -> String {
        let divisor = Double(max(1, frames))
        let perFrame = { (count: Int) in String(format: "%.1f", Double(count) / divisor) }
        return "  memos/frame: measure \(perFrame(measureHits + measureMisses)) lookups, "
            + "\(perFrame(measureHits)) hits, \(perFrame(measureMisses)) misses, "
            + "\(perFrame(measureStores)) stores; child views \(perFrame(childViewsHits + childViewsMisses)) "
            + "lookups, \(perFrame(childViewsHits)) hits"
    }
}
