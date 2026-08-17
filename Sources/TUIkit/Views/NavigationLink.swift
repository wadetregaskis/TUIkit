//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationLink.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - NavigationLink

/// A control that pushes a screen onto the enclosing ``NavigationStack``.
/// Matches SwiftUI's type of the same name.
///
/// There are two ways to say what to show, and they are the two SwiftUI offers.
/// Push a **value**, and let a `.navigationDestination(for:)` somewhere in the
/// stack decide what it looks like:
///
/// ```swift
/// NavigationLink("Bread", value: Recipe.bread)
/// ```
///
/// …or push a **view** directly, when the screen is one specific thing and
/// there is no data to route on:
///
/// ```swift
/// NavigationLink("Settings") { SettingsView() }
/// ```
///
/// A link renders as a `Button`, so it is a Tab stop, it activates with
/// Return/Space, and a click works — everything a `Button` does, including
/// `.buttonStyle(_:)`. A link with a `nil` value is disabled, as in SwiftUI.
///
/// > Note: A view destination needs a path that can hold the link's own token,
///   so it works in `NavigationStack { … }` and with a ``NavigationPath``
///   binding. A *typed* path binding (`NavigationStack(path: $recipes)`) can by
///   definition only carry `Recipe`s — use `NavigationLink(value:)` with one.
public struct NavigationLink<Label: View, Destination: View>: View {

    /// What this link pushes.
    enum Target {
        /// A value, routed through `.navigationDestination(for:)`. `nil`
        /// disables the link.
        case value(AnyHashable?)
        /// A view, registered with the stack under this link's identity.
        case view(Destination)
    }

    let target: Target
    let label: Label

    public var body: some View {
        _NavigationLinkCore(target: target, label: label)
    }
}

// MARK: - Value destinations

extension NavigationLink where Destination == Never {

    /// Creates a link that pushes `value` onto the stack's path.
    ///
    /// - Parameters:
    ///   - value: The value to push. `nil` disables the link.
    ///   - label: The link's visible content.
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {
        self.target = .value(value.map { AnyHashable($0) })
        self.label = label()
    }

    /// Creates a link with a localized label that pushes `value` onto the path.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the link's title.
    ///   - value: The value to push. `nil` disables the link.
    public init<P: Hashable>(_ titleKey: LocalizedStringKey, value: P?) where Label == Text {
        self.init(titleKey.localized, value: value)
    }

    /// Creates a link with a text label, shown as written, that pushes `value`.
    ///
    /// - Parameters:
    ///   - title: The link's title.
    ///   - value: The value to push. `nil` disables the link.
    @_disfavoredOverload
    public init<S: StringProtocol, P: Hashable>(_ title: S, value: P?) where Label == Text {
        self.target = .value(value.map { AnyHashable($0) })
        self.label = Text(String(title))
    }
}

// MARK: - View destinations

extension NavigationLink {

    /// Creates a link that pushes `destination` onto the stack.
    ///
    /// - Parameters:
    ///   - destination: A view builder for the screen to show.
    ///   - label: The link's visible content.
    public init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.target = .view(destination())
        self.label = label()
    }

    /// Creates a link with a localized label that pushes `destination`.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the link's title.
    ///   - destination: A view builder for the screen to show.
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder destination: () -> Destination
    ) where Label == Text {
        self.init(titleKey.localized, destination: destination)
    }

    /// Creates a link with a text label, shown as written, pushing `destination`.
    ///
    /// - Parameters:
    ///   - title: The link's title.
    ///   - destination: A view builder for the screen to show.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        @ViewBuilder destination: () -> Destination
    ) where Label == Text {
        self.target = .view(destination())
        self.label = Text(String(title))
    }
}

// MARK: - Core

/// Renders the link as a `Button` whose action pushes onto the stack's path.
///
/// A `_*Core` rather than plain composition because the action needs two things
/// only a render context carries: the coordinator to push onto, and — for a
/// view destination — this link's own identity path to register the view under.
/// Both are captured into the closure at render time, never read from the
/// environment when the button fires, which is nil by then.
private struct _NavigationLinkCore<Label: View, Destination: View>: View, Renderable, Layoutable {
    let target: NavigationLink<Label, Destination>.Target
    let label: Label

    var body: Never {
        fatalError("_NavigationLinkCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let button = button(context: context, registerViewDestination: !context.isMeasuring)
        return TUIkit.renderToBuffer(button, context: context.withChildIdentity(type: type(of: button)))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Registering a view destination is a render-pass side effect; a
        // measure only needs the button's geometry.
        let button = button(context: context, registerViewDestination: false)
        return measureChild(button, proposal: proposal, context: context.withChildIdentity(type: type(of: button)))
    }

    /// The button this link is, with its push action bound.
    private func button(context: RenderContext, registerViewDestination: Bool) -> some View {
        let coordinator = context.environment.navigationCoordinator
        let content = label
        let action: () -> Void
        var isDisabled = false

        switch target {
        case .value(let value):
            // A nil value disables the link, as in SwiftUI — there is nothing
            // to push, and a control that looks live but does nothing is worse
            // than one that looks unavailable.
            isDisabled = value == nil
            action = {
                guard let value else { return }
                coordinator?.push(value)
            }

        case .view(let destination):
            // The identity path is stable across frames and unique per link, so
            // it is both a good registry key and a good token: pushing it puts
            // "the screen this link owns" on the path without the link having
            // any data of its own.
            let token = NavigationViewToken(id: context.identity.path)
            if registerViewDestination {
                coordinator?.register(viewDestination: AnyView(destination), forToken: token.id)
            }
            action = { coordinator?.push(AnyHashable(token)) }
        }

        return Button(action: action) { content }
            .disabled(isDisabled || coordinator == nil)
    }
}
