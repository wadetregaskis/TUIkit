//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStyleAsView.swift
//
//  A style used where a view is expected fills the space it is given.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - The block a style fills

/// A rectangle of blank cells the size of whatever it is offered.
///
/// Not useful on its own — it draws nothing. It exists so that ``Color`` and
/// the gradient types can be views by filling one with themselves, which makes
/// "a style used as a view" exactly `.background(style)` over a rectangle
/// rather than a second painting path that could disagree with the first.
///
/// Flexible in both axes with a minimum of zero, like ``Spacer``: a fill claims
/// the slack and never demands any, so `HStack { Text("a"); Color.red }` gives
/// the text its width and the colour the rest.
private struct _StyleFillBlock: View {
    var body: Never { fatalError("_StyleFillBlock renders via Renderable") }
}

extension _StyleFillBlock: Renderable, Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(width: 0, height: 0, isWidthFlexible: true, isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let width = max(0, context.availableWidth)
        let height = max(0, context.availableHeight)
        guard width > 0, height > 0 else { return FrameBuffer(lines: []) }
        let row = String(repeating: " ", count: width)
        return FrameBuffer(
            lines: Array(repeating: row, count: height),
            width: width,
            lineWidths: Array(repeating: width, count: height))
    }
}

// MARK: - The styles that are also views

/// A colour used as a view fills the space it is offered — SwiftUI's
/// `Color: View`, and the reason `ZStack { Color.red; Text("hi") }` works.
///
/// The fill is a rectangle of spaces with the colour as their **background**,
/// which is what `.background(_:)` draws everywhere else in the framework.
///
/// A sibling drawn over the fill keeps the fill behind its glyphs: a cell's
/// glyph and its field are two statements, and a `Text` that sets only a
/// foreground has said nothing about the field it lands on. So
/// `ZStack { Color.red; Text("hi") }` puts the letters on the red. A sibling
/// that names its own background keeps that instead.
///
/// The conformance lives here rather than beside `Color` because of where the
/// pieces are: `Color` is `TUIkitStyling`'s and `View` is `TUIkitView`'s, and
/// the umbrella module is the first that can see both. Same package, so no
/// `@retroactive` — the compiler says as much if you write one.
extension Color: View {
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension LinearGradient: View {
    /// A gradient used as a view fills the space it is offered, exactly as a
    /// ``Color`` does — the ramp then resolves over that rectangle.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension RadialGradient: View {
    /// See ``LinearGradient/body``.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension EllipticalGradient: View {
    /// See ``LinearGradient/body``.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}

extension AngularGradient: View {
    /// See ``LinearGradient/body``.
    public var body: some View {
        _StyleFillBlock().background(self)
    }
}
