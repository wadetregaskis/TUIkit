//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Section.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Section

/// A container view that groups content with optional header and footer.
///
/// `Section` organizes list content into logical groups with visual headers
/// and footers. When used inside a `List`, sections provide hierarchical
/// structure with appropriate styling.
///
/// ## SwiftUI Conformity
///
/// This implementation matches the SwiftUI `Section` API:
/// - `Section { content } header: { header } footer: { footer }`
/// - `Section("Title") { content }`
///
/// ## Usage
///
/// ```swift
/// List(selection: $selection) {
///     Section {
///         ForEach(recentItems) { item in
///             Text(item.name)
///         }
///     } header: {
///         Text("Recent")
///     }
///
///     Section("All Items") {
///         ForEach(allItems) { item in
///             Text(item.name)
///         }
///     }
/// }
/// ```
///
/// ## Visual Rendering
///
/// - **Header**: Rendered with dimmed foreground and bold styling
/// - **Footer**: Rendered with dimmed foreground
/// - **Content**: Rendered normally between header and footer
/// - **Spacing**: Sections are separated by vertical space in List
public struct Section<Parent: View, Content: View, Footer: View>: View {
    /// The header view displayed above the section content.
    let header: Parent

    /// The main content of the section.
    let content: Content

    /// The footer view displayed below the section content.
    let footer: Footer

    public var body: some View {
        _SectionCore(header: header, content: content, footer: footer)
    }
}

// MARK: - Full Initializer (header + content + footer)

extension Section {
    /// Creates a section with content, header, and footer.
    ///
    /// This is the most flexible initializer, matching SwiftUI's signature.
    ///
    /// - Parameters:
    ///   - content: A ViewBuilder that defines the section's main content.
    ///   - header: A ViewBuilder that defines the header view.
    ///   - footer: A ViewBuilder that defines the footer view.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }
}

// MARK: - Header + Content (no footer)

extension Section where Footer == EmptyView {
    /// Creates a section with content and header, without a footer.
    ///
    /// - Parameters:
    ///   - content: A ViewBuilder that defines the section's main content.
    ///   - header: A ViewBuilder that defines the header view.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent
    ) {
        self.content = content()
        self.header = header()
        self.footer = EmptyView()
    }
}

// MARK: - Content + Footer (no header)

extension Section where Parent == EmptyView {
    /// Creates a section with content and footer, without a header.
    ///
    /// - Parameters:
    ///   - content: A ViewBuilder that defines the section's main content.
    ///   - footer: A ViewBuilder that defines the footer view.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = EmptyView()
        self.footer = footer()
    }
}

// MARK: - Content Only (no header, no footer)

extension Section where Parent == EmptyView, Footer == EmptyView {
    /// Creates a section with content only, without header or footer.
    ///
    /// - Parameter content: A ViewBuilder that defines the section's main content.
    public init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.header = EmptyView()
        self.footer = EmptyView()
    }
}

// MARK: - String Title Convenience

extension Section where Parent == Text, Footer == EmptyView {
    /// Creates a section with a string title as the header.
    ///
    /// This convenience initializer matches SwiftUI's `Section(_ title:content:)`.
    ///
    /// - Parameters:
    ///   - title: The string to use as the header text.
    ///   - content: A ViewBuilder that defines the section's main content.
    public init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.header = Text(title)
        self.content = content()
        self.footer = EmptyView()
    }
}

// MARK: - Section Core (Internal Rendering)

/// Internal core view that handles section rendering.
///
/// `_SectionCore` is a leaf node that renders the section's header, content,
/// and footer with appropriate styling. It conforms to `Renderable` for
/// direct buffer output.
private struct _SectionCore<Parent: View, Content: View, Footer: View>: View, Renderable, Layoutable {
    let header: Parent
    let content: Content
    let footer: Footer

    var body: Never {
        fatalError("_SectionCore renders via Renderable")
    }

    /// Size from one render: the stack of header/content/footer drops a *blank*
    /// header or footer (e.g. `header: { Text("") }` that padded to spaces),
    /// which can't be detected without rendering, so the height isn't a clean
    /// structural sum. Flexibility comes from the parts — measured under the same
    /// chrome contexts the render uses (chrome role styles, it does not resize) —
    /// so a `.frame(maxWidth: .infinity)` content still reports the section
    /// width-flexible to its parent.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        var widthFlexible = false
        var heightFlexible = false
        func note(_ childSize: ViewSize) {
            if childSize.isWidthFlexible { widthFlexible = true }
            if childSize.isHeightFlexible { heightFlexible = true }
        }
        if !(header is EmptyView) {
            note(measureChild(header, proposal: proposal,
                              context: sectionChromeContext(context, .sectionHeader)))
        }
        note(measureChild(content, proposal: proposal, context: context))
        if !(footer is EmptyView) {
            note(measureChild(footer, proposal: proposal,
                              context: sectionChromeContext(context, .sectionFooter)))
        }
        return ViewSize(
            width: size.width, height: size.height,
            isWidthFlexible: widthFlexible, isHeightFlexible: heightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var lines: [String] = []

        // Header and footer render under a chrome role, so their text resolves
        // the role's default styling (header bold+dim, footer dim) plus any
        // `.chrome(...)` theme overrides through the normal cascade — see
        // ``ChromeRole`` and ``Text``.
        if !(header is EmptyView) {
            let headerBuffer = TUIkit.renderToBuffer(
                header, context: sectionChromeContext(context, .sectionHeader))
            // Drop a blank header (e.g. `header: { Text("") }`) rather than show
            // an empty line above the content.
            if !sectionBufferIsBlank(headerBuffer) { lines.append(contentsOf: headerBuffer.lines) }
        }

        let contentBuffer = TUIkit.renderToBuffer(content, context: context)
        lines.append(contentsOf: contentBuffer.lines)

        if !(footer is EmptyView) {
            let footerBuffer = TUIkit.renderToBuffer(
                footer, context: sectionChromeContext(context, .sectionFooter))
            if !sectionBufferIsBlank(footerBuffer) { lines.append(contentsOf: footerBuffer.lines) }
        }

        return FrameBuffer(lines: lines)
    }
}

/// Returns `context` with `role` set as its chrome role, so a `Section`'s
/// header/footer text styles via the cascade (the ``ChromeRole`` defaults plus
/// any `.chrome(...)` overrides) rather than being post-styled with fixed ANSI.
private func sectionChromeContext(_ context: RenderContext, _ role: ChromeRole) -> RenderContext {
    context.withEnvironment(context.environment.setting(\.chromeRole, to: role))
}

/// Whether a rendered header/footer buffer is entirely blank — so it should be
/// dropped rather than shown as an empty line (e.g. an empty `Text("")` header).
private func sectionBufferIsBlank(_ buffer: FrameBuffer) -> Bool {
    buffer.isBlank
}

// MARK: - Section Row Extractor

/// Protocol for views that can provide section information for List rendering.
///
/// When a `List` contains `Section` views, it uses this protocol to extract
/// section structure for proper rendering with headers, footers, and grouping.
@MainActor
protocol SectionRowExtractor {
    /// Extracts section information for list rendering.
    ///
    /// - Parameter context: The rendering context.
    /// - Returns: Section metadata including header, content rows, and footer.
    func extractSectionInfo(context: RenderContext) -> SectionInfo
}

/// Metadata about a section for List rendering.
struct SectionInfo {
    /// The rendered header buffer (nil if no header).
    let headerBuffer: FrameBuffer?

    /// The rendered footer buffer (nil if no footer).
    let footerBuffer: FrameBuffer?

    /// The content rows within this section.
    let contentBuffer: FrameBuffer
}

extension Section: SectionRowExtractor {
    func extractSectionInfo(context: RenderContext) -> SectionInfo {
        // Header/footer render under a chrome role so their text styles through
        // the cascade (see ``ChromeRole`` / ``Text``). The styling is per-line
        // and unshifted, so overlays and hit-test regions carry through.
        func renderedChrome(_ view: some View, _ role: ChromeRole, isEmptyView: Bool) -> FrameBuffer? {
            guard !isEmptyView else { return nil }
            let buffer = TUIkit.renderToBuffer(view, context: sectionChromeContext(context, role))
            // A blank header/footer is dropped (nil), not shown as an empty row.
            return sectionBufferIsBlank(buffer) ? nil : buffer
        }
        let headerBuffer = renderedChrome(header, .sectionHeader, isEmptyView: header is EmptyView)
        let footerBuffer = renderedChrome(footer, .sectionFooter, isEmptyView: footer is EmptyView)

        let contentBuffer = TUIkit.renderToBuffer(content, context: context)

        return SectionInfo(
            headerBuffer: headerBuffer,
            footerBuffer: footerBuffer,
            contentBuffer: contentBuffer
        )
    }
}

// MARK: - Section as ChildInfoProvider

extension Section: ChildInfoProvider {
    public func childInfos(context: RenderContext) -> [ChildInfo] {
        // For stack layouts, render Section as a single unit
        let buffer = TUIkit.renderToBuffer(self, context: context)
        return [ChildInfo(buffer: buffer, isSpacer: false, spacerMinLength: nil, size: nil)]
    }
}

// MARK: - Section as ListRowExtractor

extension Section: ListRowExtractor {
    /// Extracts list rows from the section's content.
    ///
    /// Delegates to the content's `ListRowExtractor` implementation if available
    /// (e.g., `ForEach`). This allows List to extract individual content rows
    /// while separately handling section headers and footers.
    ///
    /// - Parameter context: The rendering context.
    /// - Returns: Array of list rows from the section's content.
    func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        // Delegate to content if it's a ListRowExtractor (e.g., ForEach)
        if let extractor = content as? ListRowExtractor {
            return extractor.extractListRows(context: context)
        }

        // Static children (a TupleView of rows): one row per child, each
        // carrying the badge of its `.badge(_:)` wrapper, if any — matching
        // the flat List's child extraction.
        if let provider = content as? ChildViewProvider {
            var rows: [ListRow<RowID>] = []
            for child in provider.childViews(context: context) where !child.isSpacer {
                guard let indexID = rows.count as? RowID else { continue }
                let badge = extractBadgeValue(from: child.wrappedView)
                let buffer = child.render(
                    width: context.availableWidth, height: context.availableHeight,
                    context: context)
                rows.append(ListRow(id: indexID, buffer: buffer, badge: badge))
            }
            return rows
        }

        // Fallback: render content as a single row, carrying its badge.
        let badge = extractBadgeValue(from: content)
        let buffer = TUIkit.renderToBuffer(content, context: context)
        if let indexID = 0 as? RowID {
            return [ListRow(id: indexID, buffer: buffer, badge: badge)]
        }
        return []
    }
}
