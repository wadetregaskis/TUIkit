//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DisabledModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - isEnabled environment

/// Environment key for the cascading enabled state (SwiftUI's `\.isEnabled`).
///
/// `.disabled(true)` flips it to `false` for a whole subtree; controls combine
/// it with their own disabled state. It is **additive** — a descendant cannot
/// re-enable what an ancestor disabled.
private struct IsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether interactive controls in this subtree are enabled. Set via
    /// ``SwiftUI/View/disabled(_:)`` on a container; read by each control, which
    /// combines it with its own `disabled` state.
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
}

// MARK: - Disabled modifier

/// Disables every control in its content's subtree by ANDing `isEnabled` with
/// `!disabled` (a read-modify-write at render, so it composes additively — like
/// ``StyleCascadeModifier`` and ``EnvironmentModifier``).
public struct DisabledModifier<Content: View>: View {
    public let content: Content
    public let disabled: Bool

    public init(content: Content, disabled: Bool) {
        self.content = content
        self.disabled = disabled
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        let enabled = context.environment.isEnabled && !disabled
        return context.withEnvironment(context.environment.setting(\.isEnabled, to: enabled))
    }
}

extension DisabledModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension DisabledModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

extension View {
    /// Disables (or re-enables) every interactive control in this view's subtree.
    ///
    /// Cascades through the environment and is additive — once a container is
    /// `.disabled(true)`, a descendant `.disabled(false)` does not re-enable it.
    /// A control's own `.disabled(_:)` combines with this.
    ///
    /// ```swift
    /// VStack {
    ///     Button("Save") { … }
    ///     Toggle("Wrap", isOn: $wrap)
    /// }
    /// .disabled(!isEditable)   // both controls disabled together
    /// ```
    public func disabled(_ disabled: Bool = true) -> some View {
        DisabledModifier(content: self, disabled: disabled)
    }
}
