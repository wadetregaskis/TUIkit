//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette+AdaptiveReseeding.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Entries a least-error palette spent on nothing

extension ASCIIPalette.Histogram {

    /// `chosen` with each entry no bucket is nearest to exchanged for the
    /// unclaimed lattice colour that lowers the error the most, where one does.
    ///
    /// Reported on the Images page: a "Least error" count at 256 colours drew
    /// the identical picture at 25, 26 and 27, and again at 30 and 31; at 16
    /// colours, at 6 to 9. Every step had bought a distinct entry. The extras
    /// were colours no pixel was nearest to.
    ///
    /// Such an entry comes out of `snapping(_:)`. It keeps the set distinct by
    /// handing a centre that collided with another its nearest UNCLAIMED
    /// lattice colour, and that colour can be far from every bucket. Nothing
    /// maps to it, so `refine(_:)` has no mean to move it to, re-snapping puts
    /// it straight back, and the loop settles on an entry that draws nothing
    /// while a colour some pixels would be drawn in is left out.
    ///
    /// So, once the loop has settled, each dead entry in turn is exchanged for
    /// the unclaimed colour with the largest gain,
    /// Σ weight · max(0, d²(bucket, its nearest entry) − d²(bucket, candidate)),
    /// the lower index on a tie. One at a time, against the set the earlier
    /// exchanges left, so no two claim one colour or count the same buckets
    /// twice.
    ///
    /// Where no unclaimed colour has any gain, the entry is KEPT. That is a
    /// palette past its ceiling: every colour some bucket is nearest to is in
    /// it already, the error is as low as the lattice allows, and whatever more
    /// was asked for has nothing to draw. The count asked for is still the
    /// count answered, so 240 asked for at 256 colours is still `.ansi256`.
    ///
    /// Not a guarantee. It runs once, and an exchange can in principle take
    /// every bucket from another entry and leave that one dead in turn. That
    /// has not been seen on `AdaptivePaletteTests`' fixtures, which pin the
    /// property. The unconstrained derivation is untouched.
    func reseedingDeadEntries(_ chosen: [Int], within lattice: ASCIIPalette) -> [Int] {
        guard chosen.count > 1, lattice.entries.count > chosen.count else { return chosen }
        let labs = lattice.entries.indices.map { lattice.labOfEntry($0) }
        var chosen = chosen
        var nearest = [Double](repeating: .infinity, count: buckets.count)
        var weight = [Int](repeating: 0, count: chosen.count)
        // One assignment pass: each bucket's squared distance to its nearest
        // entry, and each entry's weight. Written as `refine(_:)` is, over
        // borrowed buffers with the arithmetic spelt out, for the reason given
        // there.
        buckets.withUnsafeBufferPointer { buckets in
            labs.withUnsafeBufferPointer { labs in
                chosen.withUnsafeBufferPointer { chosen in
                    var bucketIndex = 0
                    for bucket in buckets {
                        var best = 0
                        var bestDistance = Double.infinity
                        var slot = 0
                        for entry in chosen {
                            let deltaL = bucket.lab.l - labs[entry].l
                            let deltaA = bucket.lab.a - labs[entry].a
                            let deltaB = bucket.lab.b - labs[entry].b
                            let distance = deltaL * deltaL + deltaA * deltaA + deltaB * deltaB
                            if distance < bestDistance {
                                bestDistance = distance
                                best = slot
                            }
                            slot += 1
                        }
                        nearest[bucketIndex] = bestDistance
                        weight[best] += bucket.weight
                        bucketIndex += 1
                    }
                }
            }
        }
        let dead = weight.indices.filter { weight[$0] == 0 }
        guard !dead.isEmpty else { return chosen }

        // Every unclaimed colour's gain, walked ONCE rather than once per
        // exchange. An exchange only ever shortens `nearest`, so no gain can
        // grow: a gain from before one is an upper bound on the gain after.
        // A candidate whose gain is `current` and still ranks first against
        // every other bound therefore ranks first against every true gain,
        // and is exactly the colour a full rescan would pick. Measured with
        // `ImageHarness --path palette --mode optimal64 --depth ansi256`,
        // release, per derivation: 0.55 ms with no exchange at all, 2.25 ms
        // rescanning the lattice for every dead entry, 1.03 ms like this.
        //
        // A claimed colour gains nothing and stays at zero, and so does the
        // dead entry an exchange gives back: no bucket was nearer to it than to
        // the entry it took, and nothing gets farther.
        let claimed = Set(chosen)
        var gains = labs.indices.map { claimed.contains($0) ? 0 : gain(of: labs[$0], against: nearest) }
        var current = [Bool](repeating: true, count: labs.count)
        exchanging: for slot in dead {
            var entry = 0
            while true {
                var top = -1
                var topGain = 0.0
                for candidate in gains.indices where gains[candidate] > topGain {
                    top = candidate
                    topGain = gains[candidate]
                }
                // Nothing gains anything, and nothing will after an exchange
                // either, so the rest of the dead entries are kept.
                guard top >= 0 else { break exchanging }
                if current[top] {
                    entry = top
                    break
                }
                gains[top] = gain(of: labs[top], against: nearest)
                current[top] = true
            }
            chosen[slot] = entry
            gains[entry] = 0
            current = [Bool](repeating: false, count: labs.count)
            let lab = labs[entry]
            buckets.withUnsafeBufferPointer { buckets in
                var bucketIndex = 0
                for bucket in buckets {
                    let deltaL = bucket.lab.l - lab.l
                    let deltaA = bucket.lab.a - lab.a
                    let deltaB = bucket.lab.b - lab.b
                    nearest[bucketIndex] = min(
                        nearest[bucketIndex], deltaL * deltaL + deltaA * deltaA + deltaB * deltaB)
                    bucketIndex += 1
                }
            }
        }
        return chosen
    }

    /// How much the weighted squared error falls if `lab` joins a set whose
    /// squared distance from each bucket is `nearest`.
    private func gain(of lab: (l: Double, a: Double, b: Double), against nearest: [Double]) -> Double {
        var gain = 0.0
        buckets.withUnsafeBufferPointer { buckets in
            nearest.withUnsafeBufferPointer { nearest in
                var bucketIndex = 0
                for bucket in buckets {
                    let deltaL = bucket.lab.l - lab.l
                    let deltaA = bucket.lab.a - lab.a
                    let deltaB = bucket.lab.b - lab.b
                    let distance = deltaL * deltaL + deltaA * deltaA + deltaB * deltaB
                    if distance < nearest[bucketIndex] {
                        gain += Double(bucket.weight) * (nearest[bucketIndex] - distance)
                    }
                    bucketIndex += 1
                }
            }
        }
        return gain
    }
}
