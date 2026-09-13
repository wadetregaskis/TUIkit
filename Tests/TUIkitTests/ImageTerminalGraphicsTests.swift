//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageTerminalGraphicsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// `Image` drawing with the terminal's own graphics instead of glyphs.
///
/// The load-bearing claim is that switching renderers changes the *pixels* and
/// nothing else: same cell box, same layout, same everything the surrounding
/// views were told. So every test here compares the two renderings rather than
/// asserting about one.
@MainActor
@Suite("Image through terminal graphics")
struct ImageTerminalGraphicsTests {

    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// Renders `_ImageCore` with `image` already loaded, and hands back both
    /// the buffer and the context's store so a test can see what was owed to
    /// the terminal.
    private func rendered(
        _ image: RGBAImage, path: String, width: Int, height: Int,
        measuring: Bool = false,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> (buffer: FrameBuffer, store: TerminalImageStore) {
        let tui = Self.snapshotContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
        configure(&environment)
        var context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        context.isMeasuring = measuring

        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: .loading)
        phase.value = .success(image)

        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = renderToBuffer(_ImageCore(source: .file(path)), context: context)
        return (buffer, tui.terminalImageStore)
    }

    private func load(width: Int, height: Int) throws -> (image: RGBAImage, path: String) {
        let fixture = try BitmapFixture(width: width, height: height)
        return (try PlatformImageLoader().loadImage(from: fixture.path), fixture.path)
    }

    private func placeholderCells(in buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { total, line in
            total + line.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count
        }
    }

    /// A measure pass reads a box, not a picture. On a terminal that draws
    /// real pixels the glyph conversion behind that box is never looked at,
    /// so it must not be run.
    @Test("A measure pass on a graphics terminal does not convert to glyphs")
    func measurePassSkipsGlyphConversion() throws {
        let (image, path) = try load(width: 40, height: 20)
        let glyphs = rendered(image, path: path, width: 20, height: 20).buffer
        let measured = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 20, height: 20, measuring: true).buffer
        }
        #expect(measured.width == glyphs.width)
        #expect(measured.height == glyphs.height)
        #expect(measured.lines != glyphs.lines, "it converted the whole image to measure it")
        #expect(measured.lines.allSatisfy { $0.stripped.allSatisfy { $0 == " " } }, "a measure pass draws nothing")
    }

    /// The picture is drawn as text, and it is exactly the text the layout was
    /// promised: `width` cells across, on every row.
    @Test("A supported terminal gets placeholder cells, and they measure right")
    func supportedTerminalDrawsPlaceholders() throws {
        let (image, path) = try load(width: 40, height: 20)
        let drawn = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 20, height: 20)
        }
        #expect(!drawn.buffer.lines.isEmpty)
        #expect(placeholderCells(in: drawn.buffer) == drawn.buffer.width * drawn.buffer.height)
        for line in drawn.buffer.lines {
            #expect(line.strippedLength == drawn.buffer.width)
        }
        // And the terminal was told about the image before the frame that
        // names it — in the NARROW format, because the fixture is a BMP and
        // has no alpha channel. Three bytes a pixel rather than four is a
        // quarter off a transmission that can be megabytes.
        let pending = drawn.store.takePending()
        #expect(pending.contains("a=t,q=2,f=24"))
        #expect(!pending.contains("f=32"), "nothing here is transparent")
        #expect(pending.contains("a=p,U=1,q=2"))
    }

    /// The claim that makes this safe to switch on by default: the layout does
    /// not move. The glyph renderer and the graphics renderer ask the same
    /// function for their cell box, and this is what says so.
    @Test("Switching renderers does not move the image")
    func bothRenderersProduceTheSameBox() throws {
        let (image, path) = try load(width: 40, height: 10)
        let glyphs = rendered(image, path: path, width: 40, height: 20).buffer
        let pixels = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 40, height: 20).buffer
        }
        #expect(glyphs.width == pixels.width)
        #expect(glyphs.height == pixels.height)
        #expect(pixels.height == 5, "40x10 at cellAspect 2 is 5 rows either way")
    }

    @Test("An unsupported terminal draws glyphs, as it always has")
    func unsupportedTerminalDrawsGlyphs() throws {
        let (image, path) = try load(width: 40, height: 20)
        let drawn = rendered(image, path: path, width: 20, height: 20)
        #expect(placeholderCells(in: drawn.buffer) == 0)
        #expect(drawn.store.takePending().isEmpty, "and nothing was sent to the terminal")
    }

    /// The glyph renderer is a look, not only a fallback. An app that chose a
    /// ramp must keep it on exactly the terminals that could have drawn a
    /// photograph.
    @Test("An app can ask for glyphs on a terminal that has pictures")
    func appPreferenceWins() throws {
        let (image, path) = try load(width: 40, height: 20)
        let drawn = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 20, height: 20) { $0.terminalGraphics = false }
        }
        #expect(placeholderCells(in: drawn.buffer) == 0)
        #expect(drawn.store.takePending().isEmpty)
    }

    /// Transmitting is a side effect, and a measure pass may be sizing a
    /// branch that is never drawn — a `ViewThatFits` candidate, a Card sizing
    /// its container. It must put nothing in the terminal.
    @Test("A measure pass transmits nothing")
    func measurePassIsSilent() throws {
        let (image, path) = try load(width: 40, height: 20)
        let drawn = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 20, height: 20, measuring: true)
        }
        #expect(drawn.store.takePending().isEmpty)
        #expect(drawn.store.imageCount == 0)
        #expect(placeholderCells(in: drawn.buffer) == 0, "it measured the glyphs instead")
    }

    /// An image WITH transparency keeps its alpha, because the terminal
    /// composites it over the cells' background — which is the only way a
    /// picture with a transparent corner can sit on a themed page.
    @Test("A transparent image is sent with its alpha channel")
    func transparentImageKeepsItsAlpha() throws {
        let (opaque, path) = try load(width: 20, height: 20)
        var pixels = opaque.pixels
        pixels[0] = RGBA(r: 0, g: 0, b: 0, a: 0)
        let translucent = RGBAImage(width: opaque.width, height: opaque.height, pixels: pixels)
        let drawn = KittyGraphics.withSupport(true) {
            rendered(translucent, path: path, width: 10, height: 10)
        }
        #expect(drawn.store.takePending().contains("a=t,q=2,f=32"))
    }

    /// Zoom is what makes the pathological case reachable: the cell box grows
    /// with it, and the pixels grow with its square. Upscaling past the
    /// source's own resolution buys nothing — the terminal fits the image to
    /// the placement rectangle — and costs everything.
    @Test("An image is never transmitted larger than it is")
    func transmissionIsClampedToTheSource() throws {
        let (image, path) = try load(width: 40, height: 40)
        let drawn = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 60, height: 60)
        }
        let pending = drawn.store.takePending()
        // The cell box would ask for 60 x 16 = 960 pixels across; the picture
        // has 40. It is sent at its own size, and the placement — which is
        // what decides how big it LOOKS — is unaffected.
        #expect(pending.contains("s=40,v=40"), "sent at the source's own resolution")
        #expect(pending.contains("a=p,U=1,q=2"), "and still placed at the full cell box")
    }

    /// The id has to survive into the cells, or the terminal has an image and
    /// no idea which cells want it. It rides in the foreground colour.
    @Test("Every row names the image in its foreground")
    func rowsCarryTheImageID() throws {
        let (image, path) = try load(width: 20, height: 20)
        let drawn = KittyGraphics.withSupport(true) {
            rendered(image, path: path, width: 10, height: 10)
        }
        let pending = drawn.store.takePending()
        // The id the store allocated, read back out of the transmit.
        #expect(pending.contains("i=1"))
        for line in drawn.buffer.lines {
            #expect(line.hasPrefix("\u{1B}[38;2;0;0;1m"), "id 1 as a direct-colour triple")
            #expect(line.hasSuffix("\u{1B}[39m"))
        }
    }
}

/// The one place a picture drawn as cells can be destroyed by something that
/// is only trying to change a colour.
@MainActor
@Suite("Image rows inside a fade")
struct ImageOpacityTests {

    private static func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    /// `.opacity` rewrites the foreground of every cell it covers toward the
    /// surface behind it. An image row's foreground is not a colour — it is
    /// the image's id — so blending it names an image the terminal does not
    /// have, and the picture does not dim, it disappears.
    @Test("A faded image row keeps its id")
    func fadeLeavesTheImageAlone() {
        let rows = KittyGraphics.placeholderRows(id: 0x01_0203, columns: 6, rows: 2)
        var buffer = FrameBuffer(lines: rows, width: 6)
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 6, height: 2, opacity: 0.4)
        ]
        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(lines: ["......", "......"], width: 6),
            surface: .black, palette: Self.palette())
        #expect(resolved.lines == rows, "the rows came through byte for byte")
        for line in resolved.lines {
            #expect(line.contains("38;2;1;2;3"), "id 0x010203, unblended")
        }
    }

    /// …and the guard is about IMAGE rows specifically, not a fade that has
    /// stopped working. Ordinary text in the same shape still fades.
    @Test("Ordinary rows in the same fade still blend")
    func fadeStillAppliesToText() {
        var buffer = FrameBuffer(
            lines: [ANSIRenderer.colorize("abcdef", foreground: .white)], width: 6)
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 6, height: 1, opacity: 0.4)
        ]
        let resolved = buffer.resolvingOpacity(
            over: FrameBuffer(lines: ["......"], width: 6),
            surface: .black, palette: Self.palette())
        #expect(resolved.lines != buffer.lines, "text fades")
    }
}

/// Which settings reach a picture the TERMINAL draws.
///
/// The colour half of the renderer applies to real pixels as much as to a
/// field of glyphs — more so, since there is no character in the way. The
/// glyph half does not apply at all. Getting the split wrong is invisible in
/// one direction and unmissable in the other: a setting missing from the
/// signature means turning that knob changes nothing on screen, because the
/// store believes it already sent this picture.
@MainActor
@Suite("Image settings that reach real pixels")
struct ImageGraphicsSettingsTests {

    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// Renders twice into ONE store, with `first` then `second` applied, and
    /// reports whether the second render re-transmitted.
    private func retransmits(
        _ first: @escaping (inout EnvironmentValues) -> Void,
        _ second: @escaping (inout EnvironmentValues) -> Void
    ) throws -> Bool {
        let fixture = try BitmapFixture(width: 40, height: 20)
        let image = try PlatformImageLoader().loadImage(from: fixture.path)
        let tui = Self.snapshotContext()

        func draw(_ configure: (inout EnvironmentValues) -> Void) {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.imageCellAspect = 2.0
            environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
            configure(&environment)
            let context = RenderContext(
                availableWidth: 20, availableHeight: 20, environment: environment,
                tuiContext: tui, identity: ViewIdentity(path: "Root"))
            let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
                default: .loading)
            phase.value = .success(image)
            tui.stateStorage.beginRenderPass()
            _ = renderToBuffer(_ImageCore(source: .file(fixture.path)), context: context)
            tui.stateStorage.endRenderPass()
        }

        return KittyGraphics.withSupport(true) {
            draw(first)
            _ = tui.terminalImageStore.takePending()
            draw(second)
            return tui.terminalImageStore.takePending().contains("a=t,")
        }
    }

    @Test("A colour setting changes the picture, so it is sent again")
    func colourSettingsRetransmit() throws {
        #expect(try retransmits({ _ in }, { $0.imageColorMode = .grayscale }), "colour mode")
        #expect(try retransmits({ _ in }, { $0.imageEdgeContrast = 0.8 }), "edge contrast")
        #expect(try retransmits({ _ in }, { $0.imageToneCurve = .inverted }), "tone curve")
        #expect(
            try retransmits(
                { $0.imageColorMode = .ansi16 },
                {
                    $0.imageColorMode = .ansi16
                    $0.imageDithering = .floydSteinberg
                }), "dithering")
    }

    /// …and the other half must NOT, or every one of these would re-resample
    /// and re-send megabytes to change a character nobody is drawing.
    @Test("A glyph setting changes nothing, so nothing is sent")
    func glyphSettingsDoNotRetransmit() throws {
        #expect(try !retransmits({ _ in }, { $0.imageCharacterSet = .blocks(.braille) }), "charset")
        #expect(try !retransmits({ _ in }, { $0.imageShapeAware = true }), "shape matching")
        #expect(try !retransmits({ _ in }, { $0.imageSupersampling = 4 }), "supersampling")
        #expect(try !retransmits({ _ in }, { $0.imageEdgeThreshold = 0.5 }), "edge tracing")
    }

    /// Nothing changing sends nothing — the control against which both of the
    /// above are read.
    @Test("An unchanged render sends nothing")
    func unchangedSendsNothing() throws {
        #expect(try !retransmits({ _ in }, { _ in }))
    }

    /// A theme reaches a picture's pixels only through mono's two colours, so a
    /// theme change re-sends a mono picture and nothing else.
    ///
    /// The signature carried the palette's ink and paper whatever the mode, while
    /// `recoloured` paints them only for `.mono`: switching theme re-sent every
    /// true-colour photograph on screen, megabytes each, to draw exactly the
    /// pixels the terminal already held.
    @Test("A theme change re-sends a mono picture and no other")
    func themeChangeRetransmitsOnlyMono() throws {
        #expect(
            try retransmits(
                {
                    $0.imageColorMode = .mono
                    $0.palette = SystemPalette(.green)
                },
                {
                    $0.imageColorMode = .mono
                    $0.palette = SystemPalette(.amber)
                }), "mono")
        #expect(
            try !retransmits(
                { $0.palette = SystemPalette(.green) },
                { $0.palette = SystemPalette(.amber) }), "true colour")
    }
}
