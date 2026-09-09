//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabelStyle.swift
//
//  How a ``Label`` arranges its title and icon — and, more usefully in a
//  terminal, which of the two it shows at all.
//
//  Modelled on ``ButtonStyle``: an open protocol with `makeBody(configuration:)`,
//  because unlike ``GaugeStyle`` (whose shapes a terminal cannot draw) this is
//  pure recomposition of two views the caller already supplied. Anything a
//  custom style wants to do here, a terminal can do.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Configuration

/// The title and icon a ``LabelStyle`` arranges.
public struct LabelStyleConfiguration {
    /// The label's title view.
    public let title: AnyView

    /// The label's icon view.
    public let icon: AnyView

    /// Whether the icon can actually be drawn.
    ///
    /// `false` when ``Label/init(_:systemImage:)-(LocalizedStringKey,_)`` could not resolve the SF
    /// Symbol — no glyph, or no font that carries it. A style that would show
    /// only the icon shows the title instead rather than rendering an empty
    /// label; see ``IconOnlyLabelStyle``.
    public let iconIsVisible: Bool
}

// MARK: - Protocol

/// A type that arranges a ``Label``'s title and icon, mirroring SwiftUI's
/// `LabelStyle`.
///
/// Apply one with ``View/labelStyle(_:)``:
///
/// ```swift
/// Label("Favourites", systemImage: "star.fill")
///     .labelStyle(.titleOnly)
/// ```
///
/// The style applies to every label in the subtree, which is the point: a whole
/// toolbar can drop to ``IconOnlyLabelStyle`` when the terminal is narrow
/// without every call site changing.
public protocol LabelStyle: Sendable {
    /// A view that represents the body of a label.
    associatedtype Body: View

    /// Creates a view that represents the body of a label.
    ///
    /// - Parameter configuration: The title and icon being styled.
    /// - Returns: A view describing the label's appearance.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a label.
    typealias Configuration = LabelStyleConfiguration
}

extension LabelStyle {
    /// This style's body for `configuration`, type-erased.
    ///
    /// Call sites hold the style as `any LabelStyle`; this opens the
    /// existential so ``makeBody(configuration:)`` can return its concrete
    /// ``Body``. The same trick ``ButtonStyle/makeBuffer(configuration:context:)``
    /// uses, erased rather than rendered because ``Label`` composes its result
    /// into a real `body`.
    @MainActor
    func makeAnyBody(configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

// MARK: - Built-in Styles

/// The default: the icon, a cell of space, then the title.
///
/// The icon opts out of text decorations an enclosing view cascades — a
/// ``Link`` underlining its label, say — because an underline clashes with a
/// glyph's own strokes. The title still honours them.
public struct DefaultLabelStyle: LabelStyle {
    /// Creates the default label style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if configuration.iconIsVisible {
            HStack(spacing: 1) {
                configuration.icon
                    .underline(false)
                    .strikethrough(false)
                configuration.title
            }
        } else {
            configuration.title
        }
    }
}

/// Shows the title and hides the icon.
public struct TitleOnlyLabelStyle: LabelStyle {
    /// Creates a title-only label style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

/// Shows the icon and hides the title.
///
/// - Important: When the icon cannot be drawn — an unresolved SF Symbol, or no
///   font carrying it — this shows the **title** instead. SwiftUI can rely on a
///   symbol always rendering; a terminal cannot, and a label that silently
///   disappears is a worse outcome than one that is wider than asked for. Both
///   ``Label`` and this style agree on that fallback.
public struct IconOnlyLabelStyle: LabelStyle {
    /// Creates an icon-only label style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if configuration.iconIsVisible {
            configuration.icon
        } else {
            configuration.title
        }
    }
}

/// Shows both the title and the icon, whatever the context would otherwise
/// prefer.
public struct TitleAndIconLabelStyle: LabelStyle {
    /// Creates a title-and-icon label style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        DefaultLabelStyle().makeBody(configuration: configuration)
    }
}

// MARK: - Style Shorthands

extension LabelStyle where Self == DefaultLabelStyle {
    /// The default style: icon then title, or just the title when the icon
    /// cannot be drawn.
    public static var automatic: Self { DefaultLabelStyle() }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    /// A style that shows only the title.
    public static var titleOnly: Self { TitleOnlyLabelStyle() }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
    /// A style that shows only the icon — falling back to the title when the
    /// icon cannot be drawn.
    public static var iconOnly: Self { IconOnlyLabelStyle() }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    /// A style that shows both the title and the icon.
    public static var titleAndIcon: Self { TitleAndIconLabelStyle() }
}

// MARK: - Environment

/// Environment key for the label style.
private struct LabelStyleKey: EnvironmentKey {
    static let defaultValue: any LabelStyle = DefaultLabelStyle()
}

extension EnvironmentValues {
    /// The style ``Label`` views render with. Set via ``View/labelStyle(_:)``.
    /// Default: ``DefaultLabelStyle``.
    public var labelStyle: any LabelStyle {
        get { self[LabelStyleKey.self] }
        set { self[LabelStyleKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the style for labels within this view.
    ///
    /// ```swift
    /// VStack {
    ///     Label("Inbox", systemImage: "tray")
    ///     Label("Sent", systemImage: "paperplane")
    /// }
    /// .labelStyle(.titleOnly)
    /// ```
    ///
    /// - Parameter style: The label style to apply.
    /// - Returns: A view whose labels use the specified style.
    public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
        environment(\.labelStyle, style)
    }
}
