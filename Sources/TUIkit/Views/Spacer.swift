//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Spacer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A flexible spacer that fills available space.
///
/// `Spacer` expands along the main axis of its container
/// and fills the available space between other views.
///
/// # Example in HStack
///
/// ```swift
/// HStack {
///     Text("Left")
///     Spacer()
///     Text("Right")
/// }
/// // Result: "Left                    Right"
/// ```
///
/// # Example in VStack
///
/// ```swift
/// VStack {
///     Text("Top")
///     Spacer()
///     Text("Bottom")
/// }
/// ```
public struct Spacer: View, Equatable {
    /// The minimum length of the spacer (in characters/lines).
    let minLength: Int?

    /// Creates a spacer with optional minimum length.
    ///
    /// - Parameter minLength: The minimum length. If nil, the
    ///   spacer expands as much as possible.
    public init(minLength: Int? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer is a primitive view")
    }

    /// Static witness used by the child-layout path to detect a spacer without a
    /// runtime `as? SpacerProtocol` cast. See ``View/_isSpacer``.
    public static var _isSpacer: Bool { true }
}

// MARK: - Divider

/// A visual separator between views.
///
/// `Divider` draws across the *minor* axis of the stack containing it, as
/// SwiftUI's does: a horizontal rule in a column, a vertical one in a row,
/// and horizontal anywhere that is not a stack. It draws in the palette's
/// border colour by default — a separator is chrome, not content — and
/// honours ``View/foregroundStyle(_:)-(S)`` when one is set.
///
/// # Example
///
/// ```swift
/// VStack {
///     Text("Section 1")
///     Divider()
///     Text("Section 2")
/// }
/// // Result:
/// // Section 1
/// // ─────────────
/// // Section 2
///
/// HStack {
///     Text("left")
///     Divider()
///     Text("right")
/// }
/// // Result:
/// // left │ right
/// ```
public struct Divider: View, Equatable {
    /// The character used for the line, or `nil` to pick one from the axis of
    /// the enclosing stack.
    var character: Character?

    /// Creates a divider.
    ///
    /// It draws across the *minor* axis of the stack containing it, as
    /// SwiftUI's does: a horizontal `─` rule in a `VStack` (and anywhere that
    /// is not a stack), a vertical `│` one in an `HStack`.
    public init() {
        self.character = nil
    }

    /// Creates a divider with a custom character.
    ///
    /// The character is used whichever way the divider ends up drawing, since
    /// the caller has named a specific glyph; only ``init()`` picks one from
    /// the axis.
    ///
    /// - Parameter character: The character for the separator line.
    public init(character: Character) {
        self.character = character
    }

    public var body: Never {
        fatalError("Divider is a primitive view")
    }
}

// MARK: - Spacer Protocol Conformance

extension Spacer: SpacerProtocol {
    public var spacerMinLength: Int? { minLength }
}

// MARK: - Spacer Rendering

extension Spacer: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Spacer is fully flexible - it expands to fill available space.
        // The minLength is its minimum size requirement.
        let min = minLength ?? 0
        // Natural: the answer is the minimum length and the two fill flags,
        // whatever space was offered in either direction.
        return ViewSize(
            width: min,
            height: min,
            isWidthFlexible: true,
            isHeightFlexible: true
        ).declaringNaturalSize()
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Standalone spacer (outside a stack): render as empty lines
        let count = minLength ?? 1
        return FrameBuffer(emptyWithHeight: count)
    }
}

// MARK: - Divider Rendering

extension Divider: Renderable, Layoutable {
    /// Whether this divider is a vertical rule, i.e. sits in a row.
    ///
    /// SwiftUI: "When contained in a stack, the divider extends across the
    /// minor axis of the stack, or horizontally when not in a stack." The
    /// minor axis of an `HStack` is the vertical one.
    private func isVertical(in context: RenderContext) -> Bool {
        context.environment.containerAxis == .horizontal
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // One cell across, flexible along the stack's minor axis so it spans
        // the row or column. In a row it must NOT be width-flexible: a
        // width-flexible child absorbs the row's whole slack, which pushed
        // the divider's siblings to the two ends.
        // Natural: one cell across either way, and which way is an environment
        // question (the enclosing stack's axis), not a question of budget.
        (isVertical(in: context)
            ? ViewSize.flexibleHeight(width: 1, minHeight: 1)
            : ViewSize.flexibleWidth(minWidth: 1, height: 1))
            .declaringNaturalSize()
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let vertical = isVertical(in: context)
        let glyph = character ?? (vertical ? "│" : "─")
        // A separator is chrome, not content: it defaults to the palette's
        // muted border colour (matching SwiftUI's grey rule and the rules
        // containers draw), rather than shouting in the body-text colour. A
        // `.foregroundStyle(_:)` on or above it takes precedence.
        let palette = context.environment.palette
        let color = (context.environment.foregroundStyle?.representative ?? palette.border)
            .resolve(with: palette)
        // The bytes state the opaque spelling and the alpha travels as a claim:
        // `foregroundStyle(.gray.opacity(0.5))` on a rule, or a theme whose
        // `border` role is faded. The rule is a single run of one colour, so its
        // claim is one rectangle over exactly the cells just drawn.
        if vertical {
            let height = max(1, context.availableHeight)
            let cell = ANSIRenderer.colorize(String(glyph), foreground: color.opaqueSpelling)
            var buffer = FrameBuffer(lines: Array(repeating: cell, count: height))
            buffer.opacityRegions = OpacityRegion.claim(
                width: 1, height: height, ink: color).map { [$0] } ?? []
            return buffer
        }
        // Clamped like the vertical branch above: `String(repeating:count:)`
        // requires a non-negative count, and the offered width can be negative
        // — a caller's `.frame(width: available - labelWidth)` on a terminal
        // too narrow for the label. A rule with no cells to draw draws none.
        let width = max(0, context.availableWidth)
        let line = String(repeating: glyph, count: width)
        var buffer = FrameBuffer(text: ANSIRenderer.colorize(line, foreground: color.opaqueSpelling))
        buffer.opacityRegions = OpacityRegion.claim(
            width: width, height: 1, ink: color).map { [$0] } ?? []
        return buffer
    }
}
