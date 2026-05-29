//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TupleViews.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// A view that contains multiple child views packed via a parameter pack.
///
/// `TupleView` replaces the previous `TupleView2` through `TupleView10`
/// types with a single generic struct using Swift Parameter Packs (SE-0393).
/// This removes the 10-child limit and eliminates ~400 lines of boilerplate.
///
/// `TupleView` is created automatically by `ViewBuilder` when multiple
/// views appear in a `@ViewBuilder` closure.
///
/// - Important: This is framework infrastructure. Created automatically by
///   `@ViewBuilder`. Do not instantiate directly.
public struct TupleView<each V: View>: View {
    /// The packed child views.
    public let children: (repeat each V)

    /// Creates a tuple view from a parameter pack of child views.
    ///
    /// - Parameter children: The child views.
    init(_ children: repeat each V) {
        self.children = (repeat each children)
    }

    public var body: Never {
        fatalError("TupleView renders its children directly")
    }
}

// MARK: - Equatable Conformance

extension TupleView: @preconcurrency Equatable where repeat each V: Equatable {
    public static func == (lhs: TupleView, rhs: TupleView) -> Bool {
        func isEqual<T: Equatable>(_ left: T, _ right: T) -> Bool { left == right }
        var result = true
        repeat result = result && isEqual(each lhs.children, each rhs.children)
        return result
    }
}

// MARK: - TupleView Rendering + ChildInfoProvider

extension TupleView: Renderable, ChildInfoProvider {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(verticallyStacking: childInfos(context: context).compactMap(\.buffer))
    }

    public func childInfos(context: RenderContext) -> [ChildInfo] {
        var infos: [ChildInfo] = []
        repeat Self.appendChildInfos(
            from: each children,
            into: &infos,
            context: context
        )
        return infos
    }

    /// Appends one or more `ChildInfo` entries for `child`.
    ///
    /// When `child` is itself a `ChildInfoProvider` (a nested
    /// `TupleView`, a `ForEach`, etc.), its `childInfos` are
    /// spliced in so the surrounding stack sees the children as
    /// individual siblings — rather than treating the whole
    /// provider as one opaque element. Without this a `ForEach`
    /// buried inside a TupleView would never have its body
    /// iterations enumerated, leaving the resulting `VStack` /
    /// `HStack` to render the ForEach as a single empty buffer
    /// via the Priority-3 'no rendering path' branch in
    /// `renderToBuffer`.
    @MainActor
    private static func appendChildInfos<C: View>(
        from child: C,
        into infos: inout [ChildInfo],
        context: RenderContext
    ) {
        if let provider = child as? ChildInfoProvider {
            infos.append(contentsOf: provider.childInfos(context: context))
        } else {
            infos.append(
                makeChildInfo(
                    for: child,
                    context: context.withChildIdentity(
                        type: type(of: child), index: infos.count)
                )
            )
        }
    }
}

// MARK: - TupleView Two-Pass Layout Support

extension TupleView: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        var views: [ChildView] = []
        repeat Self.appendChildViews(
            from: each children,
            into: &views,
            context: context
        )
        return views
    }

    /// Appends one or more `ChildView` entries for `child`. See
    /// the matching note on `appendChildInfos` — this exists for
    /// the same reason on the two-pass layout side.
    @MainActor
    private static func appendChildViews<C: View>(
        from child: C,
        into views: inout [ChildView],
        context: RenderContext
    ) {
        if let provider = child as? ChildViewProvider {
            views.append(contentsOf: provider.childViews(context: context))
        } else {
            views.append(ChildView(child, childIndex: views.count))
        }
    }
}
