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
    return measureChild(container, proposal: proposal, context: context)
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
private struct _ContainerViewCore<Content: View, Footer: View>: View, Renderable, Layoutable {
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

    /// Padding applied around the footer. A single source of truth shared by
    /// `renderToBuffer` and `sizeThatFits` so the two cannot disagree about the
    /// footer's width budget.
    private var footerPadding: EdgeInsets { EdgeInsets(horizontal: 1, vertical: 0) }

    var body: Never {
        fatalError("_ContainerViewCore renders via Renderable")
    }

    /// Measures the container analytically — mirroring `renderToBuffer`'s
    /// geometry but *measuring* the body and footer (cheap, and recursive
    /// through `Layoutable` children) instead of rendering the whole subtree
    /// and assembling its border chrome.
    ///
    /// `.border()` is a title- and footer-less `ContainerView`, so before this
    /// every bordered measure fell through `measureChild`'s render-to-measure
    /// fallback, which renders the entire subtree *twice* (once at the
    /// proposal, once at `naturalWidth + 8` to probe flexibility). Nested
    /// borders multiplied that: the layout-heavy RenderHarness trees
    /// (`alignment`, `nested` — deeply nested `.border()`s) ran ~12× and ~45×
    /// slower than the border-free `frames` tree. Measuring instead of
    /// double-rendering removes that cost; the measure/render equivalence
    /// tests pin the two passes together.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Resolve the space we were offered (proposal wins over the context,
        // exactly as renderChild sets availableWidth/Height before rendering).
        var base = context
        base.availableWidth = proposal.width ?? context.availableWidth
        base.availableHeight = proposal.height ?? context.availableHeight

        // Inner context between the side borders (width − 2), matching render.
        var innerContext = base.forBorderedContent()
        innerContext.environment.focusIndicatorColor = nil
        let innerWidthAvailable = innerContext.availableWidth

        // The body and footer are distinct structural children, so they get
        // distinct identities (index 0 / 1) rather than both inheriting the
        // container's. Otherwise their `@State` would share a storage slot, and
        // — since a footerless container's empty footer measures to height 0,
        // giving the body the same available height — they would collide on a
        // memoized-measurement key. Must match `renderToBuffer` exactly.
        let bodyInner = innerContext.withChildIdentity(type: Content.self, index: 0)
        let footerInner = innerContext.withChildIdentity(type: Footer.self, index: 1)

        // Vertical chrome: top + bottom border, plus the optional footer
        // separator — the same arithmetic renderToBuffer uses.
        let hasFooter = footer != nil
        let chromeHeight = 2 + ((hasFooter && style.showFooterSeparator) ? 1 : 0)
        let innerAvailableHeight = max(0, base.availableHeight - chromeHeight)

        // Footer at its natural (full inner) width: gives the height the body
        // must share and the footer's contribution to the inner-width vote.
        var footerNaturalWidth = 0
        var footerNaturalHeight = 0
        var footerFlexibleHeight = false
        if let footerView = footer {
            var footerContext = footerInner
            footerContext.availableHeight = innerAvailableHeight
            let size = measureChild(
                footerView.padding(footerPadding),
                proposal: ProposedSize(width: innerWidthAvailable, height: innerAvailableHeight),
                context: footerContext)
            footerNaturalWidth = min(size.width, innerWidthAvailable)
            footerNaturalHeight = min(size.height, innerAvailableHeight)
            footerFlexibleHeight = size.isHeightFlexible
        }

        // Body into the space the chrome and footer leave.
        let bodyAvailableHeight = max(0, innerAvailableHeight - footerNaturalHeight)
        var bodyContext = bodyInner
        bodyContext.availableHeight = bodyAvailableHeight
        let bodySize = measureChild(
            content.padding(padding),
            proposal: ProposedSize(width: innerWidthAvailable, height: bodyAvailableHeight),
            context: bodyContext)
        let bodyWidth = min(bodySize.width, innerWidthAvailable)
        let bodyHeight = min(bodySize.height, bodyAvailableHeight)

        // Bordering empty content with no footer produces nothing: render's
        // `bodyBuffer.isEmpty` short-circuit returns the (empty) body as-is,
        // WITHOUT the border chrome. A body that measures to zero width or
        // height renders to an empty buffer — e.g. `EmptyView().border()`, or
        // a border squeezed so narrow (`availableWidth <= 2`) that no content
        // column survives. Mirror that here so a collapsed border doesn't
        // measure two rows/cols taller than it renders.
        if (bodyWidth == 0 || bodyHeight == 0) && footer == nil {
            return ViewSize.fixed(bodyWidth, bodyHeight)
        }

        // Inner width: the widest of title / body / footer, capped at the
        // space between the side borders.
        let titleWidth = title.map { $0.strippedLength + 4 } ?? 0
        let contentBasedWidth = max(titleWidth, bodyWidth, footerNaturalWidth)
        let innerWidth = base.resolveContainerWidth(
            contentWidth: contentBasedWidth, innerAvailableWidth: innerWidthAvailable)

        // Footer re-measured at the resolved inner width — a narrower footer
        // may wrap taller, exactly as the constrained re-render does.
        var footerFinalHeight = 0
        if let footerView = footer {
            let footerWidth = max(0, innerWidth - footerPadding.leading - footerPadding.trailing)
            var footerContext = footerInner
            footerContext.availableWidth = footerWidth
            footerContext.availableHeight = innerAvailableHeight
            let size = measureChild(
                footerView.padding(footerPadding),
                proposal: ProposedSize(width: footerWidth, height: innerAvailableHeight),
                context: footerContext)
            footerFinalHeight = min(size.height, innerAvailableHeight)
        }

        let footerPresent = hasFooter && footerFinalHeight > 0
        let separator = (footerPresent && style.showFooterSeparator) ? 1 : 0
        let totalHeight = 1 + bodyHeight + separator + (footerPresent ? footerFinalHeight : 0) + 1
        let totalWidth = innerWidth + 2

        // Width-flexibility is render-derived, not inherited from the body's
        // (sometimes soft) flag: `resolveContainerWidth` caps the inner width at
        // what's available, so the container fills exactly when its content
        // wants at least that much. Reading the child's `isWidthFlexible`
        // instead would mislabel a container whose body merely *wraps* (a
        // wrapping `Text`, or any `AnyView`-erased body measured by the
        // imprecise +8 probe) as filling when it actually shrinks to content.
        let fillsWidth = contentBasedWidth >= innerWidthAvailable
        return ViewSize(
            width: min(totalWidth, max(0, base.availableWidth)),
            height: min(totalHeight, max(0, base.availableHeight)),
            isWidthFlexible: fillsWidth,
            isHeightFlexible: bodySize.isHeightFlexible || footerFlexibleHeight
        )
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

        // Distinct identities for the body and footer (see `sizeThatFits` — must
        // match it exactly so the two passes agree on identity, hence on
        // `@State` slots and focus IDs).
        let bodyInner = innerContext.withChildIdentity(type: Content.self, index: 0)
        let footerInner = innerContext.withChildIdentity(type: Footer.self, index: 1)

        // Vertical chrome: top + bottom border, plus the optional footer
        // separator. The body and footer must share whatever is left so the
        // assembled container never grows taller than `availableHeight`.
        let hasFooter = footer != nil
        let chromeHeight = 2 + ((hasFooter && style.showFooterSeparator) ? 1 : 0)
        let innerAvailableHeight = max(0, context.availableHeight - chromeHeight)

        // Measure the footer first (without side-effects) so the body knows
        // how much vertical space is left. Real focus registration happens in
        // the constrained re-render below, after the body — preserving Tab order.
        let measuredFooter: FrameBuffer?
        if let footerView = footer {
            var measureContext = footerInner
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
        var bodyContext = bodyInner
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
            var footerContext = footerInner
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
        // Carry overlay layers and hit-test regions from the body and
        // footer. The body content sits one row below the top border
        // and one column inside the left border; the footer follows
        // the body and its optional separator.
        var carriedOverlays = bodyBuffer.shiftedOverlays(byX: 1, y: 1)
        var carriedRegions = bodyBuffer.shiftedHitTestRegions(byX: 1, y: 1)
        if let footerBuf = footerBuffer, !footerBuf.isEmpty {
            let footerRow = 1 + bodyBuffer.lines.count + (style.showFooterSeparator ? 1 : 0)
            carriedOverlays += footerBuf.shiftedOverlays(byX: 1, y: footerRow)
            carriedRegions += footerBuf.shiftedHitTestRegions(byX: 1, y: footerRow)
        }
        result.overlays = carriedOverlays
        result.hitTestRegions = carriedRegions
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
