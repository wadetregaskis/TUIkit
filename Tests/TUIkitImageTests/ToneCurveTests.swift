//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToneCurveTests.swift
//
//  What a tone curve does to a COLOUR image — the question a greyscale test
//  fixture cannot ask, and the one the negative got wrong.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

@Suite("Tone curves")
struct ToneCurveTests {

    /// A saturated red and a saturated cyan have very different hues and, by
    /// BT.601, very different tones — so a curve indexed on tone alone tells
    /// them apart, and one that discards chroma cannot put them back.
    private let red = RGBA(r: 220, g: 30, b: 30)
    private let cyan = RGBA(r: 30, g: 220, b: 220)

    /// The reported case: "the Invert tone seems to turn the image into
    /// greyscale, even in colour modes".
    ///
    /// It did, and by construction. A transfer curve is a function of luminance
    /// alone, so `{black → white, white → black}` replaced every pixel with the
    /// grey at its tone. The arithmetic was right and the operation was wrong.
    @Test("A negative keeps the picture's colour")
    func invertedIsNotGreyscale() {
        let inverted = ASCIIToneCurve.inverted.apply(to: red)
        #expect(
            !(inverted.r == inverted.g && inverted.g == inverted.b),
            "red inverted to the grey rgb(\(inverted.r), \(inverted.g), \(inverted.b))")
        // A negative complements each channel, so red becomes cyan.
        #expect(inverted == RGBA(r: 35, g: 225, b: 225))
        #expect(ASCIIToneCurve.inverted.apply(to: cyan) == RGBA(r: 225, g: 35, b: 35))
    }

    /// It is still an inversion in the sense anyone means: it is its own
    /// opposite, and it moves every tone to the other end.
    @Test("A negative is its own inverse and reverses lightness")
    func invertedRoundTrips() {
        for pixel in [red, cyan, RGBA(r: 0, g: 0, b: 0), RGBA(r: 128, g: 128, b: 128)] {
            let once = ASCIIToneCurve.inverted.apply(to: pixel)
            #expect(ASCIIToneCurve.inverted.apply(to: once) == pixel, "\(pixel) did not round-trip")
            // `luminance` is on 0…255, like the channels it is made of.
            #expect(
                (once.luminance - (255 - pixel.luminance)).magnitude < 2,
                "\(pixel) tone \(pixel.luminance) went to \(once.luminance)")
        }
    }

    /// The alpha channel is carried through: a curve recolours, it does not
    /// reveal or hide.
    @Test("A negative leaves alpha alone")
    func invertedKeepsAlpha() {
        #expect(ASCIIToneCurve.inverted.apply(to: RGBA(r: 10, g: 20, b: 30, a: 77)).a == 77)
    }

    /// A duotone still means what it always did — two colours, every tone
    /// between them interpolated — and that IS a mapping from tone to colour,
    /// so two pixels of equal tone land on the same colour by design.
    @Test("A duotone still maps tone to colour")
    func duotoneStillFlattensToTheCurve() {
        let navyToAmber = ASCIIToneCurve([
            (Color.rgb(0, 0, 0), Color.rgb(20, 20, 60)),
            (Color.rgb(255, 255, 255), Color.rgb(255, 215, 130)),
        ])
        let darkRed = RGBA(r: 90, g: 20, b: 20)
        let darkBlue = RGBA(r: 20, g: 20, b: 90)
        // Chosen to have nearly the same BT.601 tone, so the curve is being
        // asked the same question by both.
        #expect((darkRed.luminance - darkBlue.luminance).magnitude < 24)
        let first = navyToAmber.apply(to: darkRed)
        let second = navyToAmber.apply(to: darkBlue)
        #expect(
            (Int(first.r) - Int(second.r)).magnitude < 32,
            "the duotone should answer alike for alike tones: \(first) vs \(second)")
    }

    /// Fewer than two knots cannot define a mapping, so the curve is skipped
    /// rather than applied as a flattening constant — and the negative, which
    /// has no knots at all, must not be caught by that rule.
    @Test("An unusable curve is inert; the negative is not one")
    func identityRules() {
        #expect(ASCIIToneCurve.identity.isIdentity)
        #expect(ASCIIToneCurve([(Color.rgb(0, 0, 0), Color.rgb(1, 1, 1))]).isIdentity)
        #expect(!ASCIIToneCurve.inverted.isIdentity)
        #expect(ASCIIToneCurve.identity.apply(to: red) == red)
    }
}
