//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowFillRule+Cube.swift
//
//  The row fills for a palette that arrives at runtime, on a 256-colour terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension RowFillRule {
    /// The order a first-fit tier reads its candidates in; ties go to the lower RGB.
    enum Order: Equatable {
        /// Least lift first.
        case lowest
        /// Most lift first.
        case highest
        /// Nearest this lift first.
        case nearest(Double)
    }

    /// A first-fit tier: the order it reads its candidates in, and the tests a
    /// candidate must pass. The tests are all required, so a tier lists its cheap
    /// ones first.
    typealias Tier = (order: Order, tests: [(Swatch) -> Bool])

    /// The first candidate meeting every test of the first tier any candidate meets.
    func first(_ candidates: [Swatch], _ tiers: Tier...) -> Swatch? {
        var orderedFor: Order?
        var ordered: [Int] = []
        for tier in tiers {
            // Consecutive tiers mostly share an order: sort once for them.
            if orderedFor != tier.order {
                ordered = order(candidates, tier.order)
                orderedFor = tier.order
            }
            if let found = ordered.first(where: { index in tier.tests.allSatisfy { $0(candidates[index]) } }) {
                return candidates[found]
            }
        }
        return nil
    }

    /// The indices of `candidates` in `order`: as they are, where they already are
    /// (a ladder is in order of lift), else sorted.
    private func order(_ candidates: [Swatch], _ order: Order) -> [Int] {
        let keys = candidates.map { candidate -> Double in
            switch order {
            case .lowest: lift(candidate)
            case .highest: -lift(candidate)
            case .nearest(let target): abs(lift(candidate) - target)
            }
        }
        func precedes(_ first: Int, _ second: Int) -> Bool {
            keys[first] != keys[second] ? keys[first] < keys[second] : candidates[first].packed < candidates[second].packed
        }
        let indices = Array(candidates.indices)
        if zip(indices, indices.dropFirst()).allSatisfy({ !precedes($1, $0) }) { return indices }
        return indices.sorted(by: precedes)
    }

    /// The cube entries between the page and the text that keep the text at 2:1 and
    /// the secondary text at `secondaryFloor`, never the page's own, in order of
    /// lift: `rule.py`'s `ladder`.
    ///
    /// - Parameters:
    ///   - degrees: How far (OKLCh hue) an entry may sit from the accent's tints at
    ///     25/50/75/100%, or `nil` for every entry.
    ///   - legible: `false` for the listed exception, where no entry between the page
    ///     and the text keeps the text at 2:1: entries toward the text and PAST it
    ///     that keep the text at `textFloor`.
    /// - Returns: The ladder, and the greys a grey page may lift F's dim end to ("the
    ///   page, a little brighter"), empty on a tinted page.
    func ladder(
        degrees: Double?, secondaryFloor: Double, legible: Bool = true, textFloor: Double = 2
    ) -> (entries: [Swatch], greys: [Swatch]) {
        let secondary256 = Self.at256(secondary)
        let hues = [0.25, 0.5, 0.75, 1.0].compactMap { share -> Double? in
            let (hue, chroma) = Self.hueChroma(mix(page, accent, share))
            return chroma >= 0.03 ? hue : nil
        }
        let pageIsGrey = Self.hueChroma(page256).chroma < 0.03
        let (low, high) = (min(page256.luminance, text256.luminance), max(page256.luminance, text256.luminance))
        var entries: [Swatch] = []
        var greys: [Swatch] = []
        for entry in Self.cube {
            if entry == page256 { continue }
            if legible {
                guard low <= entry.luminance, entry.luminance <= high, contrast(text256, entry) >= 2,
                    contrast(secondary256, entry) >= secondaryFloor
                else { continue }
            } else if lift(entry, page256) <= 0 || contrast(text256, entry) < textFloor {
                continue
            }
            // In hue: every entry where there is no limit; a grey where the accent is
            // grey too; else within `degrees` of one of the accent's tints.
            let (hue, chroma) = Self.hueChroma(entry)
            let inHue: Bool
            if let degrees {
                inHue =
                    chroma < 0.03
                    ? hues.isEmpty : !hues.isEmpty && hues.map { Self.hueGap(hue, $0) }.min()! <= degrees
            } else {
                inHue = true
            }
            if inHue {
                entries.append(entry)
            } else if chroma < 0.03 && pageIsGrey {
                greys.append(entry)
            }
        }
        func ordered(_ swatches: [Swatch]) -> [Swatch] {
            swatches.map { (lift: lift($0), swatch: $0) }.sorted { lhs, rhs in
                lhs.lift != rhs.lift ? lhs.lift < rhs.lift : lhs.swatch.packed < rhs.swatch.packed
            }.map(\.swatch)
        }
        return (ordered(entries), ordered(greys))
    }

    /// The rule's check of H0-H5 and H7 on a 256-colour terminal.
    func holds256(
        _ selection: Swatch, _ focus: (Swatch, Swatch), _ emphasis: (Swatch, Swatch)
    ) -> Bool {
        let (focusFrames, emphasisFrames) = (frames256(focus.0, focus.1), frames256(emphasis.0, emphasis.1))
        func off(_ colour: Swatch, _ base: Swatch) -> Bool {
            colour != base && sure(colour, base) >= Self.apartFloor && lift(colour, base) >= 2
        }
        return off(selection, page256) && focusFrames.allSatisfy { off($0, page256) }
            && !focusFrames.contains(selection) && emphasisFrames.allSatisfy { off($0, selection) }
            && !zip(focusFrames, emphasisFrames).contains { $0 == $1 } && emphasis.1 != focus.1
            && lift(emphasis.1, focus.1) >= 2 && Set(focusFrames.map(\.packed)).count > 1
            && Set(emphasisFrames.map(\.packed)).count > 1
    }

    /// One look on a 256-colour terminal, `rule.py`'s `place_256`: S nearest the
    /// truecolour S where B can still breathe 12 above it; B before F; every end the
    /// first fit over the ladder by distance to its target, the hard invariants as
    /// filters and the soft wishes dropped in tiers.
    func place256(
        _ ladder: (entries: [Swatch], greys: [Swatch]), toward target: Look, selectionAt: Swatch? = nil
    ) -> Look? {
        let (entries, greys) = ladder
        guard entries.count >= 3 else { return nil }
        let page = page256
        func off(_ colour: Swatch, _ base: Swatch) -> Bool {
            colour != base && sure(colour, base) >= Self.apartFloor && lift(colour, base) >= 2
        }
        // The ladder is already in order of lift, ties by RGB: its first match is the
        // lowest.
        func emphasisDim(over selection: Swatch) -> Swatch? { entries.first { off($0, selection) } }
        func emphasisHasRoom(_ selection: Swatch) -> Bool {
            guard let dim = emphasisDim(over: selection) else { return false }
            return lift(entries.last!, dim) >= 12
        }
        func focusDimFits(_ selection: Swatch) -> Bool {
            let fits = { (dim: Swatch) in off(dim, page) && dim != selection && self.lift(selection, dim) >= 2 }
            return entries.contains(where: fits) || greys.contains(where: fits)
        }
        let offPage: (Swatch) -> Bool = { off($0, page) }
        let towardS = Order.nearest(lift(target.selection))
        guard
            let selection = selectionAt
                ?? first(
                    Array(entries.dropLast(2)),
                    (towardS, [{ self.sure($0, page) >= 8 }, { self.lift($0) > 0 }, emphasisHasRoom, focusDimFits]),
                    (towardS, [offPage, emphasisHasRoom, focusDimFits]), (towardS, [offPage, emphasisHasRoom]),
                    (.lowest, [offPage, focusDimFits]), (.lowest, [offPage])),
            let dimB = emphasisDim(over: selection)
        else { return nil }

        // B first: its peak nearest the truecolour peak, breathing 12, else the highest.
        let keepsSOffB: (Swatch) -> Bool = { !self.frames256(dimB, $0).contains(selection) }
        guard
            var topB = first(
                entries.filter { lift($0, dimB) > 0 },
                (.nearest(max(lift(target.emphasis.top), lift(dimB) + 12)), [{ self.lift($0, dimB) >= 12 }, keepsSOffB]),
                (.highest, [keepsSOffB]))
        else { return nil }
        let framesB = frames256(dimB, topB)

        // Then F under it.
        let focusBase: [(Swatch) -> Bool] = [offPage, { $0 != selection }]
        guard
            let dimF = first(
                entries + greys,
                (.lowest, focusBase + [{ self.lift(selection, $0) >= 2 }, { self.lift($0) <= 0.6 * self.lift(selection) }]),
                (.lowest, focusBase + [{ self.lift(selection, $0) >= 2 }]), (.lowest, focusBase))
        else { return nil }
        // Every tier asks this of the same candidates, and it reads 16 frames, so it is
        // asked once per candidate, and after the tier's cheap tests (a tier's tests are
        // all required, so their order changes only the work).
        var fits: [UInt32: Bool] = [:]
        let focusFits: (Swatch) -> Bool = { top in
            if let known = fits[top.packed] { return known }
            let framesF = self.frames256(dimF, top)
            let answer =
                self.lift(topB, top) >= 2 && top != topB && !framesF.contains(selection) && !framesF.contains(page)
                && framesF.allSatisfy { off($0, page) } && !zip(framesF, framesB).contains { $0 == $1 }
            fits[top.packed] = answer
            return answer
        }
        let breathesF: (Swatch) -> Bool = { self.lift($0, dimF) >= 12 }
        let clearsS: (Swatch) -> Bool = { self.lift($0, selection) >= 4 }
        let towardF = Order.nearest(min(lift(target.focus.top), lift(topB) - 8))
        guard
            let topF = first(
                entries.filter { lift($0, dimF) > 0 },
                (towardF, [breathesF, { self.lift(topB, $0) >= 8 }, clearsS, focusFits]),
                (towardF, [breathesF, clearsS, focusFits]), (towardF, [breathesF, focusFits]), (.highest, [focusFits]))
        else { return nil }

        // B's peak 8 L* over F's where the ladder has an entry for it (F may have had to
        // pass S's entry to breathe).
        if lift(topB, topF) < 8 {
            let framesF = frames256(dimF, topF)
            topB =
                first(
                    entries.filter { lift($0, topF) >= 8 },
                    (
                        .lowest,
                        [
                            { !self.frames256(dimB, $0).contains(selection) },
                            { !zip(framesF, self.frames256(dimB, $0)).contains { $0 == $1 } },
                        ]
                    )) ?? topB
        }
        return Look(
            selection: selection, focus: (dimF, topF), emphasis: (dimB, topB),
            holds: holds256(selection, (dimF, topF), (dimB, topB)),
            breath: min(lift(topF, dimF), lift(topB, dimB)))
    }

    /// The look on a 256-colour terminal, `rule.py`'s `rule_256`, placed toward
    /// `target` (the truecolour look): the first ladder that holds the invariants and
    /// breathes 12 — in hue (30°), then 60°, then every entry, the secondary text at
    /// 1.5:1 and then not. Else every S on the whole cube's ladder, lowest first; else
    /// the entries past the text (the listed exception); else the target, quantised.
    func cube(toward target: Look) -> Look {
        var best: Look?
        for secondaryFloor in [1.5, 0] {
            for degrees in [30.0, 60, nil] {
                guard let look = place256(ladder(degrees: degrees, secondaryFloor: secondaryFloor), toward: target)
                else { continue }
                if look.holds && look.breath >= 12 { return look }
                if look.beats(best) { best = look }
            }
        }
        if let found = best, !(found.holds && found.breath >= 12) {
            for secondaryFloor in [1.5, 0] {
                let whole = ladder(degrees: nil, secondaryFloor: secondaryFloor)
                for selection in whole.entries.dropLast(2) {
                    if let look = place256(whole, toward: target, selectionAt: selection), look.beats(best) {
                        best = look
                    }
                }
            }
        }
        if best == nil {
            best =
                place256(ladder(degrees: nil, secondaryFloor: 0, legible: false), toward: target)
                ?? place256(ladder(degrees: nil, secondaryFloor: 0, legible: false, textFloor: 0), toward: target)
        }
        return best
            ?? Look(
                selection: Self.at256(target.selection),
                focus: (Self.at256(target.focus.dim), Self.at256(target.focus.top)),
                emphasis: (Self.at256(target.emphasis.dim), Self.at256(target.emphasis.top)),
                holds: false, breath: 0)
    }
}
