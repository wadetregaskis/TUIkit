//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Menu.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// A control for presenting a menu of actions — mirrors SwiftUI's `Menu`.
///
/// The items are ordinary `Button`s (and `Divider`s), exactly as in SwiftUI, so
/// they carry their own actions, roles and keyboard shortcuts:
///
/// ```swift
/// Menu("Actions") {
///     Button("Rename") { rename() }
///     Button("Duplicate") { duplicate() }
///     Divider()
///     Button("Delete", role: .destructive) { delete() }
/// }
/// ```
///
/// By default the label is a collapsed control that opens the items as a
/// floating menu — Enter or a click opens it, Escape or a click outside closes
/// it, and choosing an item runs its action and closes it. Apply
/// ``SwiftUICore/View/menuStyle(_:)`` with ``MenuStyle/inline`` to show the
/// items expanded in place under the label instead, which is what a terminal
/// app's landing screen usually wants:
///
/// ```swift
/// Menu("Demos") {
///     Button("Text Styles") { page = .textStyles }
///         .keyboardShortcut("1", modifiers: [])
///     Button("Colors") { page = .colors }
///         .keyboardShortcut("2", modifiers: [])
/// }
/// .menuStyle(.inline)
/// ```
///
/// A row prints its button's key equivalent at its trailing edge, the way a
/// menu item's is drawn on every desktop platform — see
/// ``KeyboardShortcut/displayString``.
///
/// > Note: SwiftUI's `primaryAction:` initialisers are not offered. They split
/// > a menu into "click does one thing, a long press or a separate chevron
/// > opens the rest", and a terminal has neither a long press nor a reliable
/// > way to aim at part of a one-line control.
public struct Menu<Label: View, Content: View>: View {
    let content: Content
    let label: Label

    /// Creates a menu with a custom label.
    ///
    /// - Parameters:
    ///   - content: The menu's items — `Button`s and `Divider`s.
    ///   - label: A view describing the menu.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    public var body: some View {
        _MenuStyleBody(
            configuration: MenuStyleConfiguration(
                label: MenuStyleConfiguration.Label(content: AnyView(label)),
                content: MenuStyleConfiguration.Content(
                    content: AnyView(content),
                    // Captured here, where `Content` is still concrete, so the
                    // items can flatten into the style's column — see the
                    // `ChildViewProvider` conformance on the configuration.
                    children: { resolveChildViews(from: content, context: $0) })))
    }
}

extension Menu where Label == Text {
    /// Creates a menu that generates its label from a string.
    ///
    /// - Parameters:
    ///   - title: The menu's title.
    ///   - content: The menu's items — `Button`s and `Divider`s.
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

// MARK: - Style bridge

/// Renders whichever ``MenuStyle`` is in force.
///
/// `Renderable` because the style is held as an existential: opening it to call
/// ``MenuStyle/makeBody(configuration:)`` needs the buffer-returning bridge, the
/// same shape `Button` uses for `ButtonStyle`.
private struct _MenuStyleBody: View, Renderable, Layoutable {
    let configuration: MenuStyleConfiguration

    var body: Never {
        fatalError("_MenuStyleBody renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.environment.menuStyle.makeBuffer(configuration: configuration, context: context)
    }
}
