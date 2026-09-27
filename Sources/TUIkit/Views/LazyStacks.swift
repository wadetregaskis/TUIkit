//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyStacks.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - LazyVStack

/// A view that arranges its children in a line that grows vertically,
/// rendering only the children that fit.
///
/// TUIkit re-renders the tree every frame and retains no view objects, so
/// SwiftUI's "create items only as needed" translates here to a **render
/// window**: whole children render top-down until the next would overflow
/// `availableHeight`, and children past the fold are never rendered (their
/// `onAppear`/`task` correctly never fire). `VStack` instead distributes the
/// height and clips at the cell.
///
/// Use `LazyVStack` when the *stack itself* is the clipped region — a
/// fixed-height pane showing "as many whole rows as fit".
///
/// - Important: A `LazyVStack` that is the *direct content* of a vertical
///   ``ScrollView`` now windows to the visible viewport: only the rows
///   intersecting the scrolled slice render (and fire their lifecycle), the
///   rest becoming blank placeholders in a full-height buffer, so scrolling a
///   1000-row list costs a viewport's worth of rendering, not all 1000 — and
///   `onAppear` fires on visibility, matching SwiftUI. (A `LazyVStack` nested
///   *below* other scroll content isn't at the content origin, so it is left
///   un-windowed — and so is one alone inside an outer lazy stack, which takes
///   the window itself. A `Section`'s header and footer are not such content:
///   the section hands its content the window moved below its header, so a
///   lazy stack there windows, seeks and reports its row as it would with
///   neither. Every row of a stack left un-windowed is measured and drawn, as
///   in a `VStack`, so its cost per frame tracks its row count — and in a row
///   of an outer lazy stack it is measured whenever the outer stack places
///   that row, on screen or not. `pinnedViews:` is still absent — §2.8 of
///   `Documentation/SwiftUI-compatibility.md` records what it costs, which is
///   not an init parameter: the stack cannot see inside a `Section`, and the
///   scroll offset it would pin against lives in the `ScrollView`.)
///
/// - Note: Documented deviations from SwiftUI (per the parity rule): the
///   cross-axis width hugs the widest *placed* child (SwiftUI's ideal width
///   is its **first** subview's — an artefact of not creating the rest;
///   TUIkit has rendered every visible child anyway, so it uses the real
///   widest), the main-axis extent is exact rather than estimated, and the
///   init takes no `pinnedViews:`. "Placed" means the rows a walk at the
///   given height budget reaches; past the fold a windowed stack answers
///   from the widest row it has drawn or sampled, never below the band it is
///   currently drawing. See §2.8 of `Documentation/SwiftUI-compatibility.md`.
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
/// - Note: `LazyVStack` shares its rendering core (`_VStackCore`) with
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
/// rendering only the children that fit.
///
/// The horizontal render window: whole children render left-to-right until
/// the next would overflow `availableWidth`, and children past the fold are
/// never rendered. `HStack` instead distributes the width and clips at the
/// cell. Use `LazyHStack` when the *stack itself* is the clipped region.
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
/// - Note: `LazyHStack` is the horizontal twin of ``LazyVStack`` — see its
///   discussion for the render-window semantics, the `ScrollView` caveat, and
///   the documented deviations from SwiftUI.
///
/// - Note: `LazyHStack` shares its rendering core (`_HStackCore`) with
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
