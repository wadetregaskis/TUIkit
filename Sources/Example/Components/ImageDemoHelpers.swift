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
        .fine, .solid, .coarse, .braille,
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
    /// shape-aware ascii/unicode renderers (the block repertoire carries its
    /// own directional glyphs).
    static func usesEdgeTracing(_ charset: Charset, shapeAware: Bool) -> Bool {
        guard shapeAware else { return false }
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
