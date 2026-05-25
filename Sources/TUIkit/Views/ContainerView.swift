//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// Creates a container configuration.
    ///
    /// - Parameters:
    ///   - borderStyle: The border style (default: appearance default).
    ///   - borderColor: The border color (default: theme border).
    ///   - titleColor: The title color (default: theme accent).
    ///   - padding: The inner padding (default: horizontal 1, vertical 0).
    ///   - showFooterSeparator: Show separator before footer (default: true).
    init(
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil,
        titleColor: Color? = nil,
        padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
        showFooterSeparator: Bool = true
    ) {
        self.borderStyle = borderStyle
        self.borderColor = borderColor
        self.titleColor = titleColor
        self.padding = padding
        self.showFooterSeparator = showFooterSeparator
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

    /// The border color (nil uses theme default).
    var borderColor: Color?

    /// Creates a container style with the specified options.
    ///
    /// - Parameters:
    ///   - showHeaderSeparator: Show separator after header (default: true).
    ///   - showFooterSeparator: Show separator before footer (default: true).
    ///   - borderStyle: The border style (default: appearance default).
    ///   - borderColor: The border color (default: theme border).
    init(
        showHeaderSeparator: Bool = true,
        showFooterSeparator: Bool = true,
        borderStyle: BorderStyle? = nil,
        borderColor: Color? = nil
    ) {
        self.showHeaderSeparator = showHeaderSeparator
        self.showFooterSeparator = showFooterSeparator
        self.borderStyle = borderStyle
        self.borderColor = borderColor
    }

    /// Creates a `ContainerStyle` from a ``ContainerConfig``.
    ///
    /// - Parameter config: The container configuration to use.
    init(from config: ContainerConfig) {
        self.showHeaderSeparator = true
        self.showFooterSeparator = config.showFooterSeparator
        self.borderStyle = config.borderStyle
        self.borderColor = config.borderColor
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
    let hasFooter = footer != nil
    let style = ContainerStyle(
        showHeaderSeparator: true,
        showFooterSeparator: hasFooter && config.showFooterSeparator,
        borderStyle: config.borderStyle,
        borderColor: config.borderColor
    )

    let container = ContainerView(
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
    return TUIkit.renderToBuffer(container, context: context)
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
        _ContainerViewCore(
            title: title,
            titleColor: titleColor,
            content: content,
            footer: footer,
            style: style,
            padding: padding
        )
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

// MARK: - Container View Core

/// Internal rendering implementation for ContainerView.
///
/// This private struct contains all the complex rendering logic, allowing
/// ContainerView to have a proper `body: some View` that enables modifiers
/// to work correctly.
private struct _ContainerViewCore<Content: View, Footer: View>: View, Renderable {
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

    var body: Never {
        fatalError("_ContainerViewCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let appearance = context.environment.appearance
        let effectiveBorderStyle = style.borderStyle ?? appearance.borderStyle
        let palette = context.environment.palette
        let borderColor = style.borderColor?.resolve(with: palette) ?? palette.border

        // Inner context for content between the side borders (width − 2).
        // Padding width reduction is handled by PaddingModifier.adjustContext.
        var innerContext = context.forBorderedContent()

        // Consume focus indicator so nested containers don't also show it.
        let indicatorColor = context.environment.focusIndicatorColor
        innerContext.environment.focusIndicatorColor = nil

        // Vertical chrome: top + bottom border, plus the optional footer
        // separator. The body and footer must share whatever is left so the
        // assembled container never grows taller than `availableHeight`.
        let hasFooter = footer != nil
        let chromeHeight = 2 + ((hasFooter && style.showFooterSeparator) ? 1 : 0)
        let innerAvailableHeight = max(0, context.availableHeight - chromeHeight)

        // Measure the footer first (without side-effects) so the body knows
        // how much vertical space is left. Real focus registration happens in
        // the constrained re-render below, after the body — preserving Tab order.
        let footerPadding = EdgeInsets(horizontal: 1, vertical: 0)
        let measuredFooter: FrameBuffer?
        if let footerView = footer {
            var measureContext = innerContext
            measureContext.isMeasuring = true
            measureContext.availableHeight = innerAvailableHeight
            measuredFooter = TUIkit.renderToBuffer(footerView.padding(footerPadding), context: measureContext)
                .clamped(toWidth: innerContext.availableWidth, height: innerAvailableHeight)
        } else {
            measuredFooter = nil
        }
        let footerHeight = measuredFooter?.height ?? 0

        // Render the body into the space the chrome and footer leave.
        let bodyAvailableHeight = max(0, innerAvailableHeight - footerHeight)
        var bodyContext = innerContext
        bodyContext.availableHeight = bodyAvailableHeight
        let bodyBuffer = TUIkit.renderToBuffer(content.padding(padding), context: bodyContext)
            .clamped(toWidth: innerContext.availableWidth, height: bodyAvailableHeight)

        // Bordering empty content with no footer produces nothing
        // (e.g. `EmptyView().border()`).
        if bodyBuffer.isEmpty && footer == nil {
            return bodyBuffer
        }

        // Inner width: the widest of title / body / footer, capped at the
        // space available between the side borders.
        let titleWidth = title.map { $0.strippedLength + 4 } ?? 0  // " Title " + borders
        let footerNaturalWidth = measuredFooter?.width ?? 0
        let contentBasedWidth = max(titleWidth, bodyBuffer.width, footerNaturalWidth)
        let innerWidth = context.resolveContainerWidth(
            contentWidth: contentBasedWidth,
            innerAvailableWidth: innerContext.availableWidth
        )

        // Re-render the footer constrained to the final inner width — this is
        // the real render and registers focus, after the body.
        let footerBuffer: FrameBuffer?
        if let footerView = footer {
            var footerContext = innerContext
            footerContext.availableWidth = max(0, innerWidth - footerPadding.leading - footerPadding.trailing)
            footerContext.availableHeight = innerAvailableHeight
            footerBuffer = TUIkit.renderToBuffer(footerView.padding(footerPadding), context: footerContext)
                .clamped(toWidth: innerWidth, height: innerAvailableHeight)
        } else {
            footerBuffer = nil
        }

        let assembled = renderStandardStyle(
            bodyBuffer: bodyBuffer,
            footerBuffer: footerBuffer,
            innerWidth: innerWidth,
            borderStyle: effectiveBorderStyle,
            borderColor: borderColor,
            context: context,
            focusIndicatorColor: indicatorColor
        )
        // Final guard: never exceed the space the container was given.
        return assembled.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    // MARK: - Standard Style Rendering

    /// Renders with title in top border (line, rounded, doubleLine, heavy).
    private func renderStandardStyle(
        bodyBuffer: FrameBuffer,
        footerBuffer: FrameBuffer?,
        innerWidth: Int,
        borderStyle: BorderStyle,
        borderColor: Color,
        context: RenderContext,
        focusIndicatorColor: Color? = nil
    ) -> FrameBuffer {
        let palette = context.environment.palette
        var lines: [String] = []

        // Top border (with title if present)
        if let titleText = title {
            lines.append(
                BorderRenderer.standardTopBorder(
                    style: borderStyle,
                    innerWidth: innerWidth,
                    color: borderColor,
                    title: titleText,
                    titleColor: titleColor?.resolve(with: palette) ?? palette.accent,
                    focusIndicatorColor: focusIndicatorColor
                )
            )
        } else {
            lines.append(
                BorderRenderer.standardTopBorder(
                    style: borderStyle,
                    innerWidth: innerWidth,
                    color: borderColor,
                    focusIndicatorColor: focusIndicatorColor
                )
            )
        }

        // Body lines (no background color applied)
        for line in bodyBuffer.lines {
            lines.append(
                BorderRenderer.standardContentLine(
                    content: line,
                    innerWidth: innerWidth,
                    style: borderStyle,
                    color: borderColor
                )
            )
        }

        // Footer section (if present)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            if style.showFooterSeparator {
                lines.append(
                    BorderRenderer.standardDivider(
                        style: borderStyle,
                        innerWidth: innerWidth,
                        color: borderColor
                    )
                )
            }

            // Footer lines (no background - footer has its own styling)
            for line in footerBuf.lines {
                lines.append(
                    BorderRenderer.standardContentLine(
                        content: line,
                        innerWidth: innerWidth,
                        style: borderStyle,
                        color: borderColor
                    )
                )
            }
        }

        // Bottom border
        lines.append(
            BorderRenderer.standardBottomBorder(
                style: borderStyle,
                innerWidth: innerWidth,
                color: borderColor
            )
        )

        var result = FrameBuffer(lines: lines)
        // Carry overlay layers from the body and footer. The body content sits
        // one row below the top border and one column inside the left border;
        // the footer follows the body and its optional separator.
        var carried = bodyBuffer.shiftedOverlays(byX: 1, y: 1)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            let footerRow = 1 + bodyBuffer.lines.count + (style.showFooterSeparator ? 1 : 0)
            carried += footerBuf.shiftedOverlays(byX: 1, y: footerRow)
        }
        result.overlays = carried
        return result
    }
}

// MARK: - Equatable Conformance

extension _ContainerViewCore: @preconcurrency Equatable where Content: Equatable, Footer: Equatable {
    static func == (lhs: _ContainerViewCore<Content, Footer>, rhs: _ContainerViewCore<Content, Footer>) -> Bool {
        lhs.title == rhs.title && lhs.titleColor == rhs.titleColor && lhs.content == rhs.content && lhs.footer == rhs.footer
            && lhs.style == rhs.style && lhs.padding == rhs.padding
    }
}
