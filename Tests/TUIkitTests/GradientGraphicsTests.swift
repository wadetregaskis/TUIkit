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
                    filledColor: .rgb(0, 255, 0), emptyColor: .rgb(40, 40, 40),
                    gradientScaling: .track, cellPixels: cell))
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
        let config = TrackConfiguration(fullGlyph: "█", emptyStyle: .background, fillGradient: gradient)
        func lastLit(_ scaling: TrackGradientScaling) throws -> [UInt8] {
            let picture = try #require(
                TrackRaster.picture(
                    fraction: 0.5, width: 10, config: config,
                    filledColor: .white, emptyColor: .black,
                    gradientScaling: scaling, cellPixels: cell))
            let x = picture.width / 2 - 1
            return Array(picture.bytes[(x * 3)..<(x * 3 + 3)])
        }
        let acrossTrack = try lastLit(.track)
        let acrossFill = try lastLit(.fill)
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
        #expect(frames.count == 72, "2.4 s at 30 fps")
        #expect(store.imageCount == frames.count, "every frame is its own picture")
        #expect(Set(frames).count == frames.count, "…named by a different id in every frame")
        #expect(frames.allSatisfy { $0.unicodeScalars.filter { $0 == .terminalImagePlaceholder }.count == 20 })
        let pending = store.takePending()
        #expect(pending.components(separatedBy: "a=t,").count - 1 == frames.count, "transmitted once each")
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
