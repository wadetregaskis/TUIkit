//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette+Adaptive.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitStyling

// MARK: - Choosing the colours from the picture

extension ASCIIPalette {

    /// How an ``ASCIIPalette/adaptive(_:by:)`` palette picks its colours out of
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
    /// ``derived(from:)`` is handed one — which the converters do, once per
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
    public static func adaptive(_ count: Int, by method: Adaptation) -> Self {
        let count = max(1, count)
        return Self(shades(count).colors, mapping: .nearestColor,
                    adaptive: Adaptive(method: method, count: count))
    }

    /// This palette with its colours chosen from `image`, or itself if its
    /// colours were never in question.
    ///
    /// The result is an ORDINARY palette — the derivation happens once and the
    /// answer is a fixed set of colours — so everything downstream (the
    /// quantisation table, `nearestIndex(to:)`, the dither) is unchanged and
    /// unaware.
    public func derived(from image: RGBAImage) -> Self {
        guard let adaptive, !image.pixels.isEmpty else { return self }
        let histogram = Histogram(of: image)
        guard !histogram.buckets.isEmpty else { return self }
        let chosen: [RGBA]
        switch adaptive.method {
        case .popularity: chosen = histogram.mostPopular(adaptive.count)
        case .leastError: chosen = histogram.leastError(adaptive.count)
        }
        guard !chosen.isEmpty else { return self }
        return Self(chosen.map { .rgb($0.r, $0.g, $0.b) }, mapping: mapping)
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

        let buckets: [Bucket]

        init(of image: RGBAImage) {
            let cells = ASCIIPalette.quantisationCells
            var weight = [Int](repeating: 0, count: cells)
            var red = [Int](repeating: 0, count: cells)
            var green = [Int](repeating: 0, count: cells)
            var blue = [Int](repeating: 0, count: cells)
            for pixel in image.pixels {
                let cell = ASCIIPalette.quantisationCell(for: pixel)
                weight[cell] += 1
                red[cell] += Int(pixel.r)
                green[cell] += Int(pixel.g)
                blue[cell] += Int(pixel.b)
            }
            var populated: [Bucket] = []
            for cell in 0..<cells where weight[cell] > 0 {
                let count = weight[cell]
                let rgba = RGBA(
                    r: UInt8(clamping: red[cell] / count),
                    g: UInt8(clamping: green[cell] / count),
                    b: UInt8(clamping: blue[cell] / count))
                populated.append(
                    Bucket(
                        weight: count, rgba: rgba,
                        lab: Color.oklab(red: rgba.r, green: rgba.g, blue: rgba.b)))
            }
            self.buckets = populated
        }

        /// The `count` heaviest cells' colours, heaviest first.
        func mostPopular(_ count: Int) -> [RGBA] {
            // Ties broken by the colour itself so a picture always answers the
            // same palette — two cells of equal weight are common in flat art,
            // and an unstable order would make the same image quantise
            // differently on different runs.
            buckets.sorted {
                $0.weight != $1.weight
                    ? $0.weight > $1.weight
                    : (Int($0.rgba.r) << 16 | Int($0.rgba.g) << 8 | Int($0.rgba.b))
                        < (Int($1.rgba.r) << 16 | Int($1.rgba.g) << 8 | Int($1.rgba.b))
            }
            .prefix(count).map(\.rgba)
        }

        /// `count` colours minimising the weighted squared OKLab distance from
        /// every pixel to the entry it takes.
        ///
        /// Median cut for the starting set, then Lloyd's iteration to settle
        /// it. Median cut alone divides the colours evenly by POPULATION, which
        /// is a decent guess and not a minimum; Lloyd moves each entry to the
        /// weighted centre of what it actually serves, which is exactly the
        /// objective. Seeded rather than random, so the answer is deterministic.
        func leastError(_ count: Int) -> [RGBA] {
            let count = max(1, min(count, buckets.count))
            var centres = medianCut(into: count)
            guard centres.count > 1 else { return centres.map(Self.srgb) }

            // A budget rather than a fixed number of passes. One pass is
            // `buckets × count` distance evaluations, and both grow with what
            // is asked for: 256 colours out of a photograph's ~20,000 populated
            // cells is 5M per pass, where 8 colours is 160,000. Lloyd converges
            // fast — the first two passes do most of the work — so spending a
            // fixed budget rather than a fixed pass count keeps the worst case
            // bounded without shortchanging the cheap cases.
            let perPass = max(1, buckets.count * centres.count)
            let passes = max(1, min(12, 12_000_000 / perPass))
            for _ in 0..<passes where refine(&centres) {}
            return centres.map(Self.srgb)
        }

        /// One Lloyd pass. Returns whether anything moved, so a settled set
        /// stops early instead of spending the rest of the budget.
        private func refine(_ centres: inout [(l: Double, a: Double, b: Double)]) -> Bool {
            var sumL = [Double](repeating: 0, count: centres.count)
            var sumA = [Double](repeating: 0, count: centres.count)
            var sumB = [Double](repeating: 0, count: centres.count)
            var weight = [Int](repeating: 0, count: centres.count)
            for bucket in buckets {
                var best = 0
                var bestDistance = Double.infinity
                for (index, centre) in centres.enumerated() {
                    let distance = ASCIIPalette.distanceSquared(bucket.lab, centre)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = index
                    }
                }
                let w = Double(bucket.weight)
                sumL[best] += bucket.lab.l * w
                sumA[best] += bucket.lab.a * w
                sumB[best] += bucket.lab.b * w
                weight[best] += bucket.weight
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
                var low = (Double.infinity, Double.infinity, Double.infinity)
                var high = (-Double.infinity, -Double.infinity, -Double.infinity)
                for bucket in contents {
                    weight += bucket.weight
                    low = (min(low.0, bucket.lab.l), min(low.1, bucket.lab.a), min(low.2, bucket.lab.b))
                    high = (max(high.0, bucket.lab.l), max(high.1, bucket.lab.a), max(high.2, bucket.lab.b))
                }
                let spread = (high.0 - low.0, high.1 - low.1, high.2 - low.2)
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
                let axis = box.axis
                let sorted = box.contents.sorted {
                    Self.coordinate($0, axis) < Self.coordinate($1, axis)
                }
                // The WEIGHTED median, not the middle element: half the pixels
                // either side, which is what makes the two halves comparable
                // rather than the two element counts.
                let half = box.weight / 2
                var running = 0
                var split = 0
                for (index, bucket) in sorted.enumerated() {
                    running += bucket.weight
                    if running >= half { split = index; break }
                }
                split = min(max(1, split), sorted.count - 1)
                boxes[target] = Box(Array(sorted[..<split]))
                boxes.append(Box(Array(sorted[split...])))
            }
            return boxes.map { Self.centre($0.contents) }
        }

        private static func coordinate(_ bucket: Bucket, _ axis: Int) -> Double {
            switch axis {
            case 0: return bucket.lab.l
            case 1: return bucket.lab.a
            default: return bucket.lab.b
            }
        }

        private static func centre(_ box: [Bucket]) -> (l: Double, a: Double, b: Double) {
            let weight = Double(box.reduce(0) { $0 + $1.weight })
            guard weight > 0 else { return (0, 0, 0) }
            return (
                box.reduce(0) { $0 + $1.lab.l * Double($1.weight) } / weight,
                box.reduce(0) { $0 + $1.lab.a * Double($1.weight) } / weight,
                box.reduce(0) { $0 + $1.lab.b * Double($1.weight) } / weight
            )
        }

        private static func srgb(_ lab: (l: Double, a: Double, b: Double)) -> RGBA {
            let rgb = Color.fromOKLab(l: lab.l, a: lab.a, b: lab.b)
            return RGBA(r: rgb.red, g: rgb.green, b: rgb.blue)
        }
    }
}
