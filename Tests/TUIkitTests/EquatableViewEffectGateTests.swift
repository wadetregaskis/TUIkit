//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EquatableViewEffectGateTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A memoizable leaf whose body is built by a closure, so each case can put a
/// different effect **inside** the subtree the cache would serve.
///
/// That placement is the whole point. `Leaf().equatable().onAppear {}` puts the
/// effect *above* the boundary, where it re-runs every frame and caching the
/// inert leaf below it is perfectly correct. The dangerous shape is the effect
/// *below* the boundary, where a cache hit skips the body that registers it.
///
/// Equality is by label alone — the closure is the view's construction, not its
/// content — which is what lets two separately-built values compare equal and
/// hit.
private struct EffectLeaf<Content: View>: View, @MainActor Equatable {
    let label: String
    let build: @MainActor (Text) -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.label == rhs.label }

    var body: some View {
        build(Text(label))
    }
}

/// The row arm's key. Constant, so the memo always WANTS to hit and the only
/// thing that can stop it is the gate under test — which is the point: keyed on
/// anything that varied, a decline would be indistinguishable from a miss.
private struct AlwaysEqual: Equatable {}

private struct CountKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// A subtree that registers an effect must never be served from cache: the frame
/// the cache answers is a frame on which the effect was never registered, so
/// `onAppear` never fires and focus is not in the ring. The exception is a
/// registration the memo records and makes again on every hit — a key handler —
/// which stores.
///
/// Every effect site declares itself through
/// `VolatileReadTracker.recordRenderSideEffect()`, and `EquatableView` refuses
/// to *store* any buffer whose render tripped it. That is a single contract with
/// many call sites, so it is exactly the kind of thing that rots quietly: a new
/// effect modifier that forgets to declare itself is invisible until someone's
/// `onAppear` stops firing on the second frame.
///
/// Upstream pinned the same contract from the other side (`d4f7d3aa`,
/// characterizing the effects that vanish when it is missing).
@MainActor
@Suite("EquatableView effect gate", .serialized)
struct EquatableViewEffectGateTests {

    private func context() -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.focusManager = FocusManager()
        // Without one `.statusBarItems` registers nothing and declares nothing,
        // so its case below would store whatever the gate did.
        environment.statusBar = StatusBarState()
        environment.renderCache = RenderCache()
        environment.preferenceStorage = tuiContext.preferences
        // No mouse dispatcher. `.focusable()` registers a hit-test region when
        // one is wired, and `RenderCache.isStorable` refuses any buffer carrying
        // one — so with a dispatcher here the focus cases below would measure
        // that gate instead of this suite's, and would read as "declines" no
        // matter what a focus registration declared.
        environment.mouseEventDispatcher = nil
        return RenderContext(
            availableWidth: 40,
            availableHeight: 10,
            environment: environment,
            identity: ViewIdentity(path: "Root")
        )
    }

    /// Renders `view` through one cache lifecycle and reports whether anything
    /// was stored.
    private func storesBuffer(_ build: () -> some View) -> Bool {
        let context = self.context()
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        _ = renderToBuffer(build(), context: context)
        cache.removeInactive()
        return !cache.isEmpty
    }

    @Test("An inert subtree is cached — the control")
    func inertSubtreeIsCached() {
        // If this ever fails, every expectation below passes vacuously.
        #expect(storesBuffer { EffectLeaf(label: "inert") { $0 }.equatable() })
    }

    @Test("An effect ABOVE the boundary does not stop the subtree caching")
    func effectAboveTheBoundaryStillCaches() {
        // The distinction the rest of this suite turns on: here the effect
        // re-registers every frame regardless, because the cache is not what
        // answers for it.
        #expect(storesBuffer { EffectLeaf(label: "x") { $0 }.equatable().onAppear {} })
    }

    @Test("onAppear inside the subtree declines the cache")
    func onAppearDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.onAppear {} }.equatable() })
    }

    @Test("task inside the subtree declines the cache")
    func taskDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.task {} }.equatable() })
    }

    @Test("onChange inside the subtree declines the cache")
    func onChangeDeclines() {
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.onChange(of: 1) { _, _ in } }.equatable() })
    }

    @Test("A key handler inside the subtree is stored, because a hit replays it")
    func keyPressStores() {
        // The one registration here that the memo records and makes again on
        // every hit (`EffectJournal`), so it no longer has to decline. What
        // proves the replay is KeyPressMemoTests; this pins the gate.
        #expect(storesBuffer { EffectLeaf(label: "x") { $0.onKeyPress { _ in false } }.equatable() })
    }

    @Test("A refreshable inside the subtree is stored, because a hit replays its Ctrl-R")
    func refreshableStores() {
        // Its Ctrl-R handler is recorded and replayed like `onKeyPress`'s. What
        // proves the replay, and the spinner redrawing, is RefreshableMemoTests.
        #expect(storesBuffer { EffectLeaf(label: "x") { $0.refreshable {} }.equatable() })
    }

    @Test("Status bar items inside the subtree are stored, because a hit registers them again")
    func statusBarItemsStore() {
        // Replayed like `onKeyPress`. What proves the replay, the per-section
        // precedence and the dimmed case is StatusBarItemsMemoTests.
        #expect(
            storesBuffer {
                EffectLeaf(label: "x") { $0.statusBarItems { StatusBarItem(shortcut: "h", label: "help") } }
                    .equatable()
            })
    }

    @Test("An UNFOCUSED focus registration inside the subtree is stored, because a hit replays it")
    func unfocusedFocusableStores() {
        // The stop ahead of it takes the focus as it registers (an empty section
        // auto-focuses its first registrant), so the memoized one renders
        // unfocused — and an unfocused registration is one a hit can make again.
        // What proves the replay, and the Tab ring surviving it, is
        // FocusRegistrationMemoTests.
        #expect(
            storesBuffer {
                VStack {
                    Text("ahead").focusable()
                    EffectLeaf(label: "x") { $0.focusable() }.equatable()
                }
            })
    }

    @Test("A Button's keyboard shortcut inside the subtree is stored, because a hit registers it again")
    func keyboardShortcutStores() {
        // The registry is emptied every pass like the dispatcher, so this is
        // recorded and replayed as `onKeyPress` is. The stop ahead takes the
        // focus, so the button's own focus registration is not what decides
        // this. What proves the replay is KeyboardShortcutMemoTests.
        #expect(
            storesBuffer {
                VStack {
                    Text("ahead").focusable()
                    EffectLeaf(label: "x") { _ in
                        Button("go") {}.keyboardShortcut("s", modifiers: [])
                    }
                    .equatable()
                }
            })
    }

    @Test("A keyboard shortcut planted ABOVE the subtree declines the cache")
    func keyboardShortcutAboveTheBoundaryDeclines() {
        // The exception to the case above, and the reason it is not simply "a
        // shortcut is replayable": the carrier is claimed by the first control
        // that renders under it, and on a served frame no control does. The key
        // is made of the view value BELOW the modifier, so it cannot see the
        // shortcut change either.
        #expect(
            !storesBuffer {
                VStack {
                    Text("ahead").focusable()
                    EffectLeaf(label: "x") { _ in Button("go") {} }
                        .equatable()
                        .keyboardShortcut("s", modifiers: [])
                }
            })
    }

    @Test("A FOCUSED focus registration inside the subtree declines the cache")
    func focusedFocusableDeclines() {
        // The only stop here, so it takes the focus as it registers. Its buffer
        // draws the focus ring, and nothing in the memo's key would see the
        // focus leave it again.
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.focusable() }.equatable() })
    }

    @Test("A preference write inside the subtree declines the cache")
    func preferenceDeclines() {
        #expect(
            !storesBuffer {
                EffectLeaf(label: "x") { $0.preference(key: CountKey.self, value: 1) }.equatable()
            })
    }

    @Test("An ACTIVE focus section inside the subtree declines the cache")
    func activeFocusSectionDeclines() {
        // The first section registered on an empty manager becomes the active
        // one, and an active section hands its subtree a breathing ● drawn from
        // focus state the key never sees.
        #expect(!storesBuffer { EffectLeaf(label: "x") { $0.focusSection("rows") }.equatable() })
    }

    @Test("An INACTIVE focus section inside the subtree is stored, because a hit registers it again")
    func inactiveFocusSectionStores() {
        // The section ahead of it is the active one, so this section shows no ●
        // and its registration is one a hit can make again.
        #expect(
            storesBuffer {
                VStack {
                    Text("ahead").focusSection("ahead")
                    EffectLeaf(label: "x") { $0.focusSection("rows") }.equatable()
                }
            })
    }

    @Test("A focus section inside the subtree is still registered on every later frame")
    func focusSectionSurvivesLaterFrames() {
        // Sections are rebuilt every pass (`FocusManager.beginSceneRender`), so a
        // memo that served `.focusSection` from cache left the frame with no
        // section at all: the controls under it had nowhere to register, and the
        // ● the modifier hands its subtree kept whatever focus state it was
        // stored with. Nothing else in this subtree declares, so the section's
        // own declaration is the only thing standing between it and the cache.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        func frame() -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 40, availableHeight: 10,
                environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            _ = renderToBuffer(
                EffectLeaf(label: "x") { $0.focusSection("rows") }.equatable(), context: context)
            let sections = focusManager.sectionIDs
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return sections
        }

        for number in 1...3 {
            #expect(frame() == ["rows"], "frame \(number) lost the section")
        }
    }

    /// Every decline condition above, run through the OTHER memo wrapper too.
    ///
    /// `EquatableView` and `_MemoizedRow` are one implementation now
    /// (`renderValueMemoized`), and the reason they are is that written twice
    /// they drifted: `_MemoizedRow` was missing the uncomparable-environment
    /// clause its twin had. This is what would notice a wrapper that stopped
    /// going through the shared path — the ten conditions asserted once are
    /// asserted for both.
    ///
    /// The row arm keys on a CONSTANT element, so the memo always wants to hit
    /// and only the gate can stop it. Keyed on anything that varied, a decline
    /// would be indistinguishable from a miss.
    @Test(
        "Every gate condition holds through both memo wrappers",
        arguments: [0, 1], 0..<11)
    func gateHoldsThroughBothWrappers(wrapper: Int, condition: Int) {
        @MainActor func wrapped<V: View & Equatable>(_ inner: V) -> AnyView {
            wrapper == 0
                ? AnyView(inner.equatable())
                : AnyView(_MemoizedRow(element: AlwaysEqual(), content: inner))
        }
        let (name, view, shouldStore): (String, AnyView, Bool) =
            switch condition {
            case 0: ("inert (the control)", wrapped(EffectLeaf(label: "inert") { $0 }), true)
            case 1:
                (
                    "an effect ABOVE the boundary",
                    AnyView(wrapped(EffectLeaf(label: "x") { $0 }).onAppear {}), true
                )
            case 2: ("onAppear inside", wrapped(EffectLeaf(label: "x") { $0.onAppear {} }), false)
            case 3: ("task inside", wrapped(EffectLeaf(label: "x") { $0.task {} }), false)
            case 4:
                (
                    "onChange inside",
                    wrapped(EffectLeaf(label: "x") { $0.onChange(of: 1) { _, _ in } }), false
                )
            case 5:
                (
                    "a key handler inside (replayed on a hit)",
                    wrapped(EffectLeaf(label: "x") { $0.onKeyPress { _ in false } }), true
                )
            case 6:
                (
                    "a FOCUSED focus registration inside",
                    wrapped(EffectLeaf(label: "x") { $0.focusable() }), false
                )
            case 7:
                (
                    "an ACTIVE focus section inside",
                    wrapped(EffectLeaf(label: "x") { $0.focusSection("rows") }), false
                )
            case 8:
                (
                    "a preference write inside",
                    wrapped(
                        EffectLeaf(label: "x") { $0.preference(key: CountKey.self, value: 1) }),
                    false
                )
            case 9:
                (
                    "an UNFOCUSED focus registration inside (replayed on a hit)",
                    AnyView(
                        VStack {
                            Text("ahead").focusable()
                            wrapped(EffectLeaf(label: "x") { $0.focusable() })
                        }), true
                )
            default:
                (
                    "a Button's keyboard shortcut inside (replayed on a hit)",
                    AnyView(
                        VStack {
                            Text("ahead").focusable()
                            wrapped(
                                EffectLeaf(label: "x") { _ in
                                    Button("go") {}.keyboardShortcut("s", modifiers: [])
                                })
                        }), true
                )
            }
        let arm = wrapper == 0 ? ".equatable()" : "_MemoizedRow"
        #expect(
            storesBuffer { view } == shouldStore,
            "\(arm): \(name) should \(shouldStore ? "store" : "decline")")
    }

    @Test("A measure pass never stores")
    func measurePassNeverStores() {
        // The buffer a measure pass produces is incomplete — interactive
        // controls suppress their hit-test regions while measuring — and it is
        // produced at a different size. Storing it would let the same frame's
        // render walk hit on it, which is how upstream's first-frame effect loss
        // happened: the subtree's effects never mounted at all.
        var context = self.context()
        context.isMeasuring = true
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        _ = renderToBuffer(EffectLeaf(label: "inert") { $0 }.equatable(), context: context)
        cache.removeInactive()
        #expect(cache.isEmpty)
    }
}
