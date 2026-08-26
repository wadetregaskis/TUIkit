//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowStyleModifiers.swift
//
//  The two list-row modifiers that mean something in a grid of cells:
//  insets around a row's content, and a fill behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - listRowInsets

extension View {
    /// Applies inset padding to this list row's content. Matches SwiftUI's
    /// `listRowInsets(_:)`.
    ///
    /// A row's insets are the space between the row's edges and what it draws,
    /// which in a terminal is simply padding — so this is padding, and the
    /// rest of the list (the separator, the selection highlight, a drag's hit
    /// region) still sees a row of the full width.
    ///
    /// ```swift
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///             .listRowInsets(EdgeInsets(horizontal: 2, vertical: 0))
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter insets: The insets to apply, or `nil` for the list's own
    ///   defaults (which is what a row without this modifier gets).
    /// - Returns: A row with `insets` around its content.
    public func listRowInsets(_ insets: EdgeInsets?) -> some View {
        // `nil` is SwiftUI's "use the default", and the default is what an
        // unmodified row already does — so it is the identity, not zero.
        _ListRowInsetsView(content: self, insets: insets)
    }
}

/// Applies `insets` to `content`, or nothing at all when they are `nil`.
///
/// A wrapper rather than a plain `padding` call so that `nil` can mean
/// "unchanged" without the call site having to branch — and so the row keeps
/// one identity either way, which is what stops its `@State` resetting when an
/// app flips insets on and off.
struct _ListRowInsetsView<Content: View>: View {
    let content: Content
    let insets: EdgeInsets?

    var body: Never {
        fatalError("_ListRowInsetsView renders via Renderable")
    }
}

extension _ListRowInsetsView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let insets else { return TUIkit.renderToBuffer(content, context: context) }
        return TUIkit.renderToBuffer(content.padding(insets), context: context)
    }
}

extension _ListRowInsetsView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let insets else { return measureChild(content, proposal: proposal, context: context) }
        return measureChild(content.padding(insets), proposal: proposal, context: context)
    }
}

// MARK: - listRowBackground

extension View {
    /// Places a view behind this list row. Matches SwiftUI's
    /// `listRowBackground(_:)`.
    ///
    /// The background fills the row — its full width, not just the width the
    /// content happens to occupy — so a `Color` reads as a banded row rather
    /// than as a highlight around the text.
    ///
    /// ```swift
    /// ForEach(items) { item in
    ///     Text(item.name)
    ///         .listRowBackground(item.isOverdue ? Color.red : nil)
    /// }
    /// ```
    ///
    /// A selected row still draws the list's selection highlight over this, as
    /// in SwiftUI: the selection is feedback about what the user is doing, and
    /// has to win over decoration.
    ///
    /// - Parameter view: The view to place behind the row, or `nil` for none.
    /// - Returns: A row backed by `view`.
    public func listRowBackground<V: View>(_ view: V?) -> some View {
        _ListRowBackgroundView(content: self, background: view)
    }

    /// Fills this list row with a colour.
    ///
    /// SwiftUI writes this as `listRowBackground(Color.red)` because its
    /// `Color` is a `View`; TUIkit's `Color` is a value (it has to be — a
    /// palette is a table of them, and cells are painted with them, not
    /// composed of them). This overload keeps that call site compiling and
    /// meaning the same thing, the way `background(_:)` already does.
    ///
    /// - Parameter color: The colour to fill the row with, or `nil` for none.
    /// - Returns: A row filled with `color`.
    public func listRowBackground(_ color: Color?) -> some View {
        _ListRowColorView(content: self, color: color)
    }
}

/// Fills the row's full width with a colour, under its content.
struct _ListRowColorView<Content: View>: View {
    let content: Content
    let color: Color?

    var body: Never {
        fatalError("_ListRowColorView renders via Renderable")
    }
}

extension _ListRowColorView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let foreground = TUIkit.renderToBuffer(content, context: context)
        guard let color, !foreground.isEmpty else { return foreground }
        // The fill spans the ROW — the full width offered, not the width the
        // text happens to take. A fill that stopped at the last character
        // would read as a highlight around the words, which is the opposite of
        // what a row background is.
        let width = max(foreground.width, context.availableWidth)
        var filled = FrameBuffer(
            lines: (0..<foreground.height).map { _ in
                ANSIRenderer.colorize(String(repeating: " ", count: width), background: color)
            })
        filled = filled.compositedResolvingOpacity(
            with: foreground, at: (x: 0, y: 0), palette: context.environment.palette)
        filled.hitTestRegions = foreground.hitTestRegions
        filled.overlays = foreground.overlays
        return filled
    }
}

extension _ListRowColorView: Layoutable {
    /// Measures as its content: a fill is behind the row, not part of it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Renders `background` across the row and composites `content` over it.
struct _ListRowBackgroundView<Content: View, Background: View>: View {
    let content: Content
    let background: Background?

    var body: Never {
        fatalError("_ListRowBackgroundView renders via Renderable")
    }
}

extension _ListRowBackgroundView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let foreground = TUIkit.renderToBuffer(content, context: context)
        guard let background, !foreground.isEmpty else { return foreground }

        // The background is offered the ROW: the full width available, and the
        // height the content turned out to be. Offering it the content's width
        // instead would stop the fill at the end of the text, which is the one
        // thing a row background is for.
        let width = max(foreground.width, context.availableWidth)
        let backdrop = TUIkit.renderToBuffer(
            background,
            context: context
                .withChildIdentity(type: Background.self, index: 1)
                .withAvailableSize(width: width, height: foreground.height))
        guard !backdrop.isEmpty else { return foreground }

        // Composite rather than draw-over: the content's cells win, and its
        // hit-test regions and overlays are the ones that survive — a
        // background must not swallow a button in the row.
        var result = filled(backdrop, toWidth: width, height: foreground.height)
        result = result.compositedResolvingOpacity(
            with: foreground, at: (x: 0, y: 0), palette: context.environment.palette)
        return result.replacingLines(result.lines).withRegions(of: foreground)
    }

    /// Repeats the backdrop's own lines to cover the whole row — a one-line
    /// `Color` fills a three-line row, which is what "behind the row" means.
    private func filled(_ buffer: FrameBuffer, toWidth width: Int, height: Int) -> FrameBuffer {
        guard !buffer.lines.isEmpty else { return FrameBuffer(emptyWithHeight: height) }
        let lines = (0..<height).map { row -> String in
            let source = buffer.lines[row % buffer.lines.count]
            let visible = source.strippedLength
            return visible < width
                ? source + String(repeating: " ", count: width - visible) : source
        }
        return buffer.replacingLines(lines)
    }
}

extension _ListRowBackgroundView: Layoutable {
    /// The row measures as its content: a background is behind it, not beside
    /// it, and must not make the row taller or wider than what it holds.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension FrameBuffer {
    /// Returns this buffer carrying `other`'s hit-test regions and overlays.
    ///
    /// Compositing merges cells; the interactive metadata has to be carried
    /// deliberately, and it is the CONTENT's that matters — a background is
    /// decoration and has nothing to be clicked.
    fileprivate func withRegions(of other: FrameBuffer) -> FrameBuffer {
        var copy = self
        copy.hitTestRegions = other.hitTestRegions
        copy.overlays = other.overlays
        return copy
    }
}
