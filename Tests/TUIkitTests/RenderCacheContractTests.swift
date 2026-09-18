//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheContractTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Fixtures

/// A leaf that renders its text and nothing else — safe to memoize (no
/// hit-test regions, no overlays, no volatile reads).
private struct CacheLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
    }
}

/// An `.equatable()` view containing a *nested* `.equatable()` view. The outer
/// value can change while the inner one does not, which is the whole point:
/// the inner subtree should still be able to answer from cache.
private struct CacheOuter: View, Equatable {
    let title: String
    let leaf: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
            CacheLeaf(text: leaf).equatable()
        }
    }
}

/// The `_MemoizedRow` twin of ``CacheOuter``: `ForEach` wraps every
/// `Equatable` element row in one of these, so an outer row containing an
/// inner one is the ordinary nested-`ForEach` shape, not a contrivance.
@MainActor
private func nestedMemoizedRow(_ title: String) -> some View {
    _MemoizedRow(
        element: title,
        content: VStack(spacing: 0) {
            Text(title)
            _MemoizedRow(element: "inner", content: Text("static"))
        })
}

/// A leaf whose colour comes from the *palette accent* rather than from a
/// literal, so `.tint(_:)` applied above it changes what it renders.
private struct AccentLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text).foregroundStyle(.palette.accent)
    }
}

/// A memoizable view whose whole appearance comes from the ``LabelStyle`` in
/// force above it — the two halves are plain views, so neither depends on an
/// SF Symbol resolving on the host.
///
/// Like ``CachePicker`` and unlike the rest of these fixtures, what this draws
/// is readable straight out of the buffer: `.titleOnly` shows `Inbox` and
/// `.iconOnly` shows `*`, with no character in common. That is what lets the label's safety arm assert the
/// drawing rather than a hit count.
private struct CacheLabel: View, Equatable {
    var body: some View {
        Label { Text(verbatim: "Inbox") } icon: { Text(verbatim: "*") }
    }
}

/// A real ``Picker``, whose whole presentation comes from the ``PickerStyle`` in
/// force above it.
///
/// Like ``CacheLabel``, what this draws is readable straight out of the buffer,
/// and the two presentations share no line: `.radioGroup` draws a row per
/// option, `.menu` one collapsed row. Unlike ``CacheLabel`` it is the shipped
/// control rather than a stand-in for one — a picker memoizes, so the safety arm
/// can swap the style under a buffer that is genuinely a picker's.
private struct CachePicker: View, Equatable {
    var body: some View {
        Picker(selection: .constant(1)) {
            Text(verbatim: "One").tag(1)
            Text(verbatim: "Two").tag(2)
        } label: {
            Text(verbatim: "N")
        }
    }
}

/// A real ``Form``, whose whole layout comes from the ``FormStyle`` in force
/// above it.
///
/// Like ``CachePicker`` it is the shipped control rather than a stand-in for
/// one, and what separates the two built-in layouts is readable straight out of
/// the buffer without matching any text: ``GroupedFormStyle`` draws each section
/// as a bordered box, ``ColumnsFormStyle`` draws no border at all. So a stale
/// serve across that swap would leave a box drawn around a form that no longer
/// asks for one.
private struct CacheForm: View, Equatable {
    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Name", value: "Alice")
            }
        }
    }
}

/// A caller's own menu style with no `Equatable` conformance, so nothing can
/// tell whether the value it injects has changed.
private struct UncomparableMenuStyle: MenuStyle {
    let token = 0

    @MainActor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// A value with no `Equatable` conformance, so a change under it is
/// undetectable by construction.
private struct Incomparable {
    let token = 0
}

private struct IncomparableProbeKey: EnvironmentKey {
    static let defaultValue: Incomparable? = nil
}

extension EnvironmentValues {
    fileprivate var incomparableProbe: Incomparable? {
        get { self[IncomparableProbeKey.self] }
        set { self[IncomparableProbeKey.self] = newValue }
    }
}

private struct ComparableProbeKey: EnvironmentKey {
    static let defaultValue = "-"
}

extension EnvironmentValues {
    fileprivate var comparableProbe: String {
        get { self[ComparableProbeKey.self] }
        set { self[ComparableProbeKey.self] = newValue }
    }
}

/// Renders whatever `comparableProbe` holds — and compares equal to any other
/// instance, so a memo can only be broken by the environment digest.
private struct ProbeEcho: View, Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

    @Environment(\.comparableProbe) private var probe

    var body: some View { Text(probe) }
}

// MARK: - Tests

/// The two `EquatableView`/`RenderCache` contracts upstream fixed in PR #64
/// (`e84738728c`, `c48e35d78d`). Both reproduced here; one is fixed.
///
/// - **Nested entry liveness** — fixed. These assert the contract, and every one
///   of them fails on the pre-fix code, where an outer hit left the cache with
///   one entry instead of two.
/// - **Environment in the cache key** — fixed, but not by putting the
///   environment in the key. `EnvironmentModifier` compares the value it applied
///   here last pass and clears the subtree when it differs, which costs one
///   comparison per modifier instead of a fingerprint per lookup. A value that
///   is not `Equatable` cannot be compared, so it declines caching instead.
@MainActor
@Suite("RenderCache contracts", .serialized)
struct RenderCacheContractTests {

    /// A context with a fresh, test-local cache. Built by hand rather than via
    /// `makeRenderContext` because these tests assert absolute entry counts and
    /// cache statistics: nothing else may touch this cache.
    private func context(width: Int = 24, height: Int = 6) -> RenderContext {
        let tuiContext = TUIContext()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tuiContext)
        env.renderCache = RenderCache()
        env.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: env,
            identity: ViewIdentity(path: "Root")
        )
    }

    /// One frame of the real loop's cache lifecycle: drain invalidations, walk,
    /// then collect identities that were not visited.
    @discardableResult
    private func frame(_ context: RenderContext, _ view: some View) -> FrameBuffer {
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        cache.removeInactive()
        return buffer
    }

    // MARK: - Nested entry liveness (upstream `e84738728c`)

    @Test("A nested entry survives a cache hit at the .equatable() above it")
    func nestedEntrySurvivesOuterHit() {
        let context = self.context()
        let cache = context.environment.renderCache!

        // Frame 1 — both miss and both store.
        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        #expect(cache.count == 2, "outer and inner should both be cached")

        // Frame 2 — the outer value is unchanged, so it hits and the inner view
        // is never walked. Nothing below reaches `markActive`, so the entry
        // survives only because the hit declared its subtree retained.
        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        #expect(cache.count == 2, "the nested entry is still live and must not be collected")

        // Frame 3 — the outer value changes, so the subtree is walked again. The
        // inner value did not, so it answers from cache instead of re-rendering.
        let before = cache.stats
        frame(context, CacheOuter(title: "two", leaf: "static").equatable())
        let delta = cache.stats.delta(since: before)

        #expect(delta.hits >= 1, "the unchanged inner subtree is served from cache")
    }

    @Test("A nested entry survives a cache hit at the _MemoizedRow above it")
    func nestedRowEntrySurvivesOuterHit() {
        let context = self.context()
        let cache = context.environment.renderCache!

        // Frame 1 — both miss and both store.
        frame(context, nestedMemoizedRow("one"))
        #expect(cache.count == 2, "outer and inner row should both be cached")

        // Frame 2 — the outer element is unchanged, so it hits and nothing
        // below it is walked. Only the hit's subtree retention keeps the inner
        // entry alive; `sizeThatFits` deliberately marks nothing, so the
        // measure walk cannot rescue it either.
        frame(context, nestedMemoizedRow("one"))
        #expect(cache.count == 2, "the nested row entry is still live and must not be collected")

        // Frame 3 — the outer element changes, so the subtree is walked again.
        // The inner row did not change, so it answers from cache.
        let before = cache.stats
        frame(context, nestedMemoizedRow("two"))
        let delta = cache.stats.delta(since: before)

        #expect(delta.hits >= 1, "the unchanged inner row is served from cache")
    }

    @Test("The nested entry survives an arbitrary run of outer hits")
    func nestedEntrySurvivesRepeatedHits() {
        let context = self.context()
        let cache = context.environment.renderCache!

        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        for _ in 0..<5 {
            frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        }

        // Retention is declared per pass, so it has to be re-declared on every
        // hit frame — one missed frame and the entry is gone.
        #expect(cache.count == 2)
    }

    @Test("Retention lapses when the subtree leaves the tree")
    func retentionLapsesWhenSubtreeGoes() {
        let context = self.context()
        let cache = context.environment.renderCache!

        frame(context, CacheOuter(title: "one", leaf: "static").equatable())
        #expect(cache.count == 2)

        // Render something else at the same root: neither entry is visited and
        // nothing declares them retained, so both are collected. Retention keeps
        // live subtrees, it does not leak dead ones.
        frame(context, Text("unrelated"))
        #expect(cache.isEmpty)
    }

    // MARK: - Environment in the cache key (upstream `c48e35d78d`)

    @Test("A scoped .foregroundStyle change above an .equatable() re-renders it")
    func scopedStyleChangeIsNotServedStale() {
        let base = context()

        // The truth for each style, rendered with its own cache so neither can
        // answer for the other. If these two matched, the test below would prove
        // nothing — which is the precondition, asserted rather than assumed.
        let redTruth = frame(
            base.isolatingRenderCache(), CacheLeaf(text: "hi").equatable().foregroundStyle(.red))
        let blueTruth = frame(
            base.isolatingRenderCache(), CacheLeaf(text: "hi").equatable().foregroundStyle(.blue))
        #expect(
            redTruth.lines != blueTruth.lines,
            "precondition: .foregroundStyle must change the rendered output"
        )

        // One cache, same view value, style changed above the memoization
        // boundary. Nothing in the cache key sees the difference — the modifier
        // has to notice and clear.
        let shared = context()
        frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.red))
        let served = frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.blue))

        #expect(served.lines == blueTruth.lines, "the new style must be rendered")
        #expect(served.lines != redTruth.lines, "not the buffer from the old one")
    }

    /// `.theme(_:)` is the same environment application as the two above, and
    /// was the one that did none of the bookkeeping: it assigned the appearance,
    /// palette, tint, control styles and style cascade straight onto the child
    /// context and told the cache nothing. A memoized subtree below a theme that
    /// changed therefore served the buffer painted in the OLD palette.
    ///
    /// What it notes is the theme's INPUTS — the base palette and the tint on
    /// slots of their own — never the `TintedPalette` the two of them resolve
    /// to. The next case pins the other half, that memoization still WORKS
    /// under a theme that did not change.
    @Test("A .theme change above an .equatable() re-renders it")
    func scopedThemeChangeIsNotServedStale() {
        let base = context()
        let green = Theme(palette: SystemPalette(.green))
        let blue = Theme(palette: SystemPalette(.blue))

        let greenTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().theme(green))
        let blueTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().theme(blue))
        #expect(
            greenTruth.lines != blueTruth.lines,
            "precondition: the two themes must differ on screen")

        let shared = context()
        frame(shared, AccentLeaf(text: "hi").equatable().theme(green))
        let served = frame(shared, AccentLeaf(text: "hi").equatable().theme(blue))
        #expect(served.lines == blueTruth.lines, "the new theme must be rendered")
        #expect(served.lines != greenTruth.lines, "not the buffer from the old one")
    }

    /// The other half, and the one a careless fix breaks: an UNCHANGED theme
    /// must still let the subtree memoize. A comparison that answered "changed"
    /// for an equal rebuild — and `.theme(…)` rebuilds its `TintedPalette` on
    /// every frame — would clear the subtree on every frame, which no output
    /// comparison would catch, only the clear count.
    @Test("An unchanged theme does not defeat the memo below it")
    func unchangedThemeStillMemoizes() {
        let shared = context()
        // A TINTED theme: the resolved palette is the incomparable one.
        let theme = Theme(palette: SystemPalette(.green), tint: .red)
        frame(shared, AccentLeaf(text: "hi").equatable().theme(theme))
        let before = shared.renderCache?.stats.subtreeClears ?? 0
        frame(shared, AccentLeaf(text: "hi").equatable().theme(theme))
        let after = shared.renderCache?.stats.subtreeClears ?? 0
        #expect(after == before, "an unchanged theme cleared the subtree anyway")
    }

    /// `.tint(_:)` swaps the environment palette for a `TintedPalette`, which is
    /// an environment application like any other: a memoized subtree below it
    /// keys on the view value, which does not change when the tint above it
    /// does. Same mechanism as `.foregroundStyle` above, different modifier.
    @Test("A scoped .tint change above an .equatable() re-renders it")
    func scopedTintChangeIsNotServedStale() {
        let base = context()

        let redTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().tint(.red))
        let blueTruth = frame(
            base.isolatingRenderCache(), AccentLeaf(text: "hi").equatable().tint(.blue))
        #expect(
            redTruth.lines != blueTruth.lines,
            "precondition: .tint must change the rendered output"
        )

        let shared = context()
        frame(shared, AccentLeaf(text: "hi").equatable().tint(.red))
        let served = frame(shared, AccentLeaf(text: "hi").equatable().tint(.blue))

        #expect(served.lines == blueTruth.lines, "the new tint must be rendered")
        #expect(served.lines != redTruth.lines, "not the buffer from the old one")
    }

    @Test("An unchanged tint still memoizes")
    func unchangedTintStillHits() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, AccentLeaf(text: "hi").equatable().tint(.red))
        let before = cache.stats
        frame(shared, AccentLeaf(text: "hi").equatable().tint(.red))

        // Noticing the *change* rather than keying the cache on the palette: a
        // stable tint must still cost a comparison, not a miss.
        #expect(cache.stats.delta(since: before).hits >= 1)
    }

    /// Two modifiers injecting the SAME key path share one identity (a
    /// `Renderable` adds no child identity). With the slot keyed only on
    /// (identity, keyPath), the outer one answered for both and the inner
    /// one's changes were never compared.
    @Test("A changed inner value is seen past an unchanged outer one, same key path")
    func chainedSameKeyPathInnerChangeIsSeen() {
        let shared = context()

        // The INNER application (closest to the view) wins, so the leaf shows
        // it; the OUTER stays constant so its comparison says "unchanged"
        // every frame.
        frame(
            shared,
            ProbeEcho().equatable()
                .environment(\.comparableProbe, "aaa")
                .environment(\.comparableProbe, "outer"))
        let served = frame(
            shared,
            ProbeEcho().equatable()
                .environment(\.comparableProbe, "bbb")
                .environment(\.comparableProbe, "outer"))

        #expect(
            served.lines.first?.stripped == "bbb",
            "the inner change was eaten by the outer slot: \(served.lines.map(\.stripped))")
    }

    @Test("An unchanged style still memoizes")
    func unchangedStyleStillHits() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.red))
        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().foregroundStyle(.red))

        // The point of detecting the *change* rather than keying on the
        // environment: a stable style costs a comparison, not a miss.
        #expect(cache.stats.delta(since: before).hits >= 1)
    }

    @Test("A style change keeps the memoized sizes; any other environment change drops them")
    func scopedStyleChangeKeepsTheSizeMemo() {
        let shared = context()
        let cache = shared.environment.renderCache!
        let proposal = ProposedSize(width: nil, height: nil)

        // A pass per measurement, as the real loop does. Change detection short
        // circuits after the first visit *within* a pass — two-pass layout
        // visits one modifier many times per frame and the value it applies
        // cannot change between those visits, since structural identity gives
        // one modifier one value. Measuring twice inside a single pass would be
        // testing something that cannot happen.
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().foregroundStyle(.red),
            proposal: proposal, context: shared)
        let before = cache.stats
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().foregroundStyle(.blue),
            proposal: proposal, context: shared)

        // A paint is ink: it moves no cell, so the size measured under red is
        // the size under blue, and the measure walks keep serving it while
        // the render walk re-inks. (A ramp that rotates every frame used to
        // re-measure every row on every walk.)
        #expect(cache.stats.delta(since: before).hits >= 1, "\(cache.stats.delta(since: before))")

        // A value that CAN move cells still clears them: measurement runs
        // before rendering, so if only the render walk noticed, a change that
        // altered the size would already have been laid out wrong.
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().environment(\.comparableProbe, "one"),
            proposal: proposal, context: shared)
        let beforeProbe = cache.stats
        cache.beginRenderPass()
        _ = measureChild(
            CacheLeaf(text: "hi").equatable().environment(\.comparableProbe, "two"),
            proposal: proposal, context: shared)
        #expect(cache.stats.delta(since: beforeProbe).hits == 0, "\(cache.stats.delta(since: beforeProbe))")
    }

    @Test("A non-Equatable environment value declines caching rather than risking it")
    func incomparableEnvironmentDeclinesCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // `Incomparable` cannot be compared, so no change can ever be detected
        // below it — the only sound answer is not to memoize there.
        frame(shared, CacheLeaf(text: "hi").equatable().environment(\.incomparableProbe, Incomparable()))
        #expect(cache.isEmpty, "nothing may be stored under an uncomparable environment value")
    }

    @Test("A ForEach row declines it too, not just an .equatable() view")
    func incomparableEnvironmentDeclinesRowCaching() {
        // The same hazard, through the other memo. `_MemoizedRow` carried the
        // same five-condition gate as `EquatableView` minus this one clause, so
        // a row under an uncomparable value cached a buffer nothing could
        // invalidate. Both go through `RenderCache.isStorable` now.
        let shared = context()
        let cache = shared.environment.renderCache!
        frame(
            shared,
            VStack(spacing: 0) {
                ForEach(["a", "b"], id: \.self) { CacheLeaf(text: $0) }
            }
            .environment(\.incomparableProbe, Incomparable()))
        #expect(cache.isEmpty, "a row cached under an uncomparable environment value")
    }

    @Test("A built-in menu style does not stop the subtree below it caching")
    func builtInMenuStyleKeepsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // `.menuStyle(_:)` injects an `any MenuStyle`, and what decides whether
        // a memo below it may store is the DYNAMIC type's `Equatable`
        // conformance. The built-in styles carry one; without it every memo
        // under a styled menu declined, which is every row of an inline menu.
        frame(shared, CacheLeaf(text: "hi").equatable().menuStyle(.inline))
        #expect(!cache.isEmpty, "a memo under a built-in menu style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().menuStyle(.inline))
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
    }

    @Test("A built-in button style does not stop the subtree below it caching")
    func builtInButtonStyleKeepsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // The same clause as the menu case, on the key path a terminal app
        // reaches for far more often: `.buttonStyle(_:)` injects an
        // `any ButtonStyle`, and what decides whether a memo below it may store
        // is the DYNAMIC type's `Equatable` conformance. Without one on the
        // built-in styles, every memo under a styled button — or under a
        // container that styles the buttons it holds — declined.
        frame(shared, CacheLeaf(text: "hi").equatable().buttonStyle(.plain))
        #expect(!cache.isEmpty, "a memo under a built-in button style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().buttonStyle(.plain))
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
    }

    @Test("Neither built-in list style stops the subtree below it caching")
    func builtInListStyleKeepsCaching() {
        // The same clause once more, on a container key path rather than a
        // control's: `.listStyle(_:)` injects an `any ListStyle`, and what
        // decides whether a memo below it may store is the DYNAMIC type's
        // `Equatable` conformance. Without one the refusal covered every row of
        // the styled list, and `_ListCore`'s own hug-width size memo with them.
        //
        // Both built-ins are asked, in their own contexts, because conforming
        // only one would leave the other's lists exactly as they were.
        func styleStoresAndServes<S: ListStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().listStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().listStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.plain, ".listStyle(.plain)")
        styleStoresAndServes(.insetGrouped, ".listStyle(.insetGrouped)")
    }

    @Test("No built-in toggle style stops the subtree below it caching")
    func builtInToggleStyleKeepsCaching() {
        // The same clause again, on the control key path an app reaches for
        // whenever it spells a toggle differently: `.toggleStyle(_:)` injects an
        // `any ToggleStyle`, and what decides whether a memo below it may store
        // is the DYNAMIC type's `Equatable` conformance. Without one, every memo
        // under a `.toggleStyle(...)` declined — the toggle's own label, and
        // whatever `Toggle/toggleContent(_:)` puts under it.
        //
        // All three built-ins are asked, in their own contexts, because
        // conforming only one would leave the others exactly as they were.
        func styleStoresAndServes<S: ToggleStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".toggleStyle(.automatic)")
        styleStoresAndServes(.checkbox, ".toggleStyle(.checkbox)")
        styleStoresAndServes(.switch, ".toggleStyle(.switch)")
    }

    /// The safety half, in the shape this key path makes it take.
    ///
    /// None of the three toggle styles holds anything, so there is no stored
    /// value to change under a served buffer the way ``_ColorSwatchButtonStyle``'s
    /// colour can. What varies here is the TYPE: `_ToggleCore` picks its branch
    /// with `toggleStyle is SwitchToggleStyle` and nothing else, so a switch and a
    /// checkbox at the same slot really do draw differently. The only thing
    /// standing between that and a stale serve is the downcast in
    /// `Equatable.isEqual(to:)` — without it a comparison across the swap could
    /// answer "equal" and hand the subtree the buffer drawn for the other style.
    @Test("Swapping one built-in toggle style for another clears the subtree below it")
    func toggleStyleTypeChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(.checkbox))
        #expect(!cache.isEmpty, "a memo under a built-in toggle style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(.switch))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a checkbox replaced by a switch must not serve the checkbox's buffer: \(delta)")
    }

    @Test("No built-in label style stops the subtree below it caching")
    func builtInLabelStyleKeepsCaching() {
        // The same clause once more, on the key path a whole screen reaches
        // for at once: `.labelStyle(_:)` injects an `any LabelStyle`, and what
        // decides whether a memo below it may store is the DYNAMIC type's
        // `Equatable` conformance. Without one, a toolbar that drops to
        // `.iconOnly` when the terminal narrows — the case the protocol's own
        // documentation offers — turned the cache off for everything under it.
        //
        // All four built-ins are asked, in their own contexts, because
        // conforming only one would leave the others exactly as they were.
        func styleStoresAndServes<S: LabelStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().labelStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().labelStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".labelStyle(.automatic)")
        styleStoresAndServes(.titleOnly, ".labelStyle(.titleOnly)")
        styleStoresAndServes(.iconOnly, ".labelStyle(.iconOnly)")
        styleStoresAndServes(.titleAndIcon, ".labelStyle(.titleAndIcon)")
    }

    /// The safety half, asked of the drawing instead of the statistics.
    ///
    /// Every other style in this series contributes to a buffer some `_*Core`
    /// assembles, so the nearest an in-process test can get to "the wrong style
    /// was served" is `hits == 0`. A label style contributes the composition
    /// itself, and the two halves here share no character: if the downcast in
    /// `Equatable.isEqual(to:)` ever answered "equal" across a type change, the
    /// frame below would keep the buffer reading `Inbox` while the tree now says
    /// `.iconOnly`. So this asks the buffer.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them rather than on its own.
    @Test("Swapping one built-in label style for another redraws the label below it")
    func labelStyleTypeChangeRedrawsTheLabel() {
        let shared = context()
        let cache = shared.environment.renderCache!

        func drawn(_ buffer: FrameBuffer) -> String {
            buffer.lines.map(\.stripped).joined().trimmingCharacters(in: .whitespaces)
        }

        let titled = frame(shared, CacheLabel().equatable().labelStyle(.titleOnly))
        #expect(drawn(titled) == "Inbox", "the title-only style draws the title")
        #expect(!cache.isEmpty, "a memo under a built-in label style must store")

        // The premise, without which the swap below would pass for a label that
        // is never served from cache at all: the SAME style twice is a hit, so
        // there really is a stored buffer for the swap to have to invalidate.
        let before = cache.stats
        frame(shared, CacheLabel().equatable().labelStyle(.titleOnly))
        let repeated = cache.stats.delta(since: before)
        #expect(repeated.hits >= 1, "an unchanged label style must serve the memo: \(repeated)")

        let iconed = frame(shared, CacheLabel().equatable().labelStyle(.iconOnly))
        #expect(
            drawn(iconed) == "*",
            "a title-only label was served under .iconOnly: \(drawn(iconed))")
    }

    @Test("Neither built-in text field style stops the subtree below it caching")
    func builtInTextFieldStyleKeepsCaching() {
        // The same clause once more: `.textFieldStyle(_:)` injects an
        // `any TextFieldStyle`, and what decides whether a memo below it may
        // store is the DYNAMIC type's `Equatable` conformance. Without one the
        // refusal covered everything under the modifier — Example's Text Input
        // page puts two fields and their surrounding rows under a
        // `.textFieldStyle(.plain)` (TextInputPage.swift:130 and :139), and none
        // of it could cache.
        //
        // What this is NOT, whatever this comment and `684785f1`'s message said
        // until the count was taken: "the one key path in this series an app in
        // this repo already writes". Example writes EIGHT of the nine key paths
        // this clause has been fixed on, and only `.labelStyle(_:)` goes
        // unwritten. Two of them are in the same position as this one — no
        // framework-internal injection anywhere in `Sources/TUIkit`, so the
        // refusal fires only where the app itself writes the modifier — and both
        // were fixed BEFORE it: `.listStyle(_:)` (ListPage.swift:269 and :284,
        // `d76f8d15`) and `.toggleStyle(_:)` (TogglePage.swift:90-92 and
        // :127-128, `9feef329`). The picker test below says the same of its own
        // key path, at thirteen sites. What is true of this one is narrower and
        // is all the subject claims: `.plain` is the only text field style the
        // app sets.
        //
        // Both built-ins are asked, in their own contexts, because conforming
        // only one would leave the other's fields exactly as they were.
        func styleStoresAndServes<S: TextFieldStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".textFieldStyle(.automatic)")
        styleStoresAndServes(.plain, ".textFieldStyle(.plain)")
    }

    /// The safety half, in the shape this key path makes it take.
    ///
    /// Neither text field style holds anything, so there is no stored value to
    /// change under a served buffer the way ``_ColorSwatchButtonStyle``'s colour
    /// can. What varies here is the TYPE, and it varies in both directions at
    /// once: `drawsFieldSurface` decides whether `FieldChrome` paints a surface
    /// and caps, and whether it is two cells wide or none — so a swap changes
    /// what a field DRAWS and what it MEASURES. The only thing standing between
    /// that and a stale serve, of a buffer or of a size, is the downcast in
    /// `Equatable.isEqual(to:)`.
    ///
    /// Asked of the statistics rather than of a drawing, because a text field
    /// style contributes to a buffer `_TextFieldCore` assembles rather than
    /// composing the view the way a ``LabelStyle`` does: a memo below the
    /// modifier holds ordinary content, so `hits == 0` is as near as an
    /// in-process test gets to "the wrong style was served".
    @Test("Swapping one built-in text field style for another clears the subtree below it")
    func textFieldStyleTypeChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(.automatic))
        #expect(!cache.isEmpty, "a memo under a built-in text field style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(.plain))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a capped field replaced by a plain one must not serve the capped buffer: \(delta)")
    }

    @Test("No built-in picker style stops the subtree below it caching")
    func builtInPickerStyleKeepsCaching() {
        // The same clause once more, on the key path with the most styles in
        // it: `.pickerStyle(_:)` injects an `any PickerStyle`, and what decides
        // whether a memo below it may store is the DYNAMIC type's `Equatable`
        // conformance. Without one the refusal covered everything under the
        // modifier, which in this repo's own app is whole configuration
        // panels — Example writes `.pickerStyle(...)` at thirteen places, six
        // of them on the Theme page.
        //
        // All four built-ins are asked, in their own contexts, because
        // conforming only one would leave the others exactly as they were.
        //
        // The blast radius includes the picker itself: a `Picker` is memoizable,
        // so what the missing conformance blocked first was the control its own
        // style was applied to — see the swap test below, where the same picker
        // stores and is served.
        func styleStoresAndServes<S: PickerStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().pickerStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().pickerStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".pickerStyle(.automatic)")
        styleStoresAndServes(.menu, ".pickerStyle(.menu)")
        styleStoresAndServes(.inline, ".pickerStyle(.inline)")
        styleStoresAndServes(.radioGroup, ".pickerStyle(.radioGroup)")
    }

    /// The safety half, and the one key path in this series that can be asked of
    /// a REAL control's drawing rather than of a fixture's or of the statistics.
    ///
    /// None of the four styles holds anything, so there is no stored value to
    /// change under a served buffer the way ``_ColorSwatchButtonStyle``'s colour
    /// can. What varies is the TYPE, and ``PickerStyle/resolvesToMenu`` turns it
    /// into two presentations that share no line: a menu picker is one collapsed
    /// row, a radio group is a row per option. So a stale serve here would be
    /// the wrong HEIGHT as well as the wrong glyphs, and the only thing standing
    /// between that and the frame below is the downcast in
    /// `Equatable.isEqual(to:)`.
    ///
    /// The picker is asked directly because, unlike a field or a toggle, it can
    /// be: with the conformances in place a `Picker` memoizes and is served — it
    /// was its OWN style that stopped it — so the buffer this swaps out is a
    /// real picker's, not a stand-in's.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them rather than on its own.
    @Test("Swapping one built-in picker style for another redraws the picker below it")
    func pickerStyleTypeChangeRedrawsThePicker() {
        let shared = context(width: 40, height: 8)
        let cache = shared.environment.renderCache!

        func drawn(_ buffer: FrameBuffer) -> String {
            buffer.lines
                .map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " / ")
        }

        let radio = frame(shared, CachePicker().equatable().pickerStyle(.radioGroup))
        #expect(drawn(radio) == "N ● One / ◯ Two", "the radio group draws a row per option")
        #expect(!cache.isEmpty, "a memo under a built-in picker style must store")

        // The premise, without which the swap below would pass for a picker that
        // is never served from cache at all: the SAME style twice is a hit, so
        // there really is a stored buffer for the swap to have to invalidate.
        let before = cache.stats
        frame(shared, CachePicker().equatable().pickerStyle(.radioGroup))
        let repeated = cache.stats.delta(since: before)
        #expect(repeated.hits >= 1, "an unchanged picker style must serve the memo: \(repeated)")

        let menu = frame(shared, CachePicker().equatable().pickerStyle(.menu))
        #expect(
            drawn(menu) == "N ▐ One ▾ ▌",
            "a radio group was served under .menu: \(drawn(menu))")
    }

    @Test("No built-in form style stops the subtree below it caching")
    func builtInFormStyleKeepsCaching() {
        // The same clause on the last of the eight style key paths.
        // `.formStyle(_:)` injects an `any FormStyle`, and what decides whether
        // a memo below it may store is the DYNAMIC type's `Equatable`
        // conformance. Without one the refusal covered everything under the
        // modifier — a form is a whole settings panel, so that is typically a
        // screenful.
        //
        // All three built-ins are asked, in their own contexts, because
        // conforming only one would leave the other two exactly as they were.
        func styleStoresAndServes<S: FormStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().formStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().formStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".formStyle(.automatic)")
        styleStoresAndServes(.columns, ".formStyle(.columns)")
        styleStoresAndServes(.grouped, ".formStyle(.grouped)")
    }

    /// The safety half, asked of a real ``Form``'s drawing rather than of a hit
    /// count.
    ///
    /// None of the three styles holds anything, so there is no stored value to
    /// change under a served buffer the way ``_ColorSwatchButtonStyle``'s colour
    /// can. What varies is the TYPE, and ``Form`` reads nothing off the style
    /// BUT its type — so the whole of what a swap can change is the layout that
    /// type selects, and between grouped and columns that is the section's
    /// border. A stale serve would draw a box around a form that asked for none,
    /// and the only thing standing between that and the frame below is the
    /// downcast in `Equatable.isEqual(to:)`.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them rather than on its own.
    @Test("Swapping one built-in form style for another redraws the form below it")
    func formStyleTypeChangeRedrawsTheForm() {
        let shared = context(width: 30, height: 10)
        let cache = shared.environment.renderCache!

        func isBoxed(_ buffer: FrameBuffer) -> Bool {
            buffer.lines.contains { $0.stripped.contains("\u{2500}") || $0.stripped.contains("\u{2502}") }
        }

        let grouped = frame(shared, CacheForm().equatable().formStyle(.grouped))
        #expect(isBoxed(grouped), "the grouped style draws its section as a bordered box")
        #expect(!cache.isEmpty, "a memo under a built-in form style must store")

        // The premise, without which the swap below would pass for a form that
        // is never served from cache at all: the SAME style twice is a hit, so
        // there really is a stored buffer for the swap to have to invalidate.
        let before = cache.stats
        frame(shared, CacheForm().equatable().formStyle(.grouped))
        let repeated = cache.stats.delta(since: before)
        #expect(repeated.hits >= 1, "an unchanged form style must serve the memo: \(repeated)")

        let columns = frame(shared, CacheForm().equatable().formStyle(.columns))
        #expect(!isBoxed(columns), "a grouped form was served under .columns")
    }

    /// The half the menu styles cannot pin, and the reason this is a safety
    /// question before it is a performance one.
    ///
    /// Neither built-in menu style holds anything, so `==` there is vacuous —
    /// every instance really is every other. Two of the button styles DO hold
    /// something (`_ColorSwatchButtonStyle` a `Color` and a `Bool`,
    /// `_LinkButtonStyle` a ``LinkFocusIndicator``), and both are built fresh
    /// from live binding data each frame. For those the conformance is
    /// load-bearing: a comparison that answered "equal" across a colour change
    /// would hand the swatch below it the buffer painted in the old colour, and
    /// that would convert this commit from a performance fix into a stale
    /// serve. So the store is only half of it — the invalidation is the rest.
    @Test("A button style's stored value changing clears the subtree below it")
    func buttonStyleStorageChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(
            shared,
            CacheLeaf(text: "hi").equatable()
                .buttonStyle(_ColorSwatchButtonStyle(color: .red)))
        #expect(!cache.isEmpty, "a memo under a style that holds a value must still store")

        let before = cache.stats
        frame(
            shared,
            CacheLeaf(text: "hi").equatable()
                .buttonStyle(_ColorSwatchButtonStyle(color: .blue)))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a style whose stored colour changed must not serve the old buffer: \(delta)")
    }

    @Test("A menu style that cannot be compared still declines caching")
    func uncomparableMenuStyleDeclinesCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // The other half of the same rule. A caller's style is free not to be
        // `Equatable`, and one that is not can change its stored values under a
        // served subtree with nothing to notice — so it declines, exactly as
        // any other uncomparable value does.
        frame(shared, CacheLeaf(text: "hi").equatable().menuStyle(UncomparableMenuStyle()))
        #expect(cache.isEmpty, "nothing may be stored under an uncomparable menu style")
    }

    /// The SIZE half of the same clause, on both arms, with an oracle that can
    /// see a stored size.
    ///
    /// This is the drift the two memos are now one implementation to prevent, and
    /// it went the other way: the clause was added to `EquatableView`'s size memo
    /// and MISSED on `_MemoizedRow`'s "when the buffer half was unified" — the
    /// code says so — so a Form row under an injected uncomparable value measured
    /// once and served that size forever.
    ///
    /// `cache.isEmpty` is no use as the oracle here: it and `count` inspect only
    /// the BUFFER dictionary, and `sizeEntries` has no accessor at all. A stored
    /// size shows up as a `hits` delta on the next measure of the same value, so
    /// that is what these count.
    @Test("A non-Equatable environment value declines a stored SIZE too", arguments: [false, true])
    func incomparableEnvironmentDeclinesStoredSizes(asRow: Bool) {
        let proposal = ProposedSize(width: nil, height: nil)

        // Built the same way the buffer cases above are — no `AnyView` between
        // the modifier and the wrapper, because the uncomparable flag is set
        // where the value is APPLIED and an erasure in between loses it. (The
        // first draft of this test put one there and both arms reported a stored
        // size that was not really there.)
        @MainActor func measureView(_ shared: RenderContext, uncomparable: Bool) {
            let cache = shared.environment.renderCache!
            cache.beginRenderPass()
            if uncomparable {
                _ = measureChild(
                    CacheLeaf(text: "hi").equatable()
                        .environment(\.incomparableProbe, Incomparable()),
                    proposal: proposal, context: shared)
            } else {
                _ = measureChild(
                    CacheLeaf(text: "hi").equatable(), proposal: proposal, context: shared)
            }
        }

        @MainActor func measureRow(_ shared: RenderContext, uncomparable: Bool) {
            let cache = shared.environment.renderCache!
            cache.beginRenderPass()
            let rows = VStack(spacing: 0) {
                ForEach(["a", "b"], id: \.self) { CacheLeaf(text: $0) }
            }
            if uncomparable {
                _ = measureChild(
                    rows.environment(\.incomparableProbe, Incomparable()),
                    proposal: proposal, context: shared)
            } else {
                _ = measureChild(rows, proposal: proposal, context: shared)
            }
        }

        // A FRESH cache per arm. `SizeKey` carries the identity's hash, the
        // proposal and the extents — not the environment — so a size stored by the
        // control would be served straight back to the uncomparable run, and the
        // hit counted would be the control's own entry rather than a new one.
        // (The first draft shared one cache and reported exactly that.)
        @MainActor func hitsOnSecondMeasure(uncomparable: Bool) -> Int {
            let shared = context()
            let cache = shared.environment.renderCache!
            @MainActor func measure() {
                if asRow {
                    measureRow(shared, uncomparable: uncomparable)
                } else {
                    measureView(shared, uncomparable: uncomparable)
                }
            }
            measure()
            let before = cache.stats
            measure()
            return cache.stats.delta(since: before).hits
        }

        // The control first: without it, "no hits" would pass for a memo that
        // never stores a size at all.
        #expect(
            hitsOnSecondMeasure(uncomparable: false) >= 1,
            "\(asRow ? "a row" : "an .equatable() view") stopped memoizing sizes entirely")
        #expect(
            hitsOnSecondMeasure(uncomparable: true) == 0,
            """
            a size was stored under an uncomparable environment value — nothing \
            can ever invalidate it, because the key cannot see the value
            """)
    }

    @Test("…and a ForEach row IS cached when nothing uncomparable is in force")
    func rowsAreCachedNormally() {
        // The control for the case above: without it, "cache is empty" would
        // pass for a memo that never stores anything at all.
        let shared = context()
        let cache = shared.environment.renderCache!
        frame(
            shared,
            VStack(spacing: 0) {
                ForEach(["a", "b"], id: \.self) { CacheLeaf(text: $0) }
            })
        #expect(!cache.isEmpty, "ForEach rows stopped memoizing entirely")
    }
}
