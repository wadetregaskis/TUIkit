//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RefreshableModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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
    /// The action, boxed so two handles to the SAME `.refreshable` compare
    /// equal — closures cannot be compared, but identity can, and identity is
    /// what SwiftUI's `Equatable` conformance actually means here.
    private let box: ActionBox

    /// Reference identity for the action, and its storage.
    private final class ActionBox: @unchecked Sendable {
        let action: @Sendable () async -> Void
        init(_ action: @escaping @Sendable () async -> Void) { self.action = action }
    }

    init(_ action: @escaping @Sendable () async -> Void) {
        self.box = ActionBox(action)
    }

    /// Runs the refresh action and waits for it to finish.
    public func callAsFunction() async {
        await box.action()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.box === rhs.box
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
        RefreshableModifier(content: self, action: RefreshAction(action))
    }
}

/// Publishes a ``RefreshAction`` to its subtree, binds it to
/// <kbd>Ctrl</kbd>-<kbd>R</kbd>, and shows a spinner while it runs.
public struct RefreshableModifier<Content: View>: View {
    let content: Content
    let action: RefreshAction

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }
}

/// Where this view's state lives, by name rather than by bare integer.
private enum StateIndex {
    static let isRefreshing = 0
}

extension RefreshableModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let childContext = context.withEnvironment(
            context.environment.setting(\.refresh, to: action))

        // A measure pass must not register anything: a render-to-measure
        // ancestor would bind a SECOND Ctrl-R handler within the frame, and
        // one keypress would start two refreshes.
        guard !context.isMeasuring, let stateStorage = context.environment.stateStorage else {
            return TUIkitView.renderToBuffer(content, context: childContext)
        }
        stateStorage.markActive(context.identity)
        let refreshing: StateBox<Bool> = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.isRefreshing),
            default: false)

        // Declared to any value-memoizing ancestor: the dispatcher clears its
        // handlers every frame, so a cached subtree would stop re-registering
        // and Ctrl-R would go dead while still on screen.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        context.environment.keyEventDispatcher?.addHandler(
            sectionID: context.environment.activeFocusSectionID
        ) { [action] event in
            guard event.ctrl, case .character(let character) = event.key,
                character.lowercased() == "r"
            else { return false }
            // Already running: consume the key rather than stacking a second
            // refresh on the first.
            guard !refreshing.value else { return true }
            refreshing.value = true
            AppState.shared.setNeedsRender()
            Task { @MainActor in
                await action()
                refreshing.value = false
                AppState.shared.setNeedsRender()
            }
            return true
        }

        let buffer = TUIkitView.renderToBuffer(content, context: childContext)
        // The spinner carries no label. `.overlay` sizes to the LARGER of the
        // two, so a labelled one would widen narrow content the moment a
        // refresh started — the reflow this is trying to avoid. One animated
        // glyph fits over anything at all, and one cell of content is enough
        // to put it on.
        guard refreshing.value, buffer.width >= 1 else { return buffer }
        // Composed, not hand-composited: `.overlay` already lays a view over
        // another without disturbing what is underneath it.
        return TUIkitView.renderToBuffer(
            content.overlay(alignment: .top) { Spinner() }, context: childContext)
    }
}

extension RefreshableModifier: Layoutable {
    /// The spinner overlays the content rather than displacing it, so the size
    /// is the content's whether a refresh is running or not — which is also
    /// what keeps the layout from twitching when one starts.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            content, proposal: proposal,
            context: context.withEnvironment(context.environment.setting(\.refresh, to: action)))
    }
}
