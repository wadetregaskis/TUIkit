//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderGlobalsCacheTests.swift
//
//  Three process-wide answers are read by the render and baked into what it
//  draws: the colour depth (how a colour is spelled), whether the terminal
//  takes OSC 8 links, and whether it places Kitty pictures. Each can change
//  while the app runs — a diagnostic override, `ColorDepth.cap` — and a
//  task-local pin changes them for one test. A memo served across the change
//  drew the old answer. These pin that it no longer does.
//
//  So does the terminal's cell geometry, which the render loop reads from the
//  tty every frame and publishes at the root: a font change moves it with
//  nothing a memo keys on moving.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling
@testable import TUIkitView

/// Frames of the real loop's lifecycle over one render cache.
@MainActor
private final class GlobalsLoop {
    let tui = TUIContext()

    /// Draws `view` and returns its lines, styling kept.
    func frame(_ view: some View) -> [String] {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(availableWidth: 30, availableHeight: 4, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines
    }

    /// How many memoized subtrees the next frame of `view` served.
    func served(_ view: some View) -> Int {
        let before = tui.renderCache.rowWork.served
        _ = frame(view)
        return tui.renderCache.rowWork.served - before
    }
}

/// A card compared by title alone, so only a clear can redraw it.
private struct Card<Content: View>: View, @preconcurrency Equatable {
    let title: String
    let content: Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View { content }
}

@MainActor
@Suite("Memos across a change of colour depth, link or picture support")
struct RenderGlobalsCacheTests {
    @Test("A colour spelled at one depth is not served at another")
    func colourDepth() {
        let loop = GlobalsLoop()
        let card = Card(title: "t", content: Text("hue").foregroundStyle(Color.rgb(10, 200, 30))).equatable()
        ColorDepth.withCurrent(.truecolor) {
            _ = loop.frame(card)
            #expect(loop.served(card) >= 1, "precondition: the card is served")
            #expect(loop.frame(card).joined().contains("38;2;"), "precondition: truecolor is spelled 38;2")
            let capped = ColorDepth.withCap(.palette256) { loop.frame(card).joined() }
            #expect(!capped.contains("38;2;"), "served the truecolor spelling under a 256-colour cap: \(capped)")
        }
    }

    /// Links and pictures cannot be served stale today — a `Link` and a placed
    /// picture both declare render side effects, so neither is ever stored —
    /// so what is pinned for them is the clear itself, the margin that keeps a
    /// memo that could hold one some day from inheriting the hole.
    @Test("A change of link or picture support clears the cache", arguments: ["links", "pictures", "compression"])
    func supportChangesClear(_ answer: String) {
        let loop = GlobalsLoop()
        let view = Text("x")
        func pinned(_ on: Bool, _ body: () -> Void) {
            switch answer {
            case "links": TerminalHyperlink.withSupport(on, operation: body)
            case "pictures": KittyGraphics.withSupport(on, operation: body)
            default: KittyGraphics.withSupport(true, compression: on, operation: body)
            }
        }
        pinned(false) {
            _ = loop.frame(view)
            _ = loop.frame(view)
        }
        let before = loop.tui.renderCache.stats.clears
        pinned(false) { _ = loop.frame(view) }
        #expect(loop.tui.renderCache.stats.clears == before, "precondition: an unchanged answer clears nothing")
        pinned(true) { _ = loop.frame(view) }
        #expect(loop.tui.renderCache.stats.clears == before + 1, "the \(answer) answer moved and nothing was cleared")
    }

    /// The terminal's cell geometry is read from `TIOCGWINSZ` and published at
    /// the root every frame, and a font change moves it with no view value and
    /// no state changing — the case the render loop's snapshot is for. A
    /// circle drawn in cells is one only at the aspect it was drawn for.
    ///
    /// Through the real loop, with a terminal that reports its geometry: the
    /// snapshot's fields are necessary and not sufficient. The loop published
    /// the geometry inside `renderContent`, AFTER it had taken the snapshot,
    /// so a snapshot that carried the geometry would still have compared two
    /// defaults.
    @Test("A radial ramp drawn at one cell aspect is not served at another")
    func cellAspect() {
        func drawn(_ aspects: [Double]) -> [String] {
            let harness = RenderLoopHarness()
            let loop = harness.loop(DiscApp())
            for aspect in aspects {
                harness.terminal.reportedCellAspect = aspect
                loop.render()
            }
            return loop.replayable?.contentLines ?? []
        }
        ColorDepth.withCurrent(.truecolor) {
            let fresh = drawn([1])
            #expect(fresh != drawn([2]), "precondition: the ramp must depend on the aspect or this proves nothing")
            #expect(drawn([2, 2, 1]) == fresh, "served the disc drawn for the aspect before")
        }
    }

    /// The loop's rule itself, for both halves of the geometry: the aspect an
    /// ASCII picture and a centred ramp are drawn for, and the cell's pixels a
    /// transmitted picture is resampled to. Compared as `Bool`s so a failure
    /// does not print two whole palettes.
    @Test("The snapshot carries the terminal's cell geometry", arguments: ["aspect", "pixels"])
    func cellGeometryIsInTheSnapshot(_ field: String) {
        var environment = EnvironmentValues()
        let before = EnvironmentSnapshot(from: environment)
        let unchanged = before == EnvironmentSnapshot(from: environment)
        #expect(unchanged, "an unchanged geometry keeps the cache")
        switch field {
        case "aspect": environment.imageCellAspect = 2.125
        default: environment.imageCellPixels = TerminalCellPixels(width: 8, height: 17)
        }
        let moved = before != EnvironmentSnapshot(from: environment)
        #expect(moved, "the \(field) moved and the loop would clear nothing")
    }
}

/// A memoized disc: a radial ramp behind three rows of eight cells.
private struct DiscApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Card(
                title: "disc",
                content: Text(verbatim: "        \n        \n        ").background(
                    RadialGradient(
                        colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)], center: .center, startRadius: 0, endRadius: 4))
            ).equatable()
        }
    }
}
