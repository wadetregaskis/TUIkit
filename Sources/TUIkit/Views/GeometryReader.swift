//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GeometryReader.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Geometry Proxy

/// The size and coordinate space of the container reading it.
///
/// Handed to a ``GeometryReader``'s content closure so the content can size
/// itself against the space it was actually given.
///
/// ## What this deliberately does not have
///
/// SwiftUI's `GeometryProxy` also carries `safeAreaInsets` and an `Anchor`
/// subscript. A terminal has no safe area — the whole grid is addressable, and
/// TUIkit's chrome (app header, status bar) has already been subtracted from
/// what a view is offered — and no anchor/preference geometry to resolve
/// against. Adding either as a constant would be answering a question the
/// caller should not be asking.
public struct GeometryProxy: Equatable, Sendable {
    /// The container's size in cells.
    public let size: ProxySize

    /// The container's origin in the terminal's coordinate space, if known.
    let globalOrigin: (x: Int, y: Int)?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size == rhs.size && lhs.globalOrigin?.x == rhs.globalOrigin?.x
            && lhs.globalOrigin?.y == rhs.globalOrigin?.y
    }

    init(width: Int, height: Int, globalOrigin: (x: Int, y: Int)? = nil) {
        self.size = ProxySize(width: width, height: height)
        self.globalOrigin = globalOrigin
    }

    /// The container's frame in the given coordinate space.
    ///
    /// `.local` is always exact. `.global` is only exact when the renderer knows
    /// where the reader sits on screen; where it does not — inside a buffer that
    /// is composed into its parent afterwards, which is most of them — this
    /// falls back to the local frame rather than inventing a position. Check
    /// ``hasGlobalPosition`` when the difference matters.
    public func frame(in coordinateSpace: CoordinateSpace) -> ProxyRect {
        switch coordinateSpace {
        case .local:
            return ProxyRect(x: 0, y: 0, width: size.width, height: size.height)
        case .global:
            let origin = globalOrigin ?? (x: 0, y: 0)
            return ProxyRect(
                x: origin.x, y: origin.y, width: size.width, height: size.height)
        }
    }

    /// Whether ``frame(in:)`` can answer `.global` exactly.
    public var hasGlobalPosition: Bool { globalOrigin != nil }
}

/// A size in whole terminal cells.
///
/// The counterpart of `CGSize` in `GeometryProxy`, spelled in cells for the
/// reason recorded on ``AlignmentID``: this framework's geometry is integral.
public struct ProxySize: Equatable, Sendable {
    /// The width in cells.
    public let width: Int

    /// The height in rows.
    public let height: Int
}

/// A rectangle in whole terminal cells.
public struct ProxyRect: Equatable, Sendable {
    /// The leading edge, in cells from the coordinate space's origin.
    public let x: Int

    /// The top edge, in rows from the coordinate space's origin.
    public let y: Int

    /// The width in cells.
    public let width: Int

    /// The height in rows.
    public let height: Int

    /// The trailing edge (exclusive).
    public var maxX: Int { x + width }

    /// The bottom edge (exclusive).
    public var maxY: Int { y + height }
}

/// The coordinate space a ``GeometryProxy`` frame is measured in.
public enum CoordinateSpace: Sendable {
    /// Relative to the ``GeometryReader`` itself, whose origin is `(0, 0)`.
    case local

    /// Relative to the terminal's top-left cell.
    case global
}

// MARK: - Geometry Reader

/// A container that sizes itself to the space offered, and hands that size to
/// its content.
///
/// This is the one thing an app previously could not work around: nothing in
/// TUIkit let a view read the space it was given and branch on it. The layout
/// system computes sizes top-down and the answer never reached the view.
///
/// ```swift
/// GeometryReader { proxy in
///     if proxy.size.width >= 60 {
///         HStack { Sidebar(); Detail() }
///     } else {
///         Detail()          // too narrow for two columns
///     }
/// }
/// ```
///
/// ## Sizing
///
/// As in SwiftUI, a `GeometryReader` **fills** the space proposed to it on both
/// axes rather than hugging its content, and places its content at the top
/// leading corner. That is what makes the reported size meaningful: it is the
/// container's size, not the content's.
///
/// Put one inside a `.frame(...)` when you want it bounded:
///
/// ```swift
/// GeometryReader { proxy in … }
///     .frame(width: 40, height: 10)
/// ```
public struct GeometryReader<Content: View>: View {
    /// Builds the content from the resolved geometry.
    public let content: (GeometryProxy) -> Content

    /// Creates a geometry reader.
    ///
    /// - Parameter content: A closure receiving the reader's resolved geometry.
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        _GeometryReaderCore(content: content)
    }
}

// MARK: - Core

/// Resolves the geometry and renders the content against it.
private struct _GeometryReaderCore<Content: View>: View, Renderable, Layoutable {
    let content: (GeometryProxy) -> Content

    var body: Never { fatalError("_GeometryReaderCore renders via Renderable") }

    /// Fills the proposal on both axes.
    ///
    /// The content is *not* measured. Measuring it would mean building it, which
    /// needs a proxy, which needs the size this call is computing — the
    /// circularity SwiftUI resolves the same way, by making the reader greedy.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: proposal.width ?? context.availableWidth,
            height: proposal.height ?? context.availableHeight,
            isWidthFlexible: true,
            isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        let proxy = GeometryProxy(width: width, height: height)

        let buffer = TUIkitView.renderToBuffer(content(proxy), context: context)

        // The reader occupies everything it was offered even when its content
        // does not, so a sibling below starts where the reader ends rather than
        // where its content happens to stop. Rebuilt through `replacingLines`
        // rather than `FrameBuffer(lines:)`, which would silently drop the
        // content's overlays and hit-test regions.
        guard buffer.width < width || buffer.lines.count < height else { return buffer }
        var padded = buffer.lines.map { line -> String in
            let shortfall = width - line.strippedLength
            return shortfall > 0 ? line + String(repeating: " ", count: shortfall) : line
        }
        while padded.count < height {
            padded.append(String(repeating: " ", count: width))
        }
        return buffer.replacingLines(padded, width: width, uniformWidth: true)
    }
}
