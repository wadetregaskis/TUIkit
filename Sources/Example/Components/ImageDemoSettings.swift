//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageDemoSettings.swift
//
//  Every knob the image demos expose, in one value.
//
//  It used to be fourteen `@State` properties on each page and a fourteen-
//  parameter control view, which is why the parameterised options (how many
//  greys, how many sampled colours, which two duotone colours) were hardcoded:
//  each one would have been two more bindings threaded through two pages. One
//  struct, one binding, and adding a knob costs a property.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The complete rendering configuration of an image demo page.
///
/// A plain `Equatable` struct rather than an observable object: it is `@State`
/// on the page and `@Binding` in the controls, and `$settings.charset` reaches
/// each field through `Binding`'s dynamic member lookup.
struct ImageDemoSettings: Equatable {

    // MARK: - The characters

    var charset: ImageDemoHelpers.Charset = .blocks

    /// How many glyphs the sizeable charsets use: 0 = the full repertoire.
    var glyphCount = 0

    /// Which ``ImageDemoHelpers/blockStyles`` entry the blocks charset uses
    /// (while not shape-aware).
    var blockStyleIndex = 0

    /// Whether glyphs are matched by in-cell ink distribution (shape) rather
    /// than mapped from cell luminance.
    var shapeAware = false

    /// Whether shape-aware cells may draw directional line glyphs at edges.
    var edgeLines = false

    /// The Sobel gradient threshold for edge cells (used while ``edgeLines``).
    var edgeThreshold = 0.9

    /// A custom brightness ramp, darkest character first; applies while the
    /// custom charset is selected.
    var customRamp = ""

    // MARK: - The colour

    var colour: ColourMode = .trueColor

    /// How many greys ``ColourMode/greys`` uses.
    var greyLevels = 4

    /// How many colours ``ColourMode/sampled`` picks out of the 256-colour cube.
    var sampledColours = 8

    /// Supersampling factor: 0 = the default, 1–4 explicit.
    var supersampling = 0

    var dithering = false

    /// Whether ``ColourMode/mono`` draws in the theme's colours (the default,
    /// and what it has always done) or in literal black and white.
    ///
    /// Mono emits no colour codes at all — a full block where the image is lit
    /// and a space where it is not — so its cells take whatever is in force
    /// around them, which in an app is the page's own foreground and
    /// background. Turning this off states the two colours explicitly instead.
    var monoThemeColours = true

    // MARK: - The tone

    var tone: Tone = .off

    /// ``Tone/duotone``'s two ends.
    var duotoneShadow: Color = .rgb(20, 20, 60)
    var duotoneHighlight: Color = .rgb(255, 215, 130)

    /// ``Tone/lut``'s stops, darkest first and evenly spaced across the tone
    /// range. Two or more; the editor enforces that.
    var lutStops: [Color] = [
        .rgb(10, 10, 40), .rgb(180, 40, 70), .rgb(245, 180, 60), .rgb(255, 250, 220),
    ]

    // MARK: - Colour modes

    /// The colour modes the demo offers: the fidelity ladder, then the three
    /// ways of naming a palette — so the cycler walks from "as much colour as
    /// this terminal has" all the way to "these three, and they follow the
    /// theme".
    ///
    /// The two parameterised entries come LAST so the sliders that configure
    /// them can sit directly beneath their own radio buttons.
    enum ColourMode: Int, CaseIterable {
        case trueColor, ansi256, grayscale, mono, themed, greys, sampled
    }

    /// The recolourings the demo offers.
    ///
    /// ``duotone`` and ``lut`` come last, again so their controls sit under
    /// their own radio buttons.
    enum Tone: Int, CaseIterable {
        case off, negative, accent, duotone, lut
    }

    // MARK: - What the settings render as

    /// The ``ASCIICharacterSet`` these settings describe. `glyphCount` 0 means
    /// the full repertoire; an empty custom ramp falls back to a 10-glyph ASCII
    /// ramp so the demo never renders blank.
    var characterSet: ASCIICharacterSet {
        let glyphs = glyphCount > 0 ? glyphCount : nil
        switch charset {
        case .ascii: return .ascii(glyphs: glyphs)
        case .unicode: return .unicode(glyphs: glyphs)
        case .blocks:
            return .blocks(
                ImageDemoHelpers.blockStyles[
                    min(blockStyleIndex, ImageDemoHelpers.blockStyles.count - 1)])
        case .custom:
            return customRamp.isEmpty ? .ascii(glyphs: 10) : .customRamp(customRamp)
        }
    }

    var colorMode: ASCIIColorMode {
        switch colour {
        case .trueColor: return .trueColor
        case .ansi256: return .ansi256
        case .grayscale: return .grayscale
        case .mono:
            // `.mono` proper emits no colour codes at all — a block where the
            // image is lit and a space where it is not — so its cells take
            // whatever the page is drawn in, which IS the theme's two colours.
            // That is the default and always was.
            //
            // Asked for the other reading, the two colours are stated instead,
            // as a two-entry tone ramp: `.rgb` rather than `.white` / `.black`,
            // which are palette entries a theme may define as something else,
            // and "literal" is the point of the option. (Setting them with
            // `.foregroundStyle` / `.background` on the view does nothing — an
            // `Image` emits its own lines, and mono's carry no colour for a
            // modifier to rewrite.)
            guard monoThemeColours else {
                return .palette(
                    ASCIIPalette([.rgb(0, 0, 0), .rgb(255, 255, 255)]).asToneRamp())
            }
            return .mono
        case .greys: return .palette(.shades(greyLevels))
        case .sampled: return .palette(.sampled(sampledColours))
        case .themed:
            // As a TONE RAMP, not by nearest colour: the accent and white sit
            // within 0.04 of each other in OKLab lightness, so by nearest
            // colour the accent would never be the closest entry to anything in
            // a photograph and the demo would draw two colours while claiming
            // three.
            return .palette(ASCIIPalette([.black, .palette.accent, .white]).asToneRamp())
        }
    }

    var toneCurve: ASCIIToneCurve? {
        switch tone {
        case .off: return nil
        case .negative: return .inverted
        case .accent:
            return ASCIIToneCurve([(.rgb(0, 0, 0), .black), (.rgb(255, 255, 255), .palette.accent)])
        case .duotone:
            return ASCIIToneCurve([
                (.rgb(0, 0, 0), duotoneShadow), (.rgb(255, 255, 255), duotoneHighlight),
            ])
        case .lut:
            return Self.curve(throughStops: lutStops)
        }
    }

    var ditheringMode: DitheringMode { dithering ? .floydSteinberg : .none }

    /// A curve through `stops`, read as evenly spaced across the tone range.
    ///
    /// This is what makes an ``ASCIIToneCurve`` a look-up table: the stops name
    /// the colours the image is to be MADE of, from its darkest tone to its
    /// lightest, and every tone between two of them is interpolated. Two stops
    /// is a duotone; more is a gradient map.
    ///
    /// The `from` side is a grey, because a curve is a function of luminance
    /// alone — see ``ASCIIToneCurve``. Even spacing is the editor's model too
    /// (``GradientEditorPanel`` spaces its stops evenly), so the two agree by
    /// construction rather than by a conversion nobody would maintain.
    static func curve(throughStops stops: [Color]) -> ASCIIToneCurve? {
        guard stops.count >= 2 else { return nil }
        let last = Double(stops.count - 1)
        return ASCIIToneCurve(
            stops.enumerated().map { index, colour in
                let level = UInt8(clamping: Int((Double(index) / last * 255).rounded()))
                return (Color.rgb(level, level, level), colour)
            })
    }

    // MARK: - Keeping the knobs coherent

    /// Snaps every dependent knob to a value the current configuration actually
    /// renders with, so a disabled control never displays a setting that
    /// differs from what is being drawn.
    ///
    /// Deliberately lossy: a preference does not survive a round-trip through a
    /// mode that does not support it — coherence of what is on screen wins over
    /// remembering hidden state.
    mutating func snap() {
        if !ImageDemoHelpers.usesShape(charset) { shapeAware = false }
        if !ImageDemoHelpers.usesSupersampling(charset, shapeAware: shapeAware) {
            supersampling = 0
        }
        if !ImageDemoHelpers.usesEdgeTracing(charset, shapeAware: shapeAware) { edgeLines = false }
        if !ImageDemoHelpers.usesBlockStyle(charset, shapeAware: shapeAware) { blockStyleIndex = 0 }
        if ImageDemoHelpers.usesGlyphCount(charset) {
            glyphCount = min(
                glyphCount, ImageDemoHelpers.maximumGlyphs(charset, shapeAware: shapeAware))
        } else {
            glyphCount = 0
        }
        greyLevels = min(16, max(2, greyLevels))
        sampledColours = min(64, max(2, sampledColours))
        // A one-stop LUT is not a mapping; the editor can delete down to one,
        // so the floor is asserted here rather than hoped for.
        if lutStops.count == 1 { lutStops.append(.rgb(255, 255, 255)) }
    }

    /// The status bar's label for the colour mode — the same names the radio
    /// buttons carry, shortened, and carrying the parameter where there is one.
    var colourLabel: String {
        switch colour {
        case .trueColor: return "color:true"
        case .ansi256: return "color:256"
        case .grayscale: return "color:gray"
        case .mono: return "color:mono"
        case .greys: return "color:\(greyLevels) greys"
        case .sampled: return "color:\(sampledColours) sampled"
        case .themed: return "color:themed"
        }
    }

    var toneLabel: String {
        switch tone {
        case .off: return "tone:off"
        case .negative: return "tone:invert"
        case .accent: return "tone:accent"
        case .duotone: return "tone:duotone"
        case .lut: return "tone:LUT(\(lutStops.count))"
        }
    }

    /// Advances a `CaseIterable` knob by `step`, wrapping — what the status
    /// bar's lowercase/uppercase pairs do.
    static func cycled<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T
    where T.AllCases.Index == Int {
        let all = T.allCases
        let index = all.firstIndex(of: value) ?? 0
        return all[(index + step + all.count) % all.count]
    }
}
