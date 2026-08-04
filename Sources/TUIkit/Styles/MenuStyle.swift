//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - MenuStyleConfiguration

/// The label and content of a ``Menu``, handed to a ``MenuStyle`` so it can
/// produce the menu's appearance — mirrors SwiftUI's `MenuStyleConfiguration`.
///
/// You don't create this type yourself; TUIkit builds one for each `Menu`.
public struct MenuStyleConfiguration {
    /// A type-erased view of the menu's label — its title, or whatever the
    /// caller built with the `label:` closure.
    public struct Label: View {
        let content: AnyView

        public var body: some View { content }
    }

    /// A type-erased view of the menu's items: the `Button`s and `Divider`s
    /// from the `content:` closure.
    public struct Content: View {
        let content: AnyView

        /// The items as separate children of whatever stack a style puts this
        /// in — see the ``ChildViewProvider`` conformance below. Captured in
        /// ``Menu`` where the items' concrete type is still known.
        let children: @MainActor (RenderContext) -> [ChildView]

        public var body: some View { content }
    }

    /// The menu's label.
    public let label: Label

    /// The menu's items.
    public let content: Content
}

/// The items flatten into whatever stack a style places them in — SwiftUI
/// semantics, and the same flattening a conditional's branch gets: a `ForEach`
/// of `Button`s must contribute its rows to the menu's column, not arrive as
/// one opaque block. (A bare `ForEach` has no standalone rendering, so without
/// this the rows silently vanish — which is exactly what happened.)
///
/// The children are resolved through a closure captured in ``Menu``, where the
/// items' concrete type is still known: by the time they are here they have
/// been erased, and `AnyView` is not itself a child-view provider.
extension MenuStyleConfiguration.Content: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        children(context)
    }
}

// MARK: - MenuStyle

/// A type that applies a standard appearance to all menus within a view
/// hierarchy — mirrors SwiftUI's `MenuStyle`.
///
/// Set it with ``View/menuStyle(_:)``:
///
/// ```swift
/// Menu("Actions") {
///     Button("Rename") { rename() }
///     Button("Delete", role: .destructive) { delete() }
/// }
/// .menuStyle(.inline)
/// ```
///
/// ## Built-in styles
///
/// - ``DefaultMenuStyle`` (``automatic``) — a collapsed label that opens a
///   floating menu, the way a pop-up button behaves everywhere else.
/// - ``InlineMenuStyle`` (``inline``) — the items expanded in place under a
///   heading, always visible.
public protocol MenuStyle: Sendable {
    /// A view that represents the body of a menu.
    associatedtype Body: View

    /// Creates a view that represents the body of a menu.
    ///
    /// - Parameter configuration: The label and items of the menu being styled.
    /// - Returns: A view describing the menu's appearance.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The label and content of a menu.
    typealias Configuration = MenuStyleConfiguration
}

extension MenuStyle {
    /// Renders this style's body for `configuration` into a frame buffer.
    ///
    /// Call sites hold the style as `any MenuStyle`; this opens the existential
    /// so ``makeBody(configuration:)`` can return its concrete ``Body``, which
    /// the renderer then resolves. (Same shape as `ButtonStyle.makeBuffer`.)
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }
}

// MARK: - Built-in styles

/// The default menu style: a collapsed label that opens the items as a floating
/// menu, dismissed by Escape, by choosing an item, or by clicking outside.
///
/// Access this style with the ``MenuStyle/automatic`` static property.
public struct DefaultMenuStyle: MenuStyle {
    /// Creates a default menu style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _MenuPopupCore(label: configuration.label, content: configuration.content)
    }
}

/// A menu style that shows the items expanded in place, under the label as a
/// heading — nothing to open, everything visible.
///
/// Access this style with the ``MenuStyle/inline`` static property.
///
/// - Note: TUI-specific addition; SwiftUI has no inline menu style. A terminal
///   app's landing screen often *is* a menu, and it would be perverse to make
///   the user open the only thing on the page. Rendering it inline keeps that
///   screen a `Menu` — one API, one look, one set of keyboard shortcuts —
///   rather than a hand-built column of buttons.
public struct InlineMenuStyle: MenuStyle {
    /// Creates an inline menu style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _InlineMenuCore(label: configuration.label, content: configuration.content)
    }
}

extension MenuStyle where Self == DefaultMenuStyle {
    /// The default menu style — a collapsed label that opens a floating menu.
    public static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

extension MenuStyle where Self == InlineMenuStyle {
    /// A menu style that shows its items expanded in place.
    public static var inline: InlineMenuStyle { InlineMenuStyle() }
}

// MARK: - Environment

private struct MenuStyleKey: EnvironmentKey {
    static let defaultValue: any MenuStyle = DefaultMenuStyle()
}

extension EnvironmentValues {
    /// The menu style for this environment — see ``MenuStyle``. Set via
    /// ``View/menuStyle(_:)``. Default: ``DefaultMenuStyle``.
    public var menuStyle: any MenuStyle {
        get { self[MenuStyleKey.self] }
        set { self[MenuStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for menus within this view.
    ///
    /// ```swift
    /// Menu("Demos") { … }
    ///     .menuStyle(.inline)
    /// ```
    ///
    /// - Parameter style: The menu style to apply.
    /// - Returns: A view whose menus use the specified style.
    public func menuStyle<S: MenuStyle>(_ style: S) -> some View {
        environment(\.menuStyle, style)
    }
}
