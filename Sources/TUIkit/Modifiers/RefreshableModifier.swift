//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RefreshableModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - RefreshAction

/// An action that initiates a refresh, read from the environment. Matches
/// SwiftUI's type of the same name.
///
/// ```swift
/// @Environment(\.refresh) private var refresh
///
/// var body: some View {
///     Button("Reload") {
///         Task { await refresh?() }
///     }
///     .disabled(refresh == nil)
/// }
/// ```
///
/// The value is `nil` unless an ancestor applied
/// ``View/refreshable(action:)``, which is what makes
/// `refresh == nil` a usable "there is nothing to refresh here" test.
public struct RefreshAction: Equatable, Sendable {
    /// Whether a run is in flight, and the identity of the `.refreshable` this
    /// handle belongs to.
    ///
    /// **Separate from the closure on purpose.** A view value is rebuilt every
    /// frame, so a flag stored beside the closure is a *new* flag every frame:
    /// the run Ctrl-R started set the flag on the frame that started it, and
    /// every frame after asked a freshly-zeroed one. The indicator therefore
    /// never drew — and, less visibly, a second Ctrl-R a frame later coalesced
    /// against nothing and started a second run. The state is persisted by
    /// ``RefreshableModifier`` in `StateStorage` and handed to each frame's
    /// action, so every frame shares one answer.
    final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var running = false

        /// Whose cached buffers show this state, so a run starting or ending
        /// can drop them: the render cache of the frame that last rendered the
        /// `.refreshable`, and its identity.
        ///
        /// A value memo above the modifier may serve a buffer instead of
        /// rendering it, and the key it compares does not change when a run
        /// starts. Without this the memo kept serving the idle picture, so the
        /// spinner never drew, and a buffer stored mid-run kept the spinner
        /// after the run ended. Weak, like a `StateBox`'s sink: the cache owns
        /// the state storage this lives in, not the other way round.
        private weak var invalidationSink: (any RenderInvalidationSink)?
        private var identity: ViewIdentity?

        init() {}

        /// Records where a change of this state has to be seen. Called by each
        /// render of the `.refreshable` that owns it.
        func bind(to sink: (any RenderInvalidationSink)?, identity: ViewIdentity) {
            lock.lock()
            invalidationSink = sink
            self.identity = identity
            lock.unlock()
        }

        /// Claims the right to run, or reports that someone else already has.
        func beginIfIdle() -> Bool {
            lock.lock()
            if running {
                lock.unlock()
                return false
            }
            running = true
            lock.unlock()
            invalidateBound()
            return true
        }

        func finish() {
            lock.lock()
            running = false
            lock.unlock()
            invalidateBound()
        }

        /// Drops the bound identity's cached buffers, and its ancestors', and
        /// asks for a frame. Thread-safe: the sink only queues the identity.
        private func invalidateBound() {
            lock.lock()
            let sink = invalidationSink
            let identity = identity
            lock.unlock()
            // Never `nil`, which would clear the whole cache.
            guard let sink, let identity else { return }
            sink.invalidateRender(for: identity)
        }

        var isRunning: Bool {
            lock.lock()
            defer { lock.unlock() }
            return running
        }
    }

    private let state: RunState
    private let action: @Sendable () async -> Void

    init(_ action: @escaping @Sendable () async -> Void, state: RunState) {
        self.action = action
        self.state = state
    }

    /// Whether this refresh is currently running.
    ///
    /// What the in-flight indicator draws from, and what makes a second request
    /// a no-op rather than a second run.
    public var isRunning: Bool { state.isRunning }

    /// Runs the refresh action and waits for it to finish.
    ///
    /// A call made while one is already in flight returns immediately without
    /// running the action again — SwiftUI likewise will not start a refresh
    /// over a running one, and it must not matter whether the request came from
    /// the key binding or from a button reaching this through the environment.
    public func callAsFunction() async {
        guard state.beginIfIdle() else { return }
        await MainActor.run { AppState.shared.setNeedsRender() }
        await action()
        state.finish()
        await MainActor.run { AppState.shared.setNeedsRender() }
    }

    /// Two handles to the same `.refreshable` are equal. The run state carries
    /// that identity — it is the part that persists across frames, where the
    /// closure is rebuilt with the view every time.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state
    }
}

// MARK: - Environment key

private struct RefreshKey: EnvironmentKey {
    /// No enclosing `.refreshable`, so there is nothing to refresh.
    static let defaultValue: RefreshAction? = nil
}

extension EnvironmentValues {
    /// The refresh action from the nearest enclosing
    /// ``View/refreshable(action:)``, or `nil` if there is none.
    public var refresh: RefreshAction? {
        get { self[RefreshKey.self] }
        set { self[RefreshKey.self] = newValue }
    }
}

// MARK: - refreshable

extension View {
    /// Marks this view as refreshable. Matches SwiftUI's `refreshable(action:)`.
    ///
    /// ```swift
    /// List(articles) { Text($0.title) }
    ///     .refreshable { articles = await reload() }
    /// ```
    ///
    /// ## The gesture a terminal doesn't have
    ///
    /// SwiftUI triggers this by pulling the content down past its top edge.
    /// There is no such gesture here — a terminal reports discrete wheel
    /// clicks, not a continuous rubber-banded drag, so "how far past the top"
    /// is not a quantity that exists. The trigger is therefore
    /// <kbd>Ctrl</kbd>-<kbd>R</kbd>, the reload key every terminal can deliver
    /// (Control being the only modifier a terminal reports for a letter — see
    /// ``KeyboardShortcut``).
    ///
    /// While the action runs, a spinner is drawn over the top row of the
    /// content, which is as close to SwiftUI's pull-to-refresh spinner as a
    /// grid gets: it *overlays* rather than insets, so nothing reflows and no
    /// row changes height while a refresh is in flight. A second
    /// <kbd>Ctrl</kbd>-<kbd>R</kbd> during one is ignored rather than queued —
    /// SwiftUI likewise will not start a second refresh over a running one.
    ///
    /// The action is also published to the subtree as ``EnvironmentValues/refresh``,
    /// so a "Reload" button anywhere inside can run the same refresh, and a
    /// view can tell whether it is inside something refreshable at all.
    ///
    /// - Parameter action: The async action to run. It is awaited, and the
    ///   spinner shows until it returns.
    /// - Returns: A view that refreshes on <kbd>Ctrl</kbd>-<kbd>R</kbd>.
    public func refreshable(action: @escaping @Sendable () async -> Void) -> some View {
        RefreshableModifier(content: self, action: action)
    }
}

/// Where ``RefreshableModifier`` keeps its persistent state. A namespace of
/// its own because a generic type cannot hold static stored properties.
private enum RefreshableStateIndex {
    // Negative: infrastructure slots share the wrapped content's identity,
    // and 0... belongs to a composite content view's own @State. See
    // `StateStorage.StateKey`'s reserved-range table.
    static let runState = -20
}

/// Publishes a ``RefreshAction`` to its subtree, binds it to
/// <kbd>Ctrl</kbd>-<kbd>R</kbd>, and shows a spinner while it runs.
public struct RefreshableModifier<Content: View>: View {
    let content: Content
    let action: @Sendable () async -> Void

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    /// This frame's handle to the refresh: the closure just built, bound to the
    /// run state that has been there all along.
    ///
    /// Measuring gets a throwaway state rather than touching storage — a
    /// measure pass must allocate none, and nothing it publishes can start a
    /// run. What a measured child can still see is that
    /// ``EnvironmentValues/refresh`` is non-nil, which is the only thing about
    /// it that affects layout.
    func resolvedAction(_ context: RenderContext) -> RefreshAction {
        guard !context.isMeasuring, let storage = context.stateStorage else {
            return RefreshAction(action, state: RefreshAction.RunState())
        }
        // Marked active or the end-of-pass prune collects it, and the next
        // frame allocates a fresh state — which is the bug this method exists
        // to fix, wearing a different hat.
        storage.markActive(context.identity)
        let key = StateStorage.StateKey(
            identity: context.identity, propertyIndex: RefreshableStateIndex.runState)
        let box: StateBox<RefreshAction.RunState> = storage.storage(
            for: key, default: RefreshAction.RunState())
        box.value.bind(to: context.renderCache, identity: context.identity)
        return RefreshAction(action, state: box.value)
    }
}

extension RefreshableModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let action = resolvedAction(context)
        let childContext = context.withEnvironment(
            context.environment.setting(\.refresh, to: action))

        // A measure pass must not register anything: a render-to-measure
        // ancestor would bind a SECOND Ctrl-R handler within the frame, and
        // one keypress would start two refreshes.
        guard !context.isMeasuring else {
            return TUIkitView.renderToBuffer(content, context: childContext)
        }

        // Declared to any value-memoizing ancestor: the dispatcher clears its
        // handlers every frame, so a cached subtree would stop re-registering
        // and Ctrl-R would go dead while still on screen. Declared as
        // REPLAYABLE, as `onKeyPress` is: the buffer memo stores the entry
        // recorded below and binds Ctrl-R again on every hit. The spinner is
        // the part a hit could get wrong, and the run state invalidates this
        // identity when a run starts or ends (`RunState.bind`).
        context.environment.volatileReadTracker?.recordReplayableEffect()
        let sectionID = context.environment.activeFocusSectionID
        RefreshRegistrar.register(action: action, sectionID: sectionID, context: context)
        if let journal = context.recordingEffectJournal {
            // Built only while a memo records. The action is captured with the
            // run state it shares with every other frame's.
            journal.append(
                EffectJournal.Entry(
                    kind: RefreshRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { [action] replay in
                    RefreshRegistrar.register(action: action, sectionID: sectionID, context: replay)
                })
        }

        let buffer = TUIkitView.renderToBuffer(content, context: childContext)
        // The spinner carries no label. `.overlay` is laid out IN its base's
        // frame and cut to it, so a labelled one would not widen the content —
        // it would be clipped BY it, and a caption sheared off mid-word is a
        // worse answer than no caption. (It would have widened the content
        // until 2026-09-20, when an overlay still sized to the larger of the
        // two; either way the label has no room it can call its own.)
        //
        // Three cells is the least that can carry the badge below — one glyph
        // between two blanks — and anything narrower would draw a blank cell
        // where the indicator should be. A multi-cell style over content
        // barely wider than that is clipped like any other overlay content,
        // and still visibly animates.
        guard action.isRunning, buffer.width >= 3 else { return buffer }
        let indicator = context.environment.refreshIndicator
        // Composed, not hand-composited: `.overlay` already lays a view over
        // another without disturbing what is underneath it — placement,
        // alignment guides and opacity resolution included.
        //
        // The base is the buffer already rendered above, NOT `content` again.
        // An overlay renders its base, so overlaying `content` walked the whole
        // subtree a SECOND time at the same identities within one pass, and
        // every render-pass side effect below a running refresh ran twice:
        // `.onChange` claims its slot by position (`nextOnChangeIndex`, reset
        // per pass, not per render) so the second walk claimed a fresh slot and
        // fired for a value that never changed, and an `.onKeyPress` handler
        // that returns `false` was dispatched twice per keystroke.
        //
        // A blank cell either side, so the indicator reads as a badge sitting
        // ON the content rather than as a glyph that has crashed into the word
        // beside it — an overlay paints over what it covers, and a lone spinner
        // butted up against text is hard to tell from part of the text.
        return TUIkitView.renderToBuffer(
            BufferView(buffer: buffer).overlay(alignment: .top) {
                Spinner(style: indicator.style, color: indicator.color)
                    .padding(.horizontal, 1)
            },
            context: childContext)
    }
}

// MARK: - Registration

/// The one registration `.refreshable` makes, shared by the live render and by
/// a value memo replaying it — see `EffectJournal`.
enum RefreshRegistrar {
    /// The journal kind of a `.refreshable`'s Ctrl-R binding.
    static let kind = EffectJournal.Kind("refreshable")

    /// Binds Ctrl-R to `action` in `context`'s key dispatcher, in `sectionID`.
    ///
    /// It looks the dispatcher up in `context` rather than taking one, so a
    /// replay binds into the channels of the frame that serves it.
    @MainActor
    static func register(action: RefreshAction, sectionID: String?, context: RenderContext) {
        context.environment.keyEventDispatcher?.addHandler(sectionID: sectionID) { event in
            guard event.ctrl, case .character(let character) = event.key,
                character.lowercased() == "r"
            else { return false }
            // The key is consumed either way. Whether it STARTS anything is
            // the action's business — it coalesces a request made while one is
            // in flight, so this route and a button reaching the same refresh
            // through the environment behave identically.
            Task { @MainActor in await action() }
            return true
        }
    }
}

extension RefreshableModifier: Layoutable {
    /// The spinner overlays the content rather than displacing it, so the size
    /// is the content's whether a refresh is running or not — which is also
    /// what keeps the layout from twitching when one starts.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: context.withEnvironment(
                context.environment.setting(\.refresh, to: resolvedAction(context))))
    }
}
