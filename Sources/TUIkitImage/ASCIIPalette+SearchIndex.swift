//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette+SearchIndex.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitStyling

// MARK: - Answering exactly, without walking every entry

extension ASCIIPalette {

    /// For every cell of the perceptually-spaced 5-bit grid, the entries that
    /// can be the nearest to SOME colour inside that cell — so a search over
    /// them is the exact search, over a handful of entries instead of all of
    /// them.
    ///
    /// ## Why a second structure beside the quantisation table
    ///
    /// ``quantisationTable()`` answers per cell and is right wherever a cell
    /// lies inside one entry's region; on a boundary cell it falls back to the
    /// full walk, and for ``ansi256`` it does not even do that, because 240
    /// entries leave two thirds of the cells on a boundary and the fallback
    /// would have cost most of what the table saved. That is the pixel path's
    /// trade, documented there, and it accepts a percent of near-boundary
    /// disagreements for a lookup that is one load.
    ///
    /// The glyph path never took that trade — it wanted the exact answer and
    /// paid a full walk per cell for it: 240 OKLab distances a cell, which the
    /// profile of the half-block renderer showed to be most of a frame once
    /// the colour spelling was fixed (513 ns a cell at `.ansi256`, 606 at a
    /// 256-shade palette). This index gives the exact answer at a fraction of
    /// that, and the table's boundary fallback can use it too.
    ///
    /// ## How it is exact
    ///
    /// For a cell with centre `c` and every colour in it within `r` of `c`
    /// (in OKLab), let `n` be the entry nearest `c`. For any colour `p` in the
    /// cell, its nearest entry `m` satisfies
    /// `|m − c| ≤ |m − p| + r ≤ |n − p| + r ≤ |n − c| + 2r`. So every entry
    /// within `|n − c| + 2r` of the centre is a candidate and no other entry
    /// can win anywhere in the cell. The radius is the farthest of the cell's
    /// eight sRGB corners from its centre in OKLab, widened by a tenth for the
    /// curvature a bucket has between its corners; widening only ever ADDS
    /// candidates, so it costs a distance or two and never an answer.
    ///
    /// Ties resolve as the walk resolves them — the lowest index among the
    /// equally near — because the candidates are kept in index order and
    /// compared with the same strict `<`. ``PaletteSearchIndexTests`` checks
    /// the index against the walk over every cell corner and a broad sample
    /// of the gamut, for the two large built-in palettes and an adaptive one.
    final class SearchIndex: @unchecked Sendable {
        /// `offsets[cell]..<offsets[cell + 1]` indexes `candidates`.
        private let offsets: [Int32]
        private let candidates: [UInt8]
        /// The entries the index was built over, for the distance walk.
        private let entries: [Entry]

        init(entries: [Entry]) {
            self.entries = entries
            let span = 1 << ASCIIPalette.quantisationBits
            let cells = ASCIIPalette.quantisationCells
            var offsets = [Int32](repeating: 0, count: cells + 1)
            var candidates: [UInt8] = []
            candidates.reserveCapacity(cells * 3)
            // The byte range each bucket covers, for the cell corners.
            var first = [Int](repeating: -1, count: span)
            var last = [Int](repeating: 0, count: span)
            for value in 0...255 {
                let bucket = Int(ASCIIPalette.quantisationBucket[value])
                if first[bucket] < 0 { first[bucket] = value }
                last[bucket] = value
            }
            var distances = [Double](repeating: 0, count: entries.count)
            for red in 0..<span {
                for green in 0..<span {
                    for blue in 0..<span {
                        let cell = (red << (2 * ASCIIPalette.quantisationBits)) | (green << ASCIIPalette.quantisationBits) | blue
                        // A bucket no byte falls in — the perceptual spacing
                        // leaves a few — is a cell no pixel can land in, so it
                        // gets no candidates rather than a corner it lacks.
                        guard first[red] >= 0, first[green] >= 0, first[blue] >= 0 else {
                            offsets[cell + 1] = Int32(candidates.count)
                            continue
                        }
                        let centre = Color.oklab(
                            red: ASCIIPalette.quantisationRepresentative[red],
                            green: ASCIIPalette.quantisationRepresentative[green],
                            blue: ASCIIPalette.quantisationRepresentative[blue])
                        // The cell's reach: its farthest corner from the centre.
                        var radius = 0.0
                        for corner in 0..<8 {
                            let lab = Color.oklab(
                                red: UInt8(corner & 1 == 0 ? first[red] : last[red]),
                                green: UInt8(corner & 2 == 0 ? first[green] : last[green]),
                                blue: UInt8(corner & 4 == 0 ? first[blue] : last[blue]))
                            let dl = lab.l - centre.l, da = lab.a - centre.a, db = lab.b - centre.b
                            radius = max(radius, (dl * dl + da * da + db * db).squareRoot())
                        }
                        radius = radius * 1.1 + 1e-6
                        var nearest = Double.infinity
                        for (index, entry) in entries.enumerated() {
                            let dl = centre.l - entry.lightness, da = centre.a - entry.a, db = centre.b - entry.b
                            let distance = (dl * dl + da * da + db * db).squareRoot()
                            distances[index] = distance
                            if distance < nearest { nearest = distance }
                        }
                        let reach = nearest + 2 * radius
                        for index in entries.indices where distances[index] <= reach {
                            candidates.append(UInt8(index))
                        }
                        offsets[cell + 1] = Int32(candidates.count)
                    }
                }
            }
            self.offsets = offsets
            self.candidates = candidates
        }

        /// How many candidates the index holds in all — a diagnostic, and
        /// what the tests use to say the lists are short.
        var candidateCount: Int { candidates.count }

        /// The exact nearest entry to `pixel`: the walk, over the cell's
        /// candidates only.
        @inline(__always)
        func nearestIndex(to pixel: RGBA) -> Int {
            let cell = ASCIIPalette.quantisationCell(for: pixel)
            let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
            var best = 0
            var bestDistance = Double.infinity
            offsets.withUnsafeBufferPointer { offsets in
                candidates.withUnsafeBufferPointer { candidates in
                    entries.withUnsafeBufferPointer { entries in
                        var position = Int(offsets[cell])
                        let end = Int(offsets[cell + 1])
                        while position < end {
                            let index = Int(candidates[position])
                            let entry = entries[index]
                            let dl = target.l - entry.lightness
                            let da = target.a - entry.a
                            let db = target.b - entry.b
                            let distance = dl * dl + da * da + db * db
                            if distance < bestDistance {
                                bestDistance = distance
                                best = index
                            }
                            position += 1
                        }
                    }
                }
            }
            return best
        }
    }

    /// Palettes with more entries than this search through an index; the
    /// rest walk. Sixteen entries walk in about the time a bucket lookup and
    /// two candidates take, and ``ansi16`` is exactly sixteen.
    static let indexedEntryThreshold = 16

    /// This palette's index, built on first use and shared by every palette
    /// whose entries measure the same — so a `.shades(256)` made afresh each
    /// frame does not build one each frame, and every copy of one palette
    /// shares one.
    /// `nil` for a palette with more entries than a byte can name, exactly as
    /// ``quantisationTable()`` declines one and for the same reason: the
    /// candidate lists store an entry index in a `UInt8`, so building an index
    /// for the 257th entry trapped on `UInt8(index)` — on the FIRST pixel
    /// looked up, taking the app with it. Those palettes take the exact walk
    /// instead, which is what the index is measured against.
    var searchIndex: SearchIndex? {
        guard entries.count <= Self.indexableEntryLimit else { return nil }
        return search.index(for: self)
    }

    /// The index ``nearestIndex(to:)`` will actually consult, or `nil` where it
    /// consults none — what a loop asking per cell or per pixel resolves ONCE
    /// and hands to `nearestIndex(to:using:)`.
    ///
    /// Not ``searchIndex``, which is the lazy BUILDER: that one builds an index
    /// for any palette a byte can index, so reading it for a three-entry
    /// palette would build 32,768 cells of candidate lists the search will
    /// never look at. The two gates — a ramp searches nothing, and a palette at
    /// or below ``indexedEntryThreshold`` walks faster than it can look a
    /// bucket up — live here so that no loop has to restate them, and so that
    /// resolving costs the handle's lock once instead of once a cell.
    var consultedSearchIndex: SearchIndex? {
        guard mapping == .nearestColor, entries.count > Self.indexedEntryThreshold else { return nil }
        return searchIndex
    }

    /// The per-instance memo, and the process-wide cache behind it.
    ///
    /// A reference held by every copy of the palette, so the first search
    /// pays a hash of the entries (once per palette instance) and every later
    /// one pays a lock. The cache behind it is keyed by the entries' RGB and
    /// keeps the last few, the way `Color.quantisedRamp` keeps ramps.
    final class SearchIndexHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var index: SearchIndex?

        func index(for palette: ASCIIPalette) -> SearchIndex {
            lock.lock()
            defer { lock.unlock() }
            if let index { return index }
            let built = SearchIndexCache.shared.index(for: palette.entries)
            index = built
            return built
        }
    }

    private enum SearchIndexCache {
        nonisolated(unsafe) static var shared = Store()

        /// Keyed by what each entry MEASURES, its RGB packed into a `UInt32`,
        /// not by the colours as written.
        ///
        /// An index is a function of the entries alone: each one's OKLab is
        /// computed from its RGB (`ASCIIPalette.entry(for:)`, the only place an
        /// entry is made), and the index stores nothing else. The colours are
        /// NOT a function of the entries, and that is the hole this closes. A
        /// slot entry measures as the colour the terminal reported for it, or
        /// as xterm's value while it has reported none, so one list of colours
        /// made before a report and again after is two palettes with different
        /// entries and equal colours. Keyed by the colours, the second was
        /// searched through the first's index, which carries the first's entries,
        /// and answered as the terminal it no longer was: measured, (220, 0, 0)
        /// took slot 1 on Apple Terminal "Basic" where its own walk takes slot 9.
        ///
        /// Two palettes spelled differently that measure the same now share an
        /// index, which is right for the same reason: they search identically.
        final class Store: @unchecked Sendable {
            private let lock = NSLock()
            private var indexes: [[UInt32]: SearchIndex] = [:]
            private var order: [[UInt32]] = []
            private let capacity = 8

            func index(for entries: [Entry]) -> SearchIndex {
                let key = entries.map { UInt32($0.rgba.r) << 16 | UInt32($0.rgba.g) << 8 | UInt32($0.rgba.b) }
                lock.lock()
                defer { lock.unlock() }
                if let cached = indexes[key] { return cached }
                let built = SearchIndex(entries: entries)
                indexes[key] = built
                order.append(key)
                if order.count > capacity {
                    indexes.removeValue(forKey: order.removeFirst())
                }
                return built
            }
        }
    }
}
