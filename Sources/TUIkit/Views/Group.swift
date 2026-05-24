//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Group.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Group

/// A view that collects multiple views into a single unit, without imposing
/// any layout of its own.
///
/// `Group` is transparent: it renders its children exactly as if they had
/// been written in its place. Use it to apply a modifier to several views at
/// once, to return more than one view from a branch, or to exceed the
/// ten-view limit of a single `@ViewBuilder` block.
///
/// ```swift
/// VStack {
///     Group {
///         Text("First")
///         Text("Second")
///     }
///     .foregroundStyle(.palette.accent)
///
///     Text("Third")
/// }
/// ```
public struct Group<Content: View>: View {
    /// The grouped content.
    let content: Content

    /// Creates a group from the given content.
    ///
    /// - Parameter content: A ``ViewBuilder`` that defines the grouped views.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
    }
}

// MARK: - Equatable Conformance

extension Group: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: Group<Content>, rhs: Group<Content>) -> Bool {
        lhs.content == rhs.content
    }
}

// MARK: - Transparent Child Resolution

// Forwarding child resolution to the content lets a parent stack see the
// grouped views as its own direct children, so `Group` adds no nesting and
// no layout of its own.

extension Group: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        resolveChildViews(from: content, context: context)
    }
}

extension Group: ChildInfoProvider {
    public func childInfos(context: RenderContext) -> [ChildInfo] {
        resolveChildInfos(from: content, context: context)
    }
}
