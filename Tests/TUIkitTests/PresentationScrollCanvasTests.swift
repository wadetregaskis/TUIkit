//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationScrollCanvasTests.swift
//
//  A presentation is attached inside the content that presents it and drawn
//  over the screen. It used to inherit the canvas a scroll view published for
//  that content — the viewport, the whole-width mark, the visible window — so a
//  sheet presented from a horizontal strip laid itself out as if it were the
//  strip. These pin that it starts clean.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

@MainActor
private final class CanvasLog {
    var isUp = false
    /// What each render of the presented content saw: the whole-width mark, and
    /// whether a viewport was published.
    var seen: [(wholeWidth: Bool, viewport: Bool)] = []
}

/// Records the scroll canvas it is drawn in.
private struct CanvasSpy: View {
    let log: CanvasLog
    @Environment(\.asksWholeContentWidth) private var wholeWidth
    @Environment(\.scrollViewportSize) private var viewport

    var body: some View {
        log.seen.append((wholeWidth, viewport != nil))
        return Text("presented")
    }
}

/// A horizontal strip that presents from inside its content.
private struct StripApp: App {
    let log: CanvasLog
    let popover: Bool

    init() { self.init(log: CanvasLog(), popover: false) }
    init(log: CanvasLog, popover: Bool) {
        self.log = log
        self.popover = popover
    }

    var body: some Scene {
        WindowGroup {
            ScrollView(.horizontal) {
                strip
            }
        }
    }

    @ViewBuilder private var strip: some View {
        let isUp = Binding(get: { log.isUp }, set: { log.isUp = $0 })
        let content = Text(String(repeating: "x", count: 80))
        if popover {
            content.popover(isPresented: isUp) { CanvasSpy(log: log) }
        } else {
            content.sheet(isPresented: isUp) { CanvasSpy(log: log) }
        }
    }
}

@MainActor
@Suite("Presentations start outside the scroll canvas")
struct PresentationScrollCanvasTests {
    @Test("A sheet or popover presented from a horizontal scroll view sees no scroll canvas", arguments: [false, true])
    func presentedContentLeavesTheCanvas(popover: Bool) {
        let log = CanvasLog()
        let app = HeadlessApp(StripApp(log: log, popover: popover), width: 40, height: 16)
        app.frame(atNanos: 0)
        log.isUp = true
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        #expect(!log.seen.isEmpty, "precondition: the presented content was drawn")
        #expect(
            log.seen.allSatisfy { !$0.wholeWidth && !$0.viewport },
            "the presented content inherited the strip's canvas: \(log.seen)")
    }
}
