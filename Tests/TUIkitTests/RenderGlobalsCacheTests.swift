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
}
