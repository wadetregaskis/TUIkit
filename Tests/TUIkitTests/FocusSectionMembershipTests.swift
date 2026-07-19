//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusSectionMembershipTests.swift
//
//  Section membership is a property of WHERE a control renders (the
//  environment's activeFocusSectionID, set by .focusSection, modal/alert
//  presentation, and NavigationSplitView's columns), never of which section
//  happens to be ACTIVE that frame. The old fallback — section-less
//  controls landing in the momentarily-active section — made membership
//  and section ORDER drift with focus: focus a split-view divider and the
//  next frame filed the page's Toggle into the divider's section (created
//  FIRST that pass, reordering the ring), collapsing Tab into a two-stop
//  oscillation and making Shift+Tab bounce through the toggle every other
//  press.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("focus section membership")
struct FocusSectionMembershipTests {
    private struct Item: Identifiable {
        let id: Int
        var label: String { "item \(id)" }
    }

    private func makeView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("resizable", isOn: .constant(true))
            NavigationSplitView {
                List("Folders", selection: Binding<Int?>.constant(nil)) {
                    ForEach((0..<3).map(Item.init)) { Text($0.label) }
                }
            } content: {
                List("Inbox", selection: Binding<Int?>.constant(nil)) {
                    ForEach((3..<6).map(Item.init)) { Text($0.label) }
                }
            } detail: {
                Text("detail")
            }
            .navigationSplitViewResizable(true)
        }
    }

    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 70, availableHeight: 14,
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

    @Test("Tab cycles page control, columns, and dividers in layout order")
    func splitViewTabCycle() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        // Toggle (default section) starts focused. Forward: sidebar list,
        // divider 0, content list, divider 1, back to the toggle (the empty
        // detail column is skipped) — then the cycle repeats. Membership
        // must not drift no matter which section was active last frame.
        let expectedForward = [
            "nav-split-sidebar", "nav-split-divider-0", "nav-split-content",
            "nav-split-divider-1", "__default__",
            "nav-split-sidebar", "nav-split-divider-0", "nav-split-content",
        ]
        for (press, expected) in expectedForward.enumerated() {
            focusManager.focusNext()
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(
                focusManager.activeSection?.id == expected,
                "forward press \(press): expected \(expected), got \(focusManager.activeSection?.id ?? "nil")")
            #expect(focusManager.currentFocusedID != nil, "forward press \(press) focuses something")
        }

        // Backward from the current position mirrors the ring exactly.
        let expectedBackward = [
            "nav-split-divider-0", "nav-split-sidebar", "__default__",
            "nav-split-divider-1", "nav-split-content", "nav-split-divider-0",
        ]
        for (press, expected) in expectedBackward.enumerated() {
            focusManager.focusPrevious()
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(
                focusManager.activeSection?.id == expected,
                "backward press \(press): expected \(expected), got \(focusManager.activeSection?.id ?? "nil")")
        }
    }

    @Test("A section-less control never migrates into the active section")
    func sectionlessControlStaysInDefault() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)

        // Put focus deep in the split view, then re-render several frames:
        // the toggle must still be registered in __default__ (not in the
        // active divider/column section), and __default__ must still exist.
        focusManager.focusNext()
        focusManager.focusNext()  // divider 0's section is now active
        for _ in 0..<3 {
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
        }
        let summary = focusManager.debugSectionsSummary()
        let defaultSection = summary.split(separator: " | ").first { $0.contains("__default__") }
        #expect(defaultSection != nil, "the default section survives: \(summary.prefix(200))")
        #expect(
            defaultSection?.contains("toggle-") == true,
            "the toggle stays filed in __default__: \(defaultSection ?? "nil")")
        let dividerSection = summary.split(separator: " | ").first { $0.contains("divider-0") }
        #expect(
            dividerSection?.contains("toggle-") != true,
            "the toggle never migrates into the active section: \(dividerSection ?? "nil")")
    }
}
