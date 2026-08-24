//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LoadedImageGeometryTests.swift
//
//  What an `Image` measures to once it has actually LOADED — the branch of
//  `_ImageCore.measure` that reports the aspect-fitted size, as against the
//  placeholder box it reserves before the pixels arrive.
//
//  These were blocked for a while on having no way to reach that branch. The
//  way in is `_ImageCore` itself: it reads its phase from `StateStorage` under
//  its own identity, so a test that renders it as the root can seat a loaded
//  image there — and `TUIContext(firesEffects: false)` is what stops the view
//  starting a real load over the top, the same switch `ViewRenderer` uses for
//  snapshots.
//
//  The image is decoded by the REAL loader from a REAL file (`BitmapFixture`
//  writes a BMP by hand so none has to be checked in), so everything from the
//  bytes on disk to the measured size is the shipping code. What is NOT
//  exercised here is the `.task` that normally does that loading: it is started
//  on the main actor and publishes back onto it, and a suite of five thousand
//  main-actor tests does not yield the actor often enough for a polling test to
//  finish — the first attempt at this file got exactly one render in twenty
//  seconds. Scheduling is not what these cases are about; geometry is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitImage

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A loaded image measures to its own aspect")
struct LoadedImageGeometryTests {

    /// A context whose effects are off, exactly as `ViewRenderer` builds one
    /// for a snapshot: the view must not start a real load over the phase these
    /// cases seat, and there is no run loop here to observe one anyway.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// Renders `_ImageCore` with `image` already loaded into it, and returns
    /// the buffer.
    private func rendered(
        _ image: RGBAImage, path: String, width: Int, height: Int,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> FrameBuffer {
        let tui = Self.snapshotContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        configure(&environment)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))

        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: .loading)
        phase.value = .success(image)

        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return renderToBuffer(_ImageCore(source: .file(path)), context: context)
    }

    /// A real file, decoded by the real loader.
    private func load(width: Int, height: Int) throws -> (image: RGBAImage, path: String) {
        let fixture = try BitmapFixture(width: width, height: height)
        let image = try PlatformImageLoader().loadImage(from: fixture.path)
        // The path outlives the fixture object below, so read the bytes now.
        return (image, fixture.path)
    }

    /// The whole point of the loaded branch: a wide image in a tall box comes
    /// back the height its own aspect asks for, not the height it was offered.
    ///
    /// 40 × 10 pixels is 4:1, and a terminal cell is twice as tall as it is
    /// wide, so 40 columns of it is 5 rows — not the 20 the box offers.
    @Test("Once loaded, the height follows the image's aspect and not the offer")
    func loadedImageFitsItsAspect() throws {
        let (image, path) = try load(width: 40, height: 10)
        #expect(image.width == 40 && image.height == 10, "the fixture did not decode as written")

        let buffer = rendered(image, path: path, width: 40, height: 20) {
            $0.imageCellAspect = 2.0
        }

        #expect(buffer.height == 5, "40×10 at cellAspect 2 is 5 rows, got \(buffer.height)")
        #expect(buffer.width == 40)
    }

    /// The placeholder branch, so the case above is a comparison rather than an
    /// assertion about one number. Before the pixels arrive the aspect is
    /// unknown, and the view reserves a box bounded by the cell aspect — this
    /// one goes through `Image` and never seats a phase, so it is the real
    /// first frame of a real load.
    @Test("Before it loads, the same image reserves the placeholder box")
    func placeholderBeforeLoad() throws {
        let fixture = try BitmapFixture(width: 40, height: 10)
        let tui = Self.snapshotContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20, environment: environment, tuiContext: tui)

        tui.stateStorage.beginRenderPass()
        let first = renderToBuffer(Image(.file(fixture.path)), context: context)
        tui.stateStorage.endRenderPass()

        #expect(first.height == 20, "the placeholder is bounded by the offer, not by 5")
    }

    /// `.fill` covers the box instead of fitting inside it, so the same image
    /// in the same box is taller.
    @Test("scaledToFill covers the box where scaledToFit fits inside it")
    func fillCoversTheBox() throws {
        let (image, path) = try load(width: 40, height: 10)
        let fit = rendered(image, path: path, width: 40, height: 20) { $0.imageCellAspect = 2.0 }
        let fill = rendered(image, path: path, width: 40, height: 20) {
            $0.imageCellAspect = 2.0
            $0.imageContentMode = .fill
        }
        #expect(fill.height > fit.height, "fill \(fill.height) did not exceed fit \(fit.height)")
    }

    /// The aspect-ratio override replaces the image's own, which is the only
    /// way to say "draw it as if it were square" in a medium whose cells are
    /// not.
    @Test("An aspect-ratio override replaces the image's own")
    func aspectRatioOverrideWins() throws {
        let (image, path) = try load(width: 40, height: 10)
        let buffer = rendered(image, path: path, width: 40, height: 20) {
            $0.imageCellAspect = 2.0
            $0.imageAspectRatio = 1.0  // square, against the file's 4:1
        }
        #expect(buffer.height == 20, "a square image in a 40×20 box fills it: \(buffer.height)")
    }

    /// The cell aspect is the TERMINAL's, not the image's, and it divides the
    /// rows: taller cells mean fewer of them for the same picture. This is the
    /// value the loaded path carries in its render cache key, and getting it
    /// out of that key is what made a resized terminal keep the old shape.
    @Test("A taller cell means fewer rows for the same image")
    func cellAspectDividesTheRows() throws {
        let (image, path) = try load(width: 40, height: 20)
        let square = rendered(image, path: path, width: 40, height: 40) {
            $0.imageCellAspect = 1.0
        }
        let tall = rendered(image, path: path, width: 40, height: 40) { $0.imageCellAspect = 2.0 }

        #expect(square.height == 20, "40×20 at cellAspect 1 is 20 rows, got \(square.height)")
        #expect(tall.height == 10, "…and 10 at cellAspect 2, got \(tall.height)")
    }
}
