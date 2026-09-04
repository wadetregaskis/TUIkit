//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageDemoHelpers.swift
//
//  What the image demos' knobs MEAN — which ones a given configuration
//  actually consumes, and how far each may go. The knobs themselves live in
//  ``ImageDemoSettings``; this is the part that has to agree with
//  `ASCIIConverter.convert`'s dispatch, and it is shared so the controls, the
//  status bar and the snapping cannot drift from one another.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Shared image demo configuration used by both `ImageFilePage` and `ImageURLPage`.
enum ImageDemoHelpers {
    /// The fundamental charsets the demo exposes — mirroring
    /// ``ASCIICharacterSet``'s cases directly rather than a list of
    /// pre-combined modes; size and shape-awareness are separate knobs.
    ///
    /// Ordered so each parameterised case is followed in the control pane by
    /// the control that parameterises it: glyph count under ascii/unicode,
    /// block resolution under blocks, the ramp field under custom.
    enum Charset: Int, CaseIterable {
        case ascii
        case unicode
        case blocks
        case custom
    }

    /// The block charset's discrete styles, in demo order (the framework
    /// default `.fine` first).
    static let blockStyles: [ASCIICharacterSet.BlockStyle] = [
        .fine, .solid, .coarse, .ramp, .braille,
    ]

    // MARK: - Labels

    static func charsetLabel(_ charset: Charset) -> String {
        switch charset {
        case .ascii: return "chars:ascii"
        case .unicode: return "chars:unicode"
        case .blocks: return "chars:blocks"
        case .custom: return "chars:custom"
        }
    }

    static func blockStyleLabel(_ index: Int) -> String {
        switch blockStyles[min(index, blockStyles.count - 1)] {
        case .fine: return "fine"
        case .solid: return "solid"
        case .coarse: return "coarse"
        case .ramp: return "ramp"
        case .braille: return "braille"
        }
    }

    // MARK: - Knob applicability

    /// Shape-awareness applies to every charset except a custom ramp (which
    /// carries no shape calibration).
    static func usesShape(_ charset: Charset) -> Bool { charset != .custom }

    /// The glyph-count knob applies to the sizeable charsets.
    static func usesGlyphCount(_ charset: Charset) -> Bool {
        switch charset {
        case .ascii, .unicode: return true
        case .blocks, .custom: return false
        }
    }

    /// The block-resolution knob applies to non-shape blocks (shape-aware
    /// blocks match over the block glyph repertoire instead).
    static func usesBlockStyle(_ charset: Charset, shapeAware: Bool) -> Bool {
        charset == .blocks && !shapeAware
    }

    /// Whether the configuration consumes the supersampling factor — every
    /// non-shape renderer (each sample becomes an N×N area average; the shape
    /// matcher's 96-sample grid needs no factor). A custom ramp is never
    /// shape-matched, so it always qualifies.
    static func usesSupersampling(_ charset: Charset, shapeAware: Bool) -> Bool {
        charset == .custom || !shapeAware
    }

    /// Whether the configuration consumes the edge-tracing knobs — the
    /// ascii and unicode charsets, which have directional line glyphs to draw
    /// an edge WITH.
    ///
    /// Not a question about shape-awareness: both renderers trace edges, from
    /// whatever gradient each has to hand. The parameter is kept because the
    /// answer is about the charset in a configuration, and every other
    /// applicability question here takes both.
    static func usesEdgeTracing(_ charset: Charset, shapeAware _: Bool) -> Bool {
        switch charset {
        case .ascii, .unicode: return true
        case .blocks, .custom: return false
        }
    }

    /// The largest useful glyph count for the current configuration (the
    /// slider's upper bound), or 0 when the axis doesn't apply.
    static func maximumGlyphs(_ charset: Charset, shapeAware: Bool) -> Int {
        var probe = ImageDemoSettings()
        probe.charset = charset

        probe.blockStyleIndex = 0
        probe.customRamp = ""
        return probe.characterSet.maximumGlyphs(shapeAware: shapeAware) ?? 0
    }

    // MARK: - Zoom

    /// `1` = fit the viewport exactly. Above 1× we step linearly up to a sane
    /// on-screen maximum; below 1× we step multiplicatively (halving) down to
    /// `minZoom`, so a handful of presses shrinks the image all the way to a
    /// single pixel for typical terminal sizes (1/512 ≈ 2⁻⁹).
    static let minZoom = 1.0 / 512.0
    static let maxZoom = 6.0

    /// Zoom in one step. Below 1× this doubles back toward 1×; at/above 1× it
    /// adds 0.5. The two regimes meet cleanly at 1×.
    static func zoomedIn(_ zoom: Double) -> Double {
        zoom < 1.0 ? min(1.0, zoom * 2.0) : min(maxZoom, zoom + 0.5)
    }

    /// Zoom out one step. Above 1× this subtracts 0.5 down to 1×; at/below 1× it
    /// halves down to `minZoom`.
    static func zoomedOut(_ zoom: Double) -> Double {
        zoom > 1.0 ? max(1.0, zoom - 0.5) : max(minZoom, zoom / 2.0)
    }

    /// Below 1× the scale is an exact power-of-two fraction, so show it as `1/N`
    /// (e.g. `zoom:1/512x`); at/above 1× show one decimal (`zoom:2.0x`).
    static func zoomLabel(_ zoom: Double) -> String {
        if zoom < 1.0 {
            let denominator = Int((1.0 / zoom).rounded())
            return "zoom:1/\(denominator)x"
        }
        return "zoom:\(String(format: "%.1f", zoom))x"
    }

    // MARK: - Custom palettes

    /// A named set of colours someone wrote down, for
    /// ``ImageDemoSettings/ColourMode/customPalette``.
    ///
    /// The point of the mode, and why the demo ships four rather than one: a
    /// palette does not have to be derived from anything. These are subsets of
    /// the terminal's own 256 chosen by eye — a duotone, a sepia, a cool set and
    /// the cube's eight corners — and they are mapped by NEAREST COLOUR, so the
    /// order they are written in does not matter and no entry is guaranteed to
    /// be drawn. Every entry is a `.palette(_:)` index, so it renders exactly on
    /// any 256-colour terminal.
    ///
    /// The names are `Text(verbatim:)` on purpose: they name a look the way a
    /// font name does, and translating "Sepia" would make the demo describe a
    /// different palette in each language.
    struct NamedPalette {
        let name: String
        let palette: ASCIIPalette
    }

    static let customPalettes: [NamedPalette] = [
        NamedPalette(
            name: "Sepia",
            palette: ASCIIPalette([
                .palette(16), .palette(52), .palette(94), .palette(130),
                .palette(172), .palette(179), .palette(223), .palette(230),
            ])),
        NamedPalette(
            name: "Ice",
            palette: ASCIIPalette([
                .palette(17), .palette(18), .palette(25), .palette(31),
                .palette(38), .palette(45), .palette(123), .palette(195),
            ])),
        NamedPalette(
            name: "Poster",
            palette: ASCIIPalette([
                .palette(16), .palette(88), .palette(160), .palette(202),
                .palette(214), .palette(226), .palette(231),
            ])),
        NamedPalette(
            name: "Cube corners",
            palette: ASCIIPalette([
                .palette(16), .palette(21), .palette(46), .palette(51),
                .palette(196), .palette(201), .palette(226), .palette(231),
            ])),
    ]
}

extension View {
    /// Wraps an image in a two-axis `ScrollView` that fits the visible viewport at
    /// `zoom` 1 — so the whole image shows with no scrollbars — and reveals
    /// scrollbars only as you zoom in past it. The view tree is the same at every
    /// zoom level; only `zoom` changes (see ``ImageFitTarget/viewport``).
    func zoomableImageScroll(zoom: Double) -> some View {
        ScrollView([.horizontal, .vertical]) {
            self
                .imageFitTarget(.viewport)
                .imageZoom(zoom)
        }
        .scrollIndicators(.automatic)
    }
}
