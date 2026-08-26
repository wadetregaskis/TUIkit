//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusSectionDefaultIDTests.swift
//
//  SwiftUI's `focusSection()` names nothing — a section there is just "these
//  focusables form a cohort". TUIkit needs a name for one, so the parameterless
//  spelling derives it from the view's identity path. What that has to buy is
//  distinctness: two siblings written identically must not land in one section,
//  which is exactly what a constant default (or an empty string) would do while
//  still compiling and still passing any single-section test.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("focus section default identifier")
struct FocusSectionDefaultIDTests {
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) {
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

    private func makeView() -> some View {
        HStack {
            Button("left") {}.focusSection()
            Button("right") {}.focusSection()
        }
    }

    @Test("Two unnamed sibling sections are distinct")
    func siblingsDoNotCollide() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        let derived = focusManager.sectionIDs.filter { $0.hasPrefix("section-") }
        #expect(derived.count == 2, "one section per call site, got \(focusManager.sectionIDs)")
        #expect(Set(derived).count == 2, "the two identifiers differ: \(derived)")

        // Each section owns exactly its own button — a collision would file
        // both buttons in one section and leave the other empty.
        let summary = focusManager.debugSectionsSummary()
        for id in derived {
            let entry = summary.split(separator: " | ").first { $0.contains(id) }
            #expect(entry?.contains("button-") == true, "\(id) holds a button: \(summary)")
        }
    }

    @Test("An unnamed section is stable across frames")
    func identifierIsStable() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        let first = focusManager.sectionIDs.filter { $0.hasPrefix("section-") }.sorted()
        for _ in 0..<3 {
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        let later = focusManager.sectionIDs.filter { $0.hasPrefix("section-") }.sorted()
        #expect(first == later, "identifiers persist: \(first) then \(later)")
    }

    @Test("A named section still wins over the derived one")
    func explicitNameIsKept() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = HStack {
            Button("left") {}.focusSection("chosen")
            Button("right") {}.focusSection()
        }
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        #expect(focusManager.sectionIDs.contains("chosen"))
        #expect(focusManager.sectionIDs.filter { $0.hasPrefix("section-") }.count == 1)
    }
}
