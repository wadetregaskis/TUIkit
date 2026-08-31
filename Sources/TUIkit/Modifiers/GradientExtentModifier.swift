//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientExtentModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - GradientExtent

/// What a gradient given to ``View/foregroundStyle(_:)`` runs across.
///
/// **TUI-specific.** SwiftUI has only the first of these: a gradient resolves
/// against each leaf's own bounds, and there is no clean way to say "span this
/// set of controls" — `ShapeStyle.in(_:)` fixes the ramp's *scale* but
/// re-anchors at every leaf, and `gradient.mask(content)` costs either a
/// duplicated copy of the content or its interactivity. Both were measured;
/// see `Documentation/Gradients where a colour is accepted.md` §1.
///
/// So this is an addition, kept separate from the SwiftUI spelling rather than
/// changing its meaning: `.foregroundStyle(_:)` still means what it means, and
/// this says what it runs over.
public enum GradientExtent: Equatable, Sendable {
    /// Each leaf runs the whole ramp across its own box. SwiftUI's meaning, and
    /// the default.
    case leaf

    /// One ramp across everything below, so a column of rows fades from the
    /// first to the last rather than each row fading within itself.
    case subtree
}

extension View {
    /// Sets what a gradient foreground runs across, for this view and below.
    ///
    /// ```swift
    /// List(rows) { row in Text(row.title) }
    ///     .foregroundStyle(LinearGradient(colors: [.red, .blue],
    ///                                     startPoint: .top, endPoint: .bottom))
    ///     .gradientExtent(.subtree)
    /// ```
    ///
    /// ## What is exact, and what is approximate
    ///
    /// A container knows where it is putting a child **along its own axis**
    /// before it renders it — a `VStack` distributes heights first, an `HStack`
    /// widths — so it can hand the child its position. Across the *other* axis
    /// it cannot: alignment needs the rendered widths, which is one pass later.
    /// The cross-axis offset is therefore taken from the child's MEASURED size,
    /// which is exact wherever measure and render agree (they are required to,
    /// and a disagreement here shifts a colour rather than a layout).
    ///
    /// Every container that places children participates: the stacks and their
    /// lazy twins, `ZStack`, `ScrollView`, `Form`, `List`, `OutlineGroup`, and
    /// — through one shared placement — `Grid`, the lazy grids and any
    /// ``Layout`` an app writes for itself. `Table` is the exception: its
    /// columns yield strings rather than views, so it paints its own cells. It
    /// honours a foreground COLOUR, and collapses a ramp to one — see
    /// ``Paint/representative``.
    ///
    /// A container that does not participate hands its children its own
    /// position unchanged. The ramp then resolves as if that subtree were flat:
    /// wrong-looking, not corrupt, and it is the reason this is a modifier you
    /// ask for rather than the default.
    ///
    /// A ``List`` renders each row once and never again, so it cannot learn how
    /// tall its rows are and then re-colour them. It measures its first row and
    /// steps the ramp by that height — exact wherever the rows share a height,
    /// which is a list's ordinary shape, and approximate where they do not.
    /// Section headers and footers are chrome and take no part.
    ///
    /// ## Scrolling content
    ///
    /// The ramp spans the **content**, not the viewport, so a row keeps its
    /// colour as it scrolls past rather than the visible rows re-inking under a
    /// ramp pinned to the screen. Forty rows in a ten-row window therefore show
    /// the first quarter of the ramp. Lazy stacks (``LazyVStack``,
    /// ``LazyHStack``) place their rows in those same content coordinates; on
    /// the estimating path a very long variable-height list takes past a few
    /// hundred rows, the positions — and so the colours — are approximate and
    /// converge as the stack learns its content.
    public func gradientExtent(_ extent: GradientExtent) -> some View {
        GradientExtentModifier(content: self, extent: extent)
    }
}

// MARK: - The modifier

struct GradientExtentModifier<Content: View>: View {
    let content: Content
    let extent: GradientExtent

    var body: Never { fatalError("GradientExtentModifier renders via Renderable") }
}

extension GradientExtentModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var childContext = context
        switch extent {
        case .leaf:
            childContext.gradientFrame = nil
        case .subtree:
            // The extent has to be known BEFORE the subtree renders, because
            // every leaf in it needs `t` — but measuring for it here costs a
            // whole extra measure pass (96 µs of a 336 µs frame on a forty-row
            // list, measured), and the first container below is about to work
            // the same size out for its own layout. So this publishes the space
            // it was given as a stand-in and lets that container settle it; see
            // ``GradientFrame/isProvisional``.
            childContext.gradientFrame = GradientFrame(
                width: max(1, context.availableWidth),
                height: max(1, context.availableHeight),
                isProvisional: true)
        }
        return TUIkit.renderToBuffer(content, context: childContext)
    }
}

extension GradientExtentModifier: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
