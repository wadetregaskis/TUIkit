//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackdropAnimationTests.swift
//
//  A dimmed backdrop is inert to INPUT, not to time. The page around a sheet
//  is on screen, so it has to keep moving — and the only affordable way for it
//  to move is the run the loop replays. Dropped, the page advanced solely when
//  something else happened to render.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// A page whose top row animates, and whose bottom row animates in glyphs the
/// backdrop flattens away.
///
/// Two runs, deliberately: the first survives the dim (`░`/`▒` are content),
/// the second must not (`█` is chrome the flatten replaces with a space, so
/// every frame becomes the same blank row).
private struct AnimatedPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("░░░░")
                .animatedCells([
                    AnimatedCellRun(
                        offsetX: 0, offsetY: 0, width: 4, frames: ["░░░░", "▒▒▒▒"],
                        frameDuration: 0.1, clock: .cursor)
                ])
            Text("████")
                .animatedCells([
                    AnimatedCellRun(
                        offsetX: 0, offsetY: 0, width: 4, frames: ["█▀██", "██▄█"],
                        frameDuration: 0.1, clock: .cursor)
                ])
            Text("page")
        }
    }
}

@MainActor
@Suite("A dimmed backdrop keeps animating")
struct BackdropAnimationTests {

    private final class BoolBox {
        var v = true
        var binding: Binding<Bool> { Binding(get: { self.v }, set: { self.v = $0 }) }
    }

    /// The whole screen as the run loop assembles it: render, then composite
    /// the overlay layers at the root — which is where the backdrop is dimmed
    /// and where a covered run is punched out.
    private func screen(_ view: some View, width: Int = 40, height: Int = 20) -> FrameBuffer {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.overlayContentHeight = height
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.compositingOverlays(
            maxWidth: width, maxHeight: height, palette: context.environment.palette)
    }

    /// The report: with a dialog up, the dimmed page behind it animated in
    /// jerks. It had no run left to replay, so it advanced only when something
    /// else caused a full render — about 2.5 pictures a second on the
    /// Example's Progress page against the 30 it manages with nothing
    /// presented, each one a whole re-render of page, dim and dialog.
    @Test("A run on the page survives being the backdrop of a sheet")
    func sheetKeepsThePageAnimating() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().modal(isPresented: presented.binding) { Text("DIALOG") })
        #expect(
            composited.animatedCells.contains { $0.offsetY == 0 },
            "the page's top row lost its run behind the sheet")
    }

    /// The same run, flattened by the same rule as the row it sits in. A frame
    /// that reached the terminal in its own colours would show as a bright
    /// notch in a line that is one uniform dim span.
    @Test("The backdrop's frames are dimmed, not the page's own colours")
    func framesAreFlattenedWithTheRows() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().modal(isPresented: presented.binding) { Text("DIALOG") })
        guard let run = composited.animatedCells.first(where: { $0.offsetY == 0 }) else {
            Issue.record("no run on the backdrop's top row")
            return
        }
        let row = composited.lines[0]
        // Compared as the styling each OPENS with rather than against a fixed
        // sequence: the flatten emits one SGR run and `collapsingAdjacentSGR`
        // folds the dim into it, so the answer is `ESC[2;38;…;48;…m` and not a
        // standalone `ESC[2m`. What has to hold is that the frame and the row
        // open the same way.
        let rowStyle = Self.leadingStyle(of: row)
        #expect(rowStyle.contains("2;"), "the backdrop row is not dim: \(rowStyle.debugDescription)")
        for index in run.frames.indices {
            let frame = run.frame(atIndex: index)
            #expect(
                frame.stripped.count == run.frames[0].stripped.count,
                "frame \(index) changed the run's width")
            #expect(
                Self.leadingStyle(of: frame) == rowStyle,
                "frame \(index) opens differently from the row it splices into")
        }
    }

    /// The escape sequences a string opens with, before its first printed cell.
    private static func leadingStyle(of text: String) -> String {
        var style = ""
        var rest = Substring(text)
        while rest.first == "\u{1B}" {
            guard let end = rest.firstIndex(of: "m") else { break }
            style += rest[rest.startIndex...end]
            rest = rest[rest.index(after: end)...]
        }
        return style
    }

    /// A run whose every frame flattens to the same picture is dropped. The
    /// block glyphs are chrome, so an indeterminate `.pulse` bar has nothing
    /// left to show once they are spaces — and a run kept alive there holds
    /// the animation clock open to repaint an unchanging row forever.
    @Test("A run with nothing left to animate is dropped")
    func flattenedRunsAreDropped() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().modal(isPresented: presented.binding) { Text("DIALOG") })
        #expect(
            !composited.animatedCells.contains { $0.offsetY == 1 },
            "an all-ornament run survived the flatten with nothing to show")
    }

    /// The other half: a full-screen cover hides the page completely, so its
    /// runs are work with no picture at the end of it.
    @Test("A full-screen cover drops the page's runs")
    func coverDropsThePagesRuns() {
        let presented = BoolBox()
        let composited = screen(
            AnimatedPage().fullScreenCover(isPresented: presented.binding) { Text("COVER") })
        #expect(composited.animatedCells.isEmpty)
    }
}
