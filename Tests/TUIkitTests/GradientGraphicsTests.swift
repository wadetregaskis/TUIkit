//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientGraphicsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - The rasteriser

@Suite("Gradient raster")
struct GradientRasterTests {
    private let cell = TerminalCellPixels(width: 16, height: 34)

    @Test("The picture keeps the box's exact proportions at the largest reduction that leaves eight pixels a cell")
    func resolutionKeepsTheAspect() throws {
        let size = try #require(GradientRaster.resolution(columns: 40, rows: 1, cellPixels: cell))
        #expect(size.factor == 2, "34 shares only the 2 with a multiple of 16")
        #expect(size.width == 320 && size.height == 17)
        #expect(size.width * 34 == size.height * 640, "the aspect is the box's, exactly")
        // A box the gcd would flatten to one pixel keeps its ramp.
        let tall = try #require(GradientRaster.resolution(columns: 17, rows: 8, cellPixels: cell))
        #expect(tall.width >= 17 * GradientRaster.minimumPixelsPerCell)
        #expect(tall.height >= 8 * GradientRaster.minimumPixelsPerCell)
        #expect(tall.width * (8 * 34) == tall.height * (17 * 16))
        #expect(GradientRaster.resolution(columns: 0, rows: 1, cellPixels: cell) == nil)
    }

    private func raster(_ paint: Paint, columns: Int = 10, rows: Int = 1) -> GradientRaster.Picture? {
        GradientRaster.picture(
            paint: paint, frame: GradientFrame(width: columns, height: rows),
            columns: columns, rows: rows, cellPixels: cell)
    }

    @Test("A horizontal ramp runs red to blue across identical rows")
    func horizontalRampIsRowsOfOneRow() throws {
        let paint = Paint.gradient(
            GradientPaint(
                Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)]),
                .linear(from: .leading, to: .trailing)))
        let picture = try #require(raster(paint))
        #expect(picture.width == 80 && picture.height == 17)
        let stride = picture.width * 3
        let first = Array(picture.bytes[0..<3])
        let last = Array(picture.bytes[(stride - 3)..<stride])
        #expect(first[0] > 200 && first[2] < 60, "starts red: \(first)")
        #expect(last[2] > 200 && last[0] < 60, "ends blue: \(last)")
        for row in 1..<picture.height {
            #expect(Array(picture.bytes[(row * stride)..<((row + 1) * stride)]) == Array(picture.bytes[0..<stride]))
        }
    }

    @Test("A vertical ramp varies down the rows and not along them")
    func verticalRampVariesByRow() throws {
        let paint = Paint.gradient(
            GradientPaint(
                Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)]),
                .linear(from: .top, to: .bottom)))
        let picture = try #require(raster(paint, columns: 4, rows: 4))
        let stride = picture.width * 3
        #expect(Array(picture.bytes[0..<3]) == Array(picture.bytes[(stride - 3)..<stride]), "one colour along a row")
        let top = picture.bytes[0]
        let bottom = picture.bytes[(picture.height - 1) * stride]
        #expect(top > 200 && bottom < 60, "red at the top, blue at the bottom")
    }

    @Test("A flat colour, or a one-stop ramp, is not a picture")
    func flatPaintIsCells() {
        #expect(raster(.color(.red)) == nil)
        #expect(
            raster(.gradient(GradientPaint(Gradient(colors: [.red]), .linear(from: .leading, to: .trailing))))
                == nil)
    }
}

// MARK: - The track raster

@Suite("Track raster")
struct TrackRasterTests {
    private let cell = TerminalCellPixels(width: 16, height: 34)

    @Test("Only a solid block on a solid background is a colour field")
    func colourFieldRule() {
        #expect(TrackConfiguration.block.isColourField)
        #expect(TrackConfiguration.blockFine.isColourField)
        #expect(!TrackConfiguration.shade.isColourField, "the shade IS the look")
        #expect(!TrackConfiguration.braille.isColourField)
        #expect(!TrackConfiguration.bar.isColourField)
        #expect(!TrackConfiguration.shadeRamp(gradient: nil).isColourField, "a dotted unfill is a texture")
    }

    @Test("The boundary lands on a pixel, and the picture's width never follows the value")
    func boundaryIsAPixel() throws {
        var widths: Set<Int> = []
        var lits: Set<Int> = []
        for step in 0...20 {
            let picture = try #require(
                TrackRaster.picture(
                    fraction: Double(step) / 20, width: 10, config: .block,
                    fillColor: .rgb(0, 255, 0), backgroundColor: .rgb(40, 40, 40),
                    fillScaling: .track, backgroundScaling: .track, cellPixels: cell))
            widths.insert(picture.width)
            // Count the lit pixels of the first row.
            var lit = 0
            for x in 0..<picture.width where picture.bytes[x * 3 + 1] == 255 { lit += 1 }
            lits.insert(lit)
        }
        #expect(widths == [80])
        #expect(lits.count == 21, "twenty-one values, twenty-one distinct boundaries: \(lits.sorted())")
        #expect(lits.contains(0) && lits.contains(80) && lits.contains(40))
    }

    @Test("The fill ramp spans the bar or the lit part, as the cells' does")
    func fillRampFollowsTheScaling() throws {
        let gradient = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])
        let config = TrackConfiguration(fullGlyph: "█", background: .solid, fillGradient: gradient)
        func lastLit(_ scaling: TrackGradientScaling) throws -> [UInt8] {
            let picture = try #require(
                TrackRaster.picture(
                    fraction: 0.5, width: 10, config: config,
                    fillColor: .white, backgroundColor: .black,
                    fillScaling: scaling, backgroundScaling: scaling, cellPixels: cell))
            let x = picture.width / 2 - 1
            return Array(picture.bytes[(x * 3)..<(x * 3 + 3)])
        }
        let acrossTrack = try lastLit(.track)
        let acrossFill = try lastLit(.region)
        #expect(acrossFill[2] > 200, "the fill's last pixel is the ramp's end")
        #expect(acrossTrack[0] > 100 && acrossTrack[2] > 100, "…and the ramp's middle when the bar is the scale")
    }
}

// MARK: - Through the views

@MainActor
@Suite("Gradients drawn as pictures")
struct GradientPictureTests {
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    private func rendered<V: View>(
        _ view: V, width: Int = 20, height: Int = 3, measuring: Bool = false,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> (buffer: FrameBuffer, store: TerminalImageStore) {
        let tui = Self.snapshotContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellPixels = TerminalCellPixels(width: 16, height: 34)
        configure(&environment)
        var context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        context.isMeasuring = measuring
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        let buffer = renderToBuffer(view, context: context)
        return (buffer, tui.terminalImageStore)
    }

    private func placeholders(_ buffer: FrameBuffer) -> Int {
        buffer.lines.reduce(0) { $0 + $1.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count }
    }

    private var ramp: LinearGradient {
        LinearGradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)], startPoint: .leading, endPoint: .trailing)
    }

    @Test("A gradient used as a view is a picture where the terminal draws them, and cells elsewhere")
    func gradientViewIsAPicture() {
        let cells = rendered(ramp)
        #expect(placeholders(cells.buffer) == 0)
        #expect(cells.store.imageCount == 0)
        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(ramp) }
        #expect(placeholders(buffer) == 20 * 3, "every cell of the box")
        #expect(store.imageCount == 1)
        let pending = store.takePending()
        #expect(pending.contains("a=t,"), "one transmission")
        #expect(pending.contains("s=160,v=51") || pending.contains("s=320,v=102"), "the box's proportions: \(pending.prefix(80))")
    }

    /// **A translucent ramp is never a picture, whatever the terminal can draw.**
    ///
    /// `GradientRaster.picture` sends `rgbComponents` in an `.rgb` format and
    /// there is no alpha in it, so this path rendered a translucent ramp at full
    /// strength — silently — while the cell path trips the emitter's assertion for
    /// the same gradient. Which of those a developer met depended on their
    /// TERMINAL: quietly wrong on kitty and Ghostty, loudly unsupported on Apple
    /// Terminal. That is the worst way for a gap to be distributed.
    ///
    /// Transmitting real RGBA would not fix it even where the protocol allows it:
    /// the terminal composites against the cells' own background rather than
    /// against what TUIkit knows is behind them, which is the guess the whole
    /// opacity design exists to avoid.
    @Test("A translucent ramp declines the picture path and claims cells instead")
    func translucentRampIsNeverAPicture() {
        var faded = Color.rgb(255, 0, 0)
        faded.alpha = 128
        var clear = Color.rgb(0, 0, 255)
        clear.alpha = 128
        let veil = LinearGradient(
            colors: [faded, clear], startPoint: .leading, endPoint: .trailing)

        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(veil) }
        #expect(placeholders(buffer) == 0, "no picture was transmitted")
        #expect(store.imageCount == 0, "and nothing reached the image store")
        #expect(
            buffer.opacityRegions.count == 1,
            "the alpha travels as a claim instead: \(buffer.opacityRegions)")
        #expect(
            (buffer.opacityRegions.first?.fieldOpacity ?? 0) > 0.49,
            "at the ramp's own alpha: \(buffer.opacityRegions)")
        // The opaque twin still takes the picture path, so this is a translucency
        // gate rather than the graphics support having been switched off.
        let opaque = KittyGraphics.withSupport(true) { rendered(ramp) }
        #expect(placeholders(opaque.buffer) == 20 * 3, "the opaque ramp is still a picture")
    }

    @Test("A ramp behind text stays cells: a placeholder cannot carry a character")
    func rampBehindTextStaysCells() {
        let (buffer, store) = KittyGraphics.withSupport(true) {
            rendered(Text("hello").background(ramp), height: 1)
        }
        #expect(placeholders(buffer) == 0)
        #expect(buffer.lines[0].stripped.contains("hello"))
        #expect(store.imageCount == 0)
    }

    @Test("The switch turns it off, and so does the images switch")
    func switchesAreHonoured() {
        for off in [{ (view: LinearGradient) in AnyView(view.gradientGraphics(false)) },
                    { (view: LinearGradient) in AnyView(view.terminalGraphics(false)) }] {
            let (buffer, store) = KittyGraphics.withSupport(true) { rendered(off(ramp)) }
            #expect(placeholders(buffer) == 0)
            #expect(store.imageCount == 0)
        }
    }

    @Test("A measure pass transmits nothing")
    func measurePassTransmitsNothing() {
        let (_, store) = KittyGraphics.withSupport(true) { rendered(ramp, measuring: true) }
        #expect(store.imageCount == 0)
        #expect(store.takePending().isEmpty)
    }

    @Test("A block progress bar is a picture, and a shaded one keeps its glyphs")
    func progressBarPictures() {
        let block = KittyGraphics.withSupport(true) {
            rendered(ProgressView(value: 0.5).progressViewStyle(.block), height: 1)
        }
        #expect(placeholders(block.buffer) == 20)
        #expect(block.store.imageCount == 1)
        let shade = KittyGraphics.withSupport(true) {
            rendered(ProgressView(value: 0.5).progressViewStyle(.shade), height: 1)
        }
        #expect(placeholders(shade.buffer) == 0)
        #expect(shade.buffer.lines[0].stripped.contains("▓"))
    }

    @Test("A slider's track is a picture between its arrows, and the arrows stay")
    func sliderTrackPicture() {
        var value = 0.5
        let slider = Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...1)
            .trackStyle(.block)
        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(slider, width: 30, height: 1) }
        #expect(placeholders(buffer) > 0)
        #expect(buffer.lines[0].stripped.contains("◀") && buffer.lines[0].stripped.contains("▶"))
        #expect(store.imageCount == 1)
    }

    @Test("The indeterminate gradient sweep is a cycle of pictures, one per frame, named by the cells")
    func indeterminateSweepIsACycle() {
        let bar = ProgressView().indeterminateStyle(.gradient())
        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(bar, height: 1) }
        let run = buffer.animatedCells.first
        #expect(run != nil)
        let frames = run?.frames ?? []
        #expect(frames.count == 72, "2.4 s in frames of 2 ticks")
        #expect(store.imageCount == frames.count, "every frame is its own picture")
        #expect(Set(frames).count == frames.count, "…named by a different id in every frame")
        #expect(frames.allSatisfy { $0.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count == 20 })
        let pending = store.takePending()
        #expect(pending.components(separatedBy: "a=t,").count - 1 == frames.count, "transmitted once each")
    }

    /// The picture cycle and the glyph cycle are two builders of one bar. Each
    /// preset's period, on the `.gradient` motion over a solid fill (the one bar
    /// that has pictures), must step at the same frame duration and hold the same
    /// number of frames on both paths, or a bar would change speed with the
    /// terminal it is drawn on.
    @Test(
        "An indeterminate bar's cycle of pictures steps at its glyph cycle's frame duration, at every preset's period",
        arguments: [IndeterminateStyle.sweep, .barberPole, .pulse, .knightRider, .gradient()])
    func pictureCycleSharesTheGlyphFrame(_ preset: IndeterminateStyle) throws {
        let bar = ProgressView().indeterminateStyle(
            .custom(IndeterminateConfiguration(motion: .gradient, period: preset.configuration.period)))
        let pictures = KittyGraphics.withSupport(true) { rendered(bar, height: 1) }
        let glyphs = rendered(bar, height: 1)
        #expect(placeholders(pictures.buffer) == 20, "the picture path was not taken")
        #expect(placeholders(glyphs.buffer) == 0, "the glyph path drew pictures")
        let pictureRun = try #require(pictures.buffer.animatedCells.first)
        let glyphRun = try #require(glyphs.buffer.animatedCells.first)
        #expect(pictureRun.frameTicks == glyphRun.frameTicks)
        #expect(pictureRun.frames.count == glyphRun.frames.count)
    }

    /// A ramp of red, blue, red, blue repeats halfway across the track, so the bar slid
    /// half a pass on is the same bar. Its cycle is that half: 36 frames of 2 ticks
    /// rather than 72, on both paths, and as pictures 36 of them rather than 72 held by
    /// the terminal.
    ///
    /// Channels of 240, not 255: a sample of a red-to-blue segment is then a whole
    /// number of levels on both paths (240 · k/20 = 12k), so the two halves are the same
    /// bytes. At 255 some samples fall on a tie (255 · 9/10 = 229.5), which the two
    /// halves' floating point breaks differently, (230, 0, 26) against (229, 0, 26):
    /// those frames are not the same, and are rightly not cut.
    @Test("An indeterminate bar whose ramp repeats halfway along holds half its pass, as glyphs and as pictures")
    func repeatingRampHoldsOneRepeat() throws {
        let ramp = Gradient(colors: [.rgb(240, 0, 0), .rgb(0, 0, 240), .rgb(240, 0, 0), .rgb(0, 0, 240)])
        let bar = ProgressView().indeterminateStyle(.gradient(ramp))
        let pictures = KittyGraphics.withSupport(true) { rendered(bar, height: 1) }
        let glyphs = rendered(bar, height: 1)
        #expect(placeholders(pictures.buffer) == 20, "the picture path was not taken")
        #expect(placeholders(glyphs.buffer) == 0, "the glyph path drew pictures")
        let glyphRun = try #require(glyphs.buffer.animatedCells.first)
        let pictureRun = try #require(pictures.buffer.animatedCells.first)
        #expect(glyphRun.frames.count == 36)
        #expect(glyphRun.cycleTicks == 72)
        #expect(pictureRun.frames.count == 36)
        #expect(pictureRun.cycleTicks == 72)
        #expect(pictures.store.imageCount == 36)
    }

    @Test("Two identical bars share one picture")
    func identicalBarsShare() {
        let two = VStack {
            ProgressView(value: 0.5).progressViewStyle(.block)
            ProgressView(value: 0.5).progressViewStyle(.block)
        }
        let (buffer, store) = KittyGraphics.withSupport(true) { rendered(two, height: 2) }
        #expect(placeholders(buffer) == 40)
        #expect(store.imageCount == 1)
        #expect(buffer.lines[0] == buffer.lines[1], "the same cells naming the same id")
    }
}
