//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColourAlphaStorageTests.swift
//
//  `Color.alpha` is stored, so every function that derives a Color FROM a Color
//  has to carry it. This is that check written as a table rather than as one test
//  per function, so a derivation added later fails here instead of silently
//  dropping the alpha.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// A palette to resolve semantic colours against.
private struct AlphaTestPalette: Palette {
    let id = "alpha-test"
    let name = "Alpha test"
    let background = Color.black
    let foreground = Color.white
    let accent = Color.cyan
    let success = Color.green
    let warning = Color.yellow
    let error = Color.red
    let info = Color.blue
    let border = Color.brightBlack
}

@Suite("Colour alpha storage")
struct ColourAlphaStorageTests {

    /// Padding-free, because `viewValueHash` hashes the raw bytes of every view
    /// struct and views hold `Color`s. A `Double` alpha would align the struct to
    /// eight and introduce padding, whose contents are undefined — making the
    /// render memo's key non-deterministic for two identical views.
    @Test("Color stays padding-free")
    func layoutHasNoPadding() {
        #expect(MemoryLayout<Color>.size == 5, "got \(MemoryLayout<Color>.size)")
        #expect(
            MemoryLayout<Color>.size == MemoryLayout<Color>.stride,
            "stride \(MemoryLayout<Color>.stride) means padding")
    }

    /// A colour at `alpha`, until the public `opacity:` spellings land.
    private func translucent(_ base: Color = .rgb(200, 100, 50), _ alpha: UInt8 = 128) -> Color {
        var colour = base
        colour.alpha = alpha
        return colour
    }

    @Test("A fresh colour is opaque")
    func freshColoursAreOpaque() {
        #expect(Color.red.isOpaque)
        #expect(Color.rgb(1, 2, 3).isOpaque)
        #expect(Color.hsl(180, 50, 50).isOpaque)
        #expect(Color.palette(42).isOpaque)
    }

    /// **The table.** Every `Color` → `Color` derivation in the styling module,
    /// asked to carry a non-opaque alpha through.
    ///
    /// Written as one test over a list rather than one test per function on
    /// purpose: the failure mode this guards against is a NEW derivation that
    /// forgets, and a per-function suite cannot fail for a function nobody added
    /// to it. Anything added below `// MARK: - Color Derivations` should get a row
    /// here.
    @Test("Every derivation carries the alpha")
    func derivationsCarryAlpha() {
        let faded = translucent()
        #expect(faded.alpha == 128, "the fixture: got \(faded.alpha)")

        let derivations: [(name: String, derived: Color)] = [
            ("downsampledToPalette256", faded.downsampledToPalette256()),
            ("downsampledToANSI16", faded.downsampledToANSI16()),
            ("downsampled(to: .palette256)", faded.downsampled(to: .palette256)),
            ("downsampled(to: .basic16)", faded.downsampled(to: .basic16)),
            ("lerp(_:_:phase:)", Color.lerp(faded, faded, phase: 0.5)),
            ("mix(with:by:)", faded.mix(with: faded, by: 0.5)),
            ("ensuringContrast", faded.ensuringContrast(atLeast: 3, against: .black)),
        ]
        for (name, derived) in derivations {
            #expect(derived.alpha == 128, "\(name) dropped the alpha: got \(derived.alpha)")
        }
    }

    /// The one that would otherwise be silent AND fatal: a semantic colour
    /// resolves through the palette, and the alpha belongs to the value the
    /// caller wrote, not to the palette's answer.
    @Test("Resolving a semantic colour keeps the alpha the caller asked for")
    func resolveKeepsAlpha() {
        let accent = translucent(.accentColor)
        let resolved = accent.resolve(with: AlphaTestPalette())
        #expect(resolved.alpha == 128, "got \(resolved.alpha)")
        #expect(resolved.value != accent.value, "…and it really did resolve")
    }

    /// Interpolating between two alphas interpolates the alpha too — which is
    /// what makes a `withAnimation` fade of a colour's opacity work, since both
    /// colour animators go through `lerp`.
    @Test("Interpolation treats alpha as a fourth channel")
    func interpolationBlendsAlpha() {
        let clearish = translucent(.rgb(255, 0, 0), 0)
        let solid = Color.rgb(255, 0, 0)
        #expect(Color.lerp(clearish, solid, phase: 0.5).alpha == 128)
        #expect(Color.lerp(clearish, solid, phase: 0).alpha == 0)
        #expect(Color.lerp(clearish, solid, phase: 1).alpha == 255)
    }

    /// `opacity(_:over:)` CONSUMES the alpha — it composites over a known
    /// surface, so its result is a plain opaque colour. Stated as a test because
    /// the alternative reading (carry it) would double-apply the fade.
    @Test("opacity(_:over:) consumes the alpha it applies")
    func compositingConsumesAlpha() {
        let result = translucent(.rgb(255, 0, 0)).opacity(0.5, over: .black)
        #expect(result.isOpaque, "got \(result.alpha)")
    }
}
