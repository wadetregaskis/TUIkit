//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageSourceSwapTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitImage

@testable import TUIkit
@testable import TUIkitCore

/// Changing an `Image`'s source has to change what it draws.
///
/// The glyph cache keyed on the decoded image's pixel DIMENSIONS and every
/// styling knob, but on nothing that said which picture. Pixel dimensions are
/// not an identity — two photographs, two icons, two frames of a sequence are
/// routinely the same size — so a source change that landed on a same-size file
/// re-decoded into an entry that still "matched", and the view drew the picture
/// it used to show for as long as that view identity lived.
///
/// The pixel path never had this: `TerminalImageSignature` carries `source` as
/// its first field. So the same app switching pictures was correct on a
/// Kitty-graphics terminal and stale on every other one, which is the sort of
/// split that gets diagnosed as a terminal quirk.
@MainActor
@Suite("An image redraws when its source changes")
struct ImageSourceSwapTests {

    /// Effects off, exactly as `ViewRenderer` builds one for a snapshot: the
    /// view must not start a real load over the phase these cases seat.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// Renders `_ImageCore` for `path` with `image` already loaded, through the
    /// GIVEN context — so two calls share one `StateStorage`, one identity and
    /// therefore one cache box, which is the whole point.
    private func render(
        _ image: RGBAImage, path: String, in tui: TUIContext, width: Int, height: Int
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))

        // Seat BOTH slots, which is the state a completed load leaves behind:
        // phase 0 holds the decoded image, slot 1 the source it came from.
        //
        // Seating only the phase reproduces nothing. `manageLoadLifecycle`
        // compares the recorded source against this render's and, on a change,
        // resets the phase to `.loading` — so the second render draws the
        // PLACEHOLDER, the two buffers differ, and the test passes whether or
        // not the cache is keyed correctly. It did exactly that first time.
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
            default: .loading)
        phase.value = .success(image)
        let lastSource: StateBox<ImageSource?> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 1),
            default: nil)
        lastSource.value = .file(path)

        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return renderToBuffer(_ImageCore(source: .file(path)), context: context).lines
    }

    private func load(_ fixture: BitmapFixture) throws -> RGBAImage {
        try PlatformImageLoader().loadImage(from: fixture.path)
    }

    @Test("A different picture of the same pixel size is not the cached one")
    func sameSizeDifferentPictureRedraws() throws {
        // Same dimensions, opposite halves: the cache cannot tell them apart by
        // size, and nothing else about the render differs.
        let dark = try BitmapFixture(
            width: 16, height: 8, left: (10, 10, 10), right: (240, 240, 240))
        let light = try BitmapFixture(
            width: 16, height: 8, left: (240, 240, 240), right: (10, 10, 10))
        let darkImage = try load(dark)
        let lightImage = try load(light)
        #expect(
            darkImage.width == lightImage.width && darkImage.height == lightImage.height,
            "the fixtures must be the same size or this proves nothing")

        let tui = Self.snapshotContext()
        let first = render(darkImage, path: dark.path, in: tui, width: 16, height: 8)
        let second = render(lightImage, path: light.path, in: tui, width: 16, height: 8)

        #expect(!first.isEmpty, "the first render drew nothing, so the case is vacuous")
        #expect(first != second, "the swapped image redrew as the previous one")
    }

    /// The other half, and the one that would fail if the fix were "clear the
    /// cache whenever anything changes": an unchanged source must still hit.
    @Test("The same picture rendered twice still serves the cached conversion")
    func sameSourceStillHits() throws {
        let fixture = try BitmapFixture(width: 16, height: 8)
        let image = try load(fixture)
        let tui = Self.snapshotContext()
        let first = render(image, path: fixture.path, in: tui, width: 16, height: 8)
        let second = render(image, path: fixture.path, in: tui, width: 16, height: 8)
        #expect(first == second)
    }
}
