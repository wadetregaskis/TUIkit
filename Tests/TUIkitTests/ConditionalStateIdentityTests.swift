//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ConditionalStateIdentityTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Two views swapped by a conditional (if-else / switch) must not share @State.
//  @State binds to the *view's own render identity* (in renderToBuffer /
//  measureChild, via `bindStateProperties`), and a conditional branch carries a
//  distinct identity (`#true` / `#false`) — so each branch's @State lives in its
//  own slot. This holds whether the branches are constructed directly in the
//  body or deferred through a wrapper; both are guarded below.

import Testing

@testable import TUIkit

private struct StatefulA: View {
    // Internal rather than `private`: this fixture exists so the test can read
    // back the value the framework hydrated into it, which is the behaviour
    // under test. `private` is file-scoped and the assertions live outside.
    @State var text: String = "A"  // swiftlint:disable:this private_swiftui_state
    var body: some View { Text("A=\(text)") }
}

private struct StatefulB: View {
    // Internal rather than `private`: this fixture exists so the test can read
    // back the value the framework hydrated into it, which is the behaviour
    // under test. `private` is file-scoped and the assertions live outside.
    @State var text: String = "B"  // swiftlint:disable:this private_swiftui_state
    var body: some View { Text("B=\(text)") }
}

/// Defers construction of its content to render time (its own body scope).
private struct TestLazy<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

/// Both branches the SAME type, told apart only by an initial value.
///
/// The existing fixtures are two different types, which a type-keyed identity
/// step separates on its own; this is the case that needs the BRANCH step.
private struct Tagged: View {
    // Internal for the same reason as the fixtures above: the test reads back
    // what the framework hydrated.
    @State var text: String  // swiftlint:disable:this private_swiftui_state

    init(_ initial: String) {
        _text = State(initialValue: initial)
    }

    var body: some View { Text("T=\(text)") }
}

/// Same-typed branches inside a STACK, which is the flattening path: a stack
/// resolves its content through `ChildViewProvider.childViews`, never through
/// `ConditionalView.renderToBuffer`, so the branch step that method applies
/// was not reached at all.
private struct StackedSameTypeHost: View {
    let showA: Bool
    var body: some View {
        VStack {
            Text("header")
            if showA { Tagged("A") } else { Tagged("B") }
        }
    }
}

/// The same branches as the stack's ONLY content. No header, so no tuple:
/// `buildBlock` hands the conditional over bare and the stack resolves it
/// through `resolveChildViews` — a different site from the splice
/// `StackedSameTypeHost` reaches, and one that applied no branch step at all.
private struct LoneSameTypeHost: View {
    let showA: Bool
    var body: some View {
        VStack {
            if showA { Tagged("A") } else { Tagged("B") }
        }
    }
}

/// Different types, lone. With no step of any kind applied, not even the
/// type-keyed one that separates `DirectHost`'s branches ran, so two unrelated
/// views whose `@State` lined up by declaration order and value type collided.
private struct LoneDifferentTypeHost: View {
    let showA: Bool
    var body: some View {
        VStack {
            if showA { StatefulA() } else { StatefulB() }
        }
    }
}

/// A lone conditional whose branches are several views each. The children do
/// carry positional steps, but derived from the STACK's context, so `Tagged` at
/// position 1 was one identity in both branches.
private struct LoneTupleBranchHost: View {
    let showA: Bool
    var body: some View {
        VStack {
            if showA {
                Text("first")
                Tagged("A")
            } else {
                Text("first")
                Tagged("B")
            }
        }
    }
}

/// `Tagged` with its telling `@State` at declaration index 2, for `List`.
///
/// A `List` renders a lone row at its OWN identity, where `_ListCore` keeps two
/// slots of its own: its handler at index 0, its focus id at 1. A row whose
/// state sat at 0 would lose its box to the list's on every frame (a type
/// mismatch replaces it) and read a fresh initial value whether or not the
/// branches were told apart — the test would pass for the wrong reason. Index 2
/// is nobody's but the row's.
private struct ListTagged: View {
    @State private var handlerSlot = 0
    @State private var focusIDSlot = 0
    @State private var text: String

    init(_ initial: String) {
        _text = State(initialValue: initial)
    }

    var body: some View { Text("T=\(text)") }
}

/// A lone conditional as a `List`'s content: `_ListCore` extracts the rows
/// itself, not through a stack.
private struct LoneListHost: View {
    let showA: Bool
    var body: some View {
        List {
            if showA { ListTagged("A") } else { ListTagged("B") }
        }
    }
}

/// The same inside a `Section`, which extracts its rows through its own copy.
private struct LoneSectionHost: View {
    let showA: Bool
    var body: some View {
        List {
            Section {
                if showA { ListTagged("A") } else { ListTagged("B") }
            } header: {
                Text("S")
            }
        }
    }
}

/// Swaps two stateful views directly in the body.
private struct DirectHost: View {
    let showA: Bool
    var body: some View {
        if showA { StatefulA() } else { StatefulB() }
    }
}

/// Swaps them through a deferring wrapper.
private struct LazyHost: View {
    let showA: Bool
    var body: some View {
        if showA {
            TestLazy { StatefulA() }
        } else {
            TestLazy { StatefulB() }
        }
    }
}

@MainActor
@Suite("Conditional @State identity")
struct ConditionalStateIdentityTests {

    private func text(_ buffer: FrameBuffer) -> String {
        buffer.lines.joined(separator: "\n")
    }

    @Test("Directly-swapped conditional branches keep independent @State")
    func directConstructionIsolatesState() {
        // Reuse ONE context (and its StateStorage) across both renders, the way a
        // page switch persists state between frames. Render branch A (creates A's
        // slot = "A"), then switch to B: B must read its OWN default, not A's slot.
        let ctx = makeRenderContext()
        let a = text(renderToBuffer(DirectHost(showA: true), context: ctx))
        #expect(a.contains("A=A"))
        let b = text(renderToBuffer(DirectHost(showA: false), context: ctx))
        #expect(b.contains("B=B"), "B's @State must be independent of A's (render-identity keyed)")
    }

    /// A stack FLATTENS a conditional: it resolves its content through
    /// `ChildViewProvider.childViews`, which reached neither branch step, so
    /// two branches of the same type landed on one identity and shared a
    /// `@State` box. Flipping the condition carried the old branch's value
    /// into the new one.
    ///
    /// Same type in both branches deliberately. The identity step is keyed by
    /// type as well as position, so branches of DIFFERENT types were separated
    /// by accident — which is why the two cases above pass either way and this
    /// one does not.
    @Test("Same-typed branches inside a stack keep independent @State")
    func stackedSameTypeBranchesIsolateState() {
        let ctx = makeRenderContext()
        let a = text(renderToBuffer(StackedSameTypeHost(showA: true), context: ctx))
        #expect(a.contains("T=A"))
        let b = text(renderToBuffer(StackedSameTypeHost(showA: false), context: ctx))
        #expect(
            b.contains("T=B"),
            "the false branch read the true branch's state out of a shared box: \(b)")
    }

    /// The conditional as a container's ONLY content, which the test above does
    /// not reach: `buildBlock` hands a lone `if`/`else` over bare, no tuple is
    /// built, and the stack resolves it through `resolveChildViews`, which
    /// applied no branch step at all. One shape per half of the fix: a branch
    /// that is one plain view (transparent, so it must be pinned to its
    /// branch), the same with two DIFFERENT types (no type step ran either),
    /// and a branch of several views (positional steps, taken under the branch).
    @Test("A conditional that is a stack's only content keeps each branch's @State")
    func loneConditionalInAStackIsolatesState() {
        let sameType = renderedBeforeAndAfterFlip { LoneSameTypeHost(showA: $0) }
        #expect(sameType.before.contains("T=A"))
        #expect(
            sameType.after.contains("T=B"),
            "one view per branch — the false branch read the true one's box: \(sameType.after)")

        let differentTypes = renderedBeforeAndAfterFlip { LoneDifferentTypeHost(showA: $0) }
        #expect(differentTypes.before.contains("A=A"))
        #expect(
            differentTypes.after.contains("B=B"),
            "one view per branch, different types: \(differentTypes.after)")

        let tupleBranches = renderedBeforeAndAfterFlip { LoneTupleBranchHost(showA: $0) }
        #expect(tupleBranches.before.contains("T=A"))
        #expect(
            tupleBranches.after.contains("T=B"),
            "several views per branch: \(tupleBranches.after)")
    }

    /// `List` and `Section` extract their static rows themselves, and both asked
    /// the provider for `childViews(context:)` directly — past the one site that
    /// applies the branch step to a lone conditional.
    @Test("A conditional that is a List's or a Section's only content keeps each branch's @State")
    func loneConditionalInAListIsolatesState() {
        let list = renderedBeforeAndAfterFlip { LoneListHost(showA: $0) }
        #expect(list.before.contains("T=A"))
        #expect(list.after.contains("T=B"), "a List's rows: \(list.after)")

        let section = renderedBeforeAndAfterFlip { LoneSectionHost(showA: $0) }
        #expect(section.before.contains("T=A"))
        #expect(section.after.contains("T=B"), "a Section's rows: \(section.after)")
    }

    @Test("Deferred construction also keeps independent @State")
    func deferredConstructionIsolatesState() {
        let ctx = makeRenderContext()
        let a = text(renderToBuffer(LazyHost(showA: true), context: ctx))
        #expect(a.contains("A=A"))
        let b = text(renderToBuffer(LazyHost(showA: false), context: ctx))
        #expect(b.contains("B=B"), "deferral via a wrapper is equally isolated")
    }

    /// A conditional invalidates the branch it left — but only when a frame is
    /// actually DRAWN. Doing it while measuring deletes live `@State` that no
    /// frame has replaced, and measures are not rare: every
    /// `measureFixedByRendering` view (`Button` among them) measures by
    /// rendering, so a conditional inside a button's label was sweeping the
    /// state store on every measure of every frame.
    @Test("Measuring a conditional does not delete the other branch's @State")
    func measuringDoesNotInvalidateTheInactiveBranch() {
        let ctx = makeRenderContext()
        let storage = ctx.environment.stateStorage!

        // Draw the false branch so its three slots exist and are live.
        _ = renderToBuffer(ButtonHost(showA: false), context: ctx)
        let live = storage.count
        #expect(live >= 3, "the false branch's three stateful rows must be stored")

        // MEASURE the other branch. The button measures by rendering, so this
        // reaches the conditional with `isMeasuring` set. It may add the true
        // branch's own slot; it must not take the false branch's away.
        _ = measureChild(
            ButtonHost(showA: true), proposal: ProposedSize(width: 40, height: 10), context: ctx)

        #expect(
            storage.count > live,
            "a measure must only ever add state, never drop the branch it did not draw")
    }
}

/// A conditional inside a `Button`'s label — the shape that made this cost real.
/// `_ButtonCore` measures by rendering, so measuring this measures *through* the
/// conditional. The branches are deliberately lopsided (three stateful rows
/// against one) so a wrongly-invalidated false branch shows up as a DROP in the
/// stored-state count rather than cancelling out against the true branch's slot.
private struct ButtonHost: View {
    let showA: Bool

    var body: some View {
        Button {
        } label: {
            if showA {
                StatefulA()
            } else {
                VStack {
                    StatefulB()
                    StatefulB()
                    StatefulB()
                }
            }
        }
    }
}
