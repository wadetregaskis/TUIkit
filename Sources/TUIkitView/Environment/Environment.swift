//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Environment Modifier

/// A modifier that injects a value into the environment for child views.
///
/// `EnvironmentModifier` conforms to both `View` and ``Renderable``.
/// Because ``renderToBuffer(_:context:)`` checks `Renderable` first,
/// the `body` property below is **never called during rendering**.
/// It exists only to satisfy the `View` protocol requirement.
/// All actual work happens in `renderToBuffer(context:)`.
public struct EnvironmentModifier<Content: View, V>: View {
    /// The content view.
    public let content: Content

    /// The key path to modify.
    public let keyPath: WritableKeyPath<EnvironmentValues, V>

    /// The value to inject.
    public let value: V

    /// Creates a new environment modifier.
    public init(content: Content, keyPath: WritableKeyPath<EnvironmentValues, V>, value: V) {
        self.content = content
        self.keyPath = keyPath
        self.value = value
    }
    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View {
        content
    }
}

extension EnvironmentModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Create modified environment and render content with it.
        // The modified context carries the environment through the render tree —
        // no global state sync needed.
        let modifiedEnvironment = context.environment.setting(keyPath, to: value)
        let modifiedContext = context.withEnvironment(modifiedEnvironment)
        return TUIkitView.renderToBuffer(content, context: modifiedContext)
    }
}

// MARK: - Layoutable

extension EnvironmentModifier: Layoutable {
    /// Measures the wrapped content under the modified environment without
    /// rendering it.
    ///
    /// Without this conformance, `measureChild` would fall through to its
    /// render-to-measure fallback (the view is `Renderable` and its body
    /// returns the same content — `V.Body == Content`, which is also
    /// `View`, so it would still hit the fallback). That fallback renders
    /// the content to measure it (historically *twice* per measure — a
    /// second render at `naturalWidth + 8` probed flexibility, since
    /// retired). With `Image` typically wrapped in several environment
    /// modifiers (character set, colour mode, dithering, placeholder, …)
    /// and each layout pass touching it multiple times, that escalates
    /// into many ASCIIConverter runs per frame — the demo's "twelve-second
    /// render" was almost entirely re-running the ASCII conversion to
    /// *measure* the same image.
    ///
    /// Forwarding the measurement to the content under the modified
    /// environment matches the semantics of the render path and skips
    /// rendering the (possibly expensive) content to measure it.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let modifiedEnvironment = context.environment.setting(keyPath, to: value)
        let modifiedContext = context.withEnvironment(modifiedEnvironment)
        return measureChild(content, proposal: proposal, context: modifiedContext)
    }
}
