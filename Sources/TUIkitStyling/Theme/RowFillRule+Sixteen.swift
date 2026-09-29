//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowFillRule+Sixteen.swift
//
//  The row fills for a palette that arrives at runtime, on a 16-colour terminal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension RowFillRule {
    /// A 16-colour look: each end a slot of the terminal's table, or `nil` for reverse
    /// video — the palette's pair exchanged.
    struct Slots: Equatable {
        var selection: Int
        var focusDim: Int?
        var focusTop: Int?
        var emphasisDim: Int?
        var emphasisTop: Int?
    }

    /// Two slots a breath can run between and read as a visible change (OKLab ×100).
    static let strong = 18.0

    /// The look on a 16-colour terminal, `rule.py`'s `rule_16`, placed toward `target`
    /// (the truecolour look) against `table`, the sixteen slots the terminal paints.
    ///
    /// The page, the text and the secondary text are the slots nearest the palette's
    /// (the terminal's own page and text are themselves); the page and the text are
    /// never fills, and every fill keeps the text at 2:1. Three ways to keep every
    /// state distinguishable are tried in turn at each floor for the secondary text
    /// (1.5, 1.25, 1.1, none): five different fills, each the unused slot nearest its
    /// truecolour end; S a fill with F = (a fill, reverse video) and B = (reverse video,
    /// another fill), in anti-phase; and the same with one fill for both breaths. The
    /// ● is kept off B first, then not; breaths weaker than ``strong`` come only after
    /// all of those. Where fewer than two slots are legible, the last resort breathes
    /// each row between one other colour and reverse video.
    func sixteen(toward target: Look, table: [Swatch]) -> Slots {
        func nearest(_ colour: Swatch) -> Swatch {
            table.indices.min { lhs, rhs in
                let (one, two) = (squaredDistance(colour, table[lhs]), squaredDistance(colour, table[rhs]))
                return one != two ? one < two : lhs < rhs
            }.map { table[$0] }!
        }
        let (page, text) = live ? (self.page, self.text) : (nearest(self.page), nearest(self.text))
        let secondary = nearest(self.secondary)
        let dot = nearest(accent)
        let fadedDot = nearest(mix(accent, self.page, 1 - 0.6))
        // Every other slot once, most legible first (ties by RGB). In typed steps: as
        // one chain, the 6.2 compilers on Linux, Windows and WebAssembly gave up on it.
        var seen: Set<UInt32> = []
        var distinct: [Swatch] = []
        for slot in table where slot != page && slot != text && seen.insert(slot.packed).inserted {
            distinct.append(slot)
        }
        let legibility: [(contrast: Double, swatch: Swatch)] = distinct.map { (contrast(text, $0), $0) }
        let ordered = legibility.sorted { lhs, rhs in
            lhs.contrast != rhs.contrast ? lhs.contrast > rhs.contrast : lhs.swatch.packed < rhs.swatch.packed
        }
        let others: [Swatch] = ordered.map(\.swatch)
        let legible = others.filter { contrast(text, $0) >= 2 }
        let reversal = text
        let brightFrames = Self.phases.map { Color.breathStep(atPhase: $0, of: 2) == 1 }
        func frames(_ dim: Swatch, _ top: Swatch) -> [Swatch] { brightFrames.map { $0 ? top : dim } }

        typealias Pick = (selection: Swatch, focusDim: Swatch, focusTop: Swatch, emphasisDim: Swatch, emphasisTop: Swatch)
        func holds(_ pick: Pick, keepDot: Bool) -> Bool {
            let focus = frames(pick.focusDim, pick.focusTop)
            let emphasis = frames(pick.emphasisDim, pick.emphasisTop)
            let both = focus + emphasis
            return pick.selection != page && !both.contains(page) && !both.contains(pick.selection)
                && focus[0] != emphasis[0] && !zip(focus, emphasis).contains { $0 == $1 }
                && Set(focus.map(\.packed)).count > 1 && Set(emphasis.map(\.packed)).count > 1
                && (!keepDot || (!emphasis.contains(dot) && pick.selection != fadedDot))
        }
        func strongly(_ first: Swatch, _ second: Swatch) -> Bool { distance(first, second) >= Self.strong }

        enum Mode { case pairs, reversed, shared, weakPairs }
        func pick(from usable: [Swatch], _ mode: Mode, keepDot: Bool) -> Pick? {
            var taken: [Swatch] = []
            func take(_ target: Swatch, _ test: (Swatch) -> Bool = { _ in true }) -> Swatch? {
                let found = usable.filter { !taken.contains($0) && test($0) }.min { lhs, rhs in
                    let (one, two) = (squaredDistance(target, lhs), squaredDistance(target, rhs))
                    return one != two ? one < two : lhs.packed < rhs.packed
                }
                if let found { taken.append(found) }
                return found
            }
            guard let selection = take(target.selection, { $0 != fadedDot }) else { return nil }
            let chosen: Pick
            switch mode {
            case .pairs, .weakPairs:
                let weak = mode == .weakPairs
                guard let focusDim = take(target.focus.dim),
                    let focusTop = take(target.focus.top, { weak || strongly($0, focusDim) }),
                    let emphasisDim = take(target.emphasis.dim, { $0 != dot }),
                    let emphasisTop = take(target.emphasis.top, { $0 != dot && (weak || strongly($0, emphasisDim)) })
                else { return nil }
                chosen = (selection, focusDim, focusTop, emphasisDim, emphasisTop)
            case .reversed:
                guard let focusDim = take(target.focus.dim), let emphasisTop = take(target.emphasis.top, { $0 != dot })
                else { return nil }
                chosen = (selection, focusDim, reversal, reversal, emphasisTop)
            case .shared:
                guard let fill = take(target.focus.dim, { $0 != dot }) else { return nil }
                chosen = (selection, fill, reversal, reversal, fill)
            }
            return holds(chosen, keepDot: keepDot) ? chosen : nil
        }

        var found: Pick?
        search: for (modes, keepDot) in [
            ([Mode.pairs, .reversed, .shared], true), ([.pairs, .reversed, .shared], false), ([.weakPairs], false),
        ] {
            for floor in [1.5, 1.25, 1.1, 0] {
                let usable = legible.filter { contrast(secondary, $0) >= floor }
                for mode in modes {
                    if let chosen = pick(from: usable, mode, keepDot: keepDot) {
                        found = chosen
                        break search
                    }
                }
            }
        }
        let chosen: Pick
        if let found {
            chosen = found
        } else {
            // Fewer than two legible fills: the most legible other colour joins.
            let fill = legible.first ?? others.first ?? page
            let other = others.first { $0 != fill } ?? fill
            chosen = (fill, reversal, other, other, reversal)
        }
        func slot(_ swatch: Swatch) -> Int? {
            swatch == reversal ? nil : table.firstIndex(of: swatch)
        }
        return Slots(
            selection: table.firstIndex(of: chosen.selection) ?? 0, focusDim: slot(chosen.focusDim),
            focusTop: slot(chosen.focusTop), emphasisDim: slot(chosen.emphasisDim),
            emphasisTop: slot(chosen.emphasisTop))
    }

    /// The squared RGB distance the terminal's nearest slot is chosen by.
    private func squaredDistance(_ first: Swatch, _ second: Swatch) -> Int {
        let red = Int(first.red) - Int(second.red)
        let green = Int(first.green) - Int(second.green)
        let blue = Int(first.blue) - Int(second.blue)
        return red * red + green * green + blue * blue
    }
}
