//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Style cascade modifier

/// Appends a scoped style entry to the environment's ``StyleCascade`` for its
/// content's subtree. The read-modify-write of the cascade happens at render
/// time, so this mirrors ``EnvironmentModifier`` (View + Renderable + Layoutable)
/// rather than using the plain `.environment(_:_:)` setter.
public struct StyleCascadeModifier<Content: View>: View {
    public let content: Content
    public let scope: StyleScope
    public let attributes: StyleAttributes

    public init(content: Content, scope: StyleScope, attributes: StyleAttributes) {
        self.content = content
        self.scope = scope
        self.attributes = attributes
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        let cascade = context.environment.styleCascade.appending(scope, attributes)
        return context.withEnvironment(context.environment.setting(\.styleCascade, to: cascade))
    }
}

extension StyleCascadeModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension StyleCascadeModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

// MARK: - Generic scoped-style modifiers

extension View {
    /// Applies `attributes` to every descendant matching `scope`. The general
    /// form of the styling cascade; the typed conveniences below build on it.
    public func style(_ scope: StyleScope, _ attributes: StyleAttributes) -> some View {
        StyleCascadeModifier(content: self, scope: scope, attributes: attributes)
    }

    /// Applies attributes built in the closure to every descendant matching `scope`.
    public func style(_ scope: StyleScope, _ build: (inout StyleAttributes) -> Void) -> some View {
        var attributes = StyleAttributes()
        build(&attributes)
        return style(scope, attributes)
    }
}

// MARK: - Broad text-attribute modifiers (SwiftUI parity)

extension View {
    /// Applies a bold style to all text in this view's subtree.
    ///
    /// Cascades through the environment; a descendant can opt out with
    /// `.bold(false)`. (`Text`'s own `.bold()` continues to return `Text`.)
    public func bold(_ enabled: Bool = true) -> some View {
        style(.text, StyleAttributes(bold: enabled))
    }

    /// Applies an italic style to all text in this view's subtree.
    public func italic(_ enabled: Bool = true) -> some View {
        style(.text, StyleAttributes(italic: enabled))
    }

    /// Underlines all text in this view's subtree.
    public func underline(_ enabled: Bool = true) -> some View {
        style(.text, StyleAttributes(underline: enabled))
    }

    /// Strikes through all text in this view's subtree.
    public func strikethrough(_ enabled: Bool = true) -> some View {
        style(.text, StyleAttributes(strikethrough: enabled))
    }

    /// Sets the font weight for all text in this view's subtree. On a terminal,
    /// weight maps to bold / normal / faint (see ``FontWeight``). `nil` leaves
    /// the inherited weight unchanged.
    public func fontWeight(_ weight: FontWeight?) -> some View {
        style(.text, weight?.styleAttributes ?? StyleAttributes())
    }

    /// Applies a case transform to all text in this view's subtree.
    public func textCase(_ textCase: TextCase?) -> some View {
        style(.text, StyleAttributes(textCase: textCase))
    }
}
