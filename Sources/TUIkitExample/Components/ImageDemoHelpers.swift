//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageDemoHelpers.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Shared image demo configuration used by both `ImageFilePage` and `ImageURLPage`.
enum ImageDemoHelpers {
    static let charSets: [ASCIICharacterSet] = [
        .fineBlocks, .blocks, .coarseBlocks, .ascii, .asciiDetailed,
        .shapeBased, .shapeUnicode, .unicodeDetailed, .braille,
    ]
    static let colorModes: [ASCIIColorMode] = [.trueColor, .ansi256, .grayscale, .mono]

    static func charSetLabel(_ index: Int) -> String {
        switch charSets[index] {
        case .ascii: return "chars:ascii"
        case .asciiDetailed: return "chars:ascii+"
        case .coarseBlocks: return "chars:coarseBlocks"
        case .blocks: return "chars:blocks"
        case .fineBlocks: return "chars:fineBlocks"
        case .shapeBased: return "chars:shape"
        case .shapeUnicode: return "chars:shape+uni"
        case .unicodeDetailed: return "chars:unicode+"
        case .customRamp: return "chars:custom"
        case .braille: return "chars:braille"
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
