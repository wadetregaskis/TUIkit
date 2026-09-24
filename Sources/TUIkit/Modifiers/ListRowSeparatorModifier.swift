//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowSeparatorModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Carries ``View/listRowSeparator(_:edges:)``'s arguments and
/// renders its content unchanged.
///
/// Inert by construction: a TUIkit `List` draws no row separators, so there is
/// nothing for the visibility to govern. The arguments are stored anyway so
/// the modifier compares equal only to itself — an `EquatableView` above it
/// must not treat two differently-configured rows as the same view.
public struct ListRowSeparatorModifier<Content: View>: View {
    /// The content view.
    let content: Content

    /// The visibility of the separator.
    let visibility: Visibility

    /// The edges to apply the separator to.
    let edges: VerticalEdge.Set

    public var body: Never {
        fatalError("ListRowSeparatorModifier renders via Renderable")
    }
}

// MARK: - Visibility

/// Visibility options for list row separators.
///
/// Matches SwiftUI's Visibility enum for API compatibility.
public enum Visibility: Sendable {
    /// The separator is automatically shown or hidden based on context.
    case automatic

    /// The separator is always visible.
    case visible

    /// The separator is always hidden.
    case hidden
}

// MARK: - Vertical Edge Set

/// A set of vertical edges (top and/or bottom).
///
/// Used for specifying which edges of a list row should have separators.
public enum VerticalEdge: Sendable {
    /// The top edge.
    case top

    /// The bottom edge.
    case bottom

    /// A set of vertical edges.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Creates a set containing the one edge given — SwiftUI's
        /// `VerticalEdge.Set(_:)`, and the counterpart to ``Edge/Set/init(_:)``.
        ///
        /// - Parameter edge: The edge the set contains.
        public init(_ edge: VerticalEdge) {
            switch edge {
            case .top: self = .top
            case .bottom: self = .bottom
            }
        }

        /// The top edge only.
        public static let top = Self(rawValue: 1 << 0)

        /// The bottom edge only.
        public static let bottom = Self(rawValue: 1 << 1)

        /// All edges (top and bottom).
        public static let all: Set = [.top, .bottom]
    }
}

// MARK: - Equatable

extension ListRowSeparatorModifier: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: ListRowSeparatorModifier<Content>, rhs: ListRowSeparatorModifier<Content>) -> Bool {
        lhs.content == rhs.content && lhs.visibility == rhs.visibility && lhs.edges == rhs.edges
    }
}

extension Visibility: Equatable {}

// MARK: - Renderable

extension ListRowSeparatorModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Nothing to draw: see the type's note. Silently, too — a warning
        // here was removed in 90017af8 for being neither concurrency-safe on
        // Linux nor useful, and a stub modifier that shouts once per app is
        // noise wherever it is correct to have written it.
        TUIkit.renderToBuffer(content, context: context)
    }
}

// MARK: - Layoutable

extension ListRowSeparatorModifier: Layoutable {
    /// Stub decorator — renders `content` unchanged, so it measures as `content`.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension ListRowSeparatorModifier: SingleContentWrapper {
    public var wrappedContent: Content { content }
}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension ListRowSeparatorModifier: DrawsContentUnchanged {}
