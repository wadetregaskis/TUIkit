//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - RGBA Tests

@Suite("RGBA Pixel Tests")
struct RGBAPixelTests {

    @Test("RGBA initializes with correct values")
    func rgbaInit() {
        let pixel = RGBA(r: 255, g: 128, b: 0, a: 200)
        #expect(pixel.r == 255)
        #expect(pixel.g == 128)
        #expect(pixel.b == 0)
        #expect(pixel.a == 200)
    }

    @Test("RGBA default alpha is 255 (opaque)")
    func rgbaDefaultAlpha() {
        let pixel = RGBA(r: 100, g: 100, b: 100)
        #expect(pixel.a == 255)
    }

    @Test("Luminance calculation follows ITU-R BT.601")
    func luminanceCalculation() {
        // Pure white
        let white = RGBA(r: 255, g: 255, b: 255)
        #expect(white.luminance > 254.0)

        // Pure black
        let black = RGBA(r: 0, g: 0, b: 0)
        #expect(black.luminance == 0.0)

        // Green contributes most to luminance
        let green = RGBA(r: 0, g: 255, b: 0)
        let red = RGBA(r: 255, g: 0, b: 0)
        #expect(green.luminance > red.luminance)
    }

    @Test("RGBA equality works correctly")
    func rgbaEquality() {
        let a = RGBA(r: 10, g: 20, b: 30, a: 40)
        let b = RGBA(r: 10, g: 20, b: 30, a: 40)
        let c = RGBA(r: 10, g: 20, b: 31, a: 40)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - RGBAImage Tests

@Suite("RGBAImage Tests")
struct RGBAImageTests {

    @Test("Image stores correct dimensions")
    func imageDimensions() {
        let pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 12)
        let image = RGBAImage(width: 4, height: 3, pixels: pixels)
        #expect(image.width == 4)
        #expect(image.height == 3)
    }

    @Test("Pixel access returns correct values")
    func pixelAccess() {
        var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 4)
        pixels[3] = RGBA(r: 255, g: 0, b: 0)  // (1, 1) in a 2x2 image
        let image = RGBAImage(width: 2, height: 2, pixels: pixels)

        let topLeft = image.pixel(at: 0, 0)
        #expect(topLeft.r == 0)

        let bottomRight = image.pixel(at: 1, 1)
        #expect(bottomRight.r == 255)
    }

    @Test("Set pixel modifies correct position")
    func setPixel() {
        let pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 4)
        var image = RGBAImage(width: 2, height: 2, pixels: pixels)

        image.setPixel(at: 1, 0, value: RGBA(r: 128, g: 64, b: 32))
        let pixel = image.pixel(at: 1, 0)
        #expect(pixel.r == 128)
        #expect(pixel.g == 64)
        #expect(pixel.b == 32)
    }

    @Test("Add error clamps to valid range")
    func addErrorClamping() {
        let pixels = [RGBA(r: 250, g: 5, b: 128)]
        var image = RGBAImage(width: 1, height: 1, pixels: pixels)

        // Adding positive error should clamp at 255
        image.addError(at: 0, 0, rError: 20, gError: -10, bError: 0)
        let pixel = image.pixel(at: 0, 0)
        #expect(pixel.r == 255)  // 250 + 20 -> clamped to 255
        #expect(pixel.g == 0)  // 5 - 10 -> clamped to 0
        #expect(pixel.b == 128)  // unchanged
    }

    @Test("Nearest-neighbor scaling produces correct dimensions")
    func nearestNeighborScaling() {
        let pixels = [RGBA](repeating: RGBA(r: 128, g: 128, b: 128), count: 100)
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)

        let scaled = image.scaled(to: 5, 5)
        #expect(scaled.width == 5)
        #expect(scaled.height == 5)
    }

    @Test("Bilinear scaling produces correct dimensions")
    func bilinearScaling() {
        let pixels = [RGBA](repeating: RGBA(r: 128, g: 128, b: 128), count: 100)
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)

        let scaled = image.scaledBilinear(to: 20, 20)
        #expect(scaled.width == 20)
        #expect(scaled.height == 20)
    }

    @Test("Scaling to zero returns empty image")
    func scalingToZero() {
        let pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 4)
        let image = RGBAImage(width: 2, height: 2, pixels: pixels)

        let scaled = image.scaled(to: 0, 0)
        #expect(scaled.width == 0)
        #expect(scaled.height == 0)
    }
}

// MARK: - ASCIIConverter Tests

@Suite("ASCIIConverter Tests")
struct ASCIIConverterTests {

    @Test("Target size calculation preserves aspect ratio")
    func targetSizeAspectRatio() {
        let size = ASCIIConverter.targetSize(
            imageWidth: 100,
            imageHeight: 100,
            maxWidth: 50
        )
        // 100x100 image -> 50 chars wide, ~25 chars tall (2:1 aspect correction)
        #expect(size.width == 50)
        #expect(size.height == 25)
    }

    @Test("Target size respects max height")
    func targetSizeMaxHeight() {
        let size = ASCIIConverter.targetSize(
            imageWidth: 100,
            imageHeight: 200,
            maxWidth: 80,
            maxHeight: 20
        )
        #expect(size.height <= 20)
        #expect(size.width > 0)
    }

    @Test("Target size is at least 1x1")
    func targetSizeMinimum() {
        let size = ASCIIConverter.targetSize(
            imageWidth: 1,
            imageHeight: 1,
            maxWidth: 1
        )
        #expect(size.width >= 1)
        #expect(size.height >= 1)
    }

    @Test("ASCII character set conversion produces output")
    func asciiConversion() {
        let pixels = [RGBA](repeating: RGBA(r: 128, g: 128, b: 128), count: 100)
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)

        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .mono, dithering: .none)
        let lines = converter.convert(image, width: 10, height: 5)

        #expect(lines.count == 5)
        #expect(!lines[0].isEmpty)
    }

    @Test("Block character set conversion produces output")
    func blockConversion() {
        let pixels = [RGBA](repeating: RGBA(r: 200, g: 100, b: 50), count: 100)
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)

        let converter = ASCIIConverter(characterSet: .blocks(.coarse), colorMode: .trueColor, dithering: .none)
        let lines = converter.convert(image, width: 10, height: 5)

        #expect(lines.count == 5)
    }

    @Test("Fine-block conversion uses two vertical pixels per cell")
    func halfBlocksUsesTwoPixelsPerCell() {
        // Solid red image. With .blocks(.half) the converter scales to
        // (width, height*2) pixels and emits ▄ with a foreground = bottom
        // pixel and a background = top pixel for each cell.
        let pixels = [RGBA](repeating: RGBA(r: 200, g: 50, b: 80), count: 64)
        let image = RGBAImage(width: 8, height: 8, pixels: pixels)
        let converter = ASCIIConverter(
            characterSet: .blocks(.half), colorMode: .trueColor, dithering: .none)

        withColorDepth(.truecolor) {
            let lines = converter.convert(image, width: 8, height: 4)
            #expect(lines.count == 4, "Output height matches the requested cell count")
            #expect(lines[0].contains("\u{2584}"), "Each cell uses the lower-half-block glyph")
            // True-colour mode emits both 38;2; (fg) and 48;2; (bg) codes — bg is
            // what makes the half-block effectively double the vertical resolution.
            #expect(lines[0].contains("38;2;"), "Foreground colour is emitted")
            #expect(lines[0].contains("48;2;"), "Background colour is emitted (top pixel)")
        }
    }

    @Test("Shape-based conversion picks a horizontal line for a clean top/bottom split")
    func shapeAwarePicksHorizontalEdgeForTopDarkImage() {
        // Top half black, bottom half white — a clean HORIZONTAL edge across the
        // cell. Edge detection now recognises it and draws the orientation-
        // matched line glyph `-`, rather than a top-heavy coverage char (which
        // was the pre-Sobel approximation).
        var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 100)
        for index in 50..<100 { pixels[index] = RGBA(r: 255, g: 255, b: 255) }
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)
        let converter = ASCIIConverter(
            characterSet: .ascii, shapeAware: true, colorMode: .mono, dithering: .none)
        let stripped = converter.convert(image, width: 1, height: 1).first?.stripped ?? ""
        #expect(stripped.first == "-", "a top/bottom split is a horizontal edge: '\(stripped)'")
    }

    @Test("Shape-based conversion picks a horizontal line for a clean bottom/top split")
    func shapeAwarePicksHorizontalEdgeForBottomDarkImage() {
        // Top half white, bottom half black — also a clean horizontal edge → `-`.
        var pixels = [RGBA](repeating: RGBA(r: 255, g: 255, b: 255), count: 100)
        for index in 50..<100 { pixels[index] = RGBA(r: 0, g: 0, b: 0) }
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)
        let converter = ASCIIConverter(
            characterSet: .ascii, shapeAware: true, colorMode: .mono, dithering: .none)
        let stripped = converter.convert(image, width: 1, height: 1).first?.stripped ?? ""
        #expect(stripped.first == "-", "a bottom/top split is a horizontal edge: '\(stripped)'")
    }

    @Test("Fine-block conversion in mono mode uses block glyphs only")
    func halfBlocksMonoUsesBlockGlyphs() {
        // Top half dark, bottom half bright → expect ▀ (Upper Half Block: dark
        // ink on top, light below) for every cell.
        var pixels = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 16)
        for index in 8..<16 { pixels[index] = RGBA(r: 255, g: 255, b: 255) }
        let image = RGBAImage(width: 4, height: 4, pixels: pixels)

        let converter = ASCIIConverter(
            characterSet: .blocks(.half), colorMode: .mono, dithering: .none)
        let lines = converter.convert(image, width: 4, height: 2)

        #expect(lines.count == 2)
        // Row 0 of cells covers source rows 0–1 (dark top, dark bottom) → ▀? no,
        // both rows are dark → █. Row 1 covers rows 2–3 (light top, light bottom)
        // → space. So row 0 should be all ▀ when scaled... actually after
        // bilinear scaling of (4×4 → 4×4 same size), the boundary mid-image,
        // so cells in row 0 see rows 0–1 (both dark) → █, row 1 sees 2–3 (both
        // light) → space.
        #expect(lines[0].allSatisfy { $0 == "\u{2588}" }, "Top cell row: both halves dark → █")
        #expect(lines[1].allSatisfy { $0 == " " }, "Bottom cell row: both halves light → space")
    }

    @Test("Braille conversion produces output")
    func brailleConversion() {
        let pixels = [RGBA](repeating: RGBA(r: 255, g: 255, b: 255), count: 400)
        let image = RGBAImage(width: 20, height: 20, pixels: pixels)

        let converter = ASCIIConverter(characterSet: .blocks(.braille), colorMode: .trueColor, dithering: .none)
        let lines = converter.convert(image, width: 10, height: 5)

        #expect(lines.count == 5)
    }

    @Test("True color output contains ANSI RGB codes")
    func trueColorOutput() {
        let pixels = [RGBA(r: 255, g: 0, b: 0)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)
        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .trueColor, dithering: .none)

        withColorDepth(.truecolor) {
            let lines = converter.convert(image, width: 1, height: 1)
            #expect(lines.count == 1)
            // Should contain 38;2; (foreground true color escape)
            #expect(lines[0].contains("38;2;"))
        }
    }

    @Test("Mono output contains no ANSI codes")
    func monoOutput() {
        let pixels = [RGBA(r: 128, g: 128, b: 128)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)

        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .mono, dithering: .none)
        let lines = converter.convert(image, width: 1, height: 1)

        #expect(lines.count == 1)
        // Mono should not contain color escape sequences
        #expect(!lines[0].contains("38;2;"))
        #expect(!lines[0].contains("38;5;"))
    }

    @Test("Floyd-Steinberg dithering does not crash")
    func ditheringNoCrash() {
        var pixels = [RGBA]()
        for i in 0..<100 {
            let r = UInt8(clamping: i * 2)
            let g = UInt8(clamping: i)
            let b = UInt8(clamping: 255 - i * 2)
            pixels.append(RGBA(r: r, g: g, b: b))
        }
        let image = RGBAImage(width: 10, height: 10, pixels: pixels)

        let converter = ASCIIConverter(characterSet: .blocks(.coarse), colorMode: .ansi256, dithering: .floydSteinberg)
        let lines = converter.convert(image, width: 10, height: 5)

        #expect(lines.count == 5)
    }

    @Test("Empty image returns empty lines")
    func emptyImageConversion() {
        let image = RGBAImage(width: 0, height: 0, pixels: [])
        let converter = ASCIIConverter()
        let lines = converter.convert(image, width: 10, height: 5)
        #expect(lines.isEmpty)
    }

    @Test("ANSI 256 output contains palette codes")
    func ansi256Output() {
        let pixels = [RGBA(r: 255, g: 0, b: 0)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)
        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .ansi256, dithering: .none)

        withColorDepth(.palette256) {
            let lines = converter.convert(image, width: 1, height: 1)
            #expect(lines.count == 1)
            // Should contain 38;5; (256-color escape)
            #expect(lines[0].contains("38;5;"))
        }
    }

    @Test("Grayscale output contains palette codes")
    func grayscaleOutput() {
        let pixels = [RGBA(r: 128, g: 128, b: 128)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)
        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .grayscale, dithering: .none)

        withColorDepth(.palette256) {
            let lines = converter.convert(image, width: 1, height: 1)
            #expect(lines.count == 1)
            #expect(lines[0].contains("38;5;"))
        }
    }

    @Test("True color requested on 256-color terminal falls back to palette codes")
    func trueColorDownsamplesOnPalette256() {
        let pixels = [RGBA(r: 255, g: 0, b: 0)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)
        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .trueColor, dithering: .none)

        withColorDepth(.palette256) {
            let lines = converter.convert(image, width: 1, height: 1)
            #expect(lines.count == 1)
            // Must NOT emit 24-bit codes — they corrupt 256-color terminals.
            #expect(!lines[0].contains("38;2;"))
            // Should emit 256-color codes instead.
            #expect(lines[0].contains("38;5;"))
        }
    }

    @Test("True color requested on basic16 terminal falls back to mono")
    func trueColorDownsamplesOnBasic16() {
        let pixels = [RGBA(r: 255, g: 0, b: 0)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)
        let converter = ASCIIConverter(characterSet: .ascii, colorMode: .trueColor, dithering: .none)

        withColorDepth(.basic16) {
            let lines = converter.convert(image, width: 1, height: 1)
            #expect(lines.count == 1)
            #expect(!lines[0].contains("38;2;"))
            #expect(!lines[0].contains("38;5;"))
        }
    }

    @Test("All color modes emit no color codes on noColor terminal")
    func noColorTerminalSuppressesEscapes() {
        let pixels = [RGBA(r: 200, g: 100, b: 50)]
        let image = RGBAImage(width: 1, height: 1, pixels: pixels)

        withColorDepth(.noColor) {
            for mode in [ASCIIColorMode.trueColor, .ansi256, .grayscale, .mono] {
                let converter = ASCIIConverter(characterSet: .ascii, colorMode: mode, dithering: .none)
                let lines = converter.convert(image, width: 1, height: 1)

                #expect(lines.count == 1)
                #expect(!lines[0].contains("38;2;"))
                #expect(!lines[0].contains("38;5;"))
            }
        }
    }
}

// MARK: - ASCIIColorMode.effective(for:)

@Suite("ASCIIColorMode.effective(for:)")
struct ASCIIColorModeEffectiveTests {

    @Test("True color stays true color only on truecolor terminals")
    func trueColorMapping() {
        #expect(ASCIIColorMode.trueColor.effective(for: .truecolor) == .trueColor)
        #expect(ASCIIColorMode.trueColor.effective(for: .palette256) == .ansi256)
        #expect(ASCIIColorMode.trueColor.effective(for: .basic16) == .mono)
        #expect(ASCIIColorMode.trueColor.effective(for: .noColor) == .mono)
    }

    @Test("ANSI 256 stays through palette256 terminals, drops to mono below")
    func ansi256Mapping() {
        #expect(ASCIIColorMode.ansi256.effective(for: .truecolor) == .ansi256)
        #expect(ASCIIColorMode.ansi256.effective(for: .palette256) == .ansi256)
        #expect(ASCIIColorMode.ansi256.effective(for: .basic16) == .mono)
        #expect(ASCIIColorMode.ansi256.effective(for: .noColor) == .mono)
    }

    @Test("Grayscale stays through palette256 terminals, drops to mono below")
    func grayscaleMapping() {
        #expect(ASCIIColorMode.grayscale.effective(for: .truecolor) == .grayscale)
        #expect(ASCIIColorMode.grayscale.effective(for: .palette256) == .grayscale)
        #expect(ASCIIColorMode.grayscale.effective(for: .basic16) == .mono)
        #expect(ASCIIColorMode.grayscale.effective(for: .noColor) == .mono)
    }

    @Test("Mono stays mono everywhere")
    func monoMapping() {
        #expect(ASCIIColorMode.mono.effective(for: .truecolor) == .mono)
        #expect(ASCIIColorMode.mono.effective(for: .palette256) == .mono)
        #expect(ASCIIColorMode.mono.effective(for: .basic16) == .mono)
        #expect(ASCIIColorMode.mono.effective(for: .noColor) == .mono)
    }
}

// MARK: - Image View Tests

@Suite("Image View Tests")
@MainActor
struct ImageViewTests {

    @Test("Image initializes with file source")
    func imageFileInit() {
        let image = Image(.file("/path/to/image.png"))
        #expect(image.source == .file("/path/to/image.png"))
    }

    @Test("Image initializes with URL source")
    func imageURLInit() {
        let image = Image(.url("https://example.com/image.png"))
        #expect(image.source == .url("https://example.com/image.png"))
    }

    @Test("ImageSource equality works")
    func imageSourceEquality() {
        let a = ImageSource.file("/path/a.png")
        let b = ImageSource.file("/path/a.png")
        let c = ImageSource.url("https://example.com")
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - ImageLoadError Tests

@Suite("ImageLoadError Tests")
struct ImageLoadErrorTests {

    @Test("Error descriptions are informative")
    func errorDescriptions() {
        let fileError = ImageLoadError.fileNotFound("/missing.png")
        #expect(fileError.description.contains("/missing.png"))

        let formatError = ImageLoadError.unsupportedFormat("bmp")
        #expect(formatError.description.contains("bmp"))

        let decodeError = ImageLoadError.decodingFailed("corrupt data")
        #expect(decodeError.description.contains("corrupt data"))

        let downloadError = ImageLoadError.downloadFailed("timeout")
        #expect(downloadError.description.contains("timeout"))
    }
}

// MARK: - Image sizing (aspect-driven, not greedy)

@MainActor
@Suite("Image sizing")
struct ImageSizingTests {
    @Test("An unloaded image reserves a bounded height, not an unbounded offered height")
    func unloadedImageHeightBounded() {
        // A ScrollView measures its content against a deliberately tall canvas; the
        // image must not claim that whole height before its aspect ratio is known
        // (the regression that buried the demo image thousands of lines down).
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        let context = RenderContext(
            availableWidth: 40, availableHeight: 4096,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
        let size = measureChild(
            Image(.file("/no/such/image.png")),
            proposal: ProposedSize(width: 40, height: nil),
            context: context)
        #expect(size.width == 40, "takes the offered width: \(size.width)")
        #expect(size.height < 100, "height is bounded, not the 4096-line canvas: \(size.height)")
    }

    /// Builds a context that mimics being inside a ScrollView: a tall measure canvas
    /// plus a published `scrollViewportSize` for the visible area.
    private func scrollContext(viewport: (Int, Int)) -> RenderContext {
        var environment = EnvironmentValues()
        environment.stateStorage = StateStorage()
        environment.scrollViewportSize = ScrollViewportSize(width: viewport.0, height: viewport.1)
        return RenderContext(
            availableWidth: viewport.0, availableHeight: 4096,
            environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    @Test(".imageFitTarget(.viewport) fits the visible viewport, not the proposed canvas")
    func viewportFitUsesViewport() {
        // Proposed width 80 but viewport only 20 wide → the image sizes to the
        // viewport (20), so at zoom 1 it fills the visible area and won't overflow.
        let context = scrollContext(viewport: (20, 10))
        let size = measureChild(
            Image(.file("/no/such/image.png")).imageFitTarget(.viewport),
            proposal: ProposedSize(width: 80, height: nil),
            context: context)
        #expect(size.width == 20, "uses the viewport width (20), not the proposal (80): \(size.width)")
        #expect(size.height <= 10, "bounded by the viewport height (10): \(size.height)")
    }

    @Test(".proposedSize (default) ignores the viewport and uses the proposal")
    func proposedFitIgnoresViewport() {
        // Same published viewport, but the default target tracks the proposal — so an
        // unzoomed image in a horizontal scroll can still be wider than the viewport.
        let context = scrollContext(viewport: (20, 10))
        let size = measureChild(
            Image(.file("/no/such/image.png")),
            proposal: ProposedSize(width: 80, height: nil),
            context: context)
        #expect(size.width == 80, "default uses the proposal width (80), not the viewport (20): \(size.width)")
    }

    @Test(".imageZoom multiplies the fitted size")
    func zoomMultipliesSize() {
        let context = scrollContext(viewport: (20, 10))
        let base = measureChild(
            Image(.file("/no/such/image.png")).imageFitTarget(.viewport),
            proposal: ProposedSize(width: 80, height: nil),
            context: context)
        let zoomed = measureChild(
            Image(.file("/no/such/image.png")).imageFitTarget(.viewport).imageZoom(2),
            proposal: ProposedSize(width: 80, height: nil),
            context: context)
        #expect(zoomed.width == base.width * 2, "zoom 2 doubles width: \(zoomed.width) vs \(base.width)")
        #expect(zoomed.height == base.height * 2, "zoom 2 doubles height: \(zoomed.height) vs \(base.height)")
    }

    private func renderContext(width: Int, height: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = StateStorage()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()).isolatingRenderCache()
    }

    @Test("In a real ScrollView, .viewport fits the visible area; the default overflows")
    func viewportFitComposesWithScrollView() {
        // End to end: ScrollView publishes its viewport, the Image fits it, and the
        // `.automatic` scrollbar (▼) only appears once content exceeds the viewport.
        // Two renders settle the handler's lazily-measured content height.
        func hasVerticalScrollbar(_ content: some View) -> Bool {
            let view = ScrollView { content }.scrollbarVisibility(.automatic)
            let context = renderContext(width: 24, height: 5)
            _ = renderToBuffer(view, context: context)
            let buffer = renderToBuffer(view, context: context)
            return buffer.lines.contains { $0.contains("▼") }
        }
        #expect(
            !hasVerticalScrollbar(Image(.file("/no/such/x.png")).imageFitTarget(.viewport)),
            ".viewport fits the 5-line viewport → no scrollbar")
        #expect(
            hasVerticalScrollbar(Image(.file("/no/such/x.png"))),
            "the default image overflows the short viewport → scrollbar appears")
    }
}

// MARK: - Decoder Parity

@Suite("Platform decoder parity")
struct PlatformDecoderParityTests {

    // A 2×2 PNG with four distinct opaque corners — top-left red, top-right
    // green, bottom-left blue, bottom-right white. Decoding it pins channel
    // order (R, G, B), row orientation (row 0 = top, not vertically flipped)
    // and opaque alpha for whichever backend `PlatformImageLoader` selects
    // (NSImage on Apple platforms via `canImport(AppKit)`, stb_image
    // elsewhere), so the two backends stay interchangeable.
    private static let cornerPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP4z8DwHwyBNBgAAEnICfcD2WTxAAAAAElFTkSuQmCC"

    private static func cornerPNGData() throws -> Data {
        try #require(Data(base64Encoded: cornerPNGBase64))
    }

    /// Tolerates ±a few per channel (colour-management rounding) while still
    /// catching channel-swap or vertical-flip bugs, which are off by ~255.
    private func expectCorners(_ image: RGBAImage) {
        #expect(image.width == 2)
        #expect(image.height == 2)

        func expectNear(_ pixel: RGBA, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ corner: String) {
            #expect(abs(Int(pixel.r) - Int(r)) <= 6, "\(corner) red")
            #expect(abs(Int(pixel.g) - Int(g)) <= 6, "\(corner) green")
            #expect(abs(Int(pixel.b) - Int(b)) <= 6, "\(corner) blue")
            #expect(pixel.a == 255, "\(corner) alpha")
        }

        expectNear(image.pixel(at: 0, 0), 255, 0, 0, "top-left")
        expectNear(image.pixel(at: 1, 0), 0, 255, 0, "top-right")
        expectNear(image.pixel(at: 0, 1), 0, 0, 255, "bottom-left")
        expectNear(image.pixel(at: 1, 1), 255, 255, 255, "bottom-right")
    }

    @Test("Decodes a known 2×2 image from data with correct channels, orientation and alpha")
    func decodesKnownCornersFromData() throws {
        try expectCorners(PlatformImageLoader().loadImage(from: Self.cornerPNGData()))
    }

    @Test("Decodes the same image identically from a file path")
    func decodesKnownCornersFromPath() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-corner-\(UUID().uuidString).png")
        try Self.cornerPNGData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try expectCorners(PlatformImageLoader().loadImage(from: url.path))
    }
}
