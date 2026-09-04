//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageSizingExtremesTests.swift
//
//  The image size arithmetic given the values `Int(_: Double)` refuses —
//  infinities, NaN, magnitudes past `Int.max` — each of which reached a trap
//  through a public modifier or a public sizing function. A finite answer,
//  not a dead process, is the whole claim.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitImage

@testable import TUIkit

@MainActor
@Suite("Image sizing at the extremes")
struct ImageSizingExtremesTests {

    /// `Int(_: Double)` traps on an infinity and on any product past `Int.max`,
    /// and `.imageZoom(_:)` stored whatever it was given — so the FIRST frame
    /// that measured an image zoomed to `.infinity` (or `1e18`) killed the
    /// process, on the pre-load path, before any picture was involved.
    @Test(
        "An extreme .imageZoom measures to a finite size instead of trapping",
        arguments: [Double.infinity, -.infinity, .nan, 1e308, 1e20, 0, -1])
    func zoomExtremesDoNotTrap(factor: Double) {
        let context = makeScrollContext(viewport: (20, 10))
        let base = measureChild(
            Image(.file("/no/such/image.png")).imageFitTarget(.viewport),
            proposal: ProposedSize(width: 80, height: nil),
            context: context)
        let size = measureChild(
            Image(.file("/no/such/image.png")).imageFitTarget(.viewport).imageZoom(factor),
            proposal: ProposedSize(width: 80, height: nil),
            context: context)
        #expect(size.width >= 1 && size.height >= 1, "\(factor): \(size)")
        if !factor.isFinite || factor <= 0 {
            #expect(size.width == base.width, "\(factor) has no meaning as a zoom and is 1: \(size.width) vs \(base.width)")
        } else {
            #expect(size.width == base.width * 64, "\(factor) is clamped to the 64x ceiling: \(size.width) vs \(base.width)")
        }
    }

    @Test("The zoom and cell-aspect environment values reject what the arithmetic cannot use")
    func environmentSanitisesZoomAndAspect() {
        var environment = EnvironmentValues()
        for meaningless in [Double.infinity, -.infinity, .nan, 0, -1] {
            environment.imageZoom = meaningless
            #expect(environment.imageZoom == 1, "zoom \(meaningless)")
            environment.imageCellAspect = meaningless
            #expect(environment.imageCellAspect == 2, "aspect \(meaningless)")
        }
        environment.imageZoom = 1e308
        #expect(environment.imageZoom == 64, "past the ceiling is the ceiling")
        environment.imageZoom = 0.001
        #expect(environment.imageZoom == 0.001, "any positive zoom is honoured; the floor is the rendered cell, not the factor")
        environment.imageCellAspect = 1e308
        #expect(environment.imageCellAspect == ASCIIConverter.cellAspectRange.upperBound)
        environment.imageCellAspect = 1e-9
        #expect(environment.imageCellAspect == ASCIIConverter.cellAspectRange.lowerBound)
    }

    /// The guard above covered the source ratio and nothing else: a cell
    /// aspect of `.infinity` passed `> 0`, multiplied in, and reached the same
    /// `Int(_:)` trap one line later.
    @Test(
        "A cell aspect the arithmetic cannot use falls back to the default instead of trapping",
        arguments: [Double.infinity, -.infinity, .nan, 0, -2])
    func targetSizeMeaninglessCellAspect(aspect: Double) {
        let bounded = ASCIIConverter.targetSize(imageWidth: 100, imageHeight: 100, maxWidth: 80, maxHeight: 40)
        #expect(
            ASCIIConverter.targetSize(
                imageWidth: 100, imageHeight: 100, maxWidth: 80, maxHeight: 40, cellAspect: aspect) == bounded)
        let unbounded = ASCIIConverter.targetSize(imageWidth: 100, imageHeight: 100, maxWidth: 80)
        #expect(
            ASCIIConverter.targetSize(imageWidth: 100, imageHeight: 100, maxWidth: 80, cellAspect: aspect) == unbounded)
    }

    @Test("An absurd but finite cell aspect is clamped, and neither content mode traps")
    func targetSizeHugeCellAspect() {
        for mode in [ContentMode.fit, .fill] {
            let huge = ASCIIConverter.targetSize(
                imageWidth: 100, imageHeight: 100, maxWidth: 80, maxHeight: 40, contentMode: mode, cellAspect: 1e308)
            let ceiling = ASCIIConverter.targetSize(
                imageWidth: 100, imageHeight: 100, maxWidth: 80, maxHeight: 40, contentMode: mode,
                cellAspect: ASCIIConverter.cellAspectRange.upperBound)
            #expect(huge == ceiling, "\(mode)")
            #expect(huge.width >= 1 && huge.height >= 1, "\(mode)")
        }
    }

    @Test("An override ratio past Double's range saturates instead of trapping")
    func targetSizeHugeOverrideRatio() {
        // 1e308 x the cell aspect overflows to infinity: the PRODUCT is what the
        // guard has to see, not the operands.
        #expect(
            ASCIIConverter.targetSize(
                imageWidth: 100, imageHeight: 100, maxWidth: 80, maxHeight: 40, overrideAspectRatio: 1e308) == (1, 1))
        // Finite after the multiply, but the width no Int can hold is cut back
        // to the bound and the height floored at one cell.
        let wide = ASCIIConverter.targetSize(
            imageWidth: 100, imageHeight: 100, maxWidth: 80, maxHeight: 40, overrideAspectRatio: 1e300)
        #expect(wide == (80, 1))
    }
}
