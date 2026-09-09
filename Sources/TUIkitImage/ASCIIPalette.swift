//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ASCIIPalette.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitStyling

/// How a pixel picks one of an ``ASCIIPalette``'s colours.
public enum ASCIIPaletteMapping: Sendable, Equatable {
    /// The colour the pixel is closest to, in OKLab. Reproduces the image as
    /// faithfully as the palette allows, and is right whenever the palette is
    /// meant to STAND IN for the image's own colours — `.shades(_:)`, or a set of distinct hues chosen to match a subject.
    ///
    /// Plainly nearest, not ``Color``'s hue-weighted metric, which is
    /// load-bearing for `SystemPalette` derivation and must not acquire a second
    /// caller with different needs (three attempts at retuning it during the
    /// gradient work each broke palette derivation and each was reverted).
    ///
    /// For a palette that is a ramp — greys, or any set sharing a hue — nearest
    /// in OKLab REDUCES to nearest in lightness, because the entries' `a` and
    /// `b` are then equal and drop out. So `.shades(_:)` needs no special case.
    case nearestColor

    /// The colours in dark-to-light order, spread evenly across the luminance
    /// axis — a third of 0…255 each, for three — so every colour has a band,
    /// whatever its hue.
    ///
    /// The axis is the absolute one every other renderer here reads, not the
    /// image's own range: a picture whose tones all lie inside one band draws
    /// one colour, and a two-colour ramp splits at mid-grey rather than at the
    /// image's measured (`.mono`) threshold.
    ///
    /// What "draw this in my three colours" usually means, and the case
    /// `nearestColor` cannot serve. In the shipped green theme
    /// `{black, accent, white}` has the accent at OKLab L 0.887 against white's
    /// 0.922 — so near in lightness that every grey in a photograph is closer to
    /// one of the other two, and the accent is never drawn at all. Three colours
    /// asked for, two delivered, and nothing about the result says why.
    ///
    /// The trade is the mirror image: a palette of five hues chosen to match a
    /// flag will recolour it, because rank ignores which colour a pixel
    /// actually was.
    case toneRamp
}

/// A specific set of colours an image may be drawn in.
///
/// ``ASCIIColorMode``'s other cases form a ladder of FIDELITY, chosen by what
/// the terminal can display. This is orthogonal to that ladder: it says *use
/// these colours*, chosen by intent — an image drawn in the theme's palette, or
/// in two or three named colours, so it belongs to the app rather than sitting
/// in it as a photograph.
///
/// Three ways to say it, and they are the same thing underneath:
///
/// ```swift
/// .palette(ASCIIPalette([.black, .palette.accent, .white]))  // these colours
/// .palette(.shades(5))                                       // five greys
/// .palette(.spread(8))                                       // eight, spread over the gamut
/// .palette(.adaptive(8, by: .leastError))                    // eight, taken from the picture
/// ```
///
/// ## Why `[Color]` and not `[RGBA]`
///
/// A ``Color`` can be `.palette.accent`, so a palette built from the theme
/// FOLLOWS the theme — recolour the app and the image recolours with it. An
/// `[RGBA]` would freeze the answer at construction. Resolution happens once
/// per conversion, against the palette in the environment; see
/// ``resolved(with:)``.
///
/// ## Two ways to spend a palette
///
/// See ``ASCIIPaletteMapping``. The default reproduces the image as closely as
/// the colours allow; the alternative spends every colour, spread across the
/// luminance axis in equal bands, which is what "draw this in my three
/// colours" usually means.
///
/// ## The order does not matter
///
/// The design note for this suggested a dark → light convention borrowed from
/// ``ASCIICharacterSet/customRamp(_:)``. Building it settled that it should not
/// be load-bearing: both mappings sort or ignore the order themselves, so a
/// palette that had to be written in a particular order would be one more thing
/// to get wrong for no gain. Write them in whatever order reads best.
public struct ASCIIPalette: Sendable, Equatable {

    /// The colours, as the caller wrote them.
    public let colors: [Color]

    /// How a pixel picks one of them.
    public let mapping: ASCIIPaletteMapping

    /// Entry indices ordered dark → light, which is what ``ASCIIPaletteMapping/toneRamp``
    /// walks. Precomputed because it is per-image, not per-pixel.
    let byTone: [Int]

    /// The same colours as concrete sRGB plus their OKLab coordinates,
    /// precomputed because mapping asks for them once per pixel.
    ///
    /// Not part of ``Equatable``: it is a function of ``colors``, and a palette
    /// carrying an unresolved semantic colour is equal to itself.
    let entries: [Entry]

    /// The question this palette is, when its colours are not yet decided —
    /// see ``adaptive(_:by:target:)``. `nil` for every palette whose colours the app
    /// chose, which is all of them until one meets ``derived(from:)``.
    ///
    /// Part of ``Equatable``, unlike ``entries``: two palettes standing in with
    /// the same greys are not the same palette if one of them is going to
    /// become a photograph's own colours.
    let adaptive: Adaptive?

    /// The exact-search index for a palette large enough to want one — see
    /// ``SearchIndex``. A reference, so every copy shares one; not part of
    /// ``Equatable``, which is about the colours.
    let search = SearchIndexHandle()

    /// An unanswered ``adaptive(_:by:target:)`` request.
    public struct Adaptive: Sendable, Equatable, Hashable {
        /// Which `count` colours — see ``Adaptation``.
        public let method: Adaptation
        /// How many.
        public let count: Int
        /// Which colours it may choose them from — see ``AdaptationTarget``.
        public let target: AdaptationTarget
    }

    struct Entry: Sendable {
        let rgba: RGBA
        let lightness: Double
        let a: Double
        let b: Double
        /// BT.601 luminance — what ``ASCIIPaletteMapping/toneRamp`` orders and
        /// indexes by, and the same measure every other renderer in this module
        /// reads, so a ramp's steps fall where the glyph ramps' do.
        let tone: Double
    }

    /// A palette of exactly these colours.
    ///
    /// An empty list is not a palette; it degrades to black and white, which is
    /// the one answer that always renders something.
    public init(_ colors: [Color], mapping: ASCIIPaletteMapping = .nearestColor) {
        self.init(colors, mapping: mapping, adaptive: nil)
    }

    init(_ colors: [Color], mapping: ASCIIPaletteMapping, adaptive: Adaptive?) {
        let colors = colors.isEmpty ? [.black, .white] : colors
        let entries = colors.map(Self.entry(for:))
        self.colors = colors
        self.mapping = mapping
        self.entries = entries
        self.byTone = entries.indices.sorted { entries[$0].tone < entries[$1].tone }
        self.adaptive = adaptive
    }

    /// This palette, spent as a tonal ramp instead of as a set of candidates.
    /// See ``ASCIIPaletteMapping/toneRamp``.
    public func asToneRamp() -> Self { Self(colors, mapping: .toneRamp, adaptive: adaptive) }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.colors == rhs.colors && lhs.mapping == rhs.mapping && lhs.adaptive == rhs.adaptive
    }

    /// `count` greys from black to white, evenly spaced in PERCEIVED
    /// lightness.
    ///
    /// Evenly in OKLab's L rather than in sRGB bytes, because the eye is what
    /// looks at the result: five bytes-even greys put three of them in the
    /// bright half where the differences are hardest to see. Two greys are
    /// black and white; one is black, which is a legitimate if bleak request.
    public static func shades(_ count: Int) -> Self {
        let count = max(1, count)
        guard count > 1 else { return Self([.black]) }
        return Self(
            (0..<count).map { step in
                let lightness = Double(step) / Double(count - 1)
                let value = UInt8(clamping: Int((Self.sRGBFromLightness(lightness) * 255).rounded()))
                return .rgb(value, value, value)
            })
    }

    /// The terminal's own sixteen — the 8 standard ANSI colours and their 8
    /// bright twins.
    ///
    /// What ``ASCIIColorMode/ansi16`` maps through, and available in its own
    /// right for an image that should be drawn in the colours the user's
    /// terminal profile defines rather than in colours of its own. Every entry
    /// is a `.standard`/`.bright` ``Color``, so it emits as SGR 30–37 / 90–97
    /// and FOLLOWS the profile: change the terminal's idea of "red" and the
    /// image changes with it. As glyphs, that is — an image drawn as pixels
    /// through terminal graphics gets xterm's default RGB for each name, since
    /// pixels cannot carry a name and nothing here can ask the terminal what
    /// its profile paints for one.
    ///
    /// Mapped by nearest colour in OKLab like any other palette. `.default` is
    /// deliberately absent: it is not one of the sixteen, it is "whatever the
    /// terminal would have used", and an image cannot be drawn in it.
    public static let ansi16 = Self([
        .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
        .brightBlack, .brightRed, .brightGreen, .brightYellow,
        .brightBlue, .brightMagenta, .brightCyan, .brightWhite,
    ])

    /// The terminal's own 256 — the 6×6×6 cube and the 24-step grey ramp,
    /// indices 16…255. What ``ASCIIColorMode/ansi256`` maps through.
    ///
    /// Mapped by nearest colour in OKLab, like every other palette here, and
    /// that uniformity is deliberate — see ``nearestIndex(to:)``, which says
    /// why an image must not borrow `Color.downsampledToPalette256()`'s rule
    /// even though it draws in exactly the same 240 colours.
    ///
    /// The sixteen named colours are deliberately absent, as they are from
    /// `Color`'s search: an index below 16 is a NAME, which bold may repaint
    /// in its bright twin. See ``ASCIIColorMode/foregroundSurvivesBold``.
    static let ansi256 = Self((16...255).map { .palette(UInt8($0)) })

    /// `count` colours spread as far apart as they can be, taken from the
    /// terminal's own 256-colour repertoire.
    ///
    /// About the GAMUT, not about any picture: these are `count` colours chosen
    /// to cover the space of colours a terminal can show, so the same `count`
    /// always answers the same palette whatever it is asked to draw. That makes
    /// it the wrong tool for reproducing a photograph — a picture occupies a
    /// small part of the gamut, so entries land where it has no pixels and
    /// raising `count` can change nothing at all (measured on one photograph at
    /// 24 colours: eight entries never drawn). ``adaptive(_:by:target:)`` is the one
    /// that asks the picture.
    ///
    /// The point of the constraint is that every entry is a colour any
    /// 256-colour terminal renders exactly, so a palette chosen this way never
    /// shifts underfoot when the image is downsampled.
    ///
    /// Farthest-point sampling in OKLab: start at black, then repeatedly take
    /// the candidate furthest from everything chosen so far. Deterministic, no
    /// parameters, and it covers the gamut rather than clustering where the
    /// cube happens to be dense — which is what "every k-th index" does.
    ///
    /// This is deliberately NOT a palette derived from the image. That is a
    /// different feature ("reduce this image to N colours") and it would put an
    /// image-analysis pass inside a renderer whose job is mapping; with
    /// dithering on, this plus ``ASCIIPalette`` gets most of the same look.
    public static func spread(_ count: Int) -> Self {
        let count = max(1, count)
        let candidates: [(index: UInt8, lab: (l: Double, a: Double, b: Double))] =
            (16...255).map { index in
                let rgb = Color.palette256ToRGB(UInt8(index))
                return (UInt8(index), Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue))
            }
        var chosen: [Int] = [0]  // index 16 is the cube's black
        var distance = candidates.map { Self.distanceSquared($0.lab, candidates[0].lab) }
        while chosen.count < min(count, candidates.count) {
            var best = 0
            var bestDistance = -1.0
            for (position, value) in distance.enumerated() where value > bestDistance {
                bestDistance = value
                best = position
            }
            chosen.append(best)
            for position in distance.indices {
                distance[position] = min(
                    distance[position],
                    Self.distanceSquared(candidates[position].lab, candidates[best].lab))
            }
        }
        return Self(chosen.map { .palette(candidates[$0].index) })
    }

    /// This palette with every colour made concrete.
    ///
    /// A `.semantic` colour has no RGB of its own — it is a reference into the
    /// theme — so a palette carrying one must be resolved before it can map
    /// anything. Callers that render do this once per conversion.
    public func resolved(with palette: any Palette) -> Self {
        // The adaptation survives: resolving says what a colour IS, and an
        // adaptive palette's stand-in greys are not the colours it will draw.
        Self(colors.map { $0.resolve(with: palette) }, mapping: mapping, adaptive: adaptive)
    }

    // MARK: - Mapping

    /// The palette entry that best represents `pixel`.
    ///
    /// Nearest in OKLab, plainly. Not ``Color``'s hue-weighted metric — and
    /// NOT EVEN FOR ``ansi256``, where the entries are the terminal's own and
    /// the page beside the picture is painted in them by that very function.
    /// Sharing the palette is what makes a screen coherent; sharing the RULE
    /// makes the picture wrong, because the two are answering different
    /// questions. `Color`'s asks *what stands in for this DESIGNED COLOUR,
    /// keeping its identity* — so it weights hue ×4, charges chroma LOSS ×4,
    /// and refuses the grey ramp to anything with a hue at all, which is what
    /// keeps a fading accent from stepping through grey. This one asks *what
    /// is a person least likely to see as different from this PIXEL*, of which
    /// there are a million and none has an identity to keep.
    ///
    /// Measured, borrowing the other rule: it denies the grey ramp to 99.8% of
    /// colours — every pixel with any tint at all, which in a photograph is
    /// nearly all of them — so the ramp's 24 fine steps go unused (6.4% of a
    /// random sweep down to 0.23%) and the cube's coarse ones stand in. A
    /// neutral dark grey `(96,100,106)` comes out `(95,95,135)`, a navy: the
    /// picture's greys INVENT A HUE. Across a near-neutral band the mean OKLab
    /// error is 2.1× the nearest answer's. So the metals and shadows a
    /// photograph is mostly made of are exactly what it gets worst.
    ///
    /// `Color`'s metric is also load-bearing for `SystemPalette` derivation and
    /// must not acquire a second caller with different needs (three attempts at
    /// retuning it during the gradient work each broke palette derivation and
    /// each was reverted).
    ///
    /// For a palette that is a ramp — greys, or any set sharing a hue — nearest
    /// in OKLab REDUCES to nearest in lightness, because the entries' `a` and
    /// `b` are then equal and drop out of the comparison. So there is one rule
    /// here rather than two: `.shades(_:)` needs no special case, and neither
    /// does a palette of five unrelated hues.
    ///
    /// Flattening — large regions collapsing to one entry — is answered by
    /// dithering rather than by a cleverer metric: the error diffused between
    /// two entries is what makes a boundary read as a gradient instead of a
    /// step. See ``DitheringMode``.
    func nearestIndex(to pixel: RGBA) -> Int {
        guard mapping == .nearestColor else { return toneRampIndex(for: pixel) }
        // A large palette searches its index — the same answer, over the few
        // entries that can be nearest anywhere in the pixel's cell rather than
        // over every entry. See ``SearchIndex`` for why that is exact.
        if entries.count > Self.indexedEntryThreshold, let searchIndex {
            return searchIndex.nearestIndex(to: pixel)
        }
        let target = Color.oklab(red: pixel.r, green: pixel.g, blue: pixel.b)
        var best = 0
        var bestDistance = Double.infinity
        // A plain index walk with the arithmetic written out, rather than
        // `enumerated()` and a call to `distanceSquared`. Identical comparisons
        // in an identical order, so the answer is identical — but this runs
        // once per PIXEL on the graphics path (about a million times, against
        // the character renderer's few thousand), and there a tuple built and
        // a function called per entry per pixel is sixteen million of each.
        // Measured at 155 ms per palette entry in a debug build.
        //
        // The walk is `for entry in buffer` with a counter rather than the
        // `for index in 0..<buffer.count` it reads more like, because a `Range`
        // is iterated through `IndexingIterator` and a protocol witness per
        // step where a buffer has a concrete iterator of its own — which costs
        // nothing at -O and is most of this loop at -Onone. Measured for this
        // swap alone, debug, 120×50 cells through a 256-colour palette: the
        // glyph path 467 → 178 ms and the pixel path 21.4 → 4.0 s per
        // conversion — a `.leastError` palette either way. Release is unchanged
        // — every mode within ±2%, both signs, which is inside the noise floor
        // a same-binary null test reads on the box that measured it — and so is
        // every answer.
        entries.withUnsafeBufferPointer { buffer in
            var index = 0
            for entry in buffer {
                let deltaL = target.l - entry.lightness
                let deltaA = target.a - entry.a
                let deltaB = target.b - entry.b
                let distance = deltaL * deltaL + deltaA * deltaA + deltaB * deltaB
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
                index += 1
            }
        }
        return best
    }

    /// The entry `pixel` reaches by TONAL RANK: the entries in dark-to-light
    /// order, and the pixel's own tone says how far along that order it falls.
    ///
    /// Rank, not value — which is exactly the difference that makes this worth
    /// having. `{black, accent, white}` in the shipped green theme has the
    /// accent at OKLab L 0.887 and white at 0.922, so by NEAREST COLOUR every
    /// grey in a photograph is closer to white or to black and the accent is
    /// never drawn: three colours asked for, two delivered. By rank the three
    /// take a third of the range each, which is what asking for three colours
    /// means.
    private func toneRampIndex(for pixel: RGBA) -> Int {
        let step = Int(pixel.luminance / 256.0 * Double(byTone.count))
        return byTone[min(byTone.count - 1, max(0, step))]
    }

    /// The concrete colour of entry `index` — what the dither diffuses error
    /// against, and what a mono fallback thresholds on.
    func rgba(at index: Int) -> RGBA {
        entries.indices.contains(index) ? entries[index].rgba : RGBA(r: 0, g: 0, b: 0)
    }

    /// The SGR parameters that select entry `index`, in whatever form its
    /// colour is expressed.
    ///
    /// The form matters: after ``downsampled(to:)`` an entry IS a 256-palette
    /// index or one of the 16, and saying so costs fewer bytes than an RGB
    /// triple and is the only spelling a terminal at that depth understands.
    func sgrParameters(at index: Int, background: Bool) -> String {
        guard colors.indices.contains(index) else { return background ? "49" : "39" }
        switch colors[index].value {
        case .rgb(let red, let green, let blue):
            return "\(background ? 48 : 38);2;\(red);\(green);\(blue)"
        case .palette256(let value):
            return "\(background ? 48 : 38);5;\(value)"
        case .standard(let ansi):
            return "\((background ? 40 : 30) + Int(ansi.rawValue))"
        case .bright(let ansi):
            return "\((background ? 100 : 90) + Int(ansi.rawValue))"
        case .semantic:
            // Cannot happen after `resolved(with:)`, and if it somehow does,
            // the entry's mid-grey stand-in is what is drawn.
            let grey = entries[index].rgba
            return "\(background ? 48 : 38);2;\(grey.r);\(grey.g);\(grey.b)"
        }
    }

    /// Whether SGR 1 leaves every colour in this palette alone.
    ///
    /// See ``ASCIIColorMode/foregroundSurvivesBold``: a colour named as one of
    /// the sixteen has a bright twin that bold may be swapped for, and one
    /// stated as a triple or as a 256-cube index at 16 or above does not. A
    /// palette is only as safe as its least safe entry, because the image
    /// picks per pixel and cannot embolden some cells and not others without
    /// making the weight itself part of the picture.
    ///
    /// `.semantic` cannot survive ``resolved(with:)``, and where one somehow
    /// does ``sgrParameters(at:background:)`` spells it as a triple, so it is
    /// safe by the same rule as ``Color/rgb``.
    var foregroundSurvivesBold: Bool {
        colors.allSatisfy { color in
            switch color.value {
            case .rgb, .semantic: return true
            case .palette256(let index): return index >= 16
            case .standard, .bright: return false
            }
        }
    }

    /// This palette with every colour replaced by the nearest one `depth` can
    /// render exactly.
    ///
    /// What makes a chosen palette survive a downgrade where a fidelity mode
    /// cannot: "these three colours" still means something on a 16-colour
    /// terminal, and quantising the colours keeps the intent while dropping
    /// only the accuracy. Two entries may well collapse into one — a palette of
    /// two near-identical blues has no 16-colour rendering that keeps them
    /// apart, and pretending otherwise would emit a colour the terminal then
    /// substitutes anyway.
    public func downsampled(to depth: ColorDepth) -> Self {
        switch depth {
        case .truecolor, .noColor: return self
        case .palette256:
            // Still the same colours — a `.palette256` entry downsamples to
            // itself — so ``ansi256`` stays itself here, and keeps its table.
            return Self(
                colors.map { $0.downsampledToPalette256() }, mapping: mapping, adaptive: adaptive)
        case .basic16:
            // Not there: these are sixteen NAMED colours now, and `Color`'s
            // 256-colour quantiser cannot answer with one of them.
            return Self(
                colors.map { $0.downsampledToANSI16() }, mapping: mapping, adaptive: adaptive)
        }
    }

    // MARK: - Internals

    private static func entry(for color: Color) -> Entry {
        // A semantic colour that reached here unresolved has no RGB; mid-grey
        // is what `Color.resolve(with:)` itself falls back to, so an
        // unresolved palette renders flat rather than differently-wrong.
        let rgb = color.rgbComponents ?? (red: 128, green: 128, blue: 128)
        let lab = Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
        let rgba = RGBA(r: rgb.red, g: rgb.green, b: rgb.blue)
        return Entry(rgba: rgba, lightness: lab.l, a: lab.a, b: lab.b, tone: rgba.luminance)
    }

    static func distanceSquared(
        _ lhs: (l: Double, a: Double, b: Double), _ rhs: (l: Double, a: Double, b: Double)
    ) -> Double {
        let deltaL = lhs.l - rhs.l
        let deltaA = lhs.a - rhs.a
        let deltaB = lhs.b - rhs.b
        return deltaL * deltaL + deltaA * deltaA + deltaB * deltaB
    }

    /// The sRGB value (0…1) of the grey whose OKLab lightness is `lightness`.
    ///
    /// For a neutral colour OKLab's L is the cube root of the linear-light
    /// value, so the inverse is a cube and a gamma encode — no matrix, and no
    /// need for a general OKLab → sRGB conversion this module would otherwise
    /// have to carry.
    private static func sRGBFromLightness(_ lightness: Double) -> Double {
        let linear = lightness * lightness * lightness
        return linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * pow(linear, 1.0 / 2.4) - 0.055
    }
}
