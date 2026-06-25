//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StateBindingIdentityTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - @State binding identity

/// Tests that two `@State` properties on the same `View` struct
/// — hydrated through the StateStorage self-registration path,
/// not the local `State<...>(wrappedValue:)` shortcut — get
/// independent storage, write through independent bindings, and
/// route click-to-focus + key dispatch correctly to the field
/// whose binding the user actually pointed at.
///
/// Originally written as part of an investigation into a bug
/// where typing into Search visually landed in Input on
/// `TextFieldPage`. The investigation hypothesised that two
/// @State properties on the same struct might share a
/// `StateBox`. That hypothesis was disproven — these tests pass
/// with no fix, and the real bug was hit-test regions being
/// dropped in `WindowGroup.centerBuffer` (fixed in 7fabfb01).
/// Kept because @State independence and self-hydration via
/// StateStorage are real invariants worth defending against
/// regressions.
@MainActor
@Suite("@State binding identity")
struct StateBindingIdentityTests {

    private func makeContext(width: Int = 80, height: Int = 24) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = tuiContext.stateStorage
        environment.lifecycle = tuiContext.lifecycle
        environment.keyEventDispatcher = tuiContext.keyEventDispatcher
        environment.mouseEventDispatcher = tuiContext.mouseEventDispatcher
        environment.renderCache = tuiContext.renderCache
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: tuiContext
        )
    }

    /// A page struct that mirrors `TextFieldPage`'s @State layout:
    /// two String @State properties, used as `text:` bindings on two
    /// distinct TextFields inside HStacks.
    private struct TwoFieldPage: View {
        @State var demoText: String = ""
        @State var searchQuery: String = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Text("Input:")
                    TextField("Input", text: $demoText)
                }
                HStack(spacing: 1) {
                    Text("Search:")
                    TextField("Search", text: $searchQuery)
                }
            }
        }
    }

    /// Same shape as `TwoFieldPage` but with a one-sided `if` (no
    /// `else`) sitting between the second TextField and a trailing
    /// Text — mirroring what `TextFieldPage`'s "Cursor Demo"
    /// section does. Useful because in the original investigation
    /// the bug only manifested when the conditional evaluated
    /// false (rendering `Optional<View>.none`); having a shaped
    /// repro that includes the Optional branch protects against
    /// regressions in how `_VStackCore` and `appendVertically`
    /// handle empty children intermixed with mouse-region-emitting
    /// siblings.
    private struct TwoFieldPageWithOptional: View {
        @State var demoText: String = ""
        @State var searchQuery: String = ""
        @State var submittedValue: String = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Text("Input:")
                    TextField("Input", text: $demoText)
                }
                HStack(spacing: 1) {
                    Text("Search:")
                    TextField("Search", text: $searchQuery)
                }
                if !submittedValue.isEmpty {
                    HStack(spacing: 1) {
                        Text("Submitted:")
                        Text(submittedValue)
                    }
                }
                Text("Cursor style set on container").dim()
            }
        }
    }

    /// Constructs the page *inside* an active hydration context so the
    /// @State properties self-hydrate via StateStorage, then renders
    /// it, clicks the second TextField, dispatches "Z", and asserts
    /// the value landed in `searchQuery` and not `demoText`.
    @Test("Typing into clicked field writes to its own @State, not a sibling's")
    func typingLandsInOwnState() {
        let context = makeContext()

        // Mimic the real path: page struct is constructed during a
        // parent's `body` evaluation, which is wrapped in
        // `withHydration`. Here we hand-wrap construction in the same
        // way so the @State self-hydrates through StateStorage rather
        // than falling back to local boxes.
        let page = StateRegistration.withHydration(context: context) {
            TwoFieldPage()
        }

        let buffer = renderToBuffer(page, context: context)

        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let regions = buffer.hitTestRegions
        guard regions.count >= 2 else {
            Issue.record("expected 2 TextField regions, got \(regions.count)")
            return
        }
        let second = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = second.offsetX + 2
        let y = second.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        let typed = KeyEvent(key: .character("Z"))
        _ = context.environment.focusManager!.dispatchKeyEvent(typed)

        #expect(
            page.searchQuery == "Z",
            "searchQuery should be 'Z' after typing into Search; got \(page.searchQuery.debugDescription), demoText=\(page.demoText.debugDescription)"
        )
        #expect(
            page.demoText.isEmpty,
            "demoText should remain empty; got \(page.demoText.debugDescription)"
        )
    }

    /// Direct check that two @State properties on the same struct
    /// get independent storage boxes — a write to one must not be
    /// visible through the other. Guards against a class of
    /// regressions where @State hydration accidentally shares
    /// boxes across properties (would manifest as bindings
    /// invisibly aliased to each other).
    @Test("Two @State Strings on the same struct have independent boxes")
    func independentBoxesAcrossProperties() {
        let context = makeContext()
        let page = StateRegistration.withHydration(context: context) {
            TwoFieldPage()
        }

        page.demoText = "from-demo"
        #expect(
            page.searchQuery.isEmpty,
            "searchQuery should not pick up demoText's value; got \(page.searchQuery.debugDescription)"
        )

        page.searchQuery = "from-search"
        #expect(
            page.demoText == "from-demo",
            "demoText should not be overwritten by searchQuery; got \(page.demoText.debugDescription)"
        )
    }

    /// Click + type routing in the presence of a sibling
    /// `if`-without-`else` whose condition is currently false (so
    /// it renders `Optional<View>.none`). The empty conditional
    /// child is part of the same VStack and therefore shares the
    /// region-collection path with the TextFields. Guards against
    /// regressions where empty children interfere with sibling
    /// region offsets or with focus-target identification.
    @Test("Click+type through a sibling Optional<View>(.none) routes correctly")
    func clickThroughOptionalNoneSibling() {
        let context = makeContext()
        let page = StateRegistration.withHydration(context: context) {
            TwoFieldPageWithOptional()
        }

        // submittedValue starts "", so the if-body is .none.
        let buffer = renderToBuffer(page, context: context)

        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)

        let regions = buffer.hitTestRegions
        guard regions.count >= 2 else {
            Issue.record("expected 2 TextField regions, got \(regions.count)")
            return
        }
        let second = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = second.offsetX + 2
        let y = second.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        let typed = KeyEvent(key: .character("Z"))
        _ = context.environment.focusManager!.dispatchKeyEvent(typed)

        #expect(
            page.searchQuery == "Z",
            "expected typing to land in Search; searchQuery=\(page.searchQuery.debugDescription), demoText=\(page.demoText.debugDescription)"
        )
        #expect(
            page.demoText.isEmpty,
            "demoText should remain empty; got \(page.demoText.debugDescription)"
        )
    }

    /// Tighter mirror of TextFieldPage: outer VStack → nested
    /// DemoSection-shape (VStack containing a title Text + inner
    /// VStack with two HStacks, the Optional, trailing Text) →
    /// `.padding(.horizontal, 1)` at the top. Sized to reflect the
    /// real example app's view tree so it would surface
    /// regressions sensitive to nesting depth, padding offsets, or
    /// section wrappers — anything that a flat-stack repro would
    /// fail to exercise.
    private struct DemoShapedPage: View {
        @State var demoText: String = ""
        @State var searchQuery: String = ""
        @State var disabledText: String = "Cannot edit"
        @State var submittedValue: String = ""
        @State var cursorShapeIndex: Int = 0
        @State var cursorAnimationIndex: Int = 0
        @State var cursorSpeedIndex: Int = 1

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                // Mimics DemoSection("Cursor Demo") { ... }
                VStack(alignment: .leading) {
                    Text("Cursor Demo").bold().underline()
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 1) {
                            Text("Input:")
                            TextField("Input", text: $demoText, prompt: Text("Type…"))
                        }
                        HStack(spacing: 1) {
                            Text("Search:")
                            TextField("Search", text: $searchQuery, prompt: Text("Search…"))
                                .onSubmit { submittedValue = searchQuery }
                        }
                        if !submittedValue.isEmpty {
                            HStack(spacing: 1) {
                                Text("Submitted:")
                                Text(submittedValue)
                            }
                        }
                        Text("Cursor style set on container").dim()
                    }
                }
                // Mimics DemoSection("Disabled TextField") { ... }
                VStack(alignment: .leading) {
                    Text("Disabled TextField").bold().underline()
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 1) {
                            Text("Disabled:")
                            TextField("Disabled", text: $disabledText, prompt: Text("Cannot edit"))
                                .disabled()
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 1)
        }
    }

    @Test("Click+type on the real TextFieldPage shape routes correctly")
    func clickOnDemoShapedPageRoutesCorrectly() {
        let context = makeContext()
        let page = StateRegistration.withHydration(context: context) {
            DemoShapedPage()
        }

        let focusManager = context.environment.focusManager!
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        // Several render passes back-to-back, mirroring the run loop.
        for _ in 0..<3 {
            focusManager.beginRenderPass()
            dispatcher.beginRenderPass()
            let buf = renderToBuffer(page, context: context)
            dispatcher.setRegions(buf.hitTestRegions)
            focusManager.endRenderPass()
        }

        let buffer = renderToBuffer(page, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        let regions = buffer.hitTestRegions
        // Two enabled TextFields (Input + Search) — the Disabled one
        // doesn't install a hit-test region.
        guard regions.count >= 2 else {
            Issue.record("expected 2 TextField regions, got \(regions.count)")
            return
        }
        // Sort by y and pick the second (Search).
        let sorted = regions.sorted { $0.offsetY < $1.offsetY }
        let search = sorted[1]
        let x = search.offsetX + 2
        let y = search.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        let typed = KeyEvent(key: .character("Z"))
        _ = focusManager.dispatchKeyEvent(typed)

        #expect(
            page.searchQuery == "Z",
            "expected typing to land in Search; searchQuery=\(page.searchQuery.debugDescription), demoText=\(page.demoText.debugDescription)"
        )
        #expect(page.demoText.isEmpty)
    }

    /// Like `clickThroughOptionalNoneSibling`, but with N back-to-
    /// back render passes before the click so the run-loop
    /// bookkeeping has rolled over a few times. Guards against
    /// regressions where the empty conditional + render-pass churn
    /// produces stale region state on subsequent frames.
    @Test("Click+type through Optional(.none) sibling, after multiple renders")
    func clickThroughOptionalNoneSiblingAfterReRenders() {
        let context = makeContext()
        let page = StateRegistration.withHydration(context: context) {
            TwoFieldPageWithOptional()
        }

        let focusManager = context.environment.focusManager!
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        for _ in 0..<3 {
            focusManager.beginRenderPass()
            dispatcher.beginRenderPass()
            let buf = renderToBuffer(page, context: context)
            dispatcher.setRegions(buf.hitTestRegions)
            focusManager.endRenderPass()
        }

        // Final render pass — this is the one whose regions we click.
        let buffer = renderToBuffer(page, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        let regions = buffer.hitTestRegions
        guard regions.count >= 2 else {
            Issue.record("expected 2 regions, got \(regions.count)")
            return
        }
        let second = regions.max(by: { $0.offsetY < $1.offsetY })!
        let x = second.offsetX + 2
        let y = second.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        let typed = KeyEvent(key: .character("Z"))
        _ = focusManager.dispatchKeyEvent(typed)

        #expect(
            page.searchQuery == "Z",
            "after re-renders, expected Search to capture Z; searchQuery=\(page.searchQuery.debugDescription), demoText=\(page.demoText.debugDescription)"
        )
        #expect(page.demoText.isEmpty)
    }
}
