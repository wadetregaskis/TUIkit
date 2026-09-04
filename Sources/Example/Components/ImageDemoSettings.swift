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

    /// How many glyphs the ASCII charset uses: 0 = the full repertoire.
    ///
    /// One per sizeable charset rather than one shared: the two repertoires are
    /// different sizes (`maximumGlyphs` differs), so a count chosen for one is
    /// not a count for the other, and sharing it clamped a considered ASCII
    /// choice on the way through Unicode.
    var asciiGlyphs = 0

    /// How many glyphs the Unicode charset uses: 0 = the full repertoire.
    var unicodeGlyphs = 0

    /// Which ``ImageDemoHelpers/blockStyles`` entry the blocks charset uses
    /// (while not shape-aware).
    var blockStyleIndex = 0

    /// Whether glyphs are matched by in-cell ink distribution (shape) rather
    /// than mapped from cell luminance.
    var shapeAware = false

    /// Whether the image is drawn with the terminal's OWN graphics protocol —
    /// real pixels — where the terminal has one.
    ///
    /// On by default, matching the framework: every knob above it is then
    /// inert, which is the point of having the switch on this page. Turning it
    /// off is how you compare the two renderings of the same picture on a
    /// terminal that can do both, and on every terminal that cannot it changes
    /// nothing at all.
    var terminalGraphics = true

    /// Whether shape-aware cells may draw directional line glyphs at edges.
    var edgeLines = false

    /// The Sobel gradient threshold for edge cells (used while ``edgeLines``).
    var edgeThreshold = 0.9

    /// Whether the picture's local contrast is lifted before any character is
    /// chosen for it — the third of the three, and the only one that changes
    /// the PICTURE rather than what is read off it.
    var edgeContrast = false

    /// The unsharp amount (used while ``edgeContrast``).
    var edgeContrastAmount = 0.6

    /// A custom brightness ramp, darkest character first; applies while the
    /// custom charset is selected.
    var customRamp = ""

    // MARK: - The colour

    var colour: ColourMode = .trueColor

    /// How many greys ``ColourMode/greys`` uses.
    var greyLevels = 4

    /// How many colours each of the three counted palette modes asks for.
    ///
    /// One apiece, not one shared. A shared count was the first draft, on the
    /// argument that the interesting comparison is what the same N buys under
    /// each rule — but the three sliders are on screen TOGETHER, so a shared
    /// count made two of them move when you dragged the third, which reads as a
    /// bug however good the argument behind it is. Comparing at equal N is
    /// still a drag away; a control that moves on its own is not recoverable.
    var spreadColours = 8
    var mostUsedColours = 8
    var leastErrorColours = 8

    /// Which of ``ImageDemoHelpers/customPalettes`` ``ColourMode/customPalette``
    /// draws in.
    var customPaletteIndex = 0

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

    /// ``Tone/channels``' three per-channel transfer functions.
    ///
    /// A gentle warm grade rather than the identity, for the same reason
    /// ``lutStops`` is four colours and not two greys: the identity is what the
    /// picture already looks like, so a demo that opens on it shows a control
    /// that appears to do nothing until you find a point to drag. This lifts
    /// the midtones on red, holds green, and lifts the shadows while pulling
    /// the highlights on blue — which is visible, reversible from the editor's
    /// own reset, and demonstrates the one thing a single tone curve cannot:
    /// that the three channels are independent.
    var channelCurves: ASCIIToneCurve.Channels = .init(
        red: [(0, 0), (0.5, 0.58), (1, 1)],
        green: [(0, 0), (0.5, 0.5), (1, 1)],
        blue: [(0, 0.08), (0.5, 0.42), (1, 0.94)])

    /// ``Tone/lut``'s stops: each one a tone (`0` black … `1` white) and the
    /// colour it becomes, with everything between two of them interpolated.
    /// Two or more; the editor enforces that.
    ///
    /// The positions are the point. They used to be implicit — four colours
    /// spaced evenly — which made this a gradient with the input side taken on
    /// trust, and a gradient is only the special case of a look-up table in
    /// which every stop happens to sit at an even interval.
    var lutStops: [ASCIIToneCurve.Stop] = [
        .init(at: 0, to: .rgb(10, 10, 40)),
        .init(at: 0.3, to: .rgb(180, 40, 70)),
        .init(at: 0.65, to: .rgb(245, 180, 60)),
        .init(at: 1, to: .rgb(255, 250, 220)),
    ]

    // MARK: - Colour modes

    /// The colour modes the demo offers: the fidelity ladder, then the three
    /// ways of naming a palette — so the cycler walks from "as much colour as
    /// this terminal has" all the way to "these three, and they follow the
    /// theme".
    ///
    /// The order is the ladder itself; nothing about the pane constrains it,
    /// since an option carries its own control now rather than borrowing the
    /// row after it.
    enum ColourMode: Int, CaseIterable {
        case trueColor, ansi256, ansi16, grayscale, mono, themed, greys
        /// N colours spread evenly over the GAMUT — the same N whatever the
        /// picture is.
        case spread
        /// N colours taken from the picture, by how many pixels are each.
        case mostUsed
        /// N colours taken from the picture, chosen to leave it closest to
        /// itself.
        case leastError
        /// A set someone wrote down, mapped by nearest colour — so the order
        /// they wrote it in does not matter.
        case customPalette
    }

    /// The recolourings the demo offers.
    ///
    /// In order of how much they ask of you, which is also the order in which
    /// they stop being a single switch and start being a configuration.
    enum Tone: Int, CaseIterable {
        case off, negative, accent, duotone, lut, channels
    }

    // MARK: - What the settings render as

    /// The ``ASCIICharacterSet`` these settings describe. `glyphCount` 0 means
    /// the full repertoire; an empty custom ramp falls back to a 10-glyph ASCII
    /// ramp so the demo never renders blank.
    var characterSet: ASCIICharacterSet {
        switch charset {
        case .ascii: return .ascii(glyphs: asciiGlyphs > 0 ? asciiGlyphs : nil)
        case .unicode: return .unicode(glyphs: unicodeGlyphs > 0 ? unicodeGlyphs : nil)
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
        case .ansi16: return .ansi16
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
        case .spread: return .palette(.spread(spreadColours))
        case .mostUsed: return .palette(.adaptive(mostUsedColours, by: .popularity))
        case .leastError: return .palette(.adaptive(leastErrorColours, by: .leastError))
        case .customPalette:
            return .palette(ImageDemoHelpers.customPalettes[
                min(customPaletteIndex, ImageDemoHelpers.customPalettes.count - 1)].palette)
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
            return lutStops.count >= 2 ? ASCIIToneCurve(lutStops) : nil
        case .channels:
            return ASCIIToneCurve(channelCurves)
        }
    }

    var ditheringMode: DitheringMode { dithering ? .floydSteinberg : .none }

    // MARK: - Keeping the knobs coherent

    /// Snaps every dependent knob to a value the current configuration actually
    /// renders with, so a disabled control never displays a setting that
    /// differs from what is being drawn.
    ///
    /// Deliberately lossy: a preference does not survive a round-trip through a
    /// mode that does not support it — coherence of what is on screen wins over
    /// remembering hidden state.
    mutating func snap() {
        // A terminal that will not draw a picture cannot have the picture
        // switched on: the toggle is disabled AND shows off, rather than
        // sitting there on while glyphs are what is being drawn. Which is the
        // whole point of this function — a disabled control must not display a
        // setting that differs from what is on screen.
        if !KittyGraphics.isSupported { terminalGraphics = false }
        if !ImageDemoHelpers.usesShape(charset) { shapeAware = false }
        if !ImageDemoHelpers.usesSupersampling(charset, shapeAware: shapeAware) {
            supersampling = 0
        }
        if !ImageDemoHelpers.usesEdgeTracing(charset, shapeAware: shapeAware) { edgeLines = false }
        if !ImageDemoHelpers.usesBlockStyle(charset, shapeAware: shapeAware) { blockStyleIndex = 0 }
        // Each charset's own count, clamped to its own repertoire. Neither is
        // zeroed when the other is chosen: a count is not a claim about what is
        // being drawn in a mode that does not use it.
        asciiGlyphs = min(
            asciiGlyphs, ImageDemoHelpers.maximumGlyphs(.ascii, shapeAware: shapeAware))
        unicodeGlyphs = min(
            unicodeGlyphs, ImageDemoHelpers.maximumGlyphs(.unicode, shapeAware: shapeAware))
        greyLevels = min(256, max(2, greyLevels))
        spreadColours = min(256, max(2, spreadColours))
        mostUsedColours = min(256, max(2, mostUsedColours))
        leastErrorColours = min(256, max(2, leastErrorColours))
        customPaletteIndex = min(
            ImageDemoHelpers.customPalettes.count - 1, max(0, customPaletteIndex))
        // A one-stop LUT is not a mapping; the editor can delete down to one,
        // so the floor is asserted here rather than hoped for.
        if lutStops.count == 1 { lutStops.append(.init(at: 1, to: .rgb(255, 255, 255))) }
    }

    /// The status bar's label for the colour mode — the same names the radio
    /// buttons carry, shortened, and carrying the parameter where there is one.
    var colourLabel: String {
        switch colour {
        case .trueColor: return "color:true"
        case .ansi256: return "color:256"
        case .ansi16: return "color:16"
        case .grayscale: return "color:gray"
        case .mono: return "color:mono"
        case .greys: return "color:\(greyLevels) greys"
        case .spread: return "color:\(spreadColours) spread"
        case .mostUsed: return "color:\(mostUsedColours) most-used"
        case .leastError: return "color:\(leastErrorColours) least-error"
        case .customPalette:
            let index = min(customPaletteIndex, ImageDemoHelpers.customPalettes.count - 1)
            return "color:custom \(ImageDemoHelpers.customPalettes[index].name)"
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
        case .channels: return "tone:channels"
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
