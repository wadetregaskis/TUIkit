//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardShortcutModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Keyboard Shortcut Modifier

/// Plants the claimable carrier ``View/keyboardShortcut(_:)`` offers to the
/// first control rendered under it.
///
/// A plain `environment(\.assignedKeyboardShortcut, …)` did this until the
/// registration became replayable, and it did two things this must not:
///
/// - **It stopped every memo below it storing.** `KeyboardShortcutAssignment` is
///   a per-frame claim box, not a value, so `RenderCache.noteAppliedEnvironment`
///   answered `.incomparable` for it and set `hasUncomparableEnvironmentValue`
///   over the whole subtree. That is the right answer for a value a subtree
///   might draw from and nothing could compare; it is the wrong one here,
///   because the only reader is `Button`, and what a `Button` does with it —
///   register an action for the frame — is declared to the memo on its own
///   (`KeyboardShortcutRegistrar/declare(_:action:carrier:context:)`). So the
///   carrier is assigned straight into the environment, as `.focusSection`
///   assigns its section, and the subtree keeps its cache.
/// - **It could not say where it was planted.** A registration may be replayed
///   only when the modifier carrying it sits INSIDE the memo that would store
///   it; planted above one, the carrier is still there to be claimed on a frame
///   the memo serves, and the memo's key — made of the view value below the
///   modifier — cannot see the shortcut change. So each plant stamps the carrier
///   with `RenderContext.effectRecordingDepth`, the memo nesting in force where
///   it was planted, which is what the registrar compares its own against.
///
/// Both walks plant: a measure pass registers nothing, but it needs the
/// shortcut to reserve the width the hint prints in, and one carrier serves the
/// frame's measure and its render (see ``KeyboardShortcutAssignment``).
struct KeyboardShortcutModifier<Content: View>: View {
    /// The content view, whose first control claims the shortcut.
    let content: Content

    /// The claim box, built with the view value rather than per pass, so the
    /// measure and the render of one frame share it.
    let assignment: KeyboardShortcutAssignment

    var body: Never {
        fatalError("KeyboardShortcutModifier renders via Renderable")
    }

    /// The context the content renders or measures under: the carrier in the
    /// environment, stamped with the memo nesting it was planted at.
    private func planting(into context: RenderContext) -> RenderContext {
        assignment.planted(atEffectRecordingDepth: context.effectRecordingDepth)
        var planted = context
        planted.environment.assignedKeyboardShortcut = assignment
        return planted
    }
}

// MARK: - Renderable

extension KeyboardShortcutModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: planting(into: context))
    }
}

// MARK: - Layoutable

extension KeyboardShortcutModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged. Forwarding the
    /// measure keeps it off `measureChild`'s render-to-measure fallback and lets
    /// the wrapped view's flexibility propagate, exactly as `KeyPressModifier`
    /// does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: planting(into: context))
    }
}

// MARK: - Registration

/// The one registration a `Button`'s `.keyboardShortcut` makes, shared by the
/// live render and by a value memo replaying it — see `EffectJournal`.
enum KeyboardShortcutRegistrar {
    /// The journal kind of a keyboard-shortcut registration.
    static let kind = EffectJournal.Kind("keyboardShortcut")

    /// Registers `action` for `shortcut` with `context`'s shortcut registry,
    /// reporting whether there was one.
    ///
    /// It looks the registry up in `context` rather than taking one, so a replay
    /// registers into the registry of the frame that serves it — the registry is
    /// emptied before every walk (`KeyboardShortcutRegistry.beginRenderPass`),
    /// and a `.dimmed()` subtree or the page beneath a modal is handed a
    /// throwaway one.
    ///
    /// - Returns: `false` outside a running app, where there is no registry and
    ///   nothing was registered — so the caller declares nothing either.
    @MainActor
    @discardableResult
    static func register(
        _ shortcut: KeyboardShortcut, action: @escaping () -> Void, context: RenderContext
    ) -> Bool {
        guard let registry = context.environment.keyboardShortcutRegistry else { return false }
        registry.register(shortcut, action: action)
        return true
    }

    /// Tells a value-memoizing ancestor what this registration was: whether it
    /// must decline to store the subtree, or may store it and make the
    /// registration again on every hit.
    ///
    /// The registry is rebuilt every pass, so a served subtree that did not
    /// register again would leave its button's key equivalent dead while the
    /// button is still on screen — which is why this declared a plain render
    /// side effect, and why no memo holding a shortcut-bearing `Button` could
    /// store at all. Registering again reproduces it exactly: the last
    /// registration on a trigger wins, and a replay happens where the subtree
    /// would have rendered, so the frame ends with the same action on the same
    /// trigger whether the subtree rendered or was served.
    ///
    /// **Except when the carrier was planted above the memo**, which is the one
    /// case that keeps declining. The modifier offers its shortcut to the first
    /// control that renders under it, and on a served frame no control renders
    /// under it at all: the offer would stand unclaimed while the replay
    /// registered anyway, so a sibling rendered after the memo could take a
    /// shortcut that belongs to the button inside it. The key cannot rule that
    /// out either — it is made of the view value BELOW the modifier, so a
    /// changed shortcut above it is invisible.
    ///
    /// Nesting is answered conservatively: the comparison is against the
    /// INNERMOST recording memo, so a carrier planted between two nested memos
    /// declines for both, rather than only for the inner one it sits above.
    @MainActor
    static func declare(
        _ shortcut: KeyboardShortcut, action: @escaping () -> Void,
        carrier: KeyboardShortcutAssignment, context: RenderContext
    ) {
        let tracker = context.environment.volatileReadTracker
        guard carrier.isPlanted(insideMemoAtDepth: context.effectRecordingDepth) else {
            tracker?.recordRenderSideEffect()
            return
        }
        tracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        // Built only while a memo records, so the live path allocates no second
        // closure. The RESOLVED shortcut is captured, not the declared one: the
        // stand-in for `.command` comes from the environment where the button
        // rendered, and a change to it clears the entry the ordinary way.
        journal.append(
            EffectJournal.Entry(
                kind: kind, channelToken: context.environment.keyChannelToken
            ) { replay in
                register(shortcut, action: action, context: replay)
            })
    }
}
