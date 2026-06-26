//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyStacks.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - LazyVStack

/// A view that arranges its children in a line that grows vertically,
/// creating items only as needed.
///
/// Unlike ``VStack``, which renders all views immediately, `LazyVStack`
/// only renders views when they become visible. In a terminal context,
/// this means views outside the available height are not rendered.
///
/// Use `LazyVStack` when you have a large number of items or want to
/// defer rendering of offscreen content.
///
/// # Example
///
/// ```swift
/// ScrollView {
///     LazyVStack {
///         ForEach(1...1000, id: \.self) { i in
///             Text("Row \(i)")
///         }
///     }
/// }
/// ```
///
/// - Note: In TUIKit's terminal context, lazy rendering is based on
///   `availableHeight` in the render context. Items beyond this height
///   are not rendered until they scroll into view.
///
/// - Note: `LazyVStack` shares its rendering core (``_VStackCore``) with
///   ``VStack``; the only difference is the `.window` overflow policy, which
///   appends whole children while they fit `availableHeight` and stops at the
///   first that would overflow (rather than `VStack`'s `.clip`, which distributes
///   and clips trailing rows at the cell).
public struct LazyVStack<Content: View>: View {
    /// The horizontal alignment of the children.
    public let alignment: HorizontalAlignment

    /// The vertical spacing between children.
    public let spacing: Int

    /// The content of the stack.
    public let content: Content

    /// Creates a lazy vertical stack with the specified options.
    ///
    /// - Parameters:
    ///   - alignment: The horizontal alignment of children (default: .center).
    ///   - spacing: The spacing between children in lines (default: 0).
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _VStackCore(alignment: alignment, spacing: spacing, overflow: .window, content: content)
    }
}

// MARK: - LazyHStack

/// A view that arranges its children in a line that grows horizontally,
/// creating items only as needed.
///
/// Unlike ``HStack``, which renders all views immediately, `LazyHStack`
/// only renders views when they become visible. In a terminal context,
/// this means views outside the available width are not rendered.
///
/// Use `LazyHStack` when you have a large number of items or want to
/// defer rendering of offscreen content.
///
/// # Example
///
/// ```swift
/// ScrollView(.horizontal) {
///     LazyHStack {
///         ForEach(1...1000, id: \.self) { i in
///             Text("Column \(i)")
///         }
///     }
/// }
/// ```
///
/// - Note: In TUIKit's terminal context, lazy rendering is based on
///   `availableWidth` in the render context. Items beyond this width
///   are not rendered until they scroll into view.
///
/// - Note: `LazyHStack` shares its rendering core (``_HStackCore``) with
///   ``HStack``; the only difference is the `.window` overflow policy, which
///   appends whole children while they fit `availableWidth` and stops at the
///   first that would overflow (rather than `HStack`'s `.clip`, which distributes
///   and clips trailing columns at the cell).
public struct LazyHStack<Content: View>: View {
    /// The vertical alignment of the children.
    public let alignment: VerticalAlignment

    /// The horizontal spacing between children.
    public let spacing: Int

    /// The content of the stack.
    public let content: Content

    /// Creates a lazy horizontal stack with the specified options.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment of children (default: .center).
    ///   - spacing: The spacing between children in characters (default: 1).
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _HStackCore(alignment: alignment, spacing: spacing, overflow: .window, content: content)
    }
}

// MARK: - Equatable Conformances

extension LazyVStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: LazyVStack<Content>, rhs: LazyVStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
    }
}

extension LazyHStack: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: LazyHStack<Content>, rhs: LazyHStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.spacing == rhs.spacing && lhs.content == rhs.content
    }
}
