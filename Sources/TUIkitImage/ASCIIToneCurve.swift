//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIToneCurve.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// A recolouring of an image, written as "this becomes that".
///
/// ```swift
/// .imageToneCurve(.inverted)                              // a negative
/// .imageToneCurve([(.black, .rgb(20, 20, 60)),            // a duotone:
///                  (.white, .rgb(255, 215, 130))])        // navy shadows, warm highlights
/// ```
///
/// ## Why this is not a palette
///
/// `{black → white, white → black}` is the obvious first thing to ask for, and
/// expressing it as a two-entry ``ASCIIPalette`` gives a two-colour image — a
/// plausible-looking wrong answer, since what was asked for is a *continuous*
/// inversion in which mid-grey stays mid-grey. So the pairs are read as a
/// **transfer curve**: each pixel's perceived lightness picks a position on the
/// curve, and the colour there replaces it. Every tone in between is
/// interpolated, so the image keeps all of its depth and only changes what that
/// depth is made of.
///
/// The two features compose rather than overlap: a curve says what the tones
/// BECOME, a palette says which colours are available to say it in.
///
/// ## Where it lands in the pipeline
///
/// Before everything — before the monochrome threshold, before dithering,
/// before any palette mapping. It has to: an inversion moves where the
/// ink/background split falls, so a threshold measured on the original image
/// would be measured on tones that no longer exist. See
/// ``ASCIIConverter/monoInkThreshold(for:)``.
public struct ASCIIToneCurve: Sendable, Equatable, ExpressibleByArrayLiteral {

    /// The pairs, as the caller wrote them.
    public let stops: [Stop]

    /// One "this becomes that".
    public struct Stop: Sendable, Equatable {
        public let from: Color
        public let to: Color

        public init(from: Color, to: Color) {
            self.from = from
            self.to = to
        }
    }

    /// The curve as it is actually evaluated: sorted by the tone of each
    /// `from`, with each `to` ready to interpolate between.
    let knots: [Knot]

    struct Knot: Sendable {
        let tone: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    public init(_ stops: [Stop]) {
        self.stops = stops
        self.knots = Self.knots(from: stops)
    }

    public init(_ pairs: [(Color, Color)]) {
        self.init(pairs.map { Stop(from: $0.0, to: $0.1) })
    }

    public init(arrayLiteral elements: (Color, Color)...) {
        self.init(elements)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.stops == rhs.stops }

    /// A curve that changes nothing — the spelling for "no recolouring", and
    /// the one an empty list needs, since `ASCIIToneCurve([])` cannot say on
    /// its own which kind of empty list it is.
    public static let identity = Self([Stop]())

    /// Black becomes white and white becomes black: a photographic negative,
    /// continuous through every tone between.
    ///
    /// Spelled with explicit RGB rather than ``Color/black`` and
    /// ``Color/white``: the named ANSI white is 229, not 255 — it is a
    /// TERMINAL colour, and terminals reserve the top of the range for bright
    /// white. A negative that stopped at 229 would quietly lose the last of its
    /// highlights, and this is one of the few places where the sRGB extreme is
    /// what is actually meant.
    public static let inverted = Self([Stop(from: .rgb(0, 0, 0), to: .rgb(255, 255, 255)),
                                       Stop(from: .rgb(255, 255, 255), to: .rgb(0, 0, 0))])

    /// Whether this curve would change anything. An empty or single-stop curve
    /// cannot define a mapping and is skipped rather than applied as a
    /// flattening constant.
    var isIdentity: Bool { knots.count < 2 }

    /// `pixel` recoloured by this curve.
    ///
    /// The pixel's tone — ``RGBA/luminance``, the SAME BT.601 measure every
    /// other renderer in this module reads — is the position along the curve,
    /// and the colour at that position is the answer.
    ///
    /// Both the index and the interpolation are in ordinary gamma-encoded sRGB,
    /// and that consistency is the whole of the design. Mixing spaces does not
    /// merely offend tidiness: indexing perceptually while interpolating in
    /// linear light sent mid-grey to 170 under ``inverted``, a visibly washed-out
    /// negative, because 0.6 of the way perceptually is 0.6 of the LIGHT rather
    /// than 0.6 of the way to the other colour. Here `.inverted` sends 128 to
    /// 127, which is what a negative means in every tool anyone has used.
    ///
    /// Using this module's luminance rather than a perceptual lightness has a
    /// second payoff: the curve's positions agree with where
    /// ``ASCIIConverter/monoInkThreshold(for:)`` will fall, and the curve runs
    /// immediately before it.
    ///
    /// Alpha is carried through untouched: a curve recolours, it does not
    /// reveal or hide.
    func apply(to pixel: RGBA) -> RGBA {
        guard !isIdentity else { return pixel }
        let tone = pixel.luminance
        // Below the first knot and above the last, the curve holds its end
        // value rather than extrapolating into colours nobody named.
        guard tone > knots[0].tone else { return Self.encode(knots[0], alpha: pixel.a) }
        guard let last = knots.last else { return pixel }
        guard tone < last.tone else { return Self.encode(last, alpha: pixel.a) }

        var upper = knots.count - 1
        for (index, knot) in knots.enumerated() where knot.tone >= tone {
            upper = index
            break
        }
        let lower = max(0, upper - 1)
        let span = knots[upper].tone - knots[lower].tone
        let position = span > 0 ? (tone - knots[lower].tone) / span : 0
        return Self.encode(
            Knot(
                tone: tone,
                red: Self.mix(knots[lower].red, knots[upper].red, position),
                green: Self.mix(knots[lower].green, knots[upper].green, position),
                blue: Self.mix(knots[lower].blue, knots[upper].blue, position)),
            alpha: pixel.a)
    }

    // MARK: - Internals

    private static func mix(_ lhs: Double, _ rhs: Double, _ position: Double) -> Double {
        lhs + (rhs - lhs) * position
    }

    private static func knots(from stops: [Stop]) -> [Knot] {
        stops.compactMap { stop -> Knot? in
            // A stop whose colour is still `.semantic` has no tone and no
            // colour, so it drops out — and a curve left with fewer than two
            // knots is inert rather than wrong. See ``resolved(with:)``.
            guard let from = stop.from.rgbComponents, let to = stop.to.rgbComponents else {
                return nil
            }
            return Knot(
                tone: RGBA(r: from.red, g: from.green, b: from.blue).luminance,
                red: Double(to.red), green: Double(to.green), blue: Double(to.blue))
        }
        .sorted { $0.tone < $1.tone }
    }

    private static func encode(_ knot: Knot, alpha: UInt8) -> RGBA {
        func byte(_ value: Double) -> UInt8 { UInt8(clamping: Int(value.rounded())) }
        return RGBA(r: byte(knot.red), g: byte(knot.green), b: byte(knot.blue), a: alpha)
    }

    /// This curve with every colour it names made concrete, so a stop may be
    /// `.palette.accent` and follow the theme exactly as a palette entry does.
    public func resolved(with palette: any Palette) -> Self {
        Self(stops.map { Stop(from: $0.from.resolve(with: palette), to: $0.to.resolve(with: palette)) })
    }
}
