//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageDemoHelpers.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Shared image demo configuration used by both `ImageFilePage` and `ImageURLPage`.
enum ImageDemoHelpers {
    /// The fundamental charsets the demo exposes — the picker mirrors
    /// ``ASCIICharacterSet``'s cases directly rather than a list of
    /// pre-combined modes; size and shape-awareness are separate knobs.
    enum Charset: Int, CaseIterable {
        case ascii
        case blocks
        case unicode
        case custom
    }

    /// The block charset's discrete resolutions, in demo cycling order
    /// (the framework default `.half` first).
    static let blockResolutions: [ASCIICharacterSet.BlockResolution] = [
        .half, .solid, .coarse, .braille,
    ]

    static let colorModes: [ASCIIColorMode] = [.trueColor, .ansi256, .grayscale, .mono]

    static func charsetLabel(_ index: Int) -> String {
        switch Charset(rawValue: index) ?? .ascii {
        case .ascii: return "chars:ascii"
        case .blocks: return "chars:blocks"
        case .unicode: return "chars:unicode"
        case .custom: return "chars:custom"
        }
    }

    static func blockResolutionLabel(_ index: Int) -> String {
        switch blockResolutions[min(index, blockResolutions.count - 1)] {
        case .half: return "half"
        case .solid: return "solid"
        case .coarse: return "coarse"
        case .braille: return "braille"
        }
    }

    static func colorModeLabel(_ index: Int) -> String {
        switch colorModes[index] {
        case .trueColor: return "color:true"
        case .ansi256: return "color:256"
        case .grayscale: return "color:gray"
        case .mono: return "color:mono"
        }
    }

    // MARK: - The effective configuration

    /// The ``ASCIICharacterSet`` the controls currently describe.
    /// `glyphCount` 0 means the full repertoire; an empty custom ramp falls
    /// back to a 10-glyph ASCII ramp so the demo never renders blank.
    static func effectiveCharSet(
        charsetIndex: Int, glyphCount: Int, blockResolutionIndex: Int, customRamp: String
    ) -> ASCIICharacterSet {
        let glyphs = glyphCount > 0 ? glyphCount : nil
        switch Charset(rawValue: charsetIndex) ?? .ascii {
        case .ascii:
            return .ascii(glyphs: glyphs)
        case .unicode:
            return .unicode(glyphs: glyphs)
        case .blocks:
            return .blocks(blockResolutions[min(blockResolutionIndex, blockResolutions.count - 1)])
        case .custom:
            return customRamp.isEmpty ? .ascii(glyphs: 10) : .customRamp(customRamp)
        }
    }

    // MARK: - Knob applicability

    /// Shape-awareness applies to every charset except a custom ramp
    /// (which carries no shape calibration).
    static func usesShape(charsetIndex: Int) -> Bool {
        Charset(rawValue: charsetIndex) != .custom
    }

    /// The glyph-count knob applies to the sizeable charsets.
    static func usesGlyphCount(charsetIndex: Int) -> Bool {
        switch Charset(rawValue: charsetIndex) ?? .ascii {
        case .ascii, .unicode: return true
        case .blocks, .custom: return false
        }
    }

    /// The block-resolution knob applies to non-shape blocks (shape-aware
    /// blocks match over the block glyph repertoire instead).
    static func usesBlockResolution(charsetIndex: Int, shapeAware: Bool) -> Bool {
        Charset(rawValue: charsetIndex) == .blocks && !shapeAware
    }

    /// Whether the configuration consumes the supersampling factor — every
    /// non-shape renderer (each sample becomes an N×N area average; the
    /// shape matcher's 96-sample grid needs no factor). A custom ramp is
    /// never shape-matched, so it always qualifies.
    static func usesSupersampling(charsetIndex: Int, shapeAware: Bool) -> Bool {
        Charset(rawValue: charsetIndex) == .custom || !shapeAware
    }

    /// Whether the configuration consumes the edge-tracing knobs — the
    /// shape-aware ascii/unicode renderers (the block repertoire carries
    /// its own directional glyphs).
    static func usesEdgeTracing(charsetIndex: Int, shapeAware: Bool) -> Bool {
        guard shapeAware else { return false }
        switch Charset(rawValue: charsetIndex) ?? .ascii {
        case .ascii, .unicode: return true
        case .blocks, .custom: return false
        }
    }

    /// The largest useful glyph count for the current configuration (the
    /// stepper's upper bound), or 0 when the axis doesn't apply.
    static func maximumGlyphs(charsetIndex: Int, shapeAware: Bool) -> Int {
        effectiveCharSet(
            charsetIndex: charsetIndex, glyphCount: 0,
            blockResolutionIndex: 0, customRamp: ""
        ).maximumGlyphs(shapeAware: shapeAware) ?? 0
    }

    // MARK: - State snapping

    /// Snaps every dependent knob to a value the current configuration
    /// actually renders with, so a disabled control never displays a
    /// setting that differs from what is being drawn:
    ///
    /// - shape-awareness turns off for a custom ramp (which is always
    ///   luminance-mapped);
    /// - the supersampling picker returns to Auto while shape matching
    ///   ignores it;
    /// - the edge-lines toggle turns off while no edges can be traced;
    /// - the block resolution returns to its default while the block
    ///   subdivision path isn't in use;
    /// - the glyph count clamps to the charset's real ceiling (pool size
    ///   for shape matching, distinct density levels for luminance), and
    ///   resets to 0 (= full) when the axis doesn't apply.
    ///
    /// Deliberately lossy: a preference does not survive a round-trip
    /// through a mode that doesn't support it — coherence of what's on
    /// screen wins over remembering hidden state.
    static func snap(
        charsetIndex: Int,
        glyphCount: inout Int,
        blockResolutionIndex: inout Int,
        shapeAware: inout Bool,
        supersampling: inout Int,
        edgeLines: inout Bool
    ) {
        if !usesShape(charsetIndex: charsetIndex) {
            shapeAware = false
        }
        if !usesSupersampling(charsetIndex: charsetIndex, shapeAware: shapeAware) {
            supersampling = 0
        }
        if !usesEdgeTracing(charsetIndex: charsetIndex, shapeAware: shapeAware) {
            edgeLines = false
        }
        if !usesBlockResolution(charsetIndex: charsetIndex, shapeAware: shapeAware) {
            blockResolutionIndex = 0
        }
        if usesGlyphCount(charsetIndex: charsetIndex) {
            glyphCount = min(
                glyphCount, maximumGlyphs(charsetIndex: charsetIndex, shapeAware: shapeAware))
        } else {
            glyphCount = 0
        }
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
        .scrollbarVisibility(.automatic)
    }
}
