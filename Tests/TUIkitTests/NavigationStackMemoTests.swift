//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationStackMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A pushed `NavigationStack` under a value memo.
///
/// Two things the stack does on a pushed frame belong to that frame alone: it
/// registers the depth's focus section, and it files the Escape handler that
/// pops. The section ring and the key dispatcher are emptied before every pass,
/// so a memo that served the stack's buffer would leave a frame with no section
/// and an Escape that does nothing.
///
/// The context has no mouse dispatcher on purpose. With one, the bar's Back
/// button adds a hit region and the memo refuses the buffer for that reason
/// alone. Keyboard-only, the only thing keeping the stack out of the cache is
/// what the subtree declares.
@MainActor
@Suite("NavigationStack through the render memos")
struct NavigationStackMemoTests {

    private struct Step: Hashable {
        let number: Int
    }

    /// An `.equatable()` boundary around content built by a closure. Equal by
    /// label alone, so every frame's value compares equal and the memo always
    /// wants to serve: the only thing that can stop it is a declaration.
    private struct Memoized<Content: View>: View, @MainActor Equatable {
        let label: String
        let build: @MainActor () -> Content

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.label == rhs.label }

        var body: some View {
            build()
        }
    }

    @Test("A memoized pushed stack keeps its section and still pops on Escape on the third frame")
    func escapePopsOnALaterFrame() {
        var path = NavigationPath()
        path.append(Step(number: 1))
        let binding = Binding(get: { path }, set: { path = $0 })
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let statusBar = StatusBarState()
        statusBar.focusManager = focusManager

        func frame() -> RenderContext {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            environment.mouseEventDispatcher = nil
            environment.focusManager = focusManager
            environment.statusBar = statusBar
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10,
                environment: environment, identity: ViewIdentity(path: "Root"))
            // What `RenderLoop` resets before every pass.
            tuiContext.keyEventDispatcher.clearHandlers()
            statusBar.escapeLabelOverride = nil
            statusBar.escapeClaimGrabsInput = true
            statusBar.beginRenderPass()
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(
                Memoized(label: "stack") {
                    NavigationStack(path: binding) {
                        Text("root")
                            .navigationDestination(for: Step.self) { _ in Text("detail") }
                    }
                }.equatable(),
                context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return context
        }

        _ = frame()
        _ = frame()
        let context = frame()

        #expect(
            focusManager.sectionIDs.contains { $0.hasPrefix("navigation-") },
            "the third frame has no section for the pushed depth: \(focusManager.sectionIDs)")
        let consumed = withExtendedLifetime(context) {
            tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        }
        #expect(consumed, "nothing on the third frame answered Escape")
        #expect(path.isEmpty, "Escape did not go back")
    }
}
