//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowFillRule.swift
//
//  The row fills for a palette that arrives at runtime: what they are measured
//  with, and the truecolour look.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The row fills (``RowFills``) of a palette whose fills were not chosen at coding
/// time: a custom palette, the terminal's own colours, a `.tint` subtree.
///
/// One-for-one with `Tools/RowFillValues/rule.py`, its reference, which also
/// explains each step. The names here are that file's, so the two read side by
/// side: S is the selected row, F the unselected cursor row's breath, B the
/// selected cursor row's; `lift` is L\* away from the page toward the text; `near`
/// and `sure` are two estimates of CIEDE2000 from L\* and OKLab, one for placing a
/// colour and one for checking it. `RowFillRuleTests` holds this to the
/// reference's answers for 155 palettes, to the bit.
///
/// There are no criteria and no scoring here: every end is placed by a walk
/// (truecolour: along a path from the page to the accent; 256 colours: first fit
/// along a ladder of cube entries), and the rule checks its own hard invariants —
/// S off the page, F off the page and off S, B off S and above it, F and B never
/// alike on one frame, B's peak above F's, the text readable on every frame, no
/// flat breath — and retries until a look holds them.
///
/// One run measures many colours several times over, so it keeps what it has
/// measured; a run is one palette at one depth, and ``RowFills`` caches its answer.
final class RowFillRule {
    /// A colour the rule reads, with what it reads of it measured once.
    struct Swatch: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        /// ``Color/perceivedLightness``.
        let lightness: Double
        /// ``Color/relativeLuminance``.
        let luminance: Double
        /// ``Color/oklab(red:green:blue:)``.
        let lab: (l: Double, a: Double, b: Double)

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            (self.red, self.green, self.blue) = (red, green, blue)
            let colour = Color.rgb(red, green, blue)
            luminance = colour.relativeLuminance ?? 0
            lightness = colour.perceivedLightness ?? 0
            lab = Color.oklab(red: red, green: green, blue: blue)
        }

        /// 0xRRGGBB, which also orders swatches as the reference breaks ties: by
        /// the RGB triple.
        var packed: UInt32 { UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue) }

        var color: Color { .rgb(red, green, blue) }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.packed == rhs.packed }
    }

    /// Five fills: S, and F's and B's two ends.
    struct Look {
        var selection: Swatch
        var focus: (dim: Swatch, top: Swatch)
        var emphasis: (dim: Swatch, top: Swatch)
        /// Whether the look holds the rule's hard invariants.
        var holds: Bool
        /// The weaker of the two breaths, in L\*.
        var breath: Double
        /// Where S sits on the path (truecolour only).
        var selectionStep = 0

        /// Whether this look is better than `other`: it holds the invariants where
        /// that does not, else it breathes more, up to the 12 L\* the rule asks for.
        func beats(_ other: Self?) -> Bool {
            guard let other else { return true }
            if holds != other.holds { return holds }
            return min(breath, 12) > min(other.breath, 12)
        }
    }

    /// The frames a breath is checked at: `SelectionEmphasisCycle`'s at the
    /// automatic speed.
    static let frameCount = 16
    /// The path's steps from the page to its far end.
    static let steps = 128
    /// The invariants' 4 ΔE00, with a 10% margin for the estimate.
    static let apartFloor = 4.4
    /// A breath's phase at each of its frames.
    static let phases = (0..<frameCount).map { Color.breathPhase(atFrame: $0, of: frameCount) }

    let page: Swatch
    let text: Swatch
    let secondary: Swatch
    let accent: Swatch
    /// The page and the text are the terminal's own (SGR 49 and 39), so they are
    /// drawn as they are at every depth, never quantised.
    let live: Bool
    /// 1 where the text is lighter than the page, else -1: the way "up" is.
    let direction: Double
    /// The page and the text as a 256-colour terminal draws them.
    let page256: Swatch
    let text256: Swatch

    /// The accent, pushed toward the text in its own hue (see ``pushAccent()``).
    var pushed: Swatch
    /// The path S and every peak ride: the page to ``pushed``, in ``steps``.
    var path: [Swatch] = []

    private var measured: [UInt32: Swatch] = [:]
    private var frameMemo: [UInt16: [Swatch]] = [:]

    init(page: Color, text: Color, secondary: Color, accent: Color, live: Bool) {
        func swatch(_ colour: Color) -> Swatch {
            let (red, green, blue) = colour.rgbComponents ?? (0, 0, 0)
            return Swatch(red, green, blue)
        }
        self.page = swatch(page)
        self.text = swatch(text)
        self.secondary = swatch(secondary)
        self.accent = swatch(accent)
        self.live = live
        direction = self.text.lightness >= self.page.lightness ? 1 : -1
        page256 = live ? self.page : Self.at256(self.page)
        text256 = live ? self.text : Self.at256(self.text)
        pushed = self.accent
    }

    // MARK: - Measures

    /// The swatch for an RGB triple, measured once per run.
    func swatch(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Swatch {
        let key = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        if let known = measured[key] { return known }
        let fresh = Swatch(red, green, blue)
        measured[key] = fresh
        return fresh
    }

    /// ``Color/lerp(_:_:phase:)``.
    func mix(_ from: Swatch, _ to: Swatch, _ phase: Double) -> Swatch {
        let clamped = min(1, max(0, phase))
        return swatch(
            Color.mixedByte(from.red, to.red, phase: clamped),
            Color.mixedByte(from.green, to.green, phase: clamped),
            Color.mixedByte(from.blue, to.blue, phase: clamped))
    }

    /// The cube entry a colour draws as on a 256-colour terminal.
    static func at256(_ colour: Swatch) -> Swatch {
        guard case .palette256(let index) = colour.color.downsampledToPalette256().value else { return colour }
        return cube[Int(index) - 16]
    }

    /// The 240 cube entries, 16 to 255.
    static let cube: [Swatch] = (16...255).map { index in
        let (red, green, blue) = Color.palette256ToRGB(UInt8(index))
        return Swatch(red, green, blue)
    }

    /// Each cube entry's index, by its RGB.
    static let cubeIndex: [UInt32: UInt8] = Dictionary(
        uniqueKeysWithValues: cube.enumerated().map { ($1.packed, UInt8($0 + 16)) })

    /// L\* from `base` (the page, by default) toward the text.
    func lift(_ colour: Swatch, _ base: Swatch? = nil) -> Double {
        (colour.lightness - (base ?? page).lightness) * direction
    }

    /// The WCAG contrast ratio.
    func contrast(_ first: Swatch, _ second: Swatch) -> Double {
        (max(first.luminance, second.luminance) + 0.05) / (min(first.luminance, second.luminance) + 0.05)
    }

    /// CIEDE2000's lightness weight.
    static func lightnessWeight(_ lightness: Double) -> Double {
        let offset = (lightness - 50) * (lightness - 50)
        return 1 + 0.015 * offset / (20 + offset).squareRoot()
    }

    /// ΔE00's lightness term.
    func step(_ first: Swatch, _ second: Swatch) -> Double {
        abs(first.lightness - second.lightness) / Self.lightnessWeight((first.lightness + second.lightness) / 2)
    }

    /// ΔE00's lightness term and a chroma-plane term, compressed with chroma as
    /// ΔE00's own weights compress it.
    func apart(_ first: Swatch, _ second: Swatch, _ weight: Double, _ compression: Double = 0) -> Double {
        let (one, two) = (first.lab, second.lab)
        let chroma = (hypot(one.a, one.b) + hypot(two.a, two.b)) / 2
        return hypot(
            step(first, second),
            weight * 100 * hypot(one.a - two.a, one.b - two.b) / (1 + compression * 100 * chroma))
    }

    /// ΔE00, estimated for placing a colour (about right at the median).
    func near(_ first: Swatch, _ second: Swatch) -> Double { apart(first, second, 1.4) }

    /// ΔE00, estimated for checking a floor: at or under it on 97.7% of pairs.
    func sure(_ first: Swatch, _ second: Swatch) -> Double { apart(first, second, 2.8, 0.2) }

    /// The OKLab distance, ×100.
    func distance(_ first: Swatch, _ second: Swatch) -> Double {
        let (one, two) = (first.lab, second.lab)
        let (lightness, greenRed, blueYellow) = (one.l - two.l, one.a - two.a, one.b - two.b)
        return 100 * (lightness * lightness + greenRed * greenRed + blueYellow * blueYellow).squareRoot()
    }

    /// OKLCh hue in degrees, and chroma.
    static func hueChroma(_ colour: Swatch) -> (hue: Double, chroma: Double) {
        var hue = 180 / Double.pi * atan2(colour.lab.b, colour.lab.a)
        hue = hue.truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        return (hue, hypot(colour.lab.a, colour.lab.b))
    }

    static func hueGap(_ first: Double, _ second: Double) -> Double {
        let gap = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(gap, 360 - gap)
    }

    /// `index` stepped by `delta` while `condition` holds, stopping at `limit`.
    func walk(_ index: Int, _ delta: Int, _ limit: Int, while condition: (Int) -> Bool) -> Int {
        var index = index
        while (delta > 0 ? index < limit : index > limit) && condition(index) { index += delta }
        return index
    }

    /// ``Color/lighter(by:)`` toward the text's side, ``Color/darker(by:)`` away.
    func push(_ colour: Swatch, _ amount: Double) -> Swatch {
        let moved = direction > 0 ? colour.color.lighter(by: amount) : colour.color.darker(by: amount)
        let (red, green, blue) = moved.rgbComponents ?? (0, 0, 0)
        return swatch(red, green, blue)
    }

    /// ``Color/hsl(_:_:_:)``, as a swatch.
    func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Swatch {
        let (red, green, blue) = Color.hsl(hue, saturation, lightness).rgbComponents ?? (0, 0, 0)
        return swatch(red, green, blue)
    }

    /// `steps + 1` points from `from` to `to`.
    func line(from: Swatch, to: Swatch) -> [Swatch] {
        (0...Self.steps).map { mix(from, to, Double($0) / Double(Self.steps)) }
    }

    /// A line's point `index`, clamped to its ends as a lerp's phase is.
    static func point(_ line: [Swatch], _ index: Int) -> Swatch { line[min(max(0, index), line.count - 1)] }

    /// A truecolour breath's 16 frames.
    func frames(_ dim: Swatch, _ top: Swatch) -> [Swatch] { Self.phases.map { mix(dim, top, $0) } }

    /// A 256-colour breath's 16 frames: ``Color/cubeRamp(from:to:)``'s steps, at
    /// ``Color/breathStep(atPhase:of:)``.
    func frames256(_ dim: Swatch, _ top: Swatch) -> [Swatch] {
        guard let dimIndex = Self.cubeIndex[dim.packed], let topIndex = Self.cubeIndex[top.packed] else {
            return Self.phases.map { _ in dim }
        }
        let key = UInt16(dimIndex) << 8 | UInt16(topIndex)
        if let known = frameMemo[key] { return known }
        let ramp: [Swatch] = Color.cubeRamp(from: dimIndex, to: topIndex).map { entry in
            guard case .palette256(let index) = entry.value else { return dim }
            return Self.cube[Int(index) - 16]
        }
        let answer = Self.phases.map { ramp[Color.breathStep(atPhase: $0, of: ramp.count)] }
        frameMemo[key] = answer
        return answer
    }

    // MARK: - Truecolour

    /// Sets ``pushed``: the accent, pushed toward the text in its own hue (HSL
    /// lightness) while it sits under 45 L\* off the page (S's ~12, 22 for the two
    /// peaks, and the ●'s margin) and the text still reads 2:1 on the next step.
    func pushAccent() {
        let count = Double(Self.steps)
        let amount = walk(0, 1, Self.steps) { step in
            lift(push(accent, Double(step) / count)) < 45 && contrast(text, push(accent, Double(step + 1) / count)) >= 2
        }
        pushed = push(accent, Double(amount) / count)
    }

    /// The rule's check of H0-H5 at truecolour (H6 holds by the path's cap).
    func holdsTrue(_ selection: Swatch, _ focus: (Swatch, Swatch), _ emphasis: (Swatch, Swatch)) -> Bool {
        let (focusFrames, emphasisFrames) = (frames(focus.0, focus.1), frames(emphasis.0, emphasis.1))
        let floor = Self.apartFloor
        func off(_ colour: Swatch, _ base: Swatch) -> Bool { sure(colour, base) >= floor && lift(colour, base) >= 2 }
        return off(selection, page) && focusFrames.allSatisfy { off($0, page) }
            && emphasisFrames.allSatisfy { off($0, selection) }
            && [15, 0, 1, 7, 8, 9].allSatisfy { sure(focusFrames[$0], selection) >= floor }
            && zip(focusFrames, emphasisFrames).allSatisfy { sure($0, $1) >= floor }
            && sure(emphasis.1, focus.1) >= floor && lift(emphasis.1, focus.1) >= 2
    }

    /// Where F's dim end rides: the path, the page's own line toward the text (it
    /// clears S by chroma where there is no lightness to spare), or a line toward the
    /// accent's opposite hue (it clears S by hue).
    enum FocusLine: CaseIterable { case path, text, complement }

    /// One look at truecolour, `rule.py`'s `place_true`: S and every peak ride the
    /// path; F's dim end rides `focusLine`. Every end is a walk, then one short walk
    /// per hard invariant, then the preferences (no F frame within one JND of S, B's
    /// peak 10 over F's).
    ///
    /// - Parameters:
    ///   - secondaryFloor: The secondary text's contrast on the path's top.
    ///   - selectionStep: Where S sits on the path, or `nil` to place it.
    ///   - keepDot: Whether the path's top stays 5.5 OKLab under the ● (the accent).
    ///   - need: The breath the walks ask for.
    func placeTrue(
        secondaryFloor: Double, selectionStep: Int?, focusLine: FocusLine, keepDot: Bool, need: Double
    ) -> Look {
        let (count, floor) = (Self.steps, Self.apartFloor)
        let rail = path
        func along(_ index: Int) -> Swatch { Self.point(rail, index) }
        let dimRail: [Swatch]
        switch focusLine {
        case .path: dimRail = rail
        case .text: dimRail = line(from: page, to: text)
        case .complement:
            let (hue, _, lightness) = Color.rgbToHSL(red: pushed.red, green: pushed.green, blue: pushed.blue)
            dimRail = line(from: page, to: hsl(hue + 180, 100, lightness))
        }
        func dimAlong(_ index: Int) -> Swatch { Self.point(dimRail, index) }

        // Up from the page to the last point before the text's 2:1 (and the secondary's
        // floor); past the text's own lightness the ratio climbs again, so the walk
        // never looks beyond the first failure. Then below the ●.
        var top = walk(1, 1, count) { index in
            contrast(text, along(index + 1)) >= 2 && contrast(secondary, along(index + 1)) >= secondaryFloor
        }
        top = walk(top, -1, 1) { keepDot && distance(accent, along($0)) < 5.5 }
        let room = lift(along(top))

        var iS: Int
        if let selectionStep {
            iS = selectionStep
        } else {
            // Today's S (the accent at 25%) where the accent faces the text, else 25% of
            // the pushed accent; moved down while the room above it cannot give F's top 8
            // over S and B's peak 10 over F's.
            let start = lift(accent) > 0 ? lift(mix(page, accent, 0.25)) : lift(along(32))
            iS = walk(1, 1, top) { lift(along($0)) < start }
            iS = walk(iS, -1, 1) { contrast(text, along($0)) < 3 }
            iS = walk(iS, 1, top) { index in
                (near(along(index), page) < 12 || lift(along(index)) < 6) && contrast(text, along(index + 1)) >= 3
            }
            iS = walk(iS, -1, 1) { index in
                room - lift(along(index)) < 18 && near(along(index - 1), page) >= 10 && lift(along(index - 1)) >= 8
            }
        }
        let selection = along(iS)
        let selectionLift = lift(selection)
        let free = max(0, room - selectionLift)
        let (focusGap, emphasisGap) =
            free >= 22 ? (10.0, 12.0) : free >= 18 ? (free / 2 - 1, free / 2 + 1) : (8 * free / 18, 10 * free / 18)
        var iFt = walk(iS, 1, top) { lift(along($0)) < selectionLift + focusGap }
        var iBt = walk(iFt, 1, top) { lift(along($0)) < selectionLift + focusGap + emphasisGap }
        let rise = lift(along(iBt), selection)
        var iBd = walk(iS + 1, 1, iBt) { index in
            lift(along(index + 1), selection) <= 0.5 * rise
                && (lift(along(index), selection) < max(3, 0.2 * rise) || near(along(index), selection) < 4)
        }
        let cap = min(0.6 * selectionLift, selectionLift - 2)
        var iFd = walk(1, 1, count) { index in
            lift(dimAlong(index + 1)) <= cap
                && (lift(dimAlong(index)) < max(3.5, 0.35 * selectionLift) || near(dimAlong(index), page) < 5)
        }
        iFd = walk(iFd, -1, 1) { near(dimAlong($0), selection) < 6 && near(dimAlong($0 - 1), page) >= 5 }

        // The hard invariants, one short walk each: H3, B's breath, H5, H2 at F's top,
        // F's breath, H1, H2 at F's dim end.
        iBd = walk(iBd, 1, iBt - 1) { sure(along($0), selection) < floor || lift(along($0), selection) < 2 }
        iBt = walk(iBt, 1, top) { lift(along($0), along(iBd)) < need }
        iFt = walk(iFt, -1, iS + 1) { sure(along(iBt), along($0)) < floor }
        iFt = walk(iFt, 1, iBt - 1) { index in
            (sure(along(index), selection) < floor || lift(along(index), dimAlong(iFd)) < need)
                && sure(along(iBt), along(index + 1)) >= floor
        }
        iFd = walk(iFd, 1, count) { sure(dimAlong($0), page) < floor || lift(dimAlong($0)) < 2 }
        iFd = walk(iFd, -1, 1) { index in
            sure(dimAlong(index), selection) < floor && sure(dimAlong(index - 1), page) >= floor
                && lift(dimAlong(index - 1)) >= 2
        }

        // A preference, not a gate: no F frame within one JND of S. F's dim end steps
        // toward the page (still 5 off it and 6 off S), else F's top up (leaving B's
        // peak room for 10 over it), else down (still 8 L* past S).
        func jnd(_ dim: Swatch, _ top: Swatch) -> Bool { frames(dim, top).map { near($0, selection) }.min()! < 1.2 }
        iFd = walk(iFd, -1, 1) { index in
            let below = dimAlong(index - 1)
            return jnd(dimAlong(index), along(iFt)) && near(below, page) >= 5 && sure(below, page) >= floor
                && near(below, selection) >= 6 && lift(below) >= 2
        }
        let focusTopBefore = iFt
        iFt = walk(iFt, 1, iBt - 1) { index in
            jnd(dimAlong(iFd), along(index)) && room - lift(along(index + 1)) >= 10
                && sure(along(iBt), along(index + 1)) >= floor
        }
        if jnd(dimAlong(iFd), along(iFt)) {
            iFt = walk(focusTopBefore, -1, iS + 1) { index in
                jnd(dimAlong(iFd), along(index)) && lift(along(index - 1), dimAlong(iFd)) >= need
                    && lift(along(index - 1), selection) >= 8 && sure(along(index - 1), selection) >= floor
            }
        }
        // B's peak keeps 10 L* over F's where the room allows.
        iBt = walk(iBt, 1, top) { lift(along($0), along(iFt)) < 10 }

        let focus = (dim: dimAlong(iFd), top: along(iFt))
        let emphasis = (dim: along(iBd), top: along(iBt))
        return Look(
            selection: selection, focus: focus, emphasis: emphasis,
            holds: holdsTrue(selection, focus, emphasis),
            breath: min(lift(focus.top, focus.dim), lift(emphasis.top, emphasis.dim)), selectionStep: iS)
    }

    /// The truecolour look, `rule.py`'s `rule_true`: the first that holds H0-H5
    /// with both breaths at least 12 L\*, else the one that holds them and breathes
    /// most.
    ///
    /// Variants, in order: the secondary text's 1.5:1 cap, then none; then the ●'s
    /// margin dropped; then the accent at full HSL saturation; then the same without
    /// the breath target. In each, F's dim end on the path, then on the page's own
    /// line (and, at full saturation, toward the complement); and S where the walk
    /// puts it, then a step down, a step up, two down… (every other step, at most 24
    /// either way; the text 3:1 on S first, then 2:1).
    func truecolour() -> Look {
        pushAccent()
        let base = pushed
        var best: Look?
        let variants: [(need: Double, secondaryFloor: Double, keepDot: Bool, vivid: Bool)] = [
            (12, 1.5, true, false), (12, 0, true, false), (12, 0, false, false),
            (12, 0, false, true), (0, 1.5, true, false), (0, 0, false, true),
        ]
        for variant in variants {
            let (hue, saturation, lightness) = Color.rgbToHSL(red: base.red, green: base.green, blue: base.blue)
            pushed = hsl(hue, variant.vivid ? 100 : saturation, lightness)
            path = line(from: page, to: pushed)
            func selectionHolds(_ index: Int, _ textFloor: Double) -> Bool {
                let point = Self.point(path, index)
                return 2 <= index && index < Self.steps && sure(point, page) >= 5 && lift(point) >= 3
                    && contrast(text, point) >= textFloor
            }
            for focusLine in variant.vivid ? FocusLine.allCases : [.path, .text] {
                func place(_ step: Int?) -> Look {
                    placeTrue(
                        secondaryFloor: variant.secondaryFloor, selectionStep: step, focusLine: focusLine,
                        keepDot: variant.keepDot, need: variant.need)
                }
                let start = place(nil).selectionStep
                for textFloor in [3.0, 2.0] {
                    for attempt in 0..<25 {
                        let index = start + 2 * ((attempt + 1) / 2) * (attempt % 2 == 1 ? 1 : -1)
                        if attempt > 0 || textFloor < 3,
                            !selectionHolds(index, textFloor) || (textFloor < 3 && selectionHolds(index, 3))
                        {
                            continue
                        }
                        let look = place(index)
                        if look.holds && look.breath >= 12 { return look }
                        if look.beats(best) { best = look }
                    }
                }
            }
        }
        return best!
    }
}
