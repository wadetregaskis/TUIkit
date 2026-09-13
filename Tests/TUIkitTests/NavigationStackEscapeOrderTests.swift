//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationStackEscapeOrderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Who hears Escape first on a pushed `NavigationStack` screen: the screen, or
/// the stack that would pop it.
///
/// The stack decides whether to claim Escape only after the screen renders — it
/// reads the title the screen publishes, and yields to anything inside that
/// already claimed the key — and it used to register its pop handler right
/// there, AFTER every handler the screen had registered. The dispatcher asks
/// the most recent registration first, so the pop always answered: a screen's
/// `.onKeyPress(keys: [.escape])` never ran, and the remedy
/// `navigationBarBackButtonHidden(_:)` documents for a screen that must not be
/// left, something that consumes Escape, could not be written.
@MainActor
@Suite("NavigationStack escape order")
struct NavigationStackEscapeOrderTests {

    private struct Step: Hashable {
        let number: Int
    }

    /// Renders `view` once, then offers it Escape the way the input handler's
    /// layer 2 does — with the frame's context kept alive, because it owns the
    /// services the handlers reach.
    private func escape(after view: some View) -> Bool {
        let context = makeRenderContext(width: 40, height: 10)
        _ = renderToBuffer(view, context: context)
        return withExtendedLifetime(context) {
            context.environment.keyEventDispatcher?.dispatch(KeyEvent(key: .escape)) == true
        }
    }

    @Test("A pushed screen's own Escape handler runs instead of the pop")
    func screenHandlerOutranksThePop() {
        var path = NavigationPath()
        path.append(Step(number: 1))
        let binding = Binding(get: { path }, set: { path = $0 })
        var screenHeard = false
        let view = NavigationStack(path: binding) {
            Text("root")
                .navigationDestination(for: Step.self) { _ in
                    Text("wizard")
                        .navigationBarBackButtonHidden()
                        .onKeyPress(keys: [.escape]) { _ in
                            screenHeard = true
                            return true
                        }
                }
        }

        let consumed = escape(after: view)
        #expect(consumed)
        #expect(screenHeard, "the screen's handler never ran: the pop answered first")
        #expect(path.count == 1, "the screen consumed Escape, so the stack must stay put")
    }

    @Test("A screen handler that declines Escape still lets the stack go back")
    func decliningScreenHandlerStillPops() {
        var path = NavigationPath()
        path.append(Step(number: 1))
        let binding = Binding(get: { path }, set: { path = $0 })
        var screenAsked = false
        let view = NavigationStack(path: binding) {
            Text("root")
                .navigationDestination(for: Step.self) { _ in
                    Text("detail")
                        .onKeyPress(keys: [.escape]) { _ in
                            screenAsked = true
                            return false
                        }
                }
        }

        let consumed = escape(after: view)
        #expect(consumed, "the stack takes what the screen declined")
        #expect(screenAsked, "the screen is asked first")
        #expect(path.isEmpty, "declined, so Escape goes back")
    }

    @Test("An Escape handler around the stack still loses to going back")
    func handlerAroundTheStackStillLoses() {
        // A page that returns to its menu on Escape (the Example's ContentView
        // does, on every page) registers before the stack renders. Moving the
        // pop behind the SCREEN must not move it behind the page as well.
        var path = NavigationPath()
        path.append(Step(number: 1))
        let binding = Binding(get: { path }, set: { path = $0 })
        var pageHeard = false
        let view = NavigationStack(path: binding) {
            Text("root")
                .navigationDestination(for: Step.self) { _ in Text("detail") }
        }
        .onKeyPress(keys: [.escape]) { _ in
            pageHeard = true
            return true
        }

        let consumed = escape(after: view)
        #expect(consumed)
        #expect(path.isEmpty, "Escape goes back before the page sees it")
        #expect(!pageHeard, "the page's handler outranked the stack's pop")
    }
}
