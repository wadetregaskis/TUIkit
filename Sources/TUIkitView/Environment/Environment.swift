//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Environment Modifier

/// A modifier that injects a value into the environment for child views.
///
/// `EnvironmentModifier` conforms to both `View` and ``Renderable``.
/// Because ``renderToBuffer(_:context:)`` checks `Renderable` first,
/// the `body` property below is **never called during rendering**.
/// It exists only to satisfy the `View` protocol requirement.
/// All actual work happens in `renderToBuffer(context:)`.
public struct EnvironmentModifier<Content: View, V>: View {
    // The key path, the content, then the value: the per-pass memos key a
    // view by its raw bytes, and padding is whatever the memory held before.
    // The content first left a gap before the word-aligned key path whatever
    // its size; here only a word-aligned value after an odd-sized content can
    // leave one, and most environment values are byte-aligned (flags, colours,
    // enums). `ContainerLayoutPaddingTests`.

    /// The key path to modify.
    public let keyPath: WritableKeyPath<EnvironmentValues, V>

    /// The content view.
    public let content: Content

    /// The value to inject.
    public let value: V

    /// Creates a new environment modifier.
    public init(content: Content, keyPath: WritableKeyPath<EnvironmentValues, V>, value: V) {
        self.content = content
        self.keyPath = keyPath
        self.value = value
    }
    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View {
        content
    }
}

extension EnvironmentModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Create modified environment and render content with it.
        // The modified context carries the environment through the render tree —
        // no global state sync needed.
        let uncomparable = noteEnvironmentChange(context: context)
        var modifiedEnvironment = context.environment.setting(keyPath, to: value)
        if uncomparable { modifiedEnvironment.hasUncomparableEnvironmentValue = true }
        // Derived from `context.environment` one line up, so the services are
        // the same two objects and the mirrors need no re-deriving.
        var modifiedContext = context.withDerivedEnvironment(modifiedEnvironment)
        modifiedContext.environmentApplicationDepth += 1
        return TUIkitView.renderToBuffer(content, context: modifiedContext)
    }
}

// MARK: - Cache Coherency

extension EnvironmentModifier {
    /// Drops cached buffers below this modifier when the value it injects has
    /// changed since the last pass.
    ///
    /// The render cache keys on identity, view value and size — not on the
    /// environment. That is what makes it cheap, and it is why a **scoped**
    /// style change is invisible to it: `.foregroundStyle(x)` applied *above* an
    /// `.equatable()` boundary leaves the view value identical, so the lookup
    /// hits and hands back the buffer rendered under the old style. Wrong
    /// pixels, not merely stale work.
    ///
    /// Detecting it here rather than in the key is the cheaper half of the
    /// trade: one comparison per environment modifier per pass, against a
    /// dictionary walk per memoized view per pass. The `@State`-driven case was
    /// already covered by accident (the declaring view's identity is an ancestor
    /// of the cached one, so `clearAffected(by:)` reaches it); this covers the
    /// rest — a preference written by a sibling, an `@AppStorage` value, a
    /// binding threaded down from somewhere that is not an ancestor.
    ///
    /// A value that is not `Equatable` cannot be compared at all, so the subtree
    /// declares itself cache-unsafe instead: `EquatableView` already refuses to
    /// store a buffer whose render tripped the tracker. Memoization is lost
    /// under such a modifier, which is a performance cost rather than a
    /// correctness one — the right way round.
    ///
    /// - Returns: `true` when the injected value is uncomparable, so the caller
    ///   marks the environment it passes down.
    fileprivate func noteEnvironmentChange(context: RenderContext) -> Bool {
        guard let cache = context.renderCache else { return false }
        switch cache.noteAppliedEnvironment(
            value, identity: context.identity, keyPath: keyPath,
            depth: context.environmentApplicationDepth)
        {
        case .changed:
            cache.clearAffected(by: context.identity)
        case .incomparable:
            // Two routes, because a memoizing view can sit on either side of
            // this modifier. Below it: the tracker exists by then, and
            // `EquatableView` already declines to store when it is tripped.
            // Above it — the usual arrangement, `.equatable().foregroundStyle(…)`
            // — there is no tracker here yet, so the signal has to travel *down*
            // the environment instead. Hence the flag as well.
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            return true
        case .first, .unchanged:
            break
        }
        return false
    }
}

// MARK: - Layoutable

extension EnvironmentModifier: Layoutable {
    /// Measures the wrapped content under the modified environment without
    /// rendering it.
    ///
    /// Without this conformance, `measureChild` would fall through to its
    /// render-to-measure fallback (the view is `Renderable` and its body
    /// returns the same content — `V.Body == Content`, which is also
    /// `View`, so it would still hit the fallback). That fallback renders
    /// the content to measure it (historically *twice* per measure — a
    /// second render at `naturalWidth + 8` probed flexibility, since
    /// retired). With `Image` typically wrapped in several environment
    /// modifiers (character set, colour mode, dithering, placeholder, …)
    /// and each layout pass touching it multiple times, that escalates
    /// into many ASCIIConverter runs per frame — the demo's "twelve-second
    /// render" was almost entirely re-running the ASCII conversion to
    /// *measure* the same image.
    ///
    /// Forwarding the measurement to the content under the modified
    /// environment matches the semantics of the render path and skips
    /// rendering the (possibly expensive) content to measure it.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Also on the measure walk. The measure memo has the same environment
        // blind spot as the buffer cache, and measurement runs first, so a
        // change noticed only on the render walk would already have served a
        // stale size. The once-per-pass short circuit in
        // `noteAppliedEnvironment` is what makes this affordable: two-pass
        // layout visits the same modifier many times per frame.
        let uncomparable = noteEnvironmentChange(context: context)
        var modifiedEnvironment = context.environment.setting(keyPath, to: value)
        if uncomparable { modifiedEnvironment.hasUncomparableEnvironmentValue = true }
        // Derived, as on the render arm — see the note there.
        var modifiedContext = context.withDerivedEnvironment(modifiedEnvironment)
        modifiedContext.environmentApplicationDepth += 1
        return measureChild(content, proposal: proposal, context: modifiedContext)
    }
}

// MARK: - Transform Environment Modifier

/// A modifier that CHANGES an environment value rather than replacing it.
///
/// The difference from ``EnvironmentModifier`` is entirely one of timing: a set
/// value is known when the view is built, a transformed one cannot be, because
/// it is a function of whatever the enclosing environment happens to hold when
/// this subtree renders. So the value is computed here, at render time, and the
/// work is then handed to `EnvironmentModifier` — which already knows how to
/// inject a value AND how to keep the render cache honest about it.
///
/// Delegating to its methods directly, rather than rendering one as a child,
/// keeps this a pure value computation: no extra node in the identity path, no
/// second dispatch, and one place where injection is implemented.
public struct TransformEnvironmentModifier<Content: View, V>: View {
    // The two word-sized fields, then the content last, so nothing follows it
    // whatever its size: the content first left seven undefined bytes before
    // the key path over a scroll view (`ContainerLayoutPaddingTests`), which
    // the per-pass memos' raw-byte key read.

    /// The key path to transform.
    public let keyPath: WritableKeyPath<EnvironmentValues, V>

    /// The transformation to apply to the inherited value.
    public let transform: (inout V) -> Void

    /// The content view.
    public let content: Content

    /// Creates a new transforming environment modifier.
    public init(
        content: Content,
        keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) {
        self.content = content
        self.keyPath = keyPath
        self.transform = transform
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View {
        content
    }

    /// The plain injection this resolves to in `context`.
    ///
    /// Run on both walks, and it must produce the same value on each or the
    /// measured size would describe a different environment than the drawn one.
    /// It does, because the only inputs are the inherited value and the
    /// caller's closure.
    private func applied(in context: RenderContext) -> EnvironmentModifier<Content, V> {
        var value = context.environment[keyPath: keyPath]
        transform(&value)
        return EnvironmentModifier(content: content, keyPath: keyPath, value: value)
    }
}

extension TransformEnvironmentModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        applied(in: context).renderToBuffer(context: context)
    }
}

extension TransformEnvironmentModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        applied(in: context).sizeThatFits(proposal: proposal, context: context)
    }
}

// MARK: - Uncomparable Environment Values

private struct UncomparableEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FocusSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a control rendered here should stay OUT of the focus ring while
    /// everything else about it goes on working.
    ///
    /// Set by `View.hidden()`. A hidden view is not somewhere Tab can land — it
    /// has no picture to land on — but it is otherwise alive: its `@State`
    /// persists, its `.onAppear` fires, its `.keyboardShortcut` still works (a
    /// hidden button holding a shortcut is a real SwiftUI idiom), and a
    /// `.sheet` it presents still presents.
    ///
    /// This is why `.hidden()` cannot use `isolatedForBackground()`, which
    /// swaps the focus manager wholesale: a presentation's own section
    /// registration and `grabInput` would go to the throwaway too, and the
    /// sheet would draw with nothing able to reach it. The flag separates the
    /// two — individual controls consult it, SECTIONS ignore it — which is the
    /// distinction "hidden" needs and "inert" (`View.dimmed()`) deliberately
    /// does not.
    package var isFocusSuppressed: Bool {
        get { self[FocusSuppressedKey.self] }
        set { self[FocusSuppressedKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Whether some ancestor injected an environment value that is not
    /// `Equatable`.
    ///
    /// Change detection at the modifier is what lets the render cache key stay
    /// free of the environment (see `EnvironmentModifier.noteEnvironmentChange`),
    /// and it needs a comparison. A value that cannot be compared could change
    /// under a memoized subtree with nothing to notice, so subtrees below one
    /// decline to cache — losing memoization there, rather than serving pixels
    /// rendered under a value that has since changed.
    public var hasUncomparableEnvironmentValue: Bool {
        get { self[UncomparableEnvironmentKey.self] }
        set { self[UncomparableEnvironmentKey.self] = newValue }
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension EnvironmentModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<Inner: View>(_ view: Inner) -> any View {
        EnvironmentModifier<Inner, V>(content: view, keyPath: keyPath, value: value)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension EnvironmentModifier: ChildViewProvider where Content: ChildViewProvider {}

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension TransformEnvironmentModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<Inner: View>(_ view: Inner) -> any View {
        TransformEnvironmentModifier<Inner, V>(content: view, keyPath: keyPath, transform: transform)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension TransformEnvironmentModifier: ChildViewProvider where Content: ChildViewProvider {}

// MARK: - Removal Transitions

/// Each draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension EnvironmentModifier: DrawsContentUnchanged {}
extension TransformEnvironmentModifier: DrawsContentUnchanged {}
