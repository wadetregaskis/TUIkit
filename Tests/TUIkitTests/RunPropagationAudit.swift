//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RunPropagationAudit.swift
//
//  Every container a view can sit in has to carry its animated runs, because a
//  producer that leaves one behind has stopped asking to be re-rendered — that
//  is the whole point of leaving one. A container that drops runs therefore
//  freezes whatever was inside it, silently, and looks like a performance win
//  while doing it.
//
//  So this is a standing audit rather than a one-off: put a run inside each
//  container in turn and require it to come out. `Section` was the one that did
//  not, found exactly this way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Run propagation through containers")
struct RunPropagationAudit {
    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 40
        return (tui, RenderContext(availableWidth: 40, availableHeight: 20,
                                   environment: environment, tuiContext: tui))
    }
    private func blinker() -> some View {
        Text("x").animatedCells([
            AnimatedCellRun(offsetX: 0, offsetY: 0, width: 1,
                            frames: ["a", "b"], clock: .cursor)])
    }
    private func count(_ view: some View) -> Int {
        let (tui, context) = harness()
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer.animatedCells.count
    }

    @Test("Every container a spinner can sit in carries its run")
    func containersCarryRuns() {
        func check(_ what: String, _ found: Int) {
            #expect(found == 1, "\(what) carried \(found) of 1 run")
        }
        check("VStack", count(VStack { blinker() }))
        check("HStack", count(HStack { blinker() }))
        check("ZStack", count(ZStack { blinker() }))
        check("padding", count(blinker().padding()))
        check("border", count(blinker().border()))
        check("background", count(blinker().background(.blue)))
        check("frame", count(blinker().frame(width: 10, height: 3)))
        check("ScrollView", count(ScrollView { blinker() }))
        check("Box", count(Box { blinker() }))
        check("Section", count(Section("s") { blinker() }))
        check("List", count(List { blinker() }))
        check("Form", count(Form { blinker() }))
        check("Group", count(Group { blinker() }))
        check("HStack with a label", count(HStack { blinker(); Text("l") }))
        check("NavigationStack", count(NavigationStack { blinker() }))
        check("overlay", count(Text("under").overlay { blinker() }))
        check("disabled", count(blinker().disabled(true)))
        check("opacity", count(blinker().opacity(0.5)))
    }
}
