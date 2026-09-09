//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AdaptationTargetTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitImage
@testable import TUIkitStyling

/// An adaptive palette chooses from the colours the output HAS.
///
/// It used to choose in continuous colour and be quantised afterwards, and the
/// entries collapsed onto each other: on `demo-image.jpg` at 256 colours, asking
/// for five gave four — a palette *bit-identical* to the one four gave, which is
/// the reported "4 to 5 changes nothing, same for 8 to 9 and 9 to 10" exactly —
/// and asking for 256 gave 51, which is why Least error at 256 colours looked
/// worse than plain 256-colour mode on Terminal.app.
///
/// Measured on that picture, weighted mean OKLab error over its 5,078 populated
/// cells, depth-blind → depth-aware:
///
/// | n | 4 | 5 | 8 | 16 | 32 | 64 | 256 |
/// |---|---|---|----|----|----|-----|-----|
/// | distinct, blind | 4 | **4** | 7 | 12 | 17 | 23 | **51** |
/// | distinct, aware | 4 | 5 | 8 | 16 | 32 | 64 | **240** |
/// | better by | 10.0% | 23.5% | 21.8% | 29.2% | 33.0% | 30.0% | 12.3% |
///
/// At 256 the aware palette reaches 0.02125 — which is plain `.ansi256`'s error
/// to five decimal places, because 240 colours out of a 240-colour lattice IS
/// that palette.
@Suite("Adaptive palettes choose colours the output has")
struct AdaptationTargetTests {

    /// A picture with more distinct colours than any small palette holds, and
    /// with them spread over the gamut rather than clustered: colours a third of
    /// a cube step apart are what make the collapse happen, so the fixture has
    /// to contain them.
    private static func subject(width: Int = 48, height: Int = 48) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(
                    RGBA(
                        r: UInt8(clamping: x * 255 / max(1, width - 1)),
                        g: UInt8(clamping: y * 255 / max(1, height - 1)),
                        b: UInt8(clamping: (x + y) * 255 / max(1, width + height - 2))))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    // MARK: - The reported bug

    /// The one that was reported. Every step of the count has to buy a colour,
    /// and on a 256-colour terminal it did not.
    @Test(
        "At 256 colours every step of the count buys a colour",
        arguments: ASCIIPalette.Adaptation.allCases)
    func everyStepBuysAColour(method: ASCIIPalette.Adaptation) {
        let image = Self.subject()
        for count in 3...24 {
            let derived = ASCIIPalette.adaptive(count, by: method)
                .derived(from: image, depth: .palette256)
            #expect(
                Set(derived.colors).count == count,
                "\(method) asked \(count), drew \(Set(derived.colors).count)")
        }
    }

    /// The other half of the same assertion: the old behaviour is still there,
    /// under the target that names it, and it still collapses. Without this the
    /// test above could pass because nothing is constrained at all.
    @Test("The depth-blind derivation is still reachable, and still collapses")
    func theBlindDerivationStillCollapses() {
        let image = Self.subject()
        var collapses = 0
        for count in 3...24 {
            let blind = ASCIIPalette.adaptive(count, by: .leastError, target: .depth(.truecolor))
                .derived(from: image, depth: .palette256)
                .downsampled(to: .palette256)
            if Set(blind.colors).count < count { collapses += 1 }
        }
        #expect(collapses > 0, "nothing collapsed, so the fixture no longer shows the bug")
    }

    // MARK: - What each target draws in

    /// The property that makes the second fit a no-op: a constrained palette is
    /// spelt in the target's OWN colours, so `downsampled(to:)` — which
    /// `ASCIIConverter.convert(_:width:height:)` runs after the derivation, and
    /// must keep running — has nothing left to change. A palette of triples
    /// carrying the same RGB would be re-quantised by it, and could land
    /// somewhere else.
    @Test("A palette targeting a depth survives that depth's fit untouched")
    func theFitIsANoOp() {
        let image = Self.subject()
        for depth in [ColorDepth.palette256, .basic16, .noColor] {
            let derived = ASCIIPalette.adaptive(12, by: .leastError, target: .depth(depth))
                .derived(from: image, depth: .truecolor)
            #expect(
                derived.downsampled(to: depth).colors == derived.colors,
                "\(depth) moved its own colours")
        }
    }

    @Test("The 256-colour target draws in palette indexes, all of them above 15")
    func palette256TargetIsIndexed() {
        let derived = ASCIIPalette.adaptive(12, by: .leastError, target: .depth(.palette256))
            .derived(from: Self.subject(), depth: .truecolor)
        for colour in derived.colors {
            guard case .palette256(let index) = colour.value else {
                Issue.record("not an index: \(colour)")
                continue
            }
            // Below 16 is a NAME, which bold may repaint in its bright twin —
            // see `ASCIIColorMode.foregroundSurvivesBold`.
            #expect(index >= 16, "index \(index) is one of the sixteen names")
        }
    }

    @Test("The 16-colour target draws in the sixteen names, so it follows the profile")
    func basic16TargetIsNamed() {
        let derived = ASCIIPalette.adaptive(12, by: .leastError, target: .depth(.basic16))
            .derived(from: Self.subject(), depth: .truecolor)
        #expect(derived.colors.count == 12)
        for colour in derived.colors {
            switch colour.value {
            case .standard, .bright: break
            default: Issue.record("not one of the sixteen: \(colour)")
            }
        }
    }

    /// Asking for more than the target holds gets what the target holds. Sixteen
    /// colours cannot be drawn as thirty different things and then be thirty
    /// different things.
    @Test("A target with fewer colours than asked for answers with the ones it has")
    func aTargetCannotInventColours() {
        let image = Self.subject()
        #expect(
            ASCIIPalette.adaptive(30, by: .leastError, target: .depth(.basic16))
                .derived(from: image, depth: .truecolor).colors.count == 16)
        // As a SET: the order is whichever centre Lloyd numbered first, and
        // nothing reads it — `.nearestColor` asks every entry.
        #expect(
            Set(
                ASCIIPalette.adaptive(30, by: .leastError, target: .depth(.noColor))
                    .derived(from: image, depth: .truecolor).colors
            ) == Set([.rgb(0, 0, 0), .rgb(255, 255, 255)]))
        // 240 distinct colours over indices 16…255 — the ceiling on any
        // 256-colour palette however much is asked for.
        #expect(
            Set(
                ASCIIPalette.adaptive(256, by: .leastError, target: .depth(.palette256))
                    .derived(from: image, depth: .truecolor).colors
            ).count <= 240)
    }

    // MARK: - Automatic follows the output

    @Test(
        "Automatic takes the depth it is handed",
        arguments: [ColorDepth.truecolor, .palette256, .basic16, .noColor])
    func automaticFollowsTheOutput(depth: ColorDepth) {
        let image = Self.subject()
        let automatic = ASCIIPalette.adaptive(8, by: .leastError)
            .derived(from: image, depth: depth)
        let named = ASCIIPalette.adaptive(8, by: .leastError, target: .depth(depth))
            .derived(from: image, depth: .truecolor)
        #expect(automatic.colors == named.colors, "automatic at \(depth) is not \(depth)")
    }

    /// The Kitty-graphics rule, and the reason the depth is a parameter rather
    /// than `ColorDepth.current`: `recoloured` sends pixels as RGB inside a
    /// picture, so its palette is 24-bit on the very terminal where the glyph
    /// rendering of the same picture is 256-colour. Constraining it would throw
    /// away colour the picture is about to be given.
    @Test("The graphics path is not constrained by the terminal's SGR depth")
    func theGraphicsPathIsUnconstrained() {
        let image = Self.subject()
        let drawn = ColorDepth.withCurrent(.palette256) {
            ASCIIConverter(colorMode: .palette(.adaptive(16, by: .leastError)))
                .recoloured(image, width: 24, height: 24)
        }
        let lattice = Set(
            ASCIIPalette.ansi256.colors.compactMap(\.rgbComponents).map {
                Int($0.red) << 16 | Int($0.green) << 8 | Int($0.blue)
            })
        let painted = Set(drawn.pixels.map { Int($0.r) << 16 | Int($0.g) << 8 | Int($0.b) })
        #expect(
            !painted.isSubset(of: lattice),
            "every pixel is a 256-colour entry, so the picture WAS constrained")
    }

    /// The same conversion, twice — a projection that broke determinism would
    /// make one picture render two ways.
    @Test("A target does not cost determinism", arguments: ASCIIPalette.Adaptation.allCases)
    func stillDeterministic(method: ASCIIPalette.Adaptation) {
        let image = Self.subject()
        for depth in [ColorDepth.palette256, .basic16] {
            let first = ASCIIPalette.adaptive(16, by: method).derived(from: image, depth: depth)
            let second = ASCIIPalette.adaptive(16, by: method).derived(from: image, depth: depth)
            #expect(first.colors == second.colors, "\(method) at \(depth)")
        }
    }

    /// Deriving twice is deriving once: the answer is an ORDINARY palette, and
    /// nothing downstream can tell it was ever a question — including a second
    /// derivation at a different depth.
    @Test("A derived palette is not adaptive any more")
    func derivationIsIdempotent() {
        let derived = ASCIIPalette.adaptive(8, by: .leastError)
            .derived(from: Self.subject(), depth: .palette256)
        #expect(
            derived.derived(from: Self.subject(width: 20, height: 20), depth: .basic16).colors
                == derived.colors)
    }

    // MARK: - The API surface

    /// A new ``ColorDepth`` must appear in the picker, and `allCases` is written
    /// out by hand because ``ASCIIPalette/AdaptationTarget/depth(_:)`` carries a
    /// value. This is what stops the two drifting apart.
    @Test("Every depth is offered")
    func everyDepthIsOffered() {
        let offered = ASCIIPalette.AdaptationTarget.allCases.compactMap { target -> ColorDepth? in
            guard case .depth(let depth) = target else { return nil }
            return depth
        }
        #expect(Set(offered) == Set([.truecolor, .palette256, .basic16, .noColor]))
        #expect(
            ASCIIPalette.AdaptationTarget.allCases.contains(.automatic),
            "the one an app should want is not on the list")
        #expect(
            ASCIIPalette.AdaptationTarget.allCases.count == offered.count + 1,
            "a case that is neither automatic nor a depth is unlabelled in the picker")
    }

    /// The request carries the target, so two palettes that differ only in it are
    /// different palettes — which is what makes every cache keyed on the colour
    /// mode invalidate when the picker moves.
    @Test("The target is part of what a palette IS")
    func theTargetIsPartOfEquality() {
        #expect(
            ASCIIPalette.adaptive(8, by: .leastError)
                != ASCIIPalette.adaptive(8, by: .leastError, target: .depth(.basic16)))
        #expect(
            ASCIIPalette.adaptive(8, by: .leastError)
                == ASCIIPalette.adaptive(8, by: .leastError, target: .automatic),
            "automatic is the default")
    }
}
