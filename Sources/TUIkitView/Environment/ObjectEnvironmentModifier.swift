//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ObjectEnvironmentModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation
import TUIkitCore

// MARK: - Object Environment Modifier

/// A modifier that injects an observable object into the environment by type.
///
/// The object is stored by its type, enabling retrieval via
/// `@Environment(MyModel.self)`. Only one object per type can be
/// stored at each level of the view hierarchy; inner modifiers
/// override outer ones for the same type.
///
/// This is framework infrastructure. Use the `.environment(_:)` modifier
/// on `View` instead.
public struct ObjectEnvironmentModifier<Content: View, T: Observable>: View {
    /// The content view.
    public let content: Content

    /// The observable object to inject.
    public let object: T

    /// Creates a new object environment modifier.
    ///
    /// - Parameters:
    ///   - content: The child view tree.
    ///   - object: The observable object to make available.
    public init(content: Content, object: T) {
        self.content = content
        self.object = object
    }

    /// Not used during rendering. ``Renderable`` conformance takes priority.
    public var body: some View {
        content
    }
}

// MARK: - Renderable

extension ObjectEnvironmentModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var modifiedEnvironment = context.environment
        modifiedEnvironment[observable: T.self] = object
        let modifiedContext = context.withEnvironment(modifiedEnvironment)
        return TUIkitView.renderToBuffer(content, context: modifiedContext)
    }
}

// MARK: - Layoutable

extension ObjectEnvironmentModifier: Layoutable {
    /// Measures the wrapped content under the injected observable, without
    /// rendering. This wrapper imposes no geometry of its own — its size is
    /// exactly the content's — so forwarding the measurement matches the render
    /// path and keeps the subtree out of `measureChild`'s render-to-measure
    /// fallback (which would render the content twice per measure). Mirrors
    /// ``EnvironmentModifier``'s conformance; injecting an observable has no
    /// layout effect, only an environment one.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        var modifiedEnvironment = context.environment
        modifiedEnvironment[observable: T.self] = object
        let modifiedContext = context.withEnvironment(modifiedEnvironment)
        return measureChild(content, proposal: proposal, context: modifiedContext)
    }
}
