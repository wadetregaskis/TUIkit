//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Container Config

/// Shared visual configuration for container-type views.
///
/// Groups the common appearance properties used by ``Alert``, ``Dialog``,
/// ``Panel``, and ``Card``. Each view stores a `ContainerConfig` instead
/// of repeating the same five properties.
///
/// # Example
///
/// ```swift
/// let config = ContainerConfig(
///     borderStyle: .doubleLine,
///     borderColor: .cyan,
///     titleColor: .cyan
/// )
/// ```
struct ContainerConfig: Sendable, Equatable {
    /// The border style (nil uses appearance default).
    var borderStyle: BorderStyle?

    /// The border color (nil uses theme default).
    var borderColor: Color?

    /// The title color (nil uses theme accent).
    var titleColor: Color?

    /// The inner padding for the body content.
    var padding: EdgeInsets

    /// Whether to show a separator line between body and footer.
    var showFooterSeparator: Bool

    /// How the footer content is aligned within the container width. Defaults to
    /// `.leading`; `.center`/`.trailing` shift the (narrower-than-the-box) footer.
    var footerAlignment: HorizontalAlignment

    /// Whether the container draws a border. When `false`, no top/bottom/side
    /// border glyphs are drawn (body and footer render at full width with no
    /// side walls) and the chrome height excludes the two border rows. This is
    /// distinct from a `nil` ``borderStyle``, which still draws a border using
    /// the appearance default — it is the only "no border at all" path. Used by
    /// `.listStyle(.plain)` (``PlainListStyle/showsBorder`` is `false`).
    var hasBorder: Bool

    /// Whether an over-tall BODY scrolls instead of being clipped, leaving the
    /// title and footer pinned.
    ///
    /// Off for ordinary containers: a `.border()` or `Card` around arbitrary
    /// content should not silently become scrollable, gaining a focus stop and
    /// scroll chrome the author never asked for. `Dialog` turns it on, because a
    /// dialog is the one container whose chrome — the title and the Done/Cancel
    /// footer — must stay reachable no matter how short the terminal is, and
    /// whose body is the part that can afford to scroll.
    var scrollsOverflowingBody: Bool

    /// Creates a container configuration.
    ///
    /// - Parameters:
    ///   - borderStyle: The border style (default: appearance default).
    ///   - borderColor: The border color (default: theme border).
    ///   - titleColor: The title color (default: theme accent).
    ///   - padding: The inner padding (default: horizontal 1, vertical 0).
    ///   - showFooterSeparator: Show separator before footer (default: true).
    ///   - footerAlignment: How to align the footer (default: leading).
    ///   - hasBorder: Whether to draw a border at all (default: true).
    ///   - scrollsOverflowingBody: Whether a too-tall body scrolls rather than
    ///     being clipped, with the title and footer pinned (default: false).
    init(
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil,
        padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
        showFooterSeparator: Bool = true,
        footerAlignment: HorizontalAlignment = .leading,
        hasBorder: Bool = true,
        scrollsOverflowingBody: Bool = false
    ) {
        self.borderStyle = borderStyle
        self.borderColor = borderColor
        self.titleColor = titleColor
        self.padding = padding
        self.showFooterSeparator = showFooterSeparator
        self.footerAlignment = footerAlignment
        self.hasBorder = hasBorder
        self.scrollsOverflowingBody = scrollsOverflowingBody
    }

    /// Default configuration.
    static let `default` = Self()
}

// MARK: - Container Style

/// Configuration options for container appearance.
///
/// Controls separators, backgrounds, and other visual aspects of containers.
struct ContainerStyle: Sendable, Equatable {
    /// Whether to show a separator line between header and body.
    var showHeaderSeparator: Bool

    /// Whether to show a separator line between body and footer.
    var showFooterSeparator: Bool

    /// The border style (nil uses appearance default).
    var borderStyle: BorderStyle?

    /// The border colour (nil uses the theme's), as every frame of it.
    ///
    /// An ``AnimatedColor`` rather than a `Color` because the border is drawn
    /// here and only here: a caller that wants it to breathe cannot know which
    /// cells to animate, and this is the type that lets it not have to. A
    /// still colour is one frame, so the common case costs nothing.
    var borderColor: AnimatedColor?

    /// How the footer content is aligned within the container width (default
    /// leading). See ``ContainerConfig/footerAlignment``.
    var footerAlignment: HorizontalAlignment

    /// Whether the container draws a border. See ``ContainerConfig/hasBorder``.
    var hasBorder: Bool

    /// Whether an over-tall body scrolls with the title/footer pinned.
    /// See ``ContainerConfig/scrollsOverflowingBody``.
    var scrollsOverflowingBody: Bool

    /// Creates a container style with the specified options.
    ///
    /// - Parameters:
    ///   - showHeaderSeparator: Show separator after header (default: true).
    ///   - showFooterSeparator: Show separator before footer (default: true).
    ///   - borderStyle: The border style (default: appearance default).
    ///   - borderColor: The border color (default: theme border).
    ///   - footerAlignment: How to align the footer (default: leading).
    ///   - hasBorder: Whether to draw a border at all (default: true).
    ///   - scrollsOverflowingBody: Whether a too-tall body scrolls (default: false).
    init(
        showHeaderSeparator: Bool = true,
        showFooterSeparator: Bool = true,
        borderStyle: BorderStyle? = nil,
        borderColor: AnimatedColor? = nil,
        footerAlignment: HorizontalAlignment = .leading,
        hasBorder: Bool = true,
        scrollsOverflowingBody: Bool = false
    ) {
        self.showHeaderSeparator = showHeaderSeparator
        self.showFooterSeparator = showFooterSeparator
        self.borderStyle = borderStyle
        self.borderColor = borderColor
        self.footerAlignment = footerAlignment
        self.hasBorder = hasBorder
        self.scrollsOverflowingBody = scrollsOverflowingBody
    }

    /// Creates a `ContainerStyle` from a ``ContainerConfig``.
    ///
    /// - Parameter config: The container configuration to use.
    init(from config: ContainerConfig) {
        self.showHeaderSeparator = true
        self.showFooterSeparator = config.showFooterSeparator
        self.borderStyle = config.borderStyle
        self.borderColor = config.borderColor.map(AnimatedColor.init)
        self.footerAlignment = config.footerAlignment
        self.hasBorder = config.hasBorder
        self.scrollsOverflowingBody = config.scrollsOverflowingBody
    }

    /// Default container style.
    static let `default` = Self()
}

// MARK: - Render Helper

/// Renders a `ContainerView` from a `ContainerConfig` and content/footer views.
///
/// Eliminates the duplicated `if/else` footer pattern found in Alert, Dialog,
/// Panel, and Card.
///
/// - Parameters:
///   - title: The container title (optional).
///   - config: The shared visual configuration.
///   - content: The body content view.
///   - footer: The footer view (optional).
///   - context: The current render context.
/// - Returns: The rendered frame buffer.
@MainActor
internal func renderContainer<Content: View, Footer: View>(
    title: String?,
    config: ContainerConfig,
    content: Content,
    footer: Footer?,
    context: RenderContext
) -> FrameBuffer {
    TUIkit.renderToBuffer(
        makeContainer(title: title, config: config, content: content, footer: footer), context: context)
}

/// Measures a `ContainerView` from a `ContainerConfig` and content/footer views.
///
/// The measure-side twin of ``renderContainer``: it builds the *identical*
/// `ContainerView` and measures it (reaching the `Layoutable`
/// `_ContainerViewCore.sizeThatFits`) instead of rendering it. Container cores
/// (`_PanelCore`, `_CardCore`, `_AlertCore`, `_DialogCore`) delegate their
/// `sizeThatFits` here so a labeled container measures analytically instead of
/// falling through `measureChild`'s render-to-measure fallback — the same win
/// `.border()` got when `_ContainerViewCore` became `Layoutable`. Because both
/// functions construct the same `ContainerView`, the two passes cannot disagree.
///
/// - Parameters:
///   - title: The container title (optional).
///   - config: The shared visual configuration.
///   - content: The body content view.
///   - footer: The footer view (optional).
///   - proposal: The proposed size from the parent.
///   - context: The current render context.
/// - Returns: The size the container needs.
@MainActor
internal func measureContainer<Content: View, Footer: View>(
    title: String?,
    config: ContainerConfig,
    content: Content,
    footer: Footer?,
    proposal: ProposedSize,
    context: RenderContext
) -> ViewSize {
    measureChild(
        makeContainer(title: title, config: config, content: content, footer: footer),
        proposal: proposal, context: context)
}

/// The height a container built by `renderContainer` offers its body.
///
/// For a view that decides how much content to make before handing it over. A
/// `List` fills its body with exactly as many row lines as fit, and the
/// container clips a taller body from the bottom — so the list asks, rather than
/// repeating the container's arithmetic. Its own copy charged a flat two lines
/// for "footer + separator", which hid the last row under a footer that wrapped
/// and left the box a line short under `.listFooterSeparator(false)`.
///
/// Built by `makeContainer`, like the render, so the footer is measured at the
/// identity and in the environment it is drawn in. That costs one
/// side-effect-free render of the footer; without a footer it is arithmetic.
///
/// - Parameters:
///   - title: The container title (optional).
///   - config: The shared visual configuration.
///   - content: A body of the type that will be rendered. Its TYPE is part of
///     the footer's identity; its value is never read.
///   - footer: The footer view (optional).
///   - context: The context the container will be rendered in.
/// - Returns: The height the container will offer its body.
@MainActor
internal func containerBodyHeight<Content: View, Footer: View>(
    title: String?,
    config: ContainerConfig,
    content: Content,
    footer: Footer?,
    context: RenderContext
) -> Int {
    // No footer to measure, and `makeContainer` draws no separator without one,
    // so the chrome is the border alone — `verticalBudget`'s answer, without
    // rendering an empty footer to learn that it is empty.
    guard footer != nil else {
        return RenderContext.extent(context.availableHeight, insideChrome: config.hasBorder ? 2 : 0)
    }
    return makeContainer(title: title, config: config, content: content, footer: footer)
        .bodyHeight(in: context)
}

/// The one `ContainerView` that `renderContainer`, `measureContainer` and
/// `containerBodyHeight` build, so they cannot disagree about its style — or
/// about its type, which every identity inside it descends from.
@MainActor
private func makeContainer<Content: View, Footer: View>(
    title: String?,
    config: ContainerConfig,
    content: Content,
    footer: Footer?
) -> ContainerView<Content, Footer?> {
    let hasFooter = footer != nil
    let style = ContainerStyle(
        showHeaderSeparator: true,
        showFooterSeparator: hasFooter && config.showFooterSeparator,
        borderStyle: config.borderStyle,
        borderColor: config.borderColor.map(AnimatedColor.init),
        footerAlignment: config.footerAlignment,
        hasBorder: config.hasBorder,
        scrollsOverflowingBody: config.scrollsOverflowingBody
    )

    return ContainerView(
        title: title,
        titleColor: config.titleColor,
        style: style,
        padding: config.padding
    ) {
        content
    } footer: {
        if let footerView = footer {
            footerView
        }
    }
}

// MARK: - Container View

/// A unified container with optional header, body, and footer sections.
///
/// `ContainerView` provides a consistent structure for all container-type views
/// like Panel, Card, Alert, and Dialog. It handles the rendering logic for
/// borders, separators, and section backgrounds.
///
/// ## Behavior by Appearance
///
/// - **Standard appearances** (line, rounded, doubleLine, heavy):
///   Title is rendered IN the top border. Footer is a separate section.
///
/// ## Example
///
/// ```swift
/// ContainerView(
///     title: "Settings",
///     style: ContainerStyle(showFooterSeparator: true)
/// ) {
///     Text("Option 1")
///     Text("Option 2")
/// } footer: {
///     ButtonRow {
///         Button("Save") { }
///         Button("Cancel") { }
///     }
/// }
/// ```
struct ContainerView<Content: View, Footer: View>: View {
    /// The container title (rendered in border or header section).
    let title: String?

    /// The title color.
    let titleColor: Color?

    /// The main content.
    let content: Content

    /// The footer content (typically buttons).
    let footer: Footer?

    /// The container style configuration.
    let style: ContainerStyle

    /// The inner padding for the body.
    let padding: EdgeInsets

    /// Creates a container with all options.
    ///
    /// - Parameters:
    ///   - title: The title (optional).
    ///   - titleColor: The title color (default: theme accent).
    ///   - style: The container style configuration.
    ///   - padding: Inner padding for body content.
    ///   - content: The main content.
    ///   - footer: The footer content (optional).
    init(
        title: String? = nil,
        titleColor: Color? = nil,
        style: ContainerStyle = .default,
        padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.titleColor = titleColor
        self.style = style
        self.padding = padding
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        core
    }

    /// What `body` returns — named so `bodyHeight(in:)` asks the very value the
    /// render walk descends into, not a second construction of it.
    private var core: _ContainerViewCore<Content, Footer> {
        _ContainerViewCore(
            title: title,
            titleColor: titleColor,
            content: content,
            footer: footer,
            style: style,
            padding: padding
        )
    }

    /// The height this container offers its body in `context` — see the core's
    /// `bodyHeight(in:)`.
    ///
    /// Descends to the core at the identity the render walk gives a composite
    /// view's `body` (`withChildIdentity(type: Body.self)`, exactly as
    /// `renderToBuffer` does), because the footer's identity hangs off it — and
    /// with it any `@State` the footer's height depends on.
    func bodyHeight(in context: RenderContext) -> Int {
        core.bodyHeight(in: context.withChildIdentity(type: Body.self))
    }
}

// MARK: - Body Budget

// The core's own arithmetic, kept beside the view only because
// `ContainerViewCore.swift` is at its file-length budget. The core's
// `renderToBuffer(context:)` renders by `verticalBudget`; `bodyHeight(in:)`
// answers from it.
extension _ContainerViewCore {
    /// How the height this container is offered divides between its chrome,
    /// its footer and its body.
    ///
    /// The footer is MEASURED — rendered with `isMeasuring` set, so nothing
    /// registers — never assumed to be a line: text wraps, and a column of views
    /// is as tall as it is. It is settled before the body, which gets what is
    /// left and is clipped from the bottom to it.
    ///
    /// - Parameters:
    ///   - availableHeight: The height the container itself was offered.
    ///   - innerWidth: The width between the side borders.
    ///   - footerContext: The footer's context, derived as `renderToBuffer` derives it.
    /// - Returns: The chrome's rows (borders and footer separator), the height
    ///   inside them, the measured footer, and the height left for the body.
    func verticalBudget(availableHeight: Int, innerWidth: Int, footerContext: RenderContext) -> (
        chromeHeight: Int, innerAvailableHeight: Int, measuredFooter: FrameBuffer?, bodyAvailableHeight: Int
    ) {
        let chromeHeight = (style.hasBorder ? 2 : 0) + ((footer != nil && style.showFooterSeparator) ? 1 : 0)
        let innerAvailableHeight = RenderContext.extent(availableHeight, insideChrome: chromeHeight)
        var measuredFooter: FrameBuffer?
        if let footerView = footer {
            var measureContext = footerContext
            measureContext.isMeasuring = true
            measureContext.availableHeight = innerAvailableHeight
            measuredFooter = TUIkit.renderToBuffer(footerView.padding(footerPadding), context: measureContext)
                .clamped(toWidth: innerWidth, height: innerAvailableHeight)
        }
        let bodyAvailableHeight = RenderContext.extent(
            innerAvailableHeight, insideChrome: measuredFooter?.height ?? 0)
        return (chromeHeight, innerAvailableHeight, measuredFooter, bodyAvailableHeight)
    }

    /// The height `renderToBuffer(context:)` offers this container's body in
    /// `context`.
    ///
    /// Not a copy of the arithmetic: it derives the footer's context by the
    /// render's own steps — the width between the borders, the focus indicator
    /// and sheet detent this box consumes rather than passes down, the footer's
    /// identity and published stack axis — and answers from `verticalBudget`.
    /// A footer measured any other way can come out a different height from the
    /// one drawn: inside an `HStack`, a `Divider` between two footer views is a
    /// full-height vertical rule unless the stack axis is published.
    func bodyHeight(in context: RenderContext) -> Int {
        var innerContext = context.forBorderedContent(hasBorder: style.hasBorder)
        innerContext.environment.focusIndicator = nil
        innerContext.environment.sheetDetentHeight = nil
        let footerContext = publishingStackAxis(
            innerContext.withChildIdentity(type: Footer.self, index: 1), stacking: footer)
        return verticalBudget(
            availableHeight: context.availableHeight, innerWidth: innerContext.availableWidth,
            footerContext: footerContext
        ).bodyAvailableHeight
    }
}

// MARK: - Equatable Conformance

extension ContainerView: @preconcurrency Equatable where Content: Equatable, Footer: Equatable {
    static func == (lhs: ContainerView<Content, Footer>, rhs: ContainerView<Content, Footer>) -> Bool {
        lhs.title == rhs.title && lhs.titleColor == rhs.titleColor && lhs.content == rhs.content && lhs.footer == rhs.footer
            && lhs.style == rhs.style && lhs.padding == rhs.padding
    }
}

// MARK: - Convenience Initializer (no footer)

extension ContainerView where Footer == EmptyView {
    /// Creates a container without a footer.
    ///
    /// - Parameters:
    ///   - title: The title (optional).
    ///   - titleColor: The title color (default: theme accent).
    ///   - style: The container style configuration.
    ///   - padding: Inner padding for body content.
    ///   - content: The main content.
    init(
        title: String? = nil,
        titleColor: Color? = nil,
        style: ContainerStyle = .default,
        padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleColor = titleColor
        self.style = style
        self.padding = padding
        self.content = content()
        self.footer = nil
    }
}
