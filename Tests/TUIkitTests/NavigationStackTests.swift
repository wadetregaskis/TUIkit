//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationStackTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Push/pop navigation: the stack shows its root until something is pushed,
/// then the matching destination under a back bar.
///
/// The properties worth pinning here are the ones a careless implementation
/// gets wrong and no compiler catches: that the pushed screen actually replaces
/// the root on screen, that the bar's height does not depend on the title, and
/// that the root's `@State` survives a push — which is what makes going back
/// feel like going back rather than starting over.
@MainActor
@Suite("NavigationStack")
struct NavigationStackTests {

    private struct Item: Hashable {
        let name: String
    }

    private func lines(_ view: some View, width: Int = 40, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    // MARK: - Path

    @Test("An empty path shows the root")
    func rootShowsWhenPathIsEmpty() {
        let rendered = lines(
            NavigationStack {
                Text("root content")
            })
        #expect(rendered.contains { $0.contains("root content") })
    }

    @Test("A pushed value shows its destination instead of the root")
    func pushedValueShowsDestination() {
        var path = NavigationPath()
        path.append(Item(name: "one"))
        let binding = Binding(get: { path }, set: { path = $0 })

        let rendered = lines(
            NavigationStack(path: binding) {
                Text("root content")
                    .navigationDestination(for: Item.self) { Text("detail: \($0.name)") }
            })

        #expect(rendered.contains { $0.contains("detail: one") })
        // The root is still rendered — off-screen, for its state and its
        // destination registrations — but must not reach the terminal.
        #expect(!rendered.contains { $0.contains("root content") })
    }

    @Test("The back bar carries the pushed screen's navigationTitle")
    func barShowsDestinationTitle() {
        var path = NavigationPath()
        path.append(Item(name: "one"))
        let binding = Binding(get: { path }, set: { path = $0 })

        let rendered = lines(
            NavigationStack(path: binding) {
                Text("root")
                    .navigationDestination(for: Item.self) { item in
                        Text("body").navigationTitle(item.name)
                    }
            })

        #expect(rendered[0].contains("one"))
        // The bar's leftmost crumb is the way out. The root here published no
        // title of its own, so it shows as the anonymous "…" — still clickable,
        // still the root.
        #expect(rendered[0].contains("\(NavigationCrumbs.separator)"), "bar: \(rendered[0])")
    }

    @Test("The bar is two rows whatever the title's length")
    func barHeightIsIndependentOfTheTitle() {
        // The chrome-height rule: content space cannot depend on content, so a
        // title that would not fit is truncated rather than wrapped. A bar that
        // grew by a row here would shift every row of the screen below it.
        func firstContentRow(_ title: String) -> Int {
            var path = NavigationPath()
            path.append(Item(name: title))
            let binding = Binding(get: { path }, set: { path = $0 })
            let rendered = lines(
                NavigationStack(path: binding) {
                    Text("root")
                        .navigationDestination(for: Item.self) { item in
                            Text("SCREEN").navigationTitle(item.name)
                        }
                })
            return rendered.firstIndex { $0.contains("SCREEN") } ?? -1
        }

        #expect(firstContentRow("x") == 2)
        #expect(firstContentRow(String(repeating: "long title ", count: 12)) == 2)
    }

    @Test("A value with no registered destination still leaves a way back")
    func unknownDestinationKeepsTheBar() {
        var path = NavigationPath()
        path.append(Item(name: "orphan"))
        let binding = Binding(get: { path }, set: { path = $0 })

        // No .navigationDestination(for: Item.self) anywhere: the screen is
        // blank, but dropping the value silently would be worse — and stranding
        // the user with no way back worse still. The screen publishes no title
        // either, so this is the barest possible bar: two anonymous crumbs, the
        // first of which still pops to the root.
        let rendered = lines(
            NavigationStack(path: binding) {
                Text("root")
            })
        #expect(rendered[0].contains("\(NavigationCrumbs.separator)"), "bar: \(rendered[0])")
    }

    // MARK: - Links

    @Test("A link pushes its value onto a bound path")
    func linkPushesValue() {
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })
        let context = makeRenderContext(width: 40, height: 10)

        let buffer = renderToBuffer(
            NavigationStack(path: binding) {
                NavigationLink("Go", value: Item(name: "one"))
                    .navigationDestination(for: Item.self) { Text($0.name) }
            }, context: context)

        // Activate through the focus system, the route Return on a focused
        // link actually takes.
        #expect(path.isEmpty)
        #expect(!buffer.lines.isEmpty)
        #expect(context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .enter)) == true)
        #expect(path.count == 1)
    }

    @Test("A link with a nil value is disabled")
    func nilValueDisablesTheLink() {
        let item: Item? = nil
        let context = makeRenderContext(width: 40, height: 10)
        let buffer = renderToBuffer(
            NavigationStack {
                NavigationLink("Go", value: item)
            }, context: context)
        // A disabled control registers no focus entry, which is the property
        // that keeps Tab from landing on something that cannot act — and with
        // nothing focused there is nothing for Return to fire.
        #expect(!buffer.lines.isEmpty)
        #expect(context.environment.focusManager?.currentFocusedID == nil)
    }

    // MARK: - NavigationPath

    @Test("NavigationPath appends and removes")
    func navigationPathArithmetic() {
        var path = NavigationPath()
        #expect(path.isEmpty)
        path.append(Item(name: "a"))
        path.append(7)
        #expect(path.count == 2)
        path.removeLast()
        #expect(path.count == 1)
        path.removeLast(1)
        #expect(path.isEmpty)

        // Mixed types are the whole point of the erased path.
        let seeded = NavigationPath(["x", "y"])
        #expect(seeded.count == 2)
    }

    @Test("A typed path binding round-trips its own element type")
    func typedPathBinding() {
        var items = [Item(name: "one")]
        let binding = Binding(get: { items }, set: { items = $0 })
        let rendered = lines(
            NavigationStack(path: binding) {
                Text("root")
                    .navigationDestination(for: Item.self) { Text("detail: \($0.name)") }
            })
        #expect(rendered.contains { $0.contains("detail: one") })
    }

    // MARK: - Going back

    /// A root that counts its own renders in `@State`, so the test can tell
    /// whether the state survived a push or was rebuilt from its default.
    private struct CountingRoot: View {
        @State private var visits = 0

        var body: some View {
            Text("visits: \(visits)")
                .onAppear { visits += 1 }
        }
    }

    @Test("The root's @State survives a push and is still there on the way back")
    func rootStateSurvivesAPush() {
        // This is the whole reason the root keeps rendering while a screen is
        // pushed. `endRenderPass` prunes the state of anything that did not
        // render this frame — so a stack that simply stopped drawing its root
        // would hand back a freshly-defaulted root, losing a scroll position, a
        // selection, or a half-filled form. The counter stands in for all of
        // those: it must not restart.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })

        func frame() -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8,
                environment: environment, tuiContext: tuiContext)

            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(
                NavigationStack(path: binding) {
                    CountingRoot()
                        .navigationDestination(for: Item.self) { Text("detail: \($0.name)") }
                }, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map(\.stripped)
        }

        // Frame 1 draws before `onAppear` runs, so the count it shows is the
        // pre-increment 0; frame 2 settles at 1.
        _ = frame()
        #expect(frame().contains { $0.contains("visits: 1") })

        path.append(Item(name: "one"))
        let pushed = frame()
        #expect(pushed.contains { $0.contains("detail: one") })

        path.removeLast()
        // Still 1: `onAppear` did not fire a second time, so the root was never
        // torn down — and the count it is showing is the one it had before.
        #expect(frame().contains { $0.contains("visits: 1") })
    }

    @Test("Escape pops the top screen")
    func escapePops() {
        var path = NavigationPath()
        path.append(Item(name: "one"))
        let binding = Binding(get: { path }, set: { path = $0 })
        let context = makeRenderContext(width: 40, height: 10)

        _ = renderToBuffer(
            NavigationStack(path: binding) {
                Text("root")
                    .navigationDestination(for: Item.self) { Text("detail: \($0.name)") }
            }, context: context)

        // The stack claims ESC for the status bar (so the bar says what the key
        // does now) and registers the handler that acts on it.
        #expect(context.environment.statusBar.escapeLabelOverride != nil)
        // …but only lightly: a pushed screen is not a modal, so the app's other
        // shortcuts must keep working behind it.
        #expect(context.environment.statusBar.escapeClaimGrabsInput == false)

        #expect(context.environment.keyEventDispatcher?.dispatch(KeyEvent(key: .escape)) == true)
        #expect(path.isEmpty)
    }

    @Test("dismiss() pops from inside a pushed screen")
    func dismissPops() {
        // SwiftUI's `\.dismiss` means "undo the presentation you are in". At the
        // top level of a TUIkit app that is quitting; here it must mean back.
        struct Screen: View {
            @Environment(\.dismiss) private var dismiss
            let onRender: (DismissAction) -> Void

            var body: some View {
                Text("screen").onAppear { onRender(dismiss) }
            }
        }

        var path = NavigationPath()
        path.append(Item(name: "one"))
        let binding = Binding(get: { path }, set: { path = $0 })
        var captured: DismissAction?

        _ = renderToBuffer(
            NavigationStack(path: binding) {
                Text("root")
                    .navigationDestination(for: Item.self) { _ in
                        Screen { captured = $0 }
                    }
            }, context: makeRenderContext(width: 40, height: 10))

        #expect(captured != nil)
        captured?()
        #expect(path.isEmpty)
    }
}
