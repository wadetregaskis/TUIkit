//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+PulseRamp.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {

    /// The colours a `dim`…`bright` fade can actually PRODUCE on this terminal,
    /// in order, with the off-hue ones removed.
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
    /// Walking this list at even intervals instead gives every shade the same
    /// screen time, so the animation is as smooth as the palette permits and
    /// never off-hue. Truecolor callers should keep the continuous lerp — there
    /// the ramp is effectively infinite.
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
        guard depth < .truecolor else { return [dim, bright] }

        // Memoised by its four inputs. A ramp is a pure function of them, and a
        // pulse asks for the SAME one every frame it runs — sixteen times a
        // breath, for as long as the control is focused — so building it walks
        // 256 candidates through the quantiser each time unless the answer is
        // kept. A caller that hoists (``SelectionEmphasisCycle`` builds one per
        // cycle) never gets here twice; one that does not pays a dictionary
        // hit rather than the walk, which is what lets the hoist be an
        // optimisation and not a correctness requirement.
        let key = PulseRampKey(dim: dim, bright: bright, depth: depth, samples: samples)
        if let cached = pulseRampCacheLock.withLock({ pulseRampCache[key] }) { return cached }

        // An achromatic step is only a defect when the fade itself is meant to
        // have colour — a grey accent (the White / Pro / Silver Aerogel
        // palettes) is *supposed* to render grey.
        let wantsHue = dim.hasHue(depth: depth) || bright.hasHue(depth: depth)

        var ramp: [Color] = []
        var seen: [Color] = []
        for step in 0...max(1, samples) {
            let candidate = Color.lerp(dim, bright, phase: Double(step) / Double(max(1, samples)))
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
            if wantsHue && rendered.isAchromatic { continue }
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

    private struct PulseRampKey: Hashable {
        let dim: Color
        let bright: Color
        let depth: ColorDepth
        let samples: Int
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
        case .palette256(let index):
            if index >= 232 { return true }  // the 24-step greyscale ramp
            if index < 16 { return index == 0 || index == 7 || index == 8 || index == 15 }
            let cube = Int(index) - 16
            let red = cube / 36
            let green = (cube % 36) / 6
            let blue = cube % 6
            return red == green && green == blue
        case .standard(let ansi), .bright(let ansi):
            return ansi == .black || ansi == .white
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
