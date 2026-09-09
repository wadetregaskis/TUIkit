//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette+Adaptive.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitStyling

// MARK: - Choosing the colours from the picture

extension ASCIIPalette {

    /// How an ``ASCIIPalette/adaptive(_:by:target:)`` palette picks its colours out of
    /// the picture it is drawing.
    ///
    /// Both answer "which `n` colours", and they disagree because they are
    /// answering different questions — which is the point of offering both
    /// rather than picking the better one.
    public enum Adaptation: Sendable, Equatable, CaseIterable {
        /// The `n` colours the most pixels ARE.
        ///
        /// The classic popularity algorithm, and deliberately the naive one: it
        /// is a ranking, so it says what the picture is mostly made of and
        /// nothing about what it loses. Its known failure is clustering — the
        /// top entries of a photograph are often near-identical shades of the
        /// one dominant colour, and a small bright subject can be missed
        /// entirely however much it matters to the picture. That is a look, and
        /// it is the one people mean by "the image's own colours".
        case popularity

        /// The `n` colours that leave the picture closest to itself.
        ///
        /// Minimises the total squared OKLab distance between every pixel and
        /// the entry it maps to — the quantity a person reads as "how wrong
        /// does this look". Median cut for the starting set, then Lloyd's
        /// iteration to settle it.
        ///
        /// **It is an optimiser, not a fairness rule, and the difference shows
        /// on exactly the case people expect it to fix.** A 1%-of-the-frame
        /// saturated red patch against a graded near-neutral field is dropped at
        /// 4, 6 and 8 colours — and dropping it is *correct*: forcing it in
        /// costs more total error than the entry it would displace, measured
        /// (0.0275 against 0.0252 at eight). By twelve it is picked up on its
        /// own, because by then the field is served well enough that the patch
        /// is the biggest thing left wrong. ``popularity`` never reaches it at
        /// any count, because a graded field has more populous cells all the way
        /// up.
        ///
        /// So this is the one to reach for when the picture should look like
        /// itself, and ``popularity`` is the one for "draw it in its own
        /// colours" as a look. Neither is the better algorithm.
        case leastError
    }

    /// A palette of `count` colours taken from whatever picture it is asked to
    /// draw, rather than chosen in advance.
    ///
    /// Every other palette here is a set of colours the app decided on. This one
    /// cannot be: it is a QUESTION about a picture, and the answer arrives when
    /// ``derived(from:depth:)`` is handed one — which the converters do, once per
    /// conversion, right after the tone curve has run, so the colours are chosen
    /// from the picture as it will actually be drawn rather than as it arrived.
    ///
    /// Until then it stands in as `count` greys, so a palette that never meets
    /// an image renders the picture rather than nothing.
    ///
    /// The result holds AT MOST `count` colours: a picture with fewer distinct
    /// colours than that has fewer to find, and inventing the difference would
    /// be inventing colours the picture does not contain.
    ///
    /// - Parameters:
    ///   - count: How many colours. Clamped to at least one.
    ///   - method: Which `count` — see ``Adaptation``.
    ///   - target: Which colours it may choose from — see ``AdaptationTarget``.
    ///     ``AdaptationTarget/automatic`` follows the output, which is what a
    ///     palette meant to spend the terminal's colours well wants.
    public static func adaptive(
        _ count: Int, by method: Adaptation, target: AdaptationTarget = .automatic
    ) -> Self {
        let count = max(1, count)
        return Self(shades(count).colors, mapping: .nearestColor,
                    adaptive: Adaptive(method: method, count: count, target: target))
    }

    /// This palette with its colours chosen from `image`, or itself if its
    /// colours were never in question.
    ///
    /// The result is an ORDINARY palette — the derivation happens once and the
    /// answer is a fixed set of colours — so everything downstream (the
    /// quantisation table, `nearestIndex(to:)`, the dither) is unchanged and
    /// unaware.
    ///
    /// - Parameters:
    ///   - image: The picture to take the colours from, as it will be DRAWN:
    ///     after any tone curve and edge lift, before anything quantises.
    ///   - depth: What the output can draw, which
    ///     ``AdaptationTarget/automatic`` follows. Asked for rather than read
    ///     from ``ColorDepth/current`` because the answer is per-call-site: the
    ///     same picture drawn as terminal graphics is a field of RGB pixels
    ///     whatever the terminal's SGR depth. See ``AdaptationTarget``.
    public func derived(from image: RGBAImage, depth: ColorDepth) -> Self {
        guard let adaptive, !image.pixels.isEmpty else { return self }
        let histogram = Histogram(of: image)
        guard !histogram.buckets.isEmpty else { return self }
        // `nil` where the target can draw whatever is chosen, which is the one
        // case with nothing to constrain.
        let lattice = Self.representable(at: adaptive.target.resolved(for: depth))
        let chosen: [Color]
        switch adaptive.method {
        case .popularity: chosen = histogram.mostPopular(adaptive.count, within: lattice)
        case .leastError: chosen = histogram.leastError(adaptive.count, within: lattice)
        }
        guard !chosen.isEmpty else { return self }
        return Self(chosen, mapping: mapping)
    }

    // MARK: - The histogram both methods read

    /// The picture reduced to its populated colour cells, which is what makes
    /// either method affordable: a megapixel becomes a few thousand weighted
    /// points, and every pass after this one is over those.
    ///
    /// The cells are ``ASCIIPalette/quantisationBucket``'s — five bits a
    /// channel, spaced by the cube root of linear light rather than by byte, so
    /// the shadows (where sRGB's transfer function is steep and the eye is
    /// sharpest) are not lumped into a handful of cells. That is the same
    /// spacing the quantisation table uses, and for the same reason.
    struct Histogram {
        /// One populated cell: how many pixels, their mean colour, and that
        /// colour in OKLab.
        struct Bucket {
            let weight: Int
            let rgba: RGBA
            let lab: (l: Double, a: Double, b: Double)
        }

        /// What one cell accumulates: how many pixels landed in it and the sum
        /// of their channels, so the mean can be taken at the end.
        ///
        /// One array of these rather than four arrays of `Int` — the same
        /// numbers, but one index computed per pixel instead of four, and the
        /// four a pixel touches adjacent rather than a megabyte apart.
        private struct Total {
            var weight = 0
            var red = 0
            var green = 0
            var blue = 0
        }

        let buckets: [Bucket]

        init(of image: RGBAImage) {
            var totals = [Total](repeating: Total(), count: ASCIIPalette.quantisationCells)
            // Borrowed buffers and one accumulator per cell, for the reason
            // `nearestIndex(to:)` borrows its entries: this walks every
            // PIXEL — a megapixel for a graphics-protocol placement — and
            // where no optimiser runs, `for pixel in image.pixels` is a
            // protocol-witness call per pixel, every `Array` subscript is a
            // bounds check, and every `+=` into one is a uniqueness check.
            // Measured on a 960×850 picture, `.popularity` at 8, whole
            // derivation: 106 ms as it stood, 90 ms with the four arrays folded
            // into one and the checks gone, 27 ms once the walk was the
            // buffer's own iterator instead of a `Range`'s — the same loop, but
            // a `Range` is iterated through a protocol witness per step.
            //
            // The cell arithmetic is `ASCIIPalette.quantisationCell(for:)`'s,
            // spelt out here against a borrowed table rather than called: the
            // call is three accesses to a `static let` array per pixel, each
            // with its one-time-initialisation check. It must stay in step with
            // that function, which is why both name `quantisationBits`.
            let bits = ASCIIPalette.quantisationBits
            image.pixels.withUnsafeBufferPointer { pixels in
                ASCIIPalette.quantisationBucket.withUnsafeBufferPointer { channelBucket in
                    totals.withUnsafeMutableBufferPointer { totals in
                        for pixel in pixels {
                            let cell = (Int(channelBucket[Int(pixel.r)]) << (2 * bits))
                                | (Int(channelBucket[Int(pixel.g)]) << bits)
                                | Int(channelBucket[Int(pixel.b)])
                            totals[cell].weight += 1
                            totals[cell].red += Int(pixel.r)
                            totals[cell].green += Int(pixel.g)
                            totals[cell].blue += Int(pixel.b)
                        }
                    }
                }
            }
            var populated: [Bucket] = []
            for total in totals where total.weight > 0 {
                let count = total.weight
                let rgba = RGBA(
                    r: UInt8(clamping: total.red / count),
                    g: UInt8(clamping: total.green / count),
                    b: UInt8(clamping: total.blue / count))
                populated.append(
                    Bucket(
                        weight: count, rgba: rgba,
                        lab: Color.oklab(red: rgba.r, green: rgba.g, blue: rgba.b)))
            }
            self.buckets = populated
        }

        /// The `count` heaviest cells' colours, heaviest first.
        ///
        /// Within `lattice` — the colours the output can draw — the ranking is
        /// walked past the cells whose colour the output has already spent: two
        /// popular cells a third of a cube step apart ARE one colour there, and
        /// counting them twice is what made asking for five give four. Walking
        /// on finds a fifth colour that is genuinely a fifth colour, which is
        /// the whole of the fix on this method.
        func mostPopular(_ count: Int, within lattice: ASCIIPalette?) -> [Color] {
            // Ties broken by the colour itself so a picture always answers the
            // same palette — two cells of equal weight are common in flat art,
            // and an unstable order would make the same image quantise
            // differently on different runs.
            let ranked = buckets.sorted {
                $0.weight != $1.weight
                    ? $0.weight > $1.weight
                    : (Int($0.rgba.r) << 16 | Int($0.rgba.g) << 8 | Int($0.rgba.b))
                        < (Int($1.rgba.r) << 16 | Int($1.rgba.g) << 8 | Int($1.rgba.b))
            }
            guard let lattice else {
                return ranked.prefix(count).map { .rgb($0.rgba.r, $0.rgba.g, $0.rgba.b) }
            }
            var chosen: [Color] = []
            var taken: Set<Int> = []
            for bucket in ranked {
                // The NEAREST entry, not the nearest unclaimed one: the cell is
                // that colour on this terminal, and offering it a different one
                // because something more popular got there first would be
                // inventing a colour the picture does not contain — which is the
                // one thing ``ASCIIPalette/adaptive(_:by:target:)`` promises not
                // to do.
                let entry = lattice.nearest(to: bucket.lab, excluding: []).entry
                guard taken.insert(entry).inserted else { continue }
                // `colors` and `entries` are one list twice over, by index.
                chosen.append(lattice.colors[entry])
                if chosen.count == count { break }
            }
            return chosen
        }

        /// `count` colours minimising the weighted squared OKLab distance from
        /// every pixel to the entry it takes.
        ///
        /// Median cut for the starting set, then Lloyd's iteration to settle
        /// it. Median cut alone divides the colours evenly by POPULATION, which
        /// is a decent guess and not a minimum; Lloyd moves each entry to the
        /// weighted centre of what it actually serves, which is exactly the
        /// objective. Seeded rather than random, so the answer is deterministic.
        func leastError(_ count: Int, within lattice: ASCIIPalette?) -> [Color] {
            let count = max(1, min(count, buckets.count))
            var centres = medianCut(into: count)
            // The seed is projected too, so every iterate this returns is a set
            // of colours the output can draw — including the one-colour case
            // below, which never enters the loop.
            var chosen = lattice.map { $0.snapping(centres) } ?? []
            if let lattice { centres = chosen.map { lattice.labOfEntry($0) } }
            guard centres.count > 1 else {
                return Self.colours(centres, chosen: chosen, within: lattice)
            }

            // A budget rather than a fixed number of passes. One pass is
            // `buckets × count` distance evaluations, and both grow with what
            // is asked for: 256 colours out of a photograph's ~20,000 populated
            // cells is 5M per pass, where 8 colours is 160,000. Lloyd converges
            // fast — the first two passes do most of the work — so spending a
            // fixed budget rather than a fixed pass count keeps the worst case
            // bounded without shortchanging the cheap cases.
            let perPass = max(1, buckets.count * centres.count)
            let passes = max(1, min(12, 12_000_000 / perPass))
            for _ in 0..<passes {
                let moved = refine(&centres)
                guard let lattice else {
                    if !moved { break }
                    continue
                }
                // Lloyd, projected: the mean is where the cluster's centre of
                // gravity is, and then the centre goes to the nearest colour the
                // output actually has. Unquantised Lloyd is monotone and this is
                // not — the projection can give back a little of what the mean
                // won — so convergence is tested on the COLOURS rather than on
                // the means, which drift on inside one lattice cell forever. The
                // budget bounds the rest: a set that alternates between two
                // equally good projections would otherwise never settle.
                let previous = chosen
                chosen = lattice.snapping(centres)
                centres = chosen.map { lattice.labOfEntry($0) }
                if chosen == previous { break }
            }
            return Self.colours(centres, chosen: chosen, within: lattice)
        }

        /// The palette entries a settled set of centres names.
        ///
        /// Two spellings, and the difference is not cosmetic: a constrained set
        /// answers with the LATTICE's own colours — `.palette(n)`,
        /// `.standard(.red)` — so the fit that runs after the derivation has
        /// nothing left to change, where a triple carrying the same RGB would be
        /// re-quantised by it. See ``ASCIIPalette/representable(at:)``.
        private static func colours(
            _ centres: [(l: Double, a: Double, b: Double)], chosen: [Int],
            within lattice: ASCIIPalette?
        ) -> [Color] {
            guard let lattice else {
                return centres.map {
                    let rgba = srgb($0)
                    return .rgb(rgba.r, rgba.g, rgba.b)
                }
            }
            return chosen.map { lattice.colors[$0] }
        }

        /// One Lloyd pass. Returns whether anything moved, so a settled set
        /// stops early instead of spending the rest of the budget.
        private func refine(_ centres: inout [(l: Double, a: Double, b: Double)]) -> Bool {
            var sumL = [Double](repeating: 0, count: centres.count)
            var sumA = [Double](repeating: 0, count: centres.count)
            var sumB = [Double](repeating: 0, count: centres.count)
            var weight = [Int](repeating: 0, count: centres.count)
            // The pass is `buckets × centres` distance evaluations — millions
            // of them at 256 colours — so it is written the way
            // `nearestIndex(to:)` is: over borrowed buffers, with the
            // arithmetic spelt out instead of `enumerated()` and a call to
            // `distanceSquared` per centre. Identical comparisons in an
            // identical order, so the answer is identical.
            //
            // What that is worth is a -Onone story rather than an arithmetic
            // one: `EnumeratedSequence.Iterator.next()` was 78% of this
            // derivation's debug profile at 256 colours, nearly all of it
            // runtime lookups of the centre tuple's metadata and the mallocs
            // behind them. The counter is there because `for … in buffer` is
            // markedly cheaper than `for index in 0..<buffer.count` at -Onone,
            // measured on this file's other hot walk (the histogram, 90 ms to
            // 27 ms): a `Range` is iterated through a protocol witness per
            // step, where a buffer has a concrete iterator of its own.
            buckets.withUnsafeBufferPointer { buckets in
                centres.withUnsafeBufferPointer { centres in
                    for bucket in buckets {
                        var best = 0
                        var bestDistance = Double.infinity
                        var index = 0
                        for centre in centres {
                            let deltaL = bucket.lab.l - centre.l
                            let deltaA = bucket.lab.a - centre.a
                            let deltaB = bucket.lab.b - centre.b
                            let distance = deltaL * deltaL + deltaA * deltaA + deltaB * deltaB
                            if distance < bestDistance {
                                bestDistance = distance
                                best = index
                            }
                            index += 1
                        }
                        let w = Double(bucket.weight)
                        sumL[best] += bucket.lab.l * w
                        sumA[best] += bucket.lab.a * w
                        sumB[best] += bucket.lab.b * w
                        weight[best] += bucket.weight
                    }
                }
            }
            var moved = false
            for index in centres.indices where weight[index] > 0 {
                let w = Double(weight[index])
                let next = (l: sumL[index] / w, a: sumA[index] / w, b: sumB[index] / w)
                if ASCIIPalette.distanceSquared(next, centres[index]) > 1e-12 { moved = true }
                centres[index] = next
            }
            // An entry nothing maps to is left where it is rather than dropped:
            // the caller asked for `count` colours, and a palette that quietly
            // returned fewer would make the slider's steps do nothing, which is
            // the very complaint this whole feature answers.
            return moved
        }

        /// A box of the histogram, with the numbers the split loop asks for
        /// computed ONCE at construction.
        ///
        /// They were derived on demand at first, which is quadratic in disguise:
        /// choosing which box to split reads every box's cost, and every read
        /// walked that box's contents and allocated three arrays to do it. At
        /// 256 colours over a photograph's ~20,000 populated cells that is the
        /// whole of the derivation's cost. A box is built twice — once when it
        /// is created — and read `count` times.
        private struct Box {
            let contents: [Bucket]
            let weight: Int
            let axis: Int
            /// Worth splitting: the widest extent times the weight. Spread alone
            /// splits a handful of outlying pixels off from each other while a
            /// thousand pixels go on sharing one entry.
            let cost: Double

            init(_ contents: [Bucket]) {
                var weight = 0
                // Six scalars rather than two 3-tuples rebuilt per bucket. A
                // bucket is walked here again every time the box holding it is
                // split, so this is one of the two loops median cut spends
                // itself in — and at -Onone rebuilding a tuple per bucket is a
                // value copy where assigning a `Double` is a register.
                var lowL = Double.infinity
                var lowA = Double.infinity
                var lowB = Double.infinity
                var highL = -Double.infinity
                var highA = -Double.infinity
                var highB = -Double.infinity
                for bucket in contents {
                    weight += bucket.weight
                    lowL = min(lowL, bucket.lab.l)
                    lowA = min(lowA, bucket.lab.a)
                    lowB = min(lowB, bucket.lab.b)
                    highL = max(highL, bucket.lab.l)
                    highA = max(highA, bucket.lab.a)
                    highB = max(highB, bucket.lab.b)
                }
                let spread = (highL - lowL, highA - lowA, highB - lowB)
                self.contents = contents
                self.weight = weight
                self.axis = spread.0 >= spread.1 && spread.0 >= spread.2
                    ? 0 : (spread.1 >= spread.2 ? 1 : 2)
                self.cost = contents.count > 1
                    ? max(spread.0, max(spread.1, spread.2)) * Double(weight)
                    : 0
            }
        }

        /// `count` starting centres: split the box holding the most weighted
        /// spread, along its own widest axis, at its weighted median.
        private func medianCut(into count: Int) -> [(l: Double, a: Double, b: Double)] {
            var boxes: [Box] = [Box(buckets)]
            while boxes.count < count {
                guard let target = boxes.indices.max(by: { boxes[$0].cost < boxes[$1].cost }),
                    boxes[target].cost > 0
                else { break }
                let box = boxes[target]
                // The axis is chosen ONCE, here, rather than inside the
                // comparison: `sorted(by:)` calls its closure n log n times,
                // and one that has to ask which axis it is on pays a call and a
                // switch for every one of them.
                let sorted: [Bucket]
                switch box.axis {
                case 0: sorted = box.contents.sorted { $0.lab.l < $1.lab.l }
                case 1: sorted = box.contents.sorted { $0.lab.a < $1.lab.a }
                default: sorted = box.contents.sorted { $0.lab.b < $1.lab.b }
                }
                // The WEIGHTED median, not the middle element: half the pixels
                // either side, which is what makes the two halves comparable
                // rather than the two element counts.
                let half = box.weight / 2
                var running = 0
                var split = 0
                var index = 0
                // A counted walk rather than `enumerated()`: see `refine(_:)`
                // for what that sequence costs at -Onone.
                for bucket in sorted {
                    running += bucket.weight
                    if running >= half { split = index; break }
                    index += 1
                }
                split = min(max(1, split), sorted.count - 1)
                boxes[target] = Box(Array(sorted[..<split]))
                boxes.append(Box(Array(sorted[split...])))
            }
            return boxes.map { Self.centre($0.contents) }
        }

        /// A box's weighted mean — the entry that serves it.
        ///
        /// One walk rather than four `reduce`s over the same array: they were
        /// four passes and, at -Onone, four closure calls per bucket for
        /// arithmetic that shares a single walk.
        ///
        /// The three lab sums are the same operations in the same order, so
        /// those are bit-identical. The weight is NOT the same operation — it
        /// was an `Int` sum converted once and is now accumulated as `Double` —
        /// and is exact anyway: every partial sum is a pixel count, and the
        /// first one a `Double` cannot hold exactly needs 2^53 pixels.
        private static func centre(_ box: [Bucket]) -> (l: Double, a: Double, b: Double) {
            var weight = 0.0
            var sumL = 0.0
            var sumA = 0.0
            var sumB = 0.0
            for bucket in box {
                let w = Double(bucket.weight)
                weight += w
                sumL += bucket.lab.l * w
                sumA += bucket.lab.a * w
                sumB += bucket.lab.b * w
            }
            guard weight > 0 else { return (0, 0, 0) }
            return (sumL / weight, sumA / weight, sumB / weight)
        }

        private static func srgb(_ lab: (l: Double, a: Double, b: Double)) -> RGBA {
            let rgb = Color.fromOKLab(l: lab.l, a: lab.a, b: lab.b)
            return RGBA(r: rgb.red, g: rgb.green, b: rgb.blue)
        }
    }
}
