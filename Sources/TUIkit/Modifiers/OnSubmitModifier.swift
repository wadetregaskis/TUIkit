//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// Sets the semantic submit label for text inputs in this view's subtree —
    /// mirrors SwiftUI's `submitLabel(_:)`.
    ///
    /// SwiftUI draws this on the on-screen keyboard's Return key. A terminal has
    /// no such key, so the value is stored for source-compatibility (and future
    /// affordances such as a status-bar hint) rather than rendered.
    ///
    /// - Parameter submitLabel: The label describing the submit action.
    public func submitLabel(_ submitLabel: SubmitLabel) -> some View {
        environment(\.submitLabel, submitLabel)
    }
}
