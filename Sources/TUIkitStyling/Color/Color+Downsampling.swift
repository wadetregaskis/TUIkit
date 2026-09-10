//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+Downsampling.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Public API

extension Color {
    /// Converts this color to the nearest 256-color palette entry.
    ///
    /// - `.standard` and `.bright` already map to palette indices 0–15;
    ///   returned unchanged.
    /// - `.palette256` already in range; returned unchanged.
    /// - `.rgb` is quantized to the nearest 6×6×6 cube color (16–231) in
    ///   OKLab, hue weighted so it stays in the original's color family. A
    ///   grayscale ramp entry (232–255) is reachable only by a near-neutral
    ///   color: one with a hue of its own may land only on an entry that has a
    ///   hue too, or on black, so a fading accent never steps through gray.
    /// - `.semantic` must be resolved before calling this method.
    public func downsampledToPalette256() -> Color {
        switch value {
        case .standard, .bright, .palette256:
            return self
        case .rgb(let red, let green, let blue):
            let index = Self.nearestPalette256Index(red: red, green: green, blue: blue)
            return Color.palette(index).carryingAlpha(of: self)
        case .semantic:
            return self
        }
    }

    /// Converts this color to the nearest basic ANSI color (16-color).
    ///
    /// - `.standard` and `.bright` already in range; returned unchanged.
    /// - `.palette256` indices 0–15 map directly to standard/bright;
    ///   indices 16–255 are converted via their RGB representation.
    /// - `.rgb` is matched to the closest of the 16 standard/bright
    ///   ANSI colors using Euclidean distance in RGB space.
    /// - `.semantic` must be resolved before calling this method.
    public func downsampledToANSI16() -> Color {
        switch value {
        case .standard, .bright:
            return self
        case .palette256(let index):
            return Self.palette256ToANSI16(index).carryingAlpha(of: self)
        case .rgb(let red, let green, let blue):
            return Self.rgbToNearestANSI16(red: red, green: green, blue: blue)
                .carryingAlpha(of: self)
        case .semantic:
            return self
        }
    }
}

// MARK: - Quantising a whole ramp

extension Color {
    /// A gradient's per-cell colours, quantised as a RAMP rather than one cell
    /// at a time.
    ///
    /// ## Why a ramp needs its own answer
    ///
    /// ``downsampledToPalette256()`` is exact about one colour and knows nothing
    /// about its neighbours, which is the right contract for a background or a
    /// label and the wrong one for a gradient. Banding is a property of the
    /// SEQUENCE: a ramp is smooth when its entries move in one direction, and a
    /// per-cell nearest-neighbour search has no reason to keep them doing so.
    ///
    /// The default track gradient — `FF5050 → FFC850 → 50DC78` over 40 cells —
    /// quantised to `203×5 202 209×5 208×2 215×4 214×2 221×4 …`. 202, 208 and
    /// 214 are the cube's **blue = 0** corner; their neighbours 203, 209, 215
    /// are the same colours at blue = 95, and the interpolated colour there has
    /// blue = 80. A 15-point error passed over for an 80-point one, once, in the
    /// middle of a smooth run — which is exactly what "out-of-place colours"
    /// looks like.
    ///
    /// ## What this does instead
    ///
    /// Quantise each cell with the ordinary metric — **unchanged**, because it
    /// is load-bearing far outside gradients (``SystemPalette`` reads quantised
    /// colours to decide when a surface has stepped far enough off its page, so
    /// retuning it moves palette derivation) — and then repair the sequence.
    ///
    /// The repair: group the entries into runs, find the first step where a
    /// run's entry moves a channel *against* the direction the ramp moves it
    /// there, drop the entry belonging to the SHORTER of the two runs, and
    /// re-quantise the affected cells among the entries that remain. Repeat.
    /// One entry dies per pass, so it terminates; three passes sufficed for
    /// every ramp measured.
    ///
    /// A run's LENGTH is the tie-break, and it needs no tuning because it is not
    /// a threshold: the number of cells an entry wins is the extent of the ramp
    /// for which it genuinely is nearest, so a lateral excursion is short by
    /// construction and a real step is long. A distance slack was tried instead
    /// and reproduces the tuning problem exactly — 0.02 collapses the default
    /// ramp to four runs, 0.005 to two, while still leaving other ramps' strays
    /// in place.
    ///
    /// Measured over ten real ramps at 40 cells: every monotonicity violation
    /// removed (6→0, 7→0, 3→0, 2→0), bit-identical on the five that had none,
    /// and mean OKLab error slightly LOWER on four of the five it changed.
    ///
    /// - Parameters:
    ///   - gradient: The ramp to sample. Fewer than two stops is a flat colour
    ///     and needs no repair.
    ///   - count: How many cells the ramp spans.
    ///   - depth: The terminal's colour depth. Anything but ``ColorDepth/palette256``
    ///     returns the plain interpolation, so a caller never has to branch.
    /// - Returns: `count` colours. Palette entries at 256-colour depth — which
    ///   the ANSI layer passes through untouched — and interpolated RGB
    ///   otherwise.
    public static func quantisedRamp(_ gradient: Gradient, count: Int, depth: ColorDepth) -> [Color] {
        // The cache is consulted BEFORE the ramp is sampled, which is the whole
        // point of having one: sampling is the expensive half, and asking after
        // doing it meant a hit cost exactly as much as a miss's first stage.
        // Measured, release: a 2-stop 40-cell hit was 0.288 µs, which is to the
        // nanosecond what the uncached truecolor path costs — i.e. all of it was
        // the interpolation the cache existed to skip.
        //
        // Sound because the key is a function of the arguments alone, and the
        // two guards below that a cached answer implies are equally so:
        // `sampled.count` IS `max(0, count)`, and an entry is only ever stored
        // on the path where both guards passed.
        let key = RampKey(gradient: gradient, count: count, depth: depth)
        let worthCaching = count > 2
        if worthCaching, let cached = cachedRamp(key) { return cached }

        let sampled = gradient.sampled(count: count)
        // Only the 6x6x6 cube bands. A truecolor terminal draws what it is
        // given, and a 16-colour one has so few entries that monotonicity is
        // not the interesting problem.
        //
        // The SAMPLING is still worth keeping at those depths, and used not to
        // be: this returned before reaching the store, so a truecolor gradient
        // re-interpolated its whole ramp for every leaf that painted it. Under
        // `.gradientExtent(.subtree)` that is once per row of the subtree, for
        // a ramp that is identical every time — measured at 40 leaves, it was
        // most of the difference between the subtree case and the manual one.
        guard depth == .palette256, sampled.count > 2 else {
            if worthCaching { storeRamp(sampled, for: key) }
            return sampled
        }
        guard sampled.allSatisfy({ $0.rgbComponents != nil }) else {
            storeRamp(sampled, for: key)
            return sampled
        }

        var entries = sampled.map { $0.downsampledToPalette256() }
        // The survivors, ASCENDING and built once. Both halves matter, and both
        // used to be paid per pass: the set was rebuilt from `(16...255)` minus a
        // banned set on every pass, and `nearestPalette256Index(among:)` sorted
        // whatever it was handed — 240 entries — once per SAMPLE. A 36-cell
        // gradient samples 145 times and can retire dozens of entries, so that is
        // thousands of 240-element sorts to answer a question whose candidate
        // order never changes.
        //
        // Free at -O, most of this function at -Onone, and the Example is run from
        // a debug build: the Progress & Gauges page's first open was **1,182 ms**,
        // of which 861 ms was one custom-stop gradient bar and 330 ms the rainbow
        // one. Release was 30 ms before and after — this is a -Onone story, like
        // `ASCIIPalette+Adaptive`'s buffer walks, and it is worth the same
        // treatment for the same reason.
        var survivors = Array(UInt8(16)...UInt8(255))
        // One entry retired per pass, and never below two, so this cannot spin.
        for _ in 0..<max(1, sampled.count) {
            guard let offender = firstMonotonicityBreak(in: entries, along: sampled) else { break }
            guard let retired = paletteIndex(of: entries[offender]) else { break }
            guard let position = survivors.firstIndex(of: retired) else { break }
            survivors.remove(at: position)
            guard survivors.count > 2 else { break }
            // Only the samples that had CHOSEN the retired entry can move. For any
            // other sample the nearest survivor is unchanged by definition — its
            // choice is still in the set — so re-deriving it produced the identical
            // answer at the cost of a full sweep per pass.
            for index in entries.indices where paletteIndex(of: entries[index]) == retired {
                guard let rgb = sampled[index].rgbComponents else { continue }
                // `.carryingAlpha` for the reason every other derivation in this
                // file has one: a ramp entry the repair remaps came back OPAQUE
                // while its untouched neighbours kept their alpha, so one
                // translucent gradient rendered differently per entry at 256-colour
                // depth and identically at truecolor — silently, since an opaque
                // colour never trips the emitter's assertion.
                entries[index] = Color.palette(
                    nearestPalette256Index(
                        red: rgb.red, green: rgb.green, blue: rgb.blue, among: survivors)
                ).carryingAlpha(of: sampled[index])
            }
        }

        storeRamp(entries, for: key)
        return entries
    }

    /// The cached ramp for `key`, promoting a previous-generation entry.
    private static func cachedRamp(_ key: RampKey) -> [Color]? {
        rampCacheLock.lock()
        defer { rampCacheLock.unlock() }
        if let live = rampCache[key] { return live }
        // A hit in the older generation is proof the entry is still wanted, so
        // it moves up rather than being re-derived when that generation goes.
        guard let stale = previousRampCache[key] else { return nil }
        rampCache[key] = stale
        return stale
    }

    /// Stores `entries`, retiring a generation rather than the whole cache when
    /// the live one fills.
    ///
    /// `removeAll` at the cap was a cliff: crossing it — a terminal resized
    /// across many widths, say, since the width is part of the key — threw away
    /// every warm ramp at once and re-paid each one cold (21.7 µs for 2 stops
    /// over 40 cells, 47.7 µs for 6 over 120). Two generations bound the loss to
    /// the half that has not been asked for since the last turnover, and cost
    /// one extra dictionary probe on a miss.
    private static func storeRamp(_ entries: [Color], for key: RampKey) {
        rampCacheLock.lock()
        defer { rampCacheLock.unlock() }
        if rampCache.count >= rampCacheGenerationSize {
            previousRampCache = rampCache
            rampCache.removeAll(keepingCapacity: true)
        }
        rampCache[key] = entries
    }

    /// The index of the first run whose entry moves a channel against the way
    /// the ramp moves it there — or `nil` when the sequence is already monotone.
    ///
    /// Returns the cell belonging to the SHORTER of the two runs at the break,
    /// because that is the one more likely to be a lateral excursion than a
    /// step (see ``quantisedRamp(_:count:depth:)``).
    private static func firstMonotonicityBreak(in entries: [Color], along ramp: [Color]) -> Int? {
        var runs: [(start: Int, end: Int)] = []
        for index in entries.indices {
            if let last = runs.last, entries[index] == entries[last.start] {
                runs[runs.count - 1].end = index
            } else {
                runs.append((start: index, end: index))
            }
        }
        guard runs.count > 1 else { return nil }

        for step in 1..<runs.count {
            let before = runs[step - 1]
            let after = runs[step]
            guard let a = entries[before.start].rgbComponents,
                let b = entries[after.start].rgbComponents,
                let sourceA = ramp[before.start].rgbComponents,
                let sourceB = ramp[after.start].rgbComponents
            else { continue }
            let entryDelta = [
                Int(b.red) - Int(a.red), Int(b.green) - Int(a.green), Int(b.blue) - Int(a.blue),
            ]
            let rampDelta = [
                Int(sourceB.red) - Int(sourceA.red),
                Int(sourceB.green) - Int(sourceA.green),
                Int(sourceB.blue) - Int(sourceA.blue),
            ]
            // A channel the entries move one way while the ramp moves it the
            // other — or moves at all while the ramp holds it still.
            let against = zip(entryDelta, rampDelta).contains { entry, source in
                entry != 0 && (source == 0 || (entry > 0) != (source > 0))
            }
            guard against else { continue }
            let beforeLength = before.end - before.start + 1
            let afterLength = after.end - after.start + 1
            return beforeLength <= afterLength ? before.start : after.start
        }
        return nil
    }

    /// The palette index behind a quantised colour, when it has one.
    private static func paletteIndex(of colour: Color) -> UInt8? {
        if case .palette256(let index) = colour.value { return index }
        return nil
    }

    /// The nearest entry among a restricted candidate set — the repair's
    /// re-assignment, using the very same metric as the unrestricted search so
    /// that dropping an entry is the ONLY difference between them.
    /// - Parameter candidates: The palette indices to choose from, **ascending**.
    ///   An array rather than a `Set` because the walk needs an order — the lowest
    ///   index wins a tie — and sorting a set to get one, per call, was most of
    ///   this function's cost at -Onone (see `quantisedRamp`).
    private static func nearestPalette256Index(
        red: UInt8, green: UInt8, blue: UInt8, among candidates: [UInt8]
    ) -> UInt8 {
        let target = oklab(red: red, green: green, blue: blue)
        let mustKeepHue = (target.a * target.a + target.b * target.b).squareRoot() >= Self.hueFloor
        var bestIndex: UInt8 = 16
        var bestDistance = Double.infinity
        let targetChroma = (target.a * target.a + target.b * target.b).squareRoot()
        for index in candidates {
            if mustKeepHue && !Self.keepsItsHue[Int(index) - 16] { continue }
            let distance = hueWeightedDistanceSquared(
                target, chroma: targetChroma, palette256Lab[Int(index) - 16])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private struct RampKey: Hashable {
        let gradient: Gradient
        let count: Int
        let depth: ColorDepth
    }

    private static let rampCacheLock = NSLock()
    nonisolated(unsafe) private static var rampCache: [RampKey: [Color]] = [:]

    /// The generation retired when ``rampCache`` fills. Still consulted, so a
    /// turnover costs a re-promotion rather than a re-derivation.
    nonisolated(unsafe) private static var previousRampCache: [RampKey: [Color]] = [:]

    /// How many ramps a generation holds. The cache therefore tops out at twice
    /// this; the number is a guard against unbounded growth, not a working-set
    /// estimate — a real app has a handful of gradients at a handful of widths.
    private static let rampCacheGenerationSize = 512
}

// MARK: - Private Helpers

extension Color {
    /// Finds the nearest 256-color palette index for an RGB color.
    ///
    /// "Nearest" is perceptual, not per-channel: candidates (the 6×6×6 cube and
    /// the grayscale ramp, less the neutral entries a colour that HAS a hue may
    /// not take — see `keepsItsHue`) are compared in OKLab with the HUE
    /// difference weighted ×4. The 216-colour cube is coarse in the pale
    /// range, where per-channel rounding shifts hue — Solid Colors' warm
    /// cream #F2DEC9 rounded to pink (255,215,215) instead of the warm
    /// (255,215,175), turning a whole background rosy. Weighting hue keeps a
    /// quantised colour in its own colour family; greys (no chroma) and
    /// saturated colours (a cube point close by) are unaffected.
    ///
    /// Results are memoised — a full-screen render quantises two colours per
    /// cell, but an app only ever uses a few dozen distinct colours.
    fileprivate static func nearestPalette256Index(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let key = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        quantiseCacheLock.lock()
        let cached = quantiseCache[key]
        quantiseCacheLock.unlock()
        if let cached { return cached }

        let target = oklab(red: red, green: green, blue: blue)
        let targetChroma = (target.a * target.a + target.b * target.b).squareRoot()
        // A colour that HAS a hue may only quantise to something that has one
        // too — or to black. See `keepsItsHue`.
        let mustKeepHue = targetChroma >= Self.hueFloor
        var bestIndex = 16
        var bestDistance = Double.infinity
        // Deliberate linear scan: n=240, and OKLab distance has no ordering to
        // exploit — don't "optimise" it into a tree. The buffer pointers are
        // not that optimisation: they are the same walk with the two static
        // arrays bound once instead of re-checked on each of 240 iterations,
        // which matters because the memo below stopped covering this. A picture
        // asks per CELL, thousands of distinct colours at a time, and every one
        // of them is a miss.
        Self.keepsItsHue.withUnsafeBufferPointer { keepsItsHue in
            palette256Lab.withUnsafeBufferPointer { candidates in
                for offset in 0..<candidates.count {
                    if mustKeepHue && !keepsItsHue[offset] { continue }
                    let distance = hueWeightedDistanceSquared(
                        target, chroma: targetChroma, candidates[offset])
                    if distance < bestDistance {
                        bestDistance = distance
                        bestIndex = offset + 16
                    }
                }
            }
        }

        quantiseCacheLock.lock()
        if quantiseCache.count > 4096 { quantiseCache.removeAll(keepingCapacity: true) }
        quantiseCache[key] = UInt8(bestIndex)
        quantiseCacheLock.unlock()
        return UInt8(bestIndex)
    }

    /// OKLab coordinates for palette indices 16...255, in index order, each
    /// with the chroma it implies.
    ///
    /// The chroma is STORED rather than derived at comparison time because
    /// ``hueWeightedDistanceSquared`` needs `sqrt(a² + b²)` for the candidate on
    /// every single comparison — the same square root of the same fixed number,
    /// 240 times per query. Storing it changes no answer: it is the same
    /// expression over the same values, evaluated once.
    private static let palette256Lab: [(l: Double, a: Double, b: Double, chroma: Double)] =
        (16...255).map {
            let rgb = palette256ToRGB(UInt8($0))
            let lab = oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
            return (lab.l, lab.a, lab.b, (lab.a * lab.a + lab.b * lab.b).squareRoot())
        }

    private static let quantiseCacheLock = NSLock()
    nonisolated(unsafe) private static var quantiseCache: [UInt32: UInt8] = [:]

    /// How much OKLab chroma a colour needs before it counts as HAVING a hue,
    /// and so before it is held to keeping one.
    ///
    /// Well above floating-point noise and well below any deliberate tint: the
    /// palest shipped palette tone (Novel's #DFDBC3) sits at ~0.02.
    private static let hueFloor = 0.01

    /// Whether each palette entry (16…255) is one a chromatic colour may
    /// quantise to: it has a hue of its own, or it is black.
    ///
    /// The 6×6×6 cube's lowest non-zero channel is 0x5F, so a dimmed colour
    /// runs out of in-family entries well before it runs out of darkness —
    /// olive has nothing tinted below OKLab L 0.47. What used to happen there
    /// is that the greyscale ramp, which matches on lightness and nothing else,
    /// took over: a fading red stepped red, red, red, GREY, grey, black. The
    /// grey stretch reads as a glitch, because a colour has no business
    /// becoming a neutral partway down.
    ///
    /// Excluding greys makes the fade hold its darkest in-family entry instead
    /// — a block of one colour — and then drop to black, which is where the
    /// fade was going anyway. Fewer distinct steps, but every one of them the
    /// right colour, which is the trade the terminal's palette actually offers.
    /// Black stays available precisely so the end of the fade is reachable.
    private static let keepsItsHue: [Bool] = (16...255).map { index in
        let rgb = palette256ToRGB(UInt8(index))
        if rgb.red == 0 && rgb.green == 0 && rgb.blue == 0 { return true }  // black
        let lab = oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
        return (lab.a * lab.a + lab.b * lab.b).squareRoot() >= hueFloor
    }

    /// Converts sRGB bytes to OKLab.
    ///
    /// `package` rather than `private` because `TUIkitImage`'s palette mapper
    /// needs the same conversion and a second copy of these coefficients is a
    /// second place for them to drift. Deliberately NOT public and deliberately
    /// not paired with ``hueWeightedDistanceSquared``, which is load-bearing for
    /// palette derivation and must not acquire callers outside this file.
    package static func oklab(red: UInt8, green: UInt8, blue: UInt8) -> (l: Double, a: Double, b: Double) {
        let linearRed = linearChannel(red)
        let linearGreen = linearChannel(green)
        let linearBlue = linearChannel(blue)
        let long = cbrt(
            0.4122214708 * linearRed + 0.5363325363 * linearGreen + 0.0514459929 * linearBlue)
        let medium = cbrt(
            0.2119034982 * linearRed + 0.6806995451 * linearGreen + 0.1073969566 * linearBlue)
        let short = cbrt(
            0.0883024619 * linearRed + 0.2817188376 * linearGreen + 0.6299787005 * linearBlue)
        return (
            l: 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short,
            a: 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short,
            b: 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
        )
    }

    /// The inverse of ``oklab(red:green:blue:)`` — OKLab back to sRGB bytes.
    ///
    /// The quantiser never needed this: it compares distances and never has to
    /// come back. Perceptual gradient interpolation does, because the point of
    /// interpolating in OKLab is to end up with a colour again.
    ///
    /// Ottosson's inverse of the matrices above, with the same transfer
    /// function on the way out that ``linearChannel(_:)`` applies on the way
    /// in. Out-of-gamut results are clamped by ``encodedChannel(_:)``, which is
    /// the only thing that can be done with them in a cell grid — a colour
    /// between two in-gamut colours can leave the gamut on the way, and the
    /// terminal has no wider one to show it in.
    ///
    /// - Parameters:
    ///   - l: Lightness.
    ///   - a: The green–red axis.
    ///   - b: The blue–yellow axis.
    /// - Returns: The sRGB bytes.
    package static func fromOKLab(l lightness: Double, a: Double, b: Double) -> (
        red: UInt8, green: UInt8, blue: UInt8
    ) {
        // The label is `l` to mirror `oklab`'s own tuple; the binding is spelt
        // out because a lone `l` is not one of the single letters the style
        // rules allow (and reads as a 1).
        let long = lightness + 0.3963377774 * a + 0.2158037573 * b
        let medium = lightness - 0.1055613458 * a - 0.0638541728 * b
        let short = lightness - 0.0894841775 * a - 1.2914855480 * b

        let longCubed = long * long * long
        let mediumCubed = medium * medium * medium
        let shortCubed = short * short * short

        return (
            red: encodedChannel(
                4.0767416621 * longCubed - 3.3077115913 * mediumCubed + 0.2309699292 * shortCubed),
            green: encodedChannel(
                -1.2684380046 * longCubed + 2.6097574011 * mediumCubed - 0.3413193965 * shortCubed),
            blue: encodedChannel(
                -0.0041960863 * longCubed - 0.7034186147 * mediumCubed + 1.7076147010 * shortCubed)
        )
    }

    /// OKLab distance with the lightness/chroma/hue components split, hue
    /// weighted ×4, and chroma LOSS weighted ×4 (à la CIEDE2000's spirit:
    /// staying in the right colour family matters more than exact chroma).
    ///
    /// The asymmetry on chroma is not decoration. A duller candidate can win on
    /// lightness alone, because a colour with less chroma than the target has a
    /// SMALLER ΔH² by construction — ΔH² = Δa² + Δb² − ΔC² shrinks as the
    /// candidate moves toward the neutral axis, and vanishes entirely for a
    /// grey. So the ×4 hue weight, which is supposed to keep a colour in its
    /// family, does the least work exactly where the family is most at risk.
    ///
    /// Measured on the Colors page's six-stop rainbow at 60 cells: the red-to-
    /// yellow run came out `FF8700 FF8700 FFAF5F FFAF00 …` — a single washed-out
    /// cell wedged between two saturated neighbours, and three more like it
    /// further along. Those speckles read as dithering noise in what should be a
    /// smooth ramp. Charging chroma loss removes all four and leaves an even
    /// `FF8700×3 FFAF00×4 FFD700×5 FFFF00×4`. Gaining chroma is charged as
    /// before, and a neutral target has none to lose, so greys are untouched.
    @inline(__always)
    private static func hueWeightedDistanceSquared(
        _ lhs: (l: Double, a: Double, b: Double),
        chroma chromaL: Double,
        _ rhs: (l: Double, a: Double, b: Double, chroma: Double)
    ) -> Double {
        let deltaL = lhs.l - rhs.l
        let chromaR = rhs.chroma
        let deltaC = chromaL - chromaR
        let deltaA = lhs.a - rhs.a
        let deltaB = lhs.b - rhs.b
        // Standard decomposition: ΔH² = Δa² + Δb² − ΔC² (tangential part).
        let deltaH2 = max(0, deltaA * deltaA + deltaB * deltaB - deltaC * deltaC)
        let chromaWeight = deltaC > 0 ? 4.0 : 1.0  // > 0 ⇒ the candidate is duller
        return deltaL * deltaL + chromaWeight * deltaC * deltaC + 4 * deltaH2
    }

    /// Squared Euclidean distance between two RGB colors.

    fileprivate static func rgbDistanceSquared(
        _ colourA: (UInt8, UInt8, UInt8),
        _ colourB: (UInt8, UInt8, UInt8)
    ) -> Int {
        let deltaRed = Int(colourA.0) - Int(colourB.0)
        let deltaGreen = Int(colourA.1) - Int(colourB.1)
        let deltaBlue = Int(colourA.2) - Int(colourB.2)

        return (deltaRed * deltaRed) + (deltaGreen * deltaGreen) + (deltaBlue * deltaBlue)
    }

    /// Converts a 256-color palette index to the nearest ANSI 16-color.
    fileprivate static func palette256ToANSI16(_ index: UInt8) -> Color {
        switch index {
        case 0...7:
            guard let ansi = ANSIColor(rawValue: index) else { return .white }
            return Color(value: .standard(ansi))
        case 8...15:
            guard let ansi = ANSIColor(rawValue: index - 8) else { return .brightWhite }
            return Color(value: .bright(ansi))
        default:
            let rgb = palette256ToRGB(index)
            return rgbToNearestANSI16(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    /// All 16 ANSI colors with their RGB values for nearest-neighbor matching.
    fileprivate static let ansi16Table: [(color: Color, red: UInt8, green: UInt8, blue: UInt8)] = {
        var table: [(Color, UInt8, UInt8, UInt8)] = []

        // Standard colors (indices 0–7)
        for raw: UInt8 in 0...7 where raw != 9 {
            guard let ansi = ANSIColor(rawValue: raw) else { continue }
            let rgb = ansi.rgbValues
            table.append((Color(value: .standard(ansi)), rgb.red, rgb.green, rgb.blue))
        }

        // Bright colors (indices 8–15)
        for raw: UInt8 in 0...7 where raw != 9 {
            guard let ansi = ANSIColor(rawValue: raw) else { continue }
            let rgb = ansi.brightRGBValues
            table.append((Color(value: .bright(ansi)), rgb.red, rgb.green, rgb.blue))
        }

        return table
    }()

    /// Finds the nearest ANSI 16-color for an RGB value.
    fileprivate static func rgbToNearestANSI16(red: UInt8, green: UInt8, blue: UInt8) -> Color {
        var bestColor = Color.white
        var bestDistance = Int.max

        // Deliberate linear scan: n=16 is trivially cheap and beats anything cleverer — don't "optimise".
        for entry in ansi16Table {
            let distance = rgbDistanceSquared(
                (red, green, blue),
                (entry.red, entry.green, entry.blue)
            )
            if distance < bestDistance {
                bestDistance = distance
                bestColor = entry.color
            }
        }

        return bestColor
    }
}
