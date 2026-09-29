//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+PulseRamp.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {
    /// The phase of a breath of `count` frames at `frame`: 1 at frame 0 (the bright
    /// end), 0 halfway round, on a cosine, so the breath eases at both ends.
    ///
    /// Here rather than on the clock that ticks it because what a breath shows at each
    /// frame is a question about colour: the row-fill rule checks every frame of the
    /// breaths it chooses, and must see the ones the terminal will draw.
    package static func breathPhase(atFrame frame: Int, of count: Int) -> Double {
        guard count > 0 else { return 1 }
        let wrapped = frame % count
        let normalized = Double(wrapped < 0 ? wrapped + count : wrapped) / Double(count)
        // Cosine wave: 1 → 0 → 1 over the cycle, so frame 0 is the bright end.
        return (cos(normalized * 2 * .pi) + 1) / 2
    }

    /// Which of a ramp's `count` steps a breath shows at `phase`, dim step first.
    ///
    /// Even intervals of TIME, not of `phase`. The phase is a cosine of the clock
    /// (``breathPhase(atFrame:of:)``), so slicing it evenly gave the ends most of the
    /// cycle: a three-shade ramp over 16 frames showed 7/2/7 frames, and the middle
    /// shade flashed past. `acos` undoes the cosine, so the same ramp shows 5/6/5; a
    /// two-shade ramp (every 16-colour breath) shows its bright end on frames 0–4 and
    /// 12–15 and its dim end on 5–11 — symmetric about the dim frame. The epsilon keeps
    /// frame 12, whose phase computes as 0.4999…, on the same side as frame 4.
    package static func breathStep(atPhase phase: Double, of count: Int) -> Int {
        let time = acos(min(1, max(-1, 1 - 2 * phase))) / .pi
        let step = Int((time * Double(count) + 1e-9).rounded(.down))
        return min(max(0, step), count - 1)
    }

    /// The colours a `dim`…`bright` fade can actually PRODUCE on this terminal,
    /// in order, with the off-hue ones removed — all but `bright`'s own.
    ///
    /// A pulse is written as a continuous lerp sampled on an even time grid,
    /// which is right on a truecolor terminal and wrong everywhere else. On a
    /// 256-colour terminal (Apple Terminal has no truecolor at all) every step
    /// is rounded onto the 6×6×6 cube, and a narrow accent ramp lands on only
    /// three or four indices — so most of the fade sits still and then jumps.
    /// Worse, the cube has no *dark tinted* entries (its lowest non-zero channel
    /// is 95), so the bottom of a ramp over a near-black background quantises to
    /// a **grey**: a green control briefly turns grey mid-breath, which reads as
    /// a glitch rather than as a dim. That is the "juddering" a pulse shows on
    /// Apple Terminal.
    ///
    /// Walking this list at even intervals of time (not of the cosine phase —
    /// see ``breathStep(atPhase:of:)``) instead gives every shade the same
    /// screen time, so the animation is as smooth as the palette permits and
    /// never off-hue. Truecolor callers should keep the continuous lerp — there
    /// the ramp is effectively infinite.
    ///
    /// The one achromatic entry kept is `bright`'s own rendering. A fade whose
    /// visible end is black or grey was asked for that colour, so showing it is
    /// no hue lost on the way: Red Sands' focus wash breathes from a dark brown
    /// down to near-black (`3D1916` to `000005`, away from a brick page), which
    /// the cube draws as `5F0000` to black — and dropping the black left it one
    /// colour, a cursor row that did not breathe. Where the grey is on the way,
    /// or at the dim end (an accent over a near-black page, whose bottom
    /// renders as the page itself), it is still dropped.
    ///
    /// - Parameters:
    ///   - dim: The recessive endpoint.
    ///   - bright: The visible endpoint.
    ///   - depth: The terminal's colour depth.
    ///   - samples: How finely to look for distinct steps. The default exceeds
    ///     the 240-entry palette, so every entry the segment passes through is
    ///     found. It used to be 64, which is enough for a typical span and not
    ///     for a wide one: sampling a LONGER segment at the same count steps
    ///     further each time and can miss a band a shorter segment catches —
    ///     Silver Aerogel's near-neutral accent lost `#8787AF` that way, so a
    ///     full-span ramp came out with FEWER shades than a bounded one drawn
    ///     from inside it. Quantisation is memoised, so the extra samples cost
    ///     dictionary hits, not conversions.
    /// - Returns: The distinct rendered colours from `dim` to `bright`, always
    ///   at least `[bright]`.
    public static func pulseRamp(
        from dim: Color, to bright: Color, depth: ColorDepth, samples: Int = 256
    ) -> [Color] {
        pulseRamp(
            from: dim, to: bright, depth: depth, samples: samples,
            terminalColorsGeneration: TerminalColors.generation)
    }

    /// `pulseRamp(from:to:depth:samples:)`, memoised under
    /// `terminalColorsGeneration` rather than the process's current generation.
    ///
    /// Internal, not private, so a test can ask under a generation of its own.
    /// Moving the process-wide one instead would clear every cache in the test
    /// process.
    static func pulseRamp(
        from dim: Color, to bright: Color, depth: ColorDepth, samples: Int = 256,
        terminalColorsGeneration: Int
    ) -> [Color] {
        guard depth < .truecolor else { return [dim, bright] }

        // Memoised by its four inputs. A ramp is a pure function of them, and a
        // pulse asks for the SAME one every frame it runs — sixteen times a
        // breath, for as long as the control is focused — so building it walks
        // 256 candidates through the quantiser each time unless the answer is
        // kept. A caller that hoists (``SelectionEmphasisCycle`` builds one per
        // cycle) never gets here twice; one that does not pays a dictionary
        // hit rather than the walk, which is what lets the hoist be an
        // optimisation and not a correctness requirement.
        //
        // Pure while the terminal's colours stand still, that is: an end that is
        // the terminal's own measures as what the terminal reported, so a new
        // report can change the ramp. Their generation is in the key.
        let key = PulseRampKey(
            dim: dim, bright: bright, depth: depth, samples: samples,
            terminalColorsGeneration: terminalColorsGeneration)
        if let cached = pulseRampCacheLock.withLock({ pulseRampCache[key] }) { return cached }

        if depth == .palette256, case .palette256(let dimIndex) = dim.value,
            case .palette256(let brightIndex) = bright.value, dimIndex >= 16, brightIndex >= 16
        {
            let answer = cubeRamp(from: dimIndex, to: brightIndex)
            pulseRampCacheLock.withLock { pulseRampCache[key] = answer }
            return answer
        }

        // An achromatic step is only a defect when the fade itself is meant to
        // have colour — a grey accent (the White / Pro / Silver Aerogel
        // palettes) is *supposed* to render grey.
        let wantsHue = dim.hasHue(depth: depth) || bright.hasHue(depth: depth)
        // …and never at the end the fade is ASKED to reach: that one is the
        // breath's own colour, not a hue the cube lost on the way. See above.
        let brightRendered = bright.rendered(at: depth)

        var ramp: [Color] = []
        var seen: [Color] = []
        for step in 0...max(1, samples) {
            let candidate = Self.lerp(dim, bright, phase: Double(step) / Double(max(1, samples)))
            let rendered = candidate.rendered(at: depth)
            // Skipped if this colour has been shown ALREADY, not merely if it
            // repeats the previous step. A continuous lerp does not have to
            // quantise monotonically: rounding two channels at different rates
            // makes the chosen entry step forward, back, and forward again.
            // Novel's accent does exactly that — #D7AF87, #D7875F, #AF875F,
            // #D7875F, #AF875F — and comparing only against the last step let
            // the bounce through, so the "breath" visibly wobbled instead of
            // fading. Each distinct shade appears once, in the order first
            // reached; `samples` is small (64) so the linear scan is nothing.
            guard !seen.contains(rendered) else { continue }
            seen.append(rendered)
            if wantsHue && rendered.isAchromatic && rendered != brightRendered { continue }
            ramp.append(candidate)
        }
        // Dropping the greys can empty a ramp whose whole span was off-hue.
        // A steady bright beats a grey flicker.
        let answer = ramp.isEmpty ? [bright] : ramp
        pulseRampCacheLock.withLock {
            // A backstop against unbounded growth, not a working-set estimate:
            // a real app has a handful of accents at a handful of depths. Same
            // shape as `ScrollbarColors.track`'s cap.
            if pulseRampCache.count > 128 { pulseRampCache.removeAll(keepingCapacity: true) }
            pulseRampCache[key] = answer
        }
        return answer
    }

    /// The breath between two cube entries: the two ends, with at most one
    /// middle step between them.
    ///
    /// A row's fills at 256 colours are chosen at coding time as cube entries
    /// (`RowFills`), and a lerp between two entries re-quantised along the way
    /// wanders: it can pass through a grey, or through S's own entry, which
    /// would put the selected row's colour on the cursor row mid-breath. So
    /// the steps are a function of the two ends alone, and every caller that
    /// breathes between them — a list or table row, a menu, a drop-down, the
    /// DatePicker, the split-view divider, `accentFillPulse` — draws the same
    /// ones.
    ///
    /// The middle is the entry nearest the ends' OKLab midpoint whose L* lies
    /// at least 2 inside both ends, in the ends' hue (within 30° OKLCh of
    /// each), or a grey between two greys; ties go to the lower index. There
    /// is none between a grey end and a hued one — a phosphor palette's cursor
    /// row, from the lifted page to the accent — because there the middle
    /// would be the cube's darkest tinted entry, which is where the selected
    /// row sits. The text stays legible on the middle: its lightness is
    /// between the ends', and so is its contrast with the text.
    ///
    /// `Tools/RowFillValues/generate.py`'s `cube_ramp` is the reference; the
    /// shipped palettes' ramps are pinned against it.
    static func cubeRamp(from dim: UInt8, to bright: UInt8) -> [Color] {
        guard dim != bright else { return [.palette256(dim)] }
        let dimRGB = palette256ToRGB(dim)
        let brightRGB = palette256ToRGB(bright)
        let dimLightness = Self.rgb(dimRGB.red, dimRGB.green, dimRGB.blue).perceivedLightness ?? 0
        let brightLightness = Self.rgb(brightRGB.red, brightRGB.green, brightRGB.blue).perceivedLightness ?? 0
        let lowest = min(dimLightness, brightLightness) + 2
        let highest = max(dimLightness, brightLightness) - 2
        let ends = [Self.palette256(dim), .palette256(bright)]
        guard lowest <= highest else { return ends }

        func isGrey(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> Bool {
            rgb.red == rgb.green && rgb.green == rgb.blue
        }
        func oklab(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> (l: Double, a: Double, b: Double) {
            Self.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        func hue(_ lab: (l: Double, a: Double, b: Double)) -> Double { atan2(lab.b, lab.a) * 180 / .pi }
        func hueGap(_ first: Double, _ second: Double) -> Double {
            let gap = abs(first - second).truncatingRemainder(dividingBy: 360)
            return min(gap, 360 - gap)
        }

        let dimLab = oklab(dimRGB)
        let brightLab = oklab(brightRGB)
        let dimHue = isGrey(dimRGB) ? nil : hue(dimLab)
        let brightHue = isGrey(brightRGB) ? nil : hue(brightLab)
        guard (dimHue == nil) == (brightHue == nil) else { return ends }
        let middle = (
            l: (dimLab.l + brightLab.l) / 2, a: (dimLab.a + brightLab.a) / 2, b: (dimLab.b + brightLab.b) / 2)

        var best: (distance: Double, index: UInt8)?
        for index in UInt8(16)...UInt8(255) where index != dim && index != bright {
            let rgb = palette256ToRGB(index)
            guard let lightness = Self.rgb(rgb.red, rgb.green, rgb.blue).perceivedLightness,
                lowest <= lightness, lightness <= highest, isGrey(rgb) == (brightHue == nil)
            else { continue }
            let lab = oklab(rgb)
            if let brightHue, let dimHue {
                guard hueGap(hue(lab), brightHue) <= 30, hueGap(hue(lab), dimHue) <= 30 else { continue }
            }
            let distance = (lab.l - middle.l) * (lab.l - middle.l) + (lab.a - middle.a) * (lab.a - middle.a)
                + (lab.b - middle.b) * (lab.b - middle.b)
            if best.map({ distance < $0.distance }) ?? true { best = (distance, index) }
        }
        guard let best else { return ends }
        return [ends[0], .palette256(best.index), ends[1]]
    }

    private struct PulseRampKey: Hashable {
        let dim: Color
        let bright: Color
        let depth: ColorDepth
        let samples: Int
        let terminalColorsGeneration: Int
    }

    private static let pulseRampCacheLock = NSLock()
    nonisolated(unsafe) private static var pulseRampCache: [PulseRampKey: [Color]] = [:]

    /// This colour as the terminal will actually draw it at `depth`.
    func rendered(at depth: ColorDepth) -> Color {
        switch depth {
        case .truecolor: return self
        case .palette256: return downsampledToPalette256()
        case .basic16, .noColor: return downsampledToANSI16()
        }
    }

    /// Whether the rendered form carries no hue — a cube grey, a greyscale ramp
    /// entry, or one of the achromatic ANSI 16.
    var isAchromatic: Bool {
        switch value {
        case .rgb(let red, let green, let blue):
            return red == green && green == blue
        case .terminalForeground, .terminalBackground:
            // The RGB the terminal reported. One it has not reported cannot be
            // measured, so it is not known to be a grey.
            guard let (red, green, blue) = rgbComponents else { return false }
            return red == green && green == blue
        case .palette256(let index):
            if index >= 232 { return true }  // the 24-step greyscale ramp
            if index < 16 { return index == 0 || index == 7 || index == 8 || index == 15 }
            let cube = Int(index) - 16
            let red = cube / 36
            let green = (cube % 36) / 6
            let blue = cube % 6
            return red == green && green == blue
        case .ansi(let slot):
            // By which slot it is: black, white and their bright twins.
            return slot == .black || slot == .white || slot == .brightBlack || slot == .brightWhite
        case .terminalDefault:
            return false
        case .semantic:
            // Unresolved — a palette lookup, not a drawable colour yet.
            return false
        }
    }

    /// Whether this colour still has a hue once the terminal has rounded it.
    func hasHue(depth: ColorDepth) -> Bool {
        !rendered(at: depth).isAchromatic
    }
}
