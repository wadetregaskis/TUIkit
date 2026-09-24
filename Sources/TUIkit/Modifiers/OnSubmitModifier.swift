//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnSubmitModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - onSubmit cascade modifier

/// Appends a scoped `SubmitActionEntry` to the environment's `submitActions`
/// for its content's subtree, so descendant text fields run it when they submit.
///
/// The append (rather than replace) is why this mirrors ``StyleCascadeModifier``
/// — a View + Renderable + Layoutable modifier that read-modify-writes the
/// environment at render time — instead of the plain `.environment(_:_:)` setter,
/// which would clobber any outer `.onSubmit`.
public struct OnSubmitModifier<Content: View>: View {
    public let content: Content
    let triggers: SubmitTriggers
    let action: () -> Void

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        var actions = context.environment.submitActions
        actions.append(SubmitActionEntry(triggers: triggers, action: action))
        return context.withEnvironment(context.environment.setting(\.submitActions, to: actions))
    }
}

extension OnSubmitModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension OnSubmitModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

// MARK: - submitScope cascade blocker

/// Hides the enclosing `.onSubmit` actions from its content's subtree.
///
/// The mirror image of ``OnSubmitModifier``, and built the same way for the
/// same reason: it has to read-modify-write the environment at render time,
/// because what it does is relative to what is already there.
struct SubmitScopeModifier<Content: View>: View {
    let content: Content
    let isBlocking: Bool

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        guard isBlocking else { return context }
        // Emptying the list is the whole mechanism: an `.onSubmit` INSIDE the
        // scope appends to this empty list and still runs, which is exactly
        // SwiftUI's rule — the scope blocks submissions from reaching actions
        // configured *higher up*, not from being handled at all.
        //
        // A constant is safe to write with `setting(_:to:)` (which skips the
        // render cache's environment-change tracking): the value cannot differ
        // between frames, so there is nothing for a cached subtree to miss.
        return context.withEnvironment(context.environment.setting(\.submitActions, to: []))
    }
}

extension SubmitScopeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension SubmitScopeModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

// MARK: - View extensions

extension View {
    /// Adds an action to perform when the user submits a value to a text input
    /// in this view's subtree — mirrors SwiftUI's `onSubmit(of:_:)`.
    ///
    /// The action fires when Return is pressed in a matching ``TextField`` /
    /// ``SecureField`` (for ``SubmitTriggers/text``) or the
    /// `.searchable` query field (for ``SubmitTriggers/search``). It cascades to
    /// every matching field in the subtree, and composes *additively* with a
    /// field's own ``TextField/onSubmit(_:)`` closure and with any enclosing
    /// `.onSubmit`: the most-specific action runs first, then outer ones.
    ///
    /// ```swift
    /// VStack {
    ///     TextField("Name", text: $name)
    ///     TextField("Email", text: $email)
    /// }
    /// .onSubmit { save() }   // Return in either field saves
    /// ```
    ///
    /// - Note: ``TextEditor`` does not submit (Return inserts a newline), matching
    ///   SwiftUI.
    ///
    /// - Parameters:
    ///   - triggers: Which submissions the action responds to (default ``SubmitTriggers/text``).
    ///   - action: The action to run on submit.
    public func onSubmit(
        of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void
    ) -> some View {
        OnSubmitModifier(content: self, triggers: triggers, action: action)
    }

    /// Stops submissions from this subtree reaching an enclosing `.onSubmit` —
    /// mirrors SwiftUI's `submitScope(_:)`.
    ///
    /// A form that saves on Return usually wants exactly that, except in the
    /// one field where Return means something local. Wrapping that field ends
    /// the cascade at it:
    ///
    /// ```swift
    /// VStack {
    ///     TextField("Name", text: $name)
    ///     TextField("Tag", text: $tag)
    ///         .submitScope()       // Return here does not save the form
    /// }
    /// .onSubmit { save() }
    /// ```
    ///
    /// It blocks only what is OUTSIDE it. An `.onSubmit` written inside the
    /// scope still runs, which is what makes the scope a boundary rather than
    /// an off switch — and is SwiftUI's rule too.
    ///
    /// - Parameter isBlocking: Whether to block the cascade. Default `true`.
    public func submitScope(_ isBlocking: Bool = true) -> some View {
        SubmitScopeModifier(content: self, isBlocking: isBlocking)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension OnSubmitModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension SubmitScopeModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Each draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnSubmitModifier: DrawsContentUnchanged {}
extension SubmitScopeModifier: DrawsContentUnchanged {}
