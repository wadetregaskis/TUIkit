//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyPressModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that adds a key press handler to a view.
///
/// The handler returns a Bool indicating whether the event was consumed.
/// If false is returned, the event continues to propagate to other handlers.
public struct KeyPressModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The keys to listen for (nil = all keys).
    let keys: Set<Key>?

    /// The handler to call when a matching key is pressed.
    /// Returns true if the event was handled, false to let it propagate.
    let handler: (KeyEvent) -> Bool

    public var body: Never {
        fatalError("KeyPressModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension KeyPressModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // The registration is a render-pass side effect, twice over:
        // - never during a measure pass — a render-to-measure ancestor would
        //   register a SECOND handler for the same modifier within the frame,
        //   running the action twice per keypress;
        // - always declared to any value-memoizing ancestor — the dispatcher
        //   clears its handlers every frame, so a row served from the cache
        //   must still register. Declared as REPLAYABLE: the buffer memo stores
        //   the entry recorded below with the row's buffer and makes the
        //   registration again on every hit, at the row's own position. Every
        //   gate that does not replay still counts it and declines.
        guard !context.isMeasuring else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        context.environment.volatileReadTracker?.recordReplayableEffect()

        let sectionID = context.environment.activeFocusSectionID
        KeyPressRegistrar.register(keys: keys, handler: handler, sectionID: sectionID, context: context)
        if let journal = context.recordingEffectJournal {
            // Built only while a memo records, so the live path allocates no
            // second closure. The section is captured, not looked up: it is
            // what this registration was made in, and the memo checks that the
            // section where it is served is the same one.
            journal.append(
                EffectJournal.Entry(
                    kind: KeyPressRegistrar.kind, channelToken: context.environment.keyChannelToken
                ) { [keys, handler] replay in
                    KeyPressRegistrar.register(
                        keys: keys, handler: handler, sectionID: sectionID, context: replay)
                })
        }

        return TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - Registration

/// The one registration `onKeyPress` makes, shared by the live render and by a
/// value memo replaying it — see `EffectJournal`.
enum KeyPressRegistrar {
    /// The journal kind of an `onKeyPress` registration.
    static let kind = EffectJournal.Kind("onKeyPress")

    /// Adds a handler for `keys` (all keys when `nil`) to `context`'s key
    /// dispatcher, in `sectionID`.
    ///
    /// It looks the dispatcher up in `context` rather than taking one, so a
    /// replay registers into the channels of the frame that serves it.
    @MainActor
    static func register(
        keys: Set<Key>?, handler: @escaping (KeyEvent) -> Bool, sectionID: String?,
        context: RenderContext
    ) {
        context.environment.keyEventDispatcher!.addHandler(sectionID: sectionID) { event in
            if let keys, !keys.contains(event.key) { return false }
            return handler(event)
        }
    }
}

// MARK: - Layoutable

extension KeyPressModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged. Forwarding the
    /// measure keeps it off `measureChild`'s render-to-measure fallback and lets
    /// the wrapped view's flexibility propagate.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension KeyPressModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension KeyPressModifier: DrawsContentUnchanged {}
