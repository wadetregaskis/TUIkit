//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewColumnArrowTests.swift
//
//  Left and Right between a split view's columns.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Reported by the owner: in a split view, Left and Right should move focus between the
/// columns. A column's content that uses those keys itself still gets them first; one
/// that declines them — a flat List, a Button — used to let them fall to the focus
/// manager's generic fallback, which stepped up and down INSIDE the column, the same
/// thing Up and Down already do.
@MainActor
@Suite("Left and Right move between a split view's columns")
struct SplitViewColumnArrowTests {

    /// A two-column split with a control in each column, rendered once.
    private func splitView() -> FocusManager {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        let view = NavigationSplitView {
            Button("sidebar") {}
        } detail: {
            Button("detail") {}
        }
        let context = RenderContext(
            availableWidth: 80, availableHeight: 24, environment: environment,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        return focusManager
    }

    /// A column's section id, which ends in the split's identity path.
    private func section(_ column: String, in focusManager: FocusManager) -> String {
        focusManager.section(withPrefix: "nav-split-\(column)")?.id ?? "missing \(column)"
    }

    @Test("Right moves to the next column, and Left back")
    func rightAndLeftCrossColumns() {
        let focusManager = splitView()
        focusManager.activateSection(id: section("sidebar", in: focusManager))
        #expect(focusManager.isActiveSection(section("sidebar", in: focusManager)), "sanity")

        let movedRight = focusManager.dispatchKeyEvent(KeyEvent(key: .right))
        #expect(movedRight)
        #expect(focusManager.isActiveSection(section("detail", in: focusManager)), "Right reaches the detail column")

        let movedLeft = focusManager.dispatchKeyEvent(KeyEvent(key: .left))
        #expect(movedLeft)
        #expect(focusManager.isActiveSection(section("sidebar", in: focusManager)), "Left comes back")
    }

    /// At an end there is no column to go to, and the key is left for whatever
    /// encloses the split — a nested split's parent, an app-level handler.
    @Test("Past the last column the key is not handled")
    func endColumnDeclines() {
        let focusManager = splitView()
        focusManager.activateSection(id: section("detail", in: focusManager))
        let handled = focusManager.dispatchKeyEvent(KeyEvent(key: .right))
        #expect(!handled)
        #expect(focusManager.isActiveSection(section("detail", in: focusManager)))
    }
}
