//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyTransition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// How a view arrives and how it leaves.
///
/// ```swift
/// if showDetail {
///     Detail().transition(.move(edge: .top).combined(with: .opacity))
/// }
/// ```
///
/// A transition is a function of one number — how *present* the view is, `0`
/// absent through `1` fully there — applied to the cells the view drew. An
/// insertion runs it forwards, a removal backwards.
///
/// ## What a terminal changes about this
///
/// The effects are applied to the **rendered buffer**, not to the layout. A
/// view sliding in gets its space at once and moves into it; it does not push
/// its siblings along as it grows. That is a real difference from SwiftUI, and
/// it is what makes a transition cost one buffer transform per frame rather
/// than a full re-layout — in a grid of whole cells, a view growing by
/// fractions of a cell has nothing to show for most of the frames anyway.
///
/// `.scale` is the effect that changes most: there is no sub-cell rendering to
/// shrink, so it reveals the view from its anchor a whole cell at a time.
public struct AnyTransition: Sendable, Equatable {

    /// One effect, or several composed. A value rather than a closure so a
    /// transition can be compared, stored, and reasoned about in a test.
    indirect enum Effect: Sendable, Equatable {
        /// Appears and disappears with no effect at all.
        case identity
        /// Fades toward the background.
        case opacity
        /// Slides in from, or out towards, an edge.
        case move(edge: Edge)
        /// Slides from a displacement of its own choosing.
        case offset(x: Int, y: Int)
        /// Reveals from an anchor, a cell at a time.
        case scale(anchor: UnitPoint)
        /// Both, applied in order.
        case combined(Self, Self)
    }

    let insertion: Effect
    let removal: Effect

    /// An animation this transition insists on, overriding the ambient one.
    var explicitAnimation: Animation?

    init(insertion: Effect, removal: Effect, explicitAnimation: Animation? = nil) {
        self.insertion = insertion
        self.removal = removal
        self.explicitAnimation = explicitAnimation
    }

    private init(_ effect: Effect) {
        self.init(insertion: effect, removal: effect)
    }
}

// MARK: - The built-in transitions

extension AnyTransition {
    /// Appears and disappears at once — the default, and what a view without
    /// `.transition(_:)` does.
    public static let identity = AnyTransition(.identity)

    /// Fades in and out.
    public static let opacity = AnyTransition(.opacity)

    /// Slides in from `edge`, and back out to it.
    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition(.move(edge: edge))
    }

    /// Slides in from a displacement, and back out to it.
    public static func offset(x: Int = 0, y: Int = 0) -> AnyTransition {
        AnyTransition(.offset(x: x, y: y))
    }

    /// Slides in from the displacement, and back out to it.
    public static func offset(_ offset: CellSize) -> AnyTransition {
        .offset(x: offset.width, y: offset.height)
    }

    /// Grows from the anchor, and shrinks back to it.
    public static func scale(anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(.scale(anchor: anchor))
    }

    /// Grows from the centre, and shrinks back to it.
    public static let scale = AnyTransition.scale(anchor: .center)

    /// In from the leading edge, out to the trailing one — SwiftUI's own
    /// definition of a slide, which is asymmetric on purpose: a row leaving a
    /// list should carry on in the direction it was going, not reverse.
    public static let slide = AnyTransition.asymmetric(
        insertion: .move(edge: .leading), removal: .move(edge: .trailing))

    /// A transition that arrives one way and leaves another.
    public static func asymmetric(
        insertion: AnyTransition, removal: AnyTransition
    ) -> AnyTransition {
        AnyTransition(
            insertion: insertion.insertion, removal: removal.removal,
            explicitAnimation: insertion.explicitAnimation ?? removal.explicitAnimation)
    }

    /// This transition and another, applied together.
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(
            insertion: .combined(insertion, other.insertion),
            removal: .combined(removal, other.removal),
            explicitAnimation: explicitAnimation ?? other.explicitAnimation)
    }

    /// This transition, run with a particular animation whatever the change
    /// that caused it was made under.
    public func animation(_ animation: Animation?) -> AnyTransition {
        AnyTransition(
            insertion: insertion, removal: removal, explicitAnimation: animation)
    }
}
