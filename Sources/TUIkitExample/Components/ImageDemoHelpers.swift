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
        .fineBlocks, .coarseBlocks, .ascii, .shapeBased, .braille,
    ]
    static let colorModes: [ASCIIColorMode] = [.trueColor, .ansi256, .grayscale, .mono]

    static func charSetLabel(_ index: Int) -> String {
        switch charSets[index] {
        case .ascii: return "chars:ascii"
        case .coarseBlocks: return "chars:coarseBlocks"
        case .fineBlocks: return "chars:fineBlocks"
        case .shapeBased: return "chars:shape"
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

    /// `1` = fit the viewport exactly; the upper bound keeps the zoomed image to a
    /// sane size on screen.
    static let minZoom = 1.0
    static let maxZoom = 6.0

    static func zoomedIn(_ zoom: Double) -> Double { min(maxZoom, zoom + 0.5) }
    static func zoomedOut(_ zoom: Double) -> Double { max(minZoom, zoom - 0.5) }
    static func zoomLabel(_ zoom: Double) -> String { "zoom:\(String(format: "%.1f", zoom))x" }
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
