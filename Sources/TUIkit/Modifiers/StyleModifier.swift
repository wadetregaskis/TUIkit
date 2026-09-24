//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// weight maps to bold / normal / faint (see ``FontWeight``).
    ///
    /// `nil` removes the effect of any weight set further out, as SwiftUI
    /// documents: "Providing `nil` removes the effect of any font weight
    /// modifier applied higher in the view hierarchy." It resolves to
    /// ``FontWeight/regular``, which states not-bold and not-faint rather than
    /// saying nothing — and saying nothing is what it used to do, leaving an
    /// inherited `.bold()` in place with no way to escape it. A `Text`'s own
    /// weight still wins, being closer.
    public func fontWeight(_ weight: FontWeight?) -> some View {
        style(.text, (weight ?? .regular).styleAttributes)
    }

    /// Applies a case transform to all text in this view's subtree.
    ///
    /// `nil` clears one set further out rather than declining to speak, which
    /// is what SwiftUI's `Text.Case?` environment value means. See
    /// ``StyleAttributes/textCase``.
    public func textCase(_ textCase: TextCase?) -> some View {
        style(.text, StyleAttributes(textCase: .some(textCase)))
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension StyleCascadeModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<V: View>(_ view: V) -> any View {
        StyleCascadeModifier<V>(content: view, scope: scope, attributes: attributes)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension StyleCascadeModifier: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension StyleCascadeModifier: GridRowProviding where Content: GridRowProviding {}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension StyleCascadeModifier: DrawsContentUnchanged {}
