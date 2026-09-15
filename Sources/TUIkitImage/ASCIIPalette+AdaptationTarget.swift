//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette+AdaptationTarget.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Which colours the adaptation may choose from

extension ASCIIPalette {

    /// The output an ``ASCIIPalette/adaptive(_:by:target:)`` palette is chosen
    /// for.
    ///
    /// An adaptive palette exists to spend the terminal's colours well, and a
    /// palette derived without knowing what those colours ARE cannot. The
    /// derivation used to run in continuous colour and be quantised afterwards,
    /// which collapses entries onto each other: on `demo-image.jpg` at 256
    /// colours, asking for five gave four — a palette **bit-identical** to the
    /// one four gave — and asking for 256 gave 51, which is why "Least error at
    /// 256 colours" looked worse than plain 256-colour mode on Terminal.app.
    /// Choosing from the target's own colours instead measured 12% better at
    /// four colours, 24% at eight and 36% at sixteen (weighted mean OKLab error
    /// over the picture's 5,078 populated cells).
    ///
    /// So the target is part of the question, and it is asked here rather than
    /// read from ``ColorDepth/current`` because the two renderings of a picture
    /// do not share an answer: a picture drawn as terminal graphics is a field
    /// of RGB pixels whatever the terminal's SGR depth, so its palette is
    /// ``depth(_:)`` `.truecolor` on the very terminal where the glyph rendering
    /// of the same picture is ``depth(_:)`` `.palette256`.
    public enum AdaptationTarget: Sendable, Equatable, Hashable, CaseIterable {
        /// Whatever the output turns out to be — the terminal's depth for a
        /// picture drawn as glyphs, and 24-bit for one drawn as pixels.
        ///
        /// The one to want. The others exist to pin a rendering that must not
        /// change with the terminal, and to SHOW the difference: a 16-colour
        /// palette on a truecolor terminal is what a 16-colour terminal will do
        /// with the picture, previewed where it can be looked at.
        case automatic

        /// The colours a particular depth can draw, whatever the output is.
        ///
        /// - ``ColorDepth/truecolor`` constrains nothing: any colour chosen can
        ///   be drawn exactly. This is the old, depth-blind behaviour, kept as a
        ///   choice rather than as the default.
        /// - ``ColorDepth/palette256`` is the 240 distinct colours of the 6×6×6
        ///   cube and the grey ramp (indices 16…255). A palette can never hold
        ///   more entries than that however many are asked for.
        /// - ``ColorDepth/basic16`` is the sixteen the terminal's own profile
        ///   defines — the picture then FOLLOWS that profile, as
        ///   ``ASCIIPalette/ansi16`` does.
        /// - ``ColorDepth/noColor`` is black and white: two colours, and the
        ///   picture is a 1-bit rendering of itself.
        case depth(ColorDepth)

        /// Written out rather than synthesised, because ``depth(_:)`` carries a
        /// value: darkest first, which is the order a picker should offer them
        /// in.
        public static let allCases: [Self] = [
            .automatic, .depth(.noColor), .depth(.basic16), .depth(.palette256),
            .depth(.truecolor),
        ]

        /// The depth this targets, given what the output actually is.
        func resolved(for output: ColorDepth) -> ColorDepth {
            switch self {
            case .automatic: return output
            case .depth(let target): return target
            }
        }
    }

    /// The colours `depth` can draw exactly, or `nil` where that is all of them.
    ///
    /// These are palettes this module already has, which is the point: an
    /// adaptive palette constrained to a depth chooses from the very entries the
    /// non-adaptive palette for that depth holds, so it is comparable with it
    /// rather than merely near it — and, at 256 colours asked for 240, converges
    /// on it.
    ///
    /// Because the entries are `.palette(n)` and `.ansi` colours
    /// rather than triples, a palette built out of them is a **fixed point** of
    /// ``downsampled(to:)``: the fit that runs after the derivation
    /// (`ASCIIConverter.convert(_:width:height:)`, which must keep running — see
    /// ``ASCIIColorMode/derived(from:depth:)``) has nothing left to change.
    static func representable(at depth: ColorDepth) -> Self? {
        switch depth {
        case .truecolor: return nil
        case .palette256: return ansi256
        case .basic16: return ansi16
        // Not a palette of the sixteen's black and white: a picture drawn at
        // `.noColor` through the graphics path is literal black and literal
        // white, and one drawn as glyphs states no colour at all.
        case .noColor: return shades(2)
        }
    }

    /// `centres` moved onto the colours this palette holds, kept DISTINCT, as
    /// indices into ``entries``.
    ///
    /// Distinctness is the whole reason this is not a nearest-neighbour call per
    /// centre: two centres a third of a cube step apart have the same nearest
    /// entry, and one of them silently disappearing is the bug this targeting
    /// exists to fix. Nearest FIRST — a centre already sitting on its colour
    /// keeps it, and the one that collided with it takes its own next best —
    /// because the alternative, first come first served, hands the entry to
    /// whichever centre happens to be earlier in the array.
    ///
    /// Fewer than `centres.count` results only when this palette has fewer
    /// entries than that, which is honest: nine colours cannot be drawn in the
    /// sixteen as nine different things and then be nine different things.
    func snapping(_ centres: [(l: Double, a: Double, b: Double)]) -> [Int] {
        // (centre, entry, distance) for every centre, then assigned in order of
        // how well the entry fits. `count × entries` distance evaluations, which
        // is 61k at 256 colours against the Lloyd pass's five million — the
        // projection is not where this algorithm spends itself.
        var claims: [(centre: Int, entry: Int, distance: Double)] = []
        claims.reserveCapacity(centres.count)
        for (index, centre) in centres.enumerated() {
            let (entry, distance) = nearest(to: centre, excluding: [])
            claims.append((index, entry, distance))
        }
        claims.sort { $0.distance < $1.distance }
        var taken: Set<Int> = []
        var chosen = [Int](repeating: -1, count: centres.count)
        for claim in claims {
            var entry = claim.entry
            if taken.contains(entry) {
                entry = nearest(to: centres[claim.centre], excluding: taken).entry
            }
            guard taken.insert(entry).inserted else { continue }
            chosen[claim.centre] = entry
        }
        return chosen.filter { $0 >= 0 }
    }

    /// One entry's OKLab coordinates, as the tuple the derivation works in.
    func labOfEntry(_ index: Int) -> (l: Double, a: Double, b: Double) {
        let entry = entries[index]
        return (entry.lightness, entry.a, entry.b)
    }

    /// The nearest entry to a point in OKLab, and how far away it is.
    ///
    /// Plain OKLab distance, which is this module's metric everywhere — see
    /// ``nearestIndex(to:)``, which says why an image must not borrow
    /// `Color.downsampledToPalette256()`'s hue-weighted rule even though it
    /// draws in the same 240 colours. It matters doubly here: the quantity being
    /// minimised by the derivation is plain OKLab error, so a projection judged
    /// by anything else would be pulling against the objective it serves.
    ///
    /// `excluding` empty is the ordinary nearest-neighbour question; a
    /// non-empty set is ``snapping(_:)``'s second look, after something else
    /// claimed the answer. Every entry is a candidate when everything is
    /// excluded — a palette cannot answer "none".
    func nearest(
        to lab: (l: Double, a: Double, b: Double), excluding taken: Set<Int>
    ) -> (entry: Int, distance: Double) {
        var best = 0
        var bestDistance = Double.infinity
        for index in entries.indices where !taken.contains(index) {
            let distance = Self.distanceSquared(lab, labOfEntry(index))
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return (best, bestDistance)
    }
}
