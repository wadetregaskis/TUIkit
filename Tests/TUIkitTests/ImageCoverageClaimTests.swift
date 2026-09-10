//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageCoverageClaimTests.swift
//
//  The seam between the converter's coverage runs and the compositor's
//  claims — §42's view half.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitImage

@Suite("An image's coverage becomes claims")
struct ImageCoverageClaimTests {

    private var half: Double { 128.0 / 255 }

    /// **Asserted at the seam, and here is why rather than end to end.**
    ///
    /// `Image` takes a file path or a URL — there is no in-memory source — so the raster
    /// view path cannot be rendered from pixels in a test at all, and never could: every
    /// existing test of it uses a path that does not exist. Feeding it real pixels would
    /// mean hand-writing an image file for `stb_image` to decode, which is a fixture
    /// harness rather than a test.
    ///
    /// So `ASCIIArt.claims` is a named property rather than four lines inside the private
    /// `_ImageCore`, and this asserts the mapping it performs. What is left untested is
    /// the wiring between it and the buffer — one `+=` — and that is said here rather
    /// than implied.
    @Test("A coverage run becomes a rectangle at its own line and columns")
    func runsBecomeRegions() throws {
        let art = ASCIIArt(
            lines: ["....", "...."],
            coverage: [
                ASCIIArt.CoverageRun(line: 0, columns: 1..<3, ink: 128, field: .max),
                ASCIIArt.CoverageRun(line: 1, columns: 0..<4, ink: .max, field: 128),
            ])
        let claims = art.claims
        #expect(claims.count == 2, "\(claims)")
        let ink = try #require(claims.first)
        #expect(ink.offsetX == 1 && ink.offsetY == 0 && ink.width == 2 && ink.height == 1, "\(ink)")
        #expect(ink.inkOpacity == half && ink.fieldOpacity == 1, "\(ink)")
        let field = try #require(claims.last)
        #expect(field.offsetY == 1 && field.width == 4, "\(field)")
        #expect(field.fieldOpacity == half && field.inkOpacity == 1, "\(field)")
    }

    /// A fully covered run states nothing — `OpacityRegion.claim` answers `nil` for it —
    /// so a picture whose coverage list happens to contain one costs no region. The
    /// converter drops those before they get here; this is the belt to that brace, and it
    /// matters because the resolver's cost is per region per covered row.
    @Test("A fully covered run owes no rectangle")
    func opaqueRunsAreDropped() {
        let art = ASCIIArt(
            lines: ["...."],
            coverage: [ASCIIArt.CoverageRun(line: 0, columns: 0..<4, ink: .max, field: .max)])
        #expect(art.claims.isEmpty, "\(art.claims)")
    }

    @Test("An opaque picture allocates no claims at all")
    func opaquePictureClaimsNothing() {
        #expect(ASCIIArt(lines: ["abc"]).claims.isEmpty)
    }

    /// The end-to-end shape, as far as it can be taken: a real conversion of a
    /// half-covered logo, through the real converter, to real regions.
    @Test("A half-covered logo's claims come out of a real conversion")
    func realConversionClaims() {
        var pixels: [RGBA] = []
        for y in 0..<8 {
            for x in 0..<8 {
                let inside = (2..<6).contains(x) && (2..<6).contains(y)
                pixels.append(
                    inside
                        ? RGBA(r: 220, g: 40, b: 40, a: 128)
                        : RGBA(r: 0, g: 0, b: 0, a: 0))
            }
        }
        let art = ColorDepth.withCurrent(.truecolor) {
            ASCIIConverter(characterSet: .blocks(.fine), shapeAware: false, colorMode: .trueColor)
                .convert(RGBAImage(width: 8, height: 8, pixels: pixels), width: 8, height: 4)
        }
        let claims = art.claims
        #expect(!claims.isEmpty, "\(art.coverage)")
        #expect(claims.allSatisfy { $0.fieldOpacity == self.half }, "\(claims)")
        // Only the square's rows and columns, not the transparent surround.
        #expect(claims.allSatisfy { $0.offsetY == 1 || $0.offsetY == 2 }, "\(claims)")
        #expect(claims.allSatisfy { $0.offsetX == 2 && $0.width == 4 }, "\(claims)")
    }
}
