//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemeStyleMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Why these tests exist
//
// `ThemeModifier` notes the theme's inputs into the render cache so a memoized
// subtree is dropped when the ink above it moves — the palette, the tint, the
// appearance, the scoped entries, and the three control styles a theme can
// install. The styles were noted as a METATYPE: `ObjectIdentifier(type(of:))`,
// so two styles of one type always compared equal however differently they
// draw. A style that HOLDS what it draws therefore changed under a memoized
// subtree with nothing to notice, and the buffer painted by the one before was
// served.
//
// The same asymmetry `5819aed2` fixed for the palette, on the slots beside it:
// `.buttonStyle(_:)` is an ordinary `EnvironmentModifier`, which notes the style
// ITSELF, so the same two styles through THAT door have always cleared. It is
// the door that was wrong, not the style.
//
// These live here rather than beside the other theme cases in
// `RenderCacheContractTests` because that file is at SwiftLint's `file_length`
// limit — 596 of 600 countable lines.

/// A caller's own button style with no `Equatable` conformance, holding a value
/// it draws from — the shape an app is free to write, and one nothing can
/// compare more finely than by its type.
private struct UncomparableButtonStyle: ButtonStyle {
    let badge: String

    func makeBody(configuration: Configuration) -> some View {
        Text(verbatim: badge)
    }
}

/// A second one, so a swap between two styles that can only be told apart by
/// their TYPE has two types to tell apart.
private struct OtherUncomparableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Text(verbatim: configuration.label)
    }
}

/// A leaf that renders its text and nothing else — safe to memoize (no
/// hit-test regions, no overlays, no volatile reads). ``CacheLeaf``'s twin in
/// `RenderCacheContractTests`, which is `private` to that file.
private struct StyleMemoLeaf: View, Equatable {
    let text: String

    var body: some View {
        Text(text)
    }
}

@MainActor
@Suite("A theme's control styles, and the memo below them", .serialized)
struct ThemeStyleMemoTests {
    /// A context with a fresh, test-local cache, built by hand for the reason
    /// `RenderCacheContractTests` builds one: these assert cache statistics, so
    /// nothing else may touch this cache.
    private func context() -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tuiContext)
        environment.renderCache = RenderCache()
        environment.preferenceStorage = tuiContext.preferences
        return RenderContext(
            availableWidth: 24, availableHeight: 6, environment: environment,
            identity: ViewIdentity(path: "Root"))
    }

    /// One frame of the real loop's cache lifecycle. The frame boundary is
    /// load-bearing rather than ceremony: `noteAppliedEnvironment` answers every
    /// visit within one pass from its short circuit, so two renders without one
    /// between them are one pass and compare nothing.
    @discardableResult
    private func frame(_ context: RenderContext, _ view: some View) -> FrameBuffer {
        let cache = context.environment.renderCache!
        cache.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        cache.removeInactive()
        return buffer
    }

    private func themed(_ style: some ButtonStyle) -> Theme {
        Theme(palette: SystemPalette(.green), buttonStyle: style)
    }

    /// The control is what makes this the theme's bug rather than the style's,
    /// and it is in the same test for the same reason the palette case keeps
    /// its own: the two doors take the identical pair of styles, and only one of
    /// them used to notice.
    @Test("A theme's button style changing its stored value clears the subtree below it")
    func themeStyleStorageChangeClearsCaching() {
        let byTheme = context()
        let themeCache = byTheme.environment.renderCache!
        frame(byTheme, StyleMemoLeaf(text: "hi").equatable().theme(themed(_ColorSwatchButtonStyle(color: .red))))
        #expect(!themeCache.isEmpty, "a memo under a theme's style must still store")
        let beforeTheme = themeCache.stats
        frame(byTheme, StyleMemoLeaf(text: "hi").equatable().theme(themed(_ColorSwatchButtonStyle(color: .blue))))
        let themeDelta = themeCache.stats.delta(since: beforeTheme)
        #expect(
            themeDelta.hits == 0,
            "a theme whose style's stored colour changed served the old buffer: \(themeDelta)")

        let byModifier = context()
        let modifierCache = byModifier.environment.renderCache!
        frame(
            byModifier,
            StyleMemoLeaf(text: "hi").equatable().buttonStyle(_ColorSwatchButtonStyle(color: .red)))
        let beforeModifier = modifierCache.stats
        frame(
            byModifier,
            StyleMemoLeaf(text: "hi").equatable().buttonStyle(_ColorSwatchButtonStyle(color: .blue)))
        let modifierDelta = modifierCache.stats.delta(since: beforeModifier)
        #expect(
            modifierDelta.hits == 0,
            "control: .buttonStyle(_:) notes the style itself, and always cleared: \(modifierDelta)")
    }

    /// The floor the metatype token did give, and which a comparison by value
    /// must not lose: a theme that swaps one style for another of a DIFFERENT
    /// type still clears, whether or not either can be compared any further.
    ///
    /// The second pair is the one that can ONLY be told apart by type, and the
    /// arm that caught the first attempt at this: written as a generic over
    /// `any ButtonStyle`, the wrapper's `type(of:)` answered the existential
    /// metatype for both, so two unrelated styles compared equal and nothing
    /// cleared. The built-in pair above passed all the same, because their
    /// `Equatable` conformance was answering instead.
    @Test("A theme swapping the type of a style it installs still clears")
    func themeStyleTypeChangeClearsCaching() {
        func typeSwapClears(
            _ first: some ButtonStyle, _ second: some ButtonStyle, _ spelling: String
        ) {
            let shared = context()
            let cache = shared.environment.renderCache!
            frame(shared, StyleMemoLeaf(text: "hi").equatable().theme(themed(first)))
            let before = cache.stats
            frame(shared, StyleMemoLeaf(text: "hi").equatable().theme(themed(second)))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits == 0, "\(spelling) served the old buffer: \(delta)")
        }

        typeSwapClears(PlainButtonStyle(), PrimaryButtonStyle(), "two built-in styles")
        typeSwapClears(
            UncomparableButtonStyle(badge: "x"), OtherUncomparableButtonStyle(),
            "two styles that can only be told apart by type")
    }

    /// The other direction, and the one a careless fix breaks in two ways. A
    /// `.theme(…)` rebuilds the styles it installs on every frame, so equal
    /// values must compare equal; and a style an app writes need not be
    /// `Equatable` at all, in which case the comparison has nothing finer than
    /// the type to go on and must answer "unchanged" rather than clearing the
    /// subtree on every frame. Only the clear count can catch either — no
    /// comparison of the output would.
    @Test("A theme's styles rebuilt unchanged do not defeat the memo below them")
    func unchangedThemeStylesStillMemoize() {
        func stillMemoizes(_ style: @autoclosure () -> some ButtonStyle, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!
            func view() -> some View {
                StyleMemoLeaf(text: "hi").equatable().theme(themed(style()))
            }
            frame(shared, view())
            let before = cache.stats.subtreeClears
            frame(shared, view())
            #expect(
                cache.stats.subtreeClears == before,
                "\(spelling) rebuilt unchanged cleared the subtree anyway")
        }

        stillMemoizes(_ColorSwatchButtonStyle(color: .red), "a style compared by value")
        stillMemoizes(UncomparableButtonStyle(badge: "x"), "a style that cannot be compared")
    }
}
