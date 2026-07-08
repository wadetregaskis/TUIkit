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
            context.environment.volatileReadTracker?.recordPreferenceWrite()
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

        // The registration and the action invocation below are per-frame
        // side effects a cached buffer cannot reproduce — decline the memos.
        context.environment.volatileReadTracker?.recordPreferenceWrite()

        // Register callback for preference changes
        prefs.onPreferenceChange(K.self, callback: action)

        // Push a new preference context
        prefs.push()

        // Render content
        let buffer = TUIkit.renderToBuffer(content, context: context)

        // Pop and get collected preferences
        let preferences = prefs.pop()

        // Trigger action with current value
        action(preferences[K.self])

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
