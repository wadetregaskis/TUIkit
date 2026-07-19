//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusSectionCycleHygieneTests.swift
//
//  A Tab cycle over explicit .focusSection groups plus a page-level
//  ScrollView must visit the ScrollView exactly ONCE per lap — before the
//  membership fix, the section-less ScrollView migrated into whichever
//  section was active each frame, so a cycle met it once per section.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("focus section cycle hygiene")
struct FocusSectionCycleHygieneTests {

    @Test("An overflowing page ScrollView appears once per Tab lap")
    func scrollViewOncePerLap() {
        // The Focus & Input page shape: two explicit sections of buttons
        // inside a page ScrollView whose content overflows (so the SV is a
        // legitimate Tab stop — once).
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Button("A · One") {}.focusID("focus-a-one")
                    Button("A · Two") {}.focusID("focus-a-two")
                }
                .focusSection("focus-section-a")
                VStack(alignment: .leading, spacing: 0) {
                    Button("B · One") {}.focusID("focus-b-one")
                    Button("B · Two") {}.focusID("focus-b-two")
                }
                .focusSection("focus-section-b")
                ForEach(0..<30, id: \.self) { i in Text("filler \(i)") }
            }
        }
        .frame(height: 8)

        func frame() {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 8,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }
        frame()
        frame()

        // Walk two full laps; count how often each control is visited.
        var visits: [String: Int] = [:]
        var lap: [String] = []
        for _ in 0..<10 {
            focusManager.focusNext()
            frame()
            let id = focusManager.currentFocusedID ?? "nil"
            let name = id.hasPrefix("focus-") ? id : (id.hasPrefix("scrollview-") ? "SV" : id)
            visits[name, default: 0] += 1
            lap.append(name)
        }
        // Five stops per lap: a-one, a-two, b-one, b-two, SV.
        #expect(visits["SV"] == 2, "the ScrollView appears exactly once per lap: \(lap)")
        for id in ["focus-a-one", "focus-a-two", "focus-b-one", "focus-b-two"] {
            #expect(visits[id] == 2, "\(id) appears exactly once per lap: \(lap)")
        }
    }

    @Test("A non-overflowing ScrollView is not a Tab stop at all")
    func nonOverflowingScrollViewSkipsRing() {
        // Container focus exists to scroll; with nothing to scroll it is
        // pure friction between the real controls. (Explicitly requested to
        // stay this way.)
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("one") {}.focusID("one")
                Button("two") {}.focusID("two")
            }
        }
        .frame(height: 10)  // taller than the content: no overflow

        func frame() {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }
        frame()
        frame()

        var lap: [String] = []
        for _ in 0..<4 {
            focusManager.focusNext()
            frame()
            lap.append(focusManager.currentFocusedID ?? "nil")
        }
        #expect(
            !lap.contains { $0.hasPrefix("scrollview-") },
            "a non-overflowing ScrollView never takes focus: \(lap)")
        #expect(lap == ["two", "one", "two", "one"], "the buttons alternate cleanly: \(lap)")
    }
}
