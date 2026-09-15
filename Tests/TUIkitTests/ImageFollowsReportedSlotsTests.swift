//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageFollowsReportedSlotsTests.swift
//
//  An image drawn in the terminal's slots measures each slot as the colour the
//  terminal reported for it, or as xterm's value while it has reported none. The
//  Image view keeps what it drew, keyed on the colour mode, and a palette mode
//  compares equal by its colours whatever they measure as. So the key has to say
//  which colours the terminal had reported, or a report arriving after the first
//  frame never reaches the picture.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitImage

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("An image drawn in the terminal's slots is drawn again when the terminal reports them")
struct ImageFollowsReportedSlotsTests {

    private static func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> TerminalColors.RGB {
        TerminalColors.RGB(red: red, green: green, blue: blue)
    }

    /// Apple Terminal 455.1's "Basic" sixteen, as its OSC 4 replies reported them on
    /// 2026-09-14 (Terminal-compatibility.md), in slot order.
    private static let appleTerminal = TerminalColors(
        foreground: rgb(0, 0, 0), background: rgb(255, 255, 255),
        slots: TerminalColors.Slots([
            rgb(0, 0, 0), rgb(153, 0, 0), rgb(0, 166, 0), rgb(153, 153, 0),
            rgb(0, 0, 179), rgb(179, 0, 179), rgb(0, 166, 179), rgb(191, 191, 191),
            rgb(102, 102, 102), rgb(230, 0, 0), rgb(0, 217, 0), rgb(230, 230, 0),
            rgb(0, 0, 255), rgb(230, 0, 230), rgb(0, 230, 230), rgb(230, 230, 230),
        ]))

    /// Red and bright red. A picture of (220, 0, 0) is nearer xterm's red (205, 0, 0)
    /// and nearer Apple Terminal's bright red (230, 0, 0). Written outside any pin on
    /// purpose: the view resolves the mode, and so measures its entries, as it renders.
    private static let slotMode = ASCIIColorMode.palette(ASCIIPalette([.ansi(.red), .ansi(.brightRed)]))

    /// Effects off, exactly as `ViewRenderer` builds one for a snapshot: the view must
    /// not start a real load over the phase these cases seat.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    private static func redPicture(width: Int, height: Int) throws -> (image: RGBAImage, fixture: BitmapFixture) {
        let fixture = try BitmapFixture(width: width, height: height, left: (220, 0, 0), right: (220, 0, 0))
        return (try PlatformImageLoader().loadImage(from: fixture.path), fixture)
    }

    /// Draws `_ImageCore` as glyphs through `tui`, with the picture already loaded, so two
    /// calls through one context share one cache box (ImageSourceSwapTests' recipe).
    private static func glyphs(_ image: RGBAImage, path: String, in tui: TUIContext) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        environment.imageColorMode = slotMode
        let context = RenderContext(
            availableWidth: 8, availableHeight: 4, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0), default: .loading)
        phase.value = .success(image)
        let lastSource: StateBox<ImageSource?> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 1), default: nil)
        lastSource.value = .file(path)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return KittyGraphics.withSupport(false) {
            ColorDepth.withCurrent(.truecolor) {
                renderToBuffer(_ImageCore(source: .file(path)), context: context).lines
            }
        }
    }

    @Test("A picture drawn as glyphs in the slots is converted again when the report changes")
    func glyphCacheFollowsTheReport() throws {
        let (image, fixture) = try Self.redPicture(width: 8, height: 4)
        let shared = Self.snapshotContext()

        let unreported = TerminalColors.withCurrent(.unknown) { Self.glyphs(image, path: fixture.path, in: shared) }
        let reported = TerminalColors.withCurrent(Self.appleTerminal) {
            Self.glyphs(image, path: fixture.path, in: shared)
        }
        let fresh = TerminalColors.withCurrent(Self.appleTerminal) {
            Self.glyphs(image, path: fixture.path, in: Self.snapshotContext())
        }
        #expect(!unreported.isEmpty, "the first render drew nothing, so the case is vacuous")
        #expect(fresh != unreported, "the report must change the picture, or this proves nothing")
        #expect(reported == fresh, "the view drew the conversion it made before the report")

        let again = TerminalColors.withCurrent(.unknown) { Self.glyphs(image, path: fixture.path, in: shared) }
        #expect(again == unreported, "and back again once the report is gone")
        // The control: the same report twice still serves the cache, byte for byte.
        #expect(TerminalColors.withCurrent(.unknown) { Self.glyphs(image, path: fixture.path, in: shared) } == again)
    }

    @Test("A picture sent as pixels in the slots is sent again when the report changes, and not otherwise")
    func pixelSignatureFollowsTheReport() throws {
        let (image, fixture) = try Self.redPicture(width: 40, height: 20)
        let tui = Self.snapshotContext()

        func draw() {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            environment.imageCellAspect = 2.0
            environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
            environment.imageColorMode = Self.slotMode
            let context = RenderContext(
                availableWidth: 20, availableHeight: 20, environment: environment,
                tuiContext: tui, identity: ViewIdentity(path: "Root"))
            let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0), default: .loading)
            phase.value = .success(image)
            tui.stateStorage.beginRenderPass()
            _ = renderToBuffer(_ImageCore(source: .file(fixture.path)), context: context)
            tui.stateStorage.endRenderPass()
        }

        KittyGraphics.withSupport(true) {
            TerminalColors.withCurrent(.unknown) { draw() }
            #expect(tui.terminalImageStore.takePending().contains("a=t,"), "the first render sends the picture")
            TerminalColors.withCurrent(.unknown) { draw() }
            #expect(!tui.terminalImageStore.takePending().contains("a=t,"), "nothing changed, so nothing is sent")
            TerminalColors.withCurrent(Self.appleTerminal) { draw() }
            #expect(
                tui.terminalImageStore.takePending().contains("a=t,"),
                "the slots measure differently, so the pixels differ and must be sent")
        }
    }
}
