//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackLayouts.swift
//
//  The stacks, as `Layout` VALUES rather than views.
//
//  ``AnyLayout`` shipped without them, which made it an eraser with nothing to
//  erase: the one line every adaptive-layout example is built from —
//
//      AnyLayout(isWide ? HStackLayout() : VStackLayout())
//
//  — did not compile, and both this framework's own doc comment and its Example
//  page had to invent private `Row`/`Column` types to have something to pass.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - VStackLayout

/// The vertical stack's arrangement, as a value.
///
/// `VStack` and `VStackLayout` place subviews identically; the difference is
/// only that one is a view and the other is a value you can switch between,
/// keeping one identity — and therefore the subviews' `@State` and focus —
/// across the switch.
///
/// ```swift
/// let layout = isWide ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
/// layout {
///     Text("one")
///     Text("two")
/// }
/// ```
///
/// Spacing is in **rows**, and defaults to none, matching `VStack`'s own
/// default rather than SwiftUI's font-derived one — a terminal has no font
/// metric to derive it from.
public struct VStackLayout: Layout, Sendable, Equatable {
    /// How subviews line up across the stack's width.
    public var alignment: HorizontalAlignment

    /// Blank rows between subviews.
    public var spacing: Int

    /// Creates a vertical stack layout.
    ///
    /// - Parameters:
    ///   - alignment: The horizontal alignment (default: `.leading`).
    ///   - spacing: Blank rows between subviews (default: none).
    public init(alignment: HorizontalAlignment = .leading, spacing: Int = 0) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        // Natural sizes: the cross axis keeps the proposal, the layout axis
        // is UNSPECIFIED. Proposing the whole extent to every subview made
        // the sum meaningless — a Spacer collapsed to zero, a GeometryReader
        // filled all of it and pushed every later sibling past the viewport.
        let natural = ProposedSize(width: proposal.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        let gaps = max(0, subviews.count - 1) * spacing
        let content = sizes.map(\.height).reduce(0, +) + gaps
        let flexible = sizes.contains { $0.isHeightFlexible }
        let height: Int
        if let proposed = proposal.height {
            // A flexible child absorbs any surplus, so the stack fills what
            // it was offered; otherwise it is its content, clamped to it.
            height = flexible ? proposed : min(content, proposed)
        } else {
            height = content
        }
        return ViewSize(
            width: sizes.map(\.width).max() ?? 0,
            height: height,
            isWidthFlexible: sizes.contains { $0.isWidthFlexible },
            isHeightFlexible: flexible)
    }

    public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        // The same distribution `VStack` itself uses: natural sizes, then
        // flexible children share the surplus (or shrink first when space is
        // short), then fixed children clip from the trailing end.
        let natural = ProposedSize(width: bounds.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        let heights = distributeLinearSpace(
            naturalSizes: sizes.map(\.height),
            isFlexible: sizes.map(\.isHeightFlexible),
            available: bounds.height,
            spacing: spacing)
        var y = bounds.y
        for (index, subview) in subviews.enumerated() {
            let height = heights[index]
            subview.place(
                at: (x: bounds.x + alignedOffset(for: sizes[index].width, in: bounds.width), y: y),
                proposal: ProposedSize(width: sizes[index].width, height: height))
            // A gap is charged behind a child that was actually placed — the
            // distributor's own rule, which is what keeps a clipped tail from
            // spending the room the visible children needed.
            y += height + (height > 0 ? spacing : 0)
        }
    }

    /// Where a subview of this width starts, given the stack's own width.
    ///
    /// ``HorizontalAlignment/childOffset(childWidth:in:)`` rather than a
    /// switch of its own: the switch had a `default` that sent every alignment
    /// it did not name to the centre, which is right for `.center` and silently
    /// wrong for a CUSTOM guide — the one kind of alignment whose whole purpose
    /// is to sit somewhere those three cases cannot express. `childOffset`
    /// resolves through `ViewDimensions`, so it asks the guide where it wants
    /// to be. It clamps at zero too: a subview wider than the stack starts at
    /// the leading edge and overflows, rather than being pushed off the front.
    private func alignedOffset(for width: Int, in available: Int) -> Int {
        alignment.childOffset(childWidth: width, in: available)
    }
}

// MARK: - HStackLayout

/// The horizontal stack's arrangement, as a value. See ``VStackLayout``.
///
/// Spacing is in **columns**, and defaults to one — the same default `HStack`
/// uses, because two words with no cell between them read as one word.
public struct HStackLayout: Layout, Sendable, Equatable {
    /// How subviews line up across the stack's height.
    public var alignment: VerticalAlignment

    /// Blank columns between subviews.
    public var spacing: Int

    /// Creates a horizontal stack layout.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment (default: `.top`).
    ///   - spacing: Blank columns between subviews (default: 1).
    public init(alignment: VerticalAlignment = .top, spacing: Int = 1) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        // See `VStackLayout.sizeThatFits` — same reasoning, other axis.
        let natural = ProposedSize(width: nil, height: proposal.height)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        let gaps = max(0, subviews.count - 1) * spacing
        let content = sizes.map(\.width).reduce(0, +) + gaps
        let flexible = sizes.contains { $0.isWidthFlexible }
        let width: Int
        if let proposed = proposal.width {
            width = flexible ? proposed : min(content, proposed)
        } else {
            width = content
        }
        return ViewSize(
            width: width,
            height: sizes.map(\.height).max() ?? 0,
            isWidthFlexible: flexible,
            isHeightFlexible: sizes.contains { $0.isHeightFlexible })
    }

    public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        // See `VStackLayout.placeSubviews` — same distribution, other axis.
        let natural = ProposedSize(width: nil, height: bounds.height)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        let widths = distributeLinearSpace(
            naturalSizes: sizes.map(\.width),
            isFlexible: sizes.map(\.isWidthFlexible),
            available: bounds.width,
            spacing: spacing)
        var x = bounds.x
        for (index, subview) in subviews.enumerated() {
            let width = widths[index]
            subview.place(
                at: (x: x, y: bounds.y + alignedOffset(for: sizes[index].height, in: bounds.height)),
                proposal: ProposedSize(width: width, height: sizes[index].height))
            x += width + (width > 0 ? spacing : 0)
        }
    }

    /// See ``VStackLayout/alignedOffset(for:in:)`` — same reasoning, other axis.
    private func alignedOffset(for height: Int, in available: Int) -> Int {
        alignment.childOffset(childHeight: height, in: available)
    }
}

// MARK: - ZStackLayout

/// The overlay stack's arrangement, as a value. See ``VStackLayout``.
///
/// Every subview is placed at the same origin, in declaration order — which is
/// draw order, so the last one written is on top. ``Layout`` permits that
/// deliberately: a layout may place its subviews overlapping.
public struct ZStackLayout: Layout, Sendable, Equatable {
    /// Where subviews sit within the stack's own frame.
    public var alignment: Alignment

    /// Creates an overlay layout.
    ///
    /// - Parameter alignment: Where subviews sit (default: `.topLeading`,
    ///   matching `ZStack` — a terminal reads from the top-left).
    public init(alignment: Alignment = .topLeading) {
        self.alignment = alignment
    }

    public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        let sizes = subviews.map { $0.sizeThatFits(proposal) }
        return ViewSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).max() ?? 0)
    }

    public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            subview.place(
                at: (
                    x: bounds.x
                        + alignment.horizontal.childOffset(
                            childWidth: size.width, in: bounds.width),
                    y: bounds.y
                        + alignment.vertical.childOffset(
                            childHeight: size.height, in: bounds.height)
                ),
                proposal: proposal)
        }
    }
}
