//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorAsView.swift
//
//  `Color: View`, and the blank rectangle it fills.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - The block a style fills

/// A rectangle of blank cells the size of whatever it is offered, optionally
/// painted flat.
///
/// Not useful on its own — with no colour it draws nothing. It exists so that
/// ``Color`` and the gradient types can be views by filling one with
/// themselves, which makes "a style used as a view" the same picture as
/// `.background(style)` over a rectangle rather than a second painting path
/// that could disagree with the first. `GradientAsViewTests` pins that
/// equivalence for the one case that IS painted here.
///
/// Flexible in both axes with a minimum of zero, like `Spacer`: a fill claims
/// the slack and never demands any, so `HStack { Text("a"); Color.red }` gives
/// the text its width and the colour the rest.
///
/// > This type is `public` only because it is the underlying type of
///   ``Color``'s `body`, which has to be at least as visible as the
///   conformance. Nothing outside the framework should name it.
public struct _StyleFillBlock: View {
    /// A flat colour to paint, or `nil` for a bare rectangle the umbrella
    /// module's `.background(_:)` will fill.
    ///
    /// The flat case exists because ``Color``'s conformance has to be declared
    /// HERE — see the note on `extension Color: View` below — and
    /// `.background(_:)` is the umbrella module's.
    public let colour: Color?

    /// Creates a fill block.
    ///
    /// - Parameter colour: What to paint it, or `nil` to leave it blank.
    public init(colour: Color? = nil) {
        self.colour = colour
    }

    public var body: Never { fatalError("_StyleFillBlock renders via Renderable") }
}

extension _StyleFillBlock: Renderable, Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(width: 0, height: 0, isWidthFlexible: true, isHeightFlexible: true)
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        guard width > 0, height > 0 else { return FrameBuffer(lines: []) }
        let row = String(repeating: " ", count: width)
        guard let colour else {
            return FrameBuffer(
                lines: Array(repeating: row, count: height),
                width: width,
                lineWidths: Array(repeating: width, count: height))
        }
        // Through the animator, so a colour changed inside `withAnimation`
        // fades rather than jumping — the same call `BackgroundModifier` makes
        // for the same reason.
        let animated = ColorAnimation.resolving(colour, owner: Self.self, context: context)
        let escape = animated.resolve(with: context.environment.palette).backgroundEscape()
        // Nothing but spaces, so there is no interior reset for a background to
        // survive: one escape, the cells, one reset. That is byte-for-byte what
        // a persistent background produces over a blank row.
        let line = escape.isEmpty ? row : escape + row + "\u{1B}[0m"
        return FrameBuffer(
            lines: Array(repeating: line, count: height),
            width: width,
            lineWidths: Array(repeating: width, count: height))
    }
}

// MARK: - A colour is a view

/// A colour used as a view fills the space it is offered — SwiftUI's
/// `Color: View`, and the reason `ZStack { Color.red; Text("hi") }` works.
///
/// The fill is a rectangle of spaces with the colour as their **background**,
/// which is what `.background(_:)` draws everywhere else in the framework. A
/// sibling drawn over it keeps the fill behind its glyphs: a cell's glyph and
/// its field are two statements, and a `Text` that sets only a foreground has
/// said nothing about the field it lands on.
///
/// ## Why this conformance is HERE and not beside `.background(_:)`
///
/// `Color` belongs to `TUIkitStyling` and `View` to this module, so the
/// natural home for this would be the umbrella module that can see both — and
/// that is where it was written first. It segfaults: a `Color` in a
/// `@ViewBuilder` pack beside a *generic* view kills the **debug** runtime
/// while instantiating the pack's metadata, before any framework code runs.
///
/// It is a toolchain bug, not a design fault. It needs a parameter pack (the
/// same two views in an ordinary generic struct are fine) AND a conformance
/// declared in a module that owns neither the type nor the protocol —
/// reproduced from scratch on unrelated types, and unaffected by the shape of
/// `body`. Confirmed on Swift 6.2.4 and still present on the 6.5-dev snapshot
/// of 2026-08-30; release builds are unaffected.
///
/// Declaring it in `View`'s own module is what makes it go away, and that is
/// the only reason `TUIkitView` depends on `TUIkitStyling` at all. §14 of
/// `Documentation/Gradients where a colour is accepted.md` has the measurements
/// and the narrowing. **If the toolchain fixes it, this can move back up beside
/// the gradients' conformances and the dependency can go.**
extension Color: View {
    public var body: some View {
        _StyleFillBlock(colour: self)
    }
}
