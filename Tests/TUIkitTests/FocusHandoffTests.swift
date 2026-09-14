//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusHandoffTests.swift
//
//  `.focusHandoff(_:_:)` through real renders: a control names, by `@FocusState`
//  value, where its focus goes when it can no longer hold it. The manager's half
//  (the chain, the sections, the lifetime) is FocusHandoffRecoveryTests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

private enum Arrow: Hashable { case left, right }

/// What the rows below read each frame, and the binding their body hands back.
private final class RowState {
    var leftDisabled = false
    var rightDisabled = false
    var rightHidden = false
    var binding: FocusState<Arrow?>.Binding?
}

/// The gradient editor's shape: a control before, ◀ and ▶ naming each other, and ⇄
/// after. With no handoff, a disabled ▶ goes to ⇄.
private struct ArrowRow: View {
    @FocusState private var arrow: Arrow?
    let state: RowState

    var body: some View {
        state.binding = $arrow
        return HStack {
            Button("top") {}
            Button("◀") {}
                .disabled(state.leftDisabled)
                .focused($arrow, equals: .left)
                .focusHandoff($arrow, .right)
            right
            Button("⇄") {}
        }
    }

    @ViewBuilder private var right: some View {
        let button = Button("▶") {}
            .disabled(state.rightDisabled)
            .focused($arrow, equals: .right)
            .focusHandoff($arrow, .left)
        if state.rightHidden { button.hidden() } else { button }
    }
}

/// ``ArrowRow`` made of `.focusable()` views, which do not register at all while
/// disabled.
private struct FocusableArrowRow: View {
    @FocusState private var arrow: Arrow?
    let state: RowState

    var body: some View {
        state.binding = $arrow
        return HStack {
            Text("top").focusable()
            Text("◀").focusable().focused($arrow, equals: .left)
            Text("▶").focusable()
                .disabled(state.rightDisabled)
                .focused($arrow, equals: .right)
                .focusHandoff($arrow, .left)
            Text("⇄").focusable()
        }
    }
}

/// A handoff written on a container of two buttons.
private struct ContainerHandoff: View {
    @FocusState private var arrow: Arrow?

    var body: some View {
        HStack {
            HStack {
                Button("a") {}
                Button("b") {}
            }
            .focusHandoff($arrow, .left)
            Button("◀") {}.focused($arrow, equals: .left)
        }
    }
}

/// ◀ ▶ ⇄ as an `Equatable` view that compares equal whatever it reads, under
/// `.equatable()`: if a memo served it, its buttons would not register.
private struct EquatableArrows: View, @preconcurrency Equatable {
    let title: String
    let arrow: FocusState<Arrow?>.Binding
    let state: RowState

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        HStack {
            Button("◀") {}.focused(arrow, equals: .left)
            Button("▶") {}
                .disabled(state.rightDisabled)
                .focused(arrow, equals: .right)
                .focusHandoff(arrow, .left)
            Button("⇄") {}
        }
    }
}

private struct MemoHost: View {
    @FocusState private var arrow: Arrow?
    let state: RowState

    var body: some View {
        state.binding = $arrow
        return VStack {
            Button("top") {}
            EquatableArrows(title: "arrows", arrow: $arrow, state: state).equatable()
        }
    }
}

@MainActor
@Suite("focusHandoff(_:_:)")
struct FocusHandoffTests {

    /// One live-loop-shaped frame: real focus manager, state storage and render cache.
    private func render(_ view: some View, _ tui: TUIContext, _ manager: FocusManager) {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        manager.beginRenderPass()
        _ = renderToBuffer(view, context: context(tui, manager))
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
    }

    private func context(_ tui: TUIContext, _ manager: FocusManager) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        return RenderContext(availableWidth: 60, availableHeight: 12, environment: environment, tuiContext: tui)
    }

    /// Renders `view`, puts the focus on `arrow` through the binding, and renders again.
    private func settle(
        _ view: some View, _ state: RowState, focusing arrow: Arrow
    ) throws -> (TUIContext, FocusManager) {
        let tui = TUIContext()
        let manager = FocusManager()
        render(view, tui, manager)
        let binding = try #require(state.binding, "the body handed back its binding")
        binding.wrappedValue = arrow
        render(view, tui, manager)
        try #require(binding.wrappedValue == arrow, "\(arrow) holds the focus")
        return (tui, manager)
    }

    @Test("A disabled ▶ hands focus to ◀, not to the ⇄ beside it")
    func disabledHandsOff() throws {
        let state = RowState()
        let view = ArrowRow(state: state)
        let (tui, manager) = try settle(view, state, focusing: .right)

        state.rightDisabled = true
        render(view, tui, manager)

        #expect(state.binding?.wrappedValue == .left, "focused: \(manager.currentFocusedID ?? "nil")")
    }

    @Test("A ▶ made .hidden() hands focus to ◀")
    func hiddenHandsOff() throws {
        let state = RowState()
        let view = ArrowRow(state: state)
        let (tui, manager) = try settle(view, state, focusing: .right)

        state.rightHidden = true
        render(view, tui, manager)

        #expect(state.binding?.wrappedValue == .left, "focused: \(manager.currentFocusedID ?? "nil")")
    }

    /// `.focusable()` stops registering while disabled, so this is the "left the
    /// ring" path: the handoff it declared on its last frame decides.
    @Test("A disabled .focusable() hands focus to its target")
    func disabledFocusableHandsOff() throws {
        let state = RowState()
        let view = FocusableArrowRow(state: state)
        let (tui, manager) = try settle(view, state, focusing: .right)

        state.rightDisabled = true
        render(view, tui, manager)

        #expect(state.binding?.wrappedValue == .left, "focused: \(manager.currentFocusedID ?? "nil")")
    }

    @Test("◀ and ▶ naming each other, both disabled, fall back to ▶'s neighbour")
    func mutualHandoffsDoNotLoop() throws {
        let state = RowState()
        let view = ArrowRow(state: state)
        let (tui, manager) = try settle(view, state, focusing: .right)
        let stops = manager.registeredFocusIDsInActiveSection()
        try #require(stops.count == 4, "top ◀ ▶ ⇄: \(stops)")

        state.leftDisabled = true
        state.rightDisabled = true
        render(view, tui, manager)

        #expect(manager.currentFocusedID == stops[3], "⇄, the neighbour after ▶")
        #expect(manager.pendingFocusID == nil)
    }

    /// Like `.focused(_:equals:)`, it names ONE control: the first to register below it.
    @Test("A handoff on a container is claimed by its first control only")
    func containerClaimsOnce() throws {
        let tui = TUIContext()
        let manager = FocusManager()
        render(ContainerHandoff(), tui, manager)
        let stops = manager.registeredFocusIDsInActiveSection()
        try #require(stops.count == 3, "a b ◀: \(stops)")

        #expect(Array(manager.focusHandoffs.keys) == [stops[0]])
    }

    @Test("A measure pass declares no handoff")
    func measureDeclaresNothing() {
        let tui = TUIContext()
        let manager = FocusManager()
        tui.stateStorage.beginRenderPass()
        manager.beginRenderPass()
        _ = measureChild(
            ArrowRow(state: RowState()), proposal: ProposedSize(width: 60, height: 12),
            context: context(tui, manager))
        #expect(manager.focusHandoffs.isEmpty)
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
    }

    /// Registration declares a render side effect, so no memo stores a subtree that
    /// registers focus, and the handoff is re-declared on every frame with it.
    @Test("A handoff inside an .equatable() view is still declared on the third frame")
    func equatableRowKeepsDeclaring() throws {
        let state = RowState()
        let view = MemoHost(state: state)
        let (tui, manager) = try settle(view, state, focusing: .right)
        render(view, tui, manager)
        let focused = try #require(manager.currentFocusedID)
        #expect(manager.focusHandoffs[focused]?.generation == manager.focusRenderGeneration, "declared this frame")

        state.rightDisabled = true
        render(view, tui, manager)

        #expect(state.binding?.wrappedValue == .left, "focused: \(manager.currentFocusedID ?? "nil")")
    }
}
