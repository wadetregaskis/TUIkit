//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Preferences.swift
//
//  Created by LAYERED.work
//  License: MIT  Similar to SwiftUI's PreferenceKey system.
//

import TUIkitCore

// MARK: - Preference Modifier

/// A modifier that sets a preference value.
struct PreferenceModifier<Content: View, K: PreferenceKey>: View {
    /// The content view.
    let content: Content

    /// The preference value to set.
    let value: K.Value

    var body: Never {
        fatalError("PreferenceModifier renders via Renderable")
    }
}

extension PreferenceModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The write is a render-pass side effect, twice over:
        // - never during a measure pass (a measure-render of this subtree —
        //   e.g. under a render-to-measure ancestor — would apply an
        //   accumulating `reduce` a second time within the same frame);
        // - always declared to any value-memoizing ancestor: the preference
        //   stack is rebuilt every render pass, so a cached buffer would
        //   silently drop this value from the frame's collection.
        if !context.isMeasuring {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
            context.environment.preferenceStorage!.setValue(value, forKey: K.self)
        }

        // Render content
        return TUIkit.renderToBuffer(content, context: context)
    }
}

extension PreferenceModifier: Layoutable {
    /// Publishes a preference and renders `content` unchanged, so it measures as
    /// `content` (and the preference write stays a render-pass side-effect).
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - OnPreferenceChange Modifier

/// A modifier that reacts to preference changes.
struct OnPreferenceChangeModifier<Content: View, K: PreferenceKey>: View
where K.Value: Equatable {
    /// The content view.
    let content: Content

    /// The action to perform when the preference changes.
    let action: (K.Value) -> Void

    var body: Never {
        fatalError("OnPreferenceChangeModifier renders via Renderable")
    }
}

extension OnPreferenceChangeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Pure passthrough during a measure pass: registering the callback and
        // invoking the action are render side effects (the action would fire
        // with a partial mid-measure collection).
        guard !context.isMeasuring else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        let prefs = context.environment.preferenceStorage!

        // The comparison and possible action below are per-frame side
        // effects a cached buffer cannot reproduce — decline the memos.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        // Push a new preference context
        prefs.push()

        // Render content
        let buffer = TUIkit.renderToBuffer(content, context: context)

        // Pop and get collected preferences
        let preferences = prefs.pop()
        let value = preferences[K.self]

        // Fire only when the subtree's REDUCED value actually changed —
        // SwiftUI's contract (that is what the `Equatable` constraint is
        // for), and what keeps the render loop settled: the canonical action
        // writes `@State`, and firing unconditionally re-rendered every
        // frame forever. The baseline persists by view identity through the
        // same silent tracked-value store `onChange` uses (its claim counter
        // too, so chained observers at one identity keep distinct slots).
        // This also replaced a per-publisher storage callback that delivered
        // RAW un-reduced values — the action now only ever sees the final
        // reduction, once, like SwiftUI.
        let storage = context.environment.stateStorage!
        let index = storage.nextOnChangeIndex(for: context.identity)
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: index)
        let previous: K.Value? = storage.trackedValue(for: key)
        storage.setTrackedValue(value, for: key)
        storage.markActive(context.identity)
        if previous != value {
            action(value)
        }

        return buffer
    }
}

extension OnPreferenceChangeModifier: Layoutable {
    /// Renders `content` unchanged (it only collects/observes preferences), so it
    /// measures as `content`. Forwarding also keeps the push/pop and the change
    /// callback to the render pass — a measure must not fire preference actions.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Common Preference Keys

/// A preference key for the navigation title.
public struct NavigationTitleKey: PreferenceKey {
    /// The default navigation title (empty string).
    public static let defaultValue: String = ""
}
