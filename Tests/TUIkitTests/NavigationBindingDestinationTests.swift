//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationBindingDestinationTests.swift
//
//  `navigationDestination(isPresented:)` and `(item:)` — the destinations
//  driven by a binding rather than by a pushed value.
//
//  The whole substance is the TWO-WAY link, and the state that makes it
//  possible: "flag true, screen not on the path" is ambiguous — it is both *the
//  app just asked for this* and *the user just went Back* — so the modifier has
//  to remember whether it was the one that pushed. Without that memory a Back
//  press pushes the screen straight back on, which is the case below that would
//  otherwise never terminate.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Binding-driven navigation destinations")
struct NavigationBindingDestinationTests {

    private struct Item: Hashable {
        let name: String
    }

    /// A live stack across frames: one `TUIContext`, so `@State` (and the
    /// modifier's own did-push memory) persists the way it does in the run
    /// loop.
    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var path = NavigationPath()
        var showing = false
        var item: Item?

        @discardableResult
        func frame(_ build: () -> some View) -> [String] {
            var env = EnvironmentValues()
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            let lines = renderToBuffer(build(), context: context).lines.map(\.stripped)
            tui.stateStorage.endRenderPass()
            return lines
        }

        func booleanStack() -> some View {
            NavigationStack(path: Binding(get: { self.path }, set: { self.path = $0 })) {
                Text("root")
                    .navigationDestination(
                        isPresented: Binding(get: { self.showing }, set: { self.showing = $0 })
                    ) {
                        Text("pushed screen")
                    }
            }
        }

        func itemStack() -> some View {
            NavigationStack(path: Binding(get: { self.path }, set: { self.path = $0 })) {
                Text("root")
                    .navigationDestination(
                        item: Binding(get: { self.item }, set: { self.item = $0 })
                    ) { item in
                        Text("about \(item.name)")
                    }
            }
        }
    }

    @Test("Setting the flag pushes the screen; clearing it pops")
    func flagDrivesThePath() {
        let fixture = Fixture()

        var lines = fixture.frame(fixture.booleanStack)
        #expect(lines.contains { $0.contains("root") })
        #expect(fixture.path.isEmpty)

        fixture.showing = true
        // The frame that notices the flag pushes; the frame after it draws the
        // screen — the path is read before the modifier runs.
        fixture.frame(fixture.booleanStack)
        #expect(fixture.path.count == 1)
        lines = fixture.frame(fixture.booleanStack)
        #expect(lines.contains { $0.contains("pushed screen") }, "\(lines)")

        fixture.showing = false
        fixture.frame(fixture.booleanStack)
        #expect(fixture.path.isEmpty)
        lines = fixture.frame(fixture.booleanStack)
        #expect(lines.contains { $0.contains("root") }, "\(lines)")
    }

    /// The case the did-push memory exists for. A pop the modifier did not ask
    /// for has to read as "the user left", not as "the flag is still true, push
    /// it again" — and this asserts BOTH: the flag clears, and the screen stays
    /// off across the frames that follow.
    @Test("Popping the screen clears the flag instead of pushing it back")
    func poppingClearsTheFlag() {
        let fixture = Fixture()
        fixture.showing = true
        fixture.frame(fixture.booleanStack)
        #expect(fixture.path.count == 1)

        // What Back does.
        fixture.path = NavigationPath()

        fixture.frame(fixture.booleanStack)
        #expect(!fixture.showing, "the pop was reported back to the app")
        for _ in 0..<3 { fixture.frame(fixture.booleanStack) }
        #expect(fixture.path.isEmpty, "and it stayed off")
    }

    @Test("A screen pushed above the destination goes when the flag clears")
    func clearingTakesTheScreensAboveItToo() {
        let fixture = Fixture()
        fixture.showing = true
        fixture.frame(fixture.booleanStack)
        #expect(fixture.path.count == 1)

        // The pushed screen pushes something of its own.
        fixture.path.append(Item(name: "deeper"))
        fixture.frame(fixture.booleanStack)
        #expect(fixture.path.count == 2)

        fixture.showing = false
        fixture.frame(fixture.booleanStack)
        #expect(
            fixture.path.isEmpty,
            "popping to the token alone would strand the user on a screen reached through it")
    }

    @Test("item: pushes a screen built from the value, and nil pops it")
    func itemDrivesThePath() {
        let fixture = Fixture()

        fixture.frame(fixture.itemStack)
        #expect(fixture.path.isEmpty)

        fixture.item = Item(name: "Ada")
        fixture.frame(fixture.itemStack)
        #expect(fixture.path.count == 1)
        let lines = fixture.frame(fixture.itemStack)
        #expect(lines.contains { $0.contains("about Ada") }, "\(lines)")

        fixture.item = nil
        fixture.frame(fixture.itemStack)
        #expect(fixture.path.isEmpty)
    }

    @Test("Popping an item screen clears the item")
    func poppingClearsTheItem() {
        let fixture = Fixture()
        fixture.item = Item(name: "Ada")
        fixture.frame(fixture.itemStack)
        #expect(fixture.path.count == 1)

        fixture.path = NavigationPath()
        fixture.frame(fixture.itemStack)
        #expect(fixture.item == nil, "the pop emptied the item, not just the path")
        for _ in 0..<3 { fixture.frame(fixture.itemStack) }
        #expect(fixture.path.isEmpty)
    }

    @Test("The screen is rebuilt each frame, so it sees current state")
    func destinationStaysFresh() {
        let fixture = Fixture()
        var caption = "first"
        func stack() -> some View {
            NavigationStack(path: Binding(get: { fixture.path }, set: { fixture.path = $0 })) {
                Text("root")
                    .navigationDestination(
                        isPresented: Binding(
                            get: { fixture.showing }, set: { fixture.showing = $0 })
                    ) {
                        Text(caption)
                    }
            }
        }

        fixture.showing = true
        fixture.frame(stack)
        var lines = fixture.frame(stack)
        #expect(lines.contains { $0.contains("first") }, "\(lines)")

        caption = "second"
        lines = fixture.frame(stack)
        #expect(lines.contains { $0.contains("second") }, "a stale screen would still say first: \(lines)")
    }
}
