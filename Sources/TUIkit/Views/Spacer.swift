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
        return ViewSize(
            width: min,
            height: min,
            isWidthFlexible: true,
            isHeightFlexible: true
        )
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
        isVertical(in: context)
            ? ViewSize.flexibleHeight(width: 1, minHeight: 1)
            : ViewSize.flexibleWidth(minWidth: 1, height: 1)
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
        if vertical {
            let cell = ANSIRenderer.colorize(String(glyph), foreground: color)
            return FrameBuffer(lines: Array(repeating: cell, count: max(1, context.availableHeight)))
        }
        let line = String(repeating: glyph, count: context.availableWidth)
        return FrameBuffer(text: ANSIRenderer.colorize(line, foreground: color))
    }
}
