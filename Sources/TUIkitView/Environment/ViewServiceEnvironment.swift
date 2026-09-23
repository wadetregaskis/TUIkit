//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewServiceEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - State Storage

/// EnvironmentKey for the persistent `@State` value storage.
private struct StateStorageKey: EnvironmentKey {
    static let defaultValue: StateStorage? = nil
}

// MARK: - Render Cache

/// EnvironmentKey for memoized subtree rendering results.
private struct RenderCacheKey: EnvironmentKey {
    static let defaultValue: RenderCache? = nil
}

// MARK: - Key Channels

/// EnvironmentKey for the identity of the key channels in force.
private struct KeyChannelTokenKey: EnvironmentKey {
    static let defaultValue: ObjectIdentifier? = nil
}

// MARK: - Active Focus Section

/// EnvironmentKey for the focus section that child views should register in.
private struct ActiveFocusSectionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

// MARK: - EnvironmentValues Extensions

extension EnvironmentValues {

    /// Which key channels registrations here go into: the `ObjectIdentifier`
    /// of the key event dispatcher in force, or `nil` without one.
    ///
    /// Here rather than beside the dispatcher because the value memos in this
    /// module compare it and cannot see the dispatcher's type. Written only by
    /// the TUIkit module's `keyEventDispatcher` setter, so the two cannot
    /// disagree. One token stands for the shortcut registry and the status bar
    /// as well: `withThrowawayKeyChannels()` swaps all three together.
    package var keyChannelToken: ObjectIdentifier? {
        get { self[KeyChannelTokenKey.self] }
        set { self[KeyChannelTokenKey.self] = newValue }
    }

    /// The ID of the focus section that child views should register in.
    ///
    /// Declared in this module, not beside the focus manager, so the value
    /// memos can compare the section a subtree's recorded registrations were
    /// made in with the one in force where it is served.
    package var activeFocusSectionID: String? {
        get { self[ActiveFocusSectionKey.self] }
        set { self[ActiveFocusSectionKey.self] = newValue }
    }

    /// The persistent `@State` value storage indexed by `ViewIdentity`.
    public var stateStorage: StateStorage? {
        get { self[StateStorageKey.self] }
        set { self[StateStorageKey.self] = newValue }
    }

    /// Cache for memoized subtree rendering results.
    public var renderCache: RenderCache? {
        get { self[RenderCacheKey.self] }
        set { self[RenderCacheKey.self] = newValue }
    }

    /// Installs `tracker` as this pass's volatile-read tracker, and mirrors it
    /// onto ``renderCache`` for the measure memo's gate.
    ///
    /// The only way to install one. Assigning ``volatileReadTracker`` directly
    /// leaves the mirror behind, and the mirror is what
    /// `measureChild` gates on — so the memo either goes quiet (mirror nil) or,
    /// worse, gates on counters this subtree does not write to (mirror stale).
    /// `measureChild` asserts the two agree, which turns the second case into a
    /// test failure rather than a stale size.
    ///
    /// Set ``renderCache`` before calling this: a tracker installed before the
    /// cache mirrors onto nothing.
    ///
    /// - Parameter tracker: The pass's tracker — a fresh one per frame in the
    ///   render loop, which derives its pulse-clock demand from the counts.
    public mutating func installVolatileReadTracker(_ tracker: VolatileReadTracker) {
        volatileReadTracker = tracker
        renderCache?.volatileReadTracker = tracker
    }
}

extension RenderContext {
    /// Renders `body` with `tracker` as the volatile-read tracker, installed
    /// with its mirror, and puts the pass's own mirror back afterwards.
    ///
    /// For a render that must count its volatile reads apart from the pass's,
    /// in the middle of the pass. The mirror is on the render cache, which the
    /// whole pass shares, so installing a tracker for one subtree with
    /// ``EnvironmentValues/installVolatileReadTracker(_:)`` alone would leave
    /// it gating every measure after the subtree was done. Assigning the
    /// environment alone is worse: the measure memo gates on the mirror, so the
    /// subtree's volatile reads land on a tracker the gate never reads, and a
    /// size that depended on the clock was stored as safe. (Debug builds trap
    /// on that in `measureChild`, which is how a navigation stack's covered
    /// root was found doing it.)
    ///
    /// - Parameters:
    ///   - tracker: The tracker the subtree records to.
    ///   - body: Renders the subtree, with the context to render it in.
    /// - Returns: What `body` returns.
    package func withVolatileReadTracker<Result>(
        _ tracker: VolatileReadTracker, _ body: (RenderContext) -> Result
    ) -> Result {
        var copy = self
        let passMirror = environment.renderCache?.volatileReadTracker
        copy.environment.installVolatileReadTracker(tracker)
        defer { environment.renderCache?.volatileReadTracker = passMirror }
        return body(copy)
    }
}
