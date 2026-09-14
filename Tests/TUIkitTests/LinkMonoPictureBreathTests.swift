//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkMonoPictureBreathTests.swift
//
//  A mono picture in a focused link's label, on a terminal that draws pictures.
//
//  A link breathes its label by rendering it once per frame of the breath, each
//  time in that frame's colour (`BreathingLabel.draw(ends:cycle:indicating:
//  isMeasuring:render:)`), and a mono picture is inked in the foreground style it
//  is rendered under. Pixels carry that ink baked in, so each frame's render was a
//  different picture, and the store sent every one of them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A mono picture in a breathing link")
struct LinkMonoPictureBreathTests {

    /// `_ImageCore` with its load already finished, at the identity it renders at.
    ///
    /// Inside a link the image sits several identities down, so its phase cannot be
    /// seeded from outside the way the image suites seed it at the root. This seeds
    /// it where the core reads it.
    private struct LoadedImage: View, Renderable {
        let image: RGBAImage
        let path: String

        var body: Never { fatalError("LoadedImage renders via Renderable") }

        func renderToBuffer(context: RenderContext) -> FrameBuffer {
            let phase: StateBox<ImageLoadingPhase> = context.stateStorage!.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0),
                default: .loading)
            if case .loading = phase.value { phase.value = .success(image) }
            return TUIkit.renderToBuffer(_ImageCore(source: .file(path)), context: context)
        }
    }

    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// One render pass of `view`: what it drew, and how many pictures it sent.
    private func pass(
        _ view: some View, tui: TUIContext, focus: FocusManager,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) -> (buffer: FrameBuffer, transmissions: Int) {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
        configure(&environment)
        let context = RenderContext(
            availableWidth: 12, availableHeight: 6, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        focus.endRenderPass()
        let owed = tui.terminalImageStore.takePending()
        return (buffer, owed.components(separatedBy: "a=t,").count - 1)
    }

    private func loaded() throws -> (image: RGBAImage, fixture: BitmapFixture) {
        let fixture = try BitmapFixture(width: 40, height: 20)
        return (try PlatformImageLoader().loadImage(from: fixture.path), fixture)
    }

    private func link(_ label: some View) -> some View {
        Link(destination: URL(string: "https://swift.org")!) { label }
            .imageColorMode(.mono)
    }

    /// Both halves of the reported cost. Every breath frame sent the picture again on
    /// a pass that re-rendered the label, and the next such pass sent them all again,
    /// because the terminal was left holding the last frame's ink and the pass starts
    /// from the frame the clock is on.
    @Test("A focused link sends its mono picture once, and not again while it breathes")
    func breathSendsThePictureOnce() throws {
        let (image, fixture) = try loaded()
        let tui = Self.snapshotContext()
        let focus = FocusManager()
        let view = link(LoadedImage(image: image, path: fixture.path))

        try KittyGraphics.withSupport(true) {
            let first = pass(view, tui: tui, focus: focus)
            try #require(!first.buffer.animatedCells.isEmpty, "the link holds the focus and breathes")
            #expect(first.transmissions == 1, "first pass")
            let second = pass(view, tui: tui, focus: focus)
            #expect(second.transmissions == 0, "second pass")
        }
    }

    /// The colour a breathing link's picture holds is its label's resting colour, the
    /// bright end of the breath. A still focus draws that colour and so does a link
    /// without the focus, so the breath starting or stopping sends nothing.
    @Test("A breathing link's mono picture is the one a still focus draws")
    func breathHoldsTheRestingInk() throws {
        let (image, fixture) = try loaded()
        let tui = Self.snapshotContext()
        let focus = FocusManager()
        let view = link(LoadedImage(image: image, path: fixture.path))

        try KittyGraphics.withSupport(true) {
            let still = pass(view, tui: tui, focus: focus) {
                $0.selectionIndicatorStyle = .none
            }
            try #require(still.buffer.animatedCells.isEmpty, "a still focus has no breath")
            #expect(still.transmissions == 1, "still focus")
            let breathing = pass(view, tui: tui, focus: focus)
            try #require(!breathing.buffer.animatedCells.isEmpty, "the default focus breathes")
            #expect(breathing.transmissions == 0, "breathing focus")
        }
    }

    /// The hold is for the breath's own ink and nothing below it: a picture that
    /// states its ink inside the label keeps that ink, and is the same picture as one
    /// drawn in that ink anywhere else.
    @Test("A picture that states its own ink keeps it inside a breathing link")
    func statedInkIsNotHeld() throws {
        let (image, fixture) = try loaded()
        let tui = Self.snapshotContext()
        let focus = FocusManager()
        let red = Color.rgb(230, 40, 40)
        let picture = LoadedImage(image: image, path: fixture.path).foregroundStyle(red)

        try KittyGraphics.withSupport(true) {
            let inLink = pass(link(picture), tui: tui, focus: focus)
            try #require(!inLink.buffer.animatedCells.isEmpty, "the link holds the focus and breathes")
            #expect(inLink.transmissions == 1, "in the link")
            // A second token asking for an equal signature in an equal box shares the
            // image rather than sending one, so zero here means the link's picture
            // was inked red.
            let alone = pass(picture.imageColorMode(.mono), tui: tui, focus: FocusManager())
            #expect(alone.transmissions == 0, "the same picture outside the link")
        }
    }

    /// Glyphs are not held: the breath's runs replay the label's rows, and on the
    /// glyph path those rows carry the ink, so each frame is its own colour.
    @Test("Without pictures, a breathing link still breathes its mono image's glyphs")
    func glyphsStillBreathe() throws {
        let (image, fixture) = try loaded()
        let tui = Self.snapshotContext()
        let focus = FocusManager()
        let view = link(LoadedImage(image: image, path: fixture.path))

        try KittyGraphics.withSupport(false) {
            let drawn = pass(view, tui: tui, focus: focus)
            #expect(drawn.transmissions == 0)
            #expect(
                !drawn.buffer.lines.contains { $0.unicodeScalars.contains(.terminalImagePlaceholder) },
                "drawn as glyphs")
            let runs = drawn.buffer.animatedCells
            try #require(!runs.isEmpty, "the link holds the focus and breathes")
            #expect(runs.allSatisfy { Set($0.frames).count > 1 }, "every row's frames differ in ink")
        }
    }
}
