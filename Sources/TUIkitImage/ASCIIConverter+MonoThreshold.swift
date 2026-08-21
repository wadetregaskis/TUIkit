//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIConverter+MonoThreshold.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension ASCIIConverter {

    /// Mid-luminance: the split every binary renderer used before there was a
    /// better answer, and the one they fall back to when there is not.
    static let midLuminance: Double = 128

    /// The luminance that best separates ink from background in this image.
    ///
    /// ## Why a fixed split is the wrong one
    ///
    /// Three of the renderers reduce a pixel to one bit — `.blocks(.solid)` and
    /// `.blocks(.fine)` in monochrome, and braille in every mode, whose dots
    /// carry the shape while colour is averaged separately. All three split at
    /// mid-luminance, which assumes the image's tones straddle the middle.
    /// Photographs mostly do not: the shipped demo image is **87% below
    /// mid-luminance**, so almost nothing crossed the line and the render came
    /// out nearly blank. Correcting the polarity (see ``isMonoInk(_:)``) fixed
    /// which side was ink; it could not fix a threshold sitting outside the
    /// tones entirely.
    ///
    /// ## Otsu's method
    ///
    /// Take the split that makes the two sides most unlike each other: the
    /// luminance maximising `wB · wF · (mB − mF)²`, where `w` are the two sides'
    /// pixel counts and `m` their mean luminances. One pass to build a 256-bin
    /// histogram and one pass over the bins — no iteration, no parameters — and
    /// it lands where a person would draw the line on a bimodal image, which is
    /// what a subject against a background is. On that same demo image it
    /// chooses 75.5 rather than 128, and the half-block render goes from 15% ink
    /// to 28% — a whole silhouette instead of pieces of one.
    ///
    /// ## When it declines
    ///
    /// A nearly-uniform image has no two sides to be unlike. Otsu will still
    /// return *a* split, and it will be sensor noise or gradient banding
    /// amplified into a field of speckle — strictly worse than the flat result
    /// the fixed threshold gives. So an image whose luminance spans less than
    /// ``minimumSeparableSpread`` keeps ``midLuminance``, and a flat image stays
    /// flat.
    ///
    /// - Parameter image: The image as the renderer will sample it — scaled,
    ///   area-reduced, and NOT yet dithered. Dithering quantises against this
    ///   threshold, so measuring after it would be measuring its own output.
    static func monoInkThreshold(for image: RGBAImage) -> Double {
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        for pixel in image.pixels {
            // The same BT.601 luminance every renderer thresholds on, bucketed
            // to whole levels — the histogram's resolution IS the output's.
            histogram[min(255, max(0, Int(pixel.luminance)))] += 1
            total += 1
        }
        guard total > 0 else { return midLuminance }

        guard let lowest = histogram.firstIndex(where: { $0 > 0 }),
            let highest = histogram.lastIndex(where: { $0 > 0 }),
            highest - lowest >= minimumSeparableSpread
        else { return midLuminance }

        var weightedTotal = 0
        for level in lowest...highest { weightedTotal += level * histogram[level] }

        var backgroundCount = 0
        var backgroundWeighted = 0
        var bestVariance = -1.0
        var bestLevel = lowest
        for level in lowest..<highest {
            backgroundCount += histogram[level]
            backgroundWeighted += level * histogram[level]
            let foregroundCount = total - backgroundCount
            guard backgroundCount > 0, foregroundCount > 0 else { continue }
            let backgroundMean = Double(backgroundWeighted) / Double(backgroundCount)
            let foregroundMean =
                Double(weightedTotal - backgroundWeighted) / Double(foregroundCount)
            let separation = backgroundMean - foregroundMean
            let variance = Double(backgroundCount) * Double(foregroundCount) * separation
                * separation
            if variance > bestVariance {
                bestVariance = variance
                bestLevel = level
            }
        }
        // Between the two bins rather than on the lower one: `bestLevel` is the
        // last level counted as background, so the split sits above it.
        return Double(bestLevel) + 0.5
    }

    /// How far apart an image's darkest and brightest levels must be before a
    /// computed threshold beats a fixed one.
    ///
    /// Sixteen levels of 256 — a sixteenth of the range. Below that there is no
    /// subject to separate from a background, only noise, and Otsu would split
    /// the noise down the middle and render it as speckle.
    static let minimumSeparableSpread = 16
}
