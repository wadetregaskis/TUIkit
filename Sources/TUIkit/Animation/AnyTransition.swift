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
///
/// While a view is ARRIVING, the slot clips it: the part still outside is not
/// drawn. A SwiftUI frame clips nothing — `View.clipped(antialiased:)`
/// documents that a bounding frame is used only for layout and that content
/// beyond it stays visible — so a view sliding in there is expected to cross
/// its siblings. Here it would cross them by *erasing* them: a terminal cell
/// holds one glyph, so an arriving view has no way to be over a neighbour
/// without taking its cell. Wrap the transition in a container that clips (a
/// `ScrollView`, a `List`) and SwiftUI agrees; put it in a plain stack and this
/// is a deviation.
///
/// ## Overshoot
///
/// A spring goes past its target and comes back, so a phase above `1` is a
/// real value and not a rounding artefact — `Animation.bouncy` peaks at
/// **1.0460**, `Animation.snappy` at **1.0063**, and `Animation.smooth`, which
/// has no bounce, at exactly 1.
///
/// ``move(edge:)`` and ``offset(x:y:)`` draw that: past 1 the view stands a
/// cell or two clear of the slot it has just arrived in, floating over
/// whatever is beside it as `View.offset(x:y:)` does. The
/// displacement follows the curve with no minimum, so `.snappy`'s 0.13 of a
/// cell across a twenty-cell view draws no bounce at all — which is right,
/// since SwiftUI's snappy does not visibly bounce either. It is a whole number
/// of cells, so the bounce is bigger on a wide view (four cells across an
/// 80-column row at `.bouncy`) and, vertically, needs a panel eleven rows tall
/// before it moves at all.
///
/// ``opacity`` and ``scale`` stop at 1, and for reasons belonging to the
/// effects rather than to the spring: nothing is more opaque than opaque, and
/// `.scale` uncovers the buffer from an anchor — the buffer IS the slot, so
/// there is nothing beyond it to uncover.
///
/// Three consequences of floating the overshoot, each chosen and each a
/// deviation from a permanent `.offset`:
///
/// - **Clicks stay at the slot.** A transitioning view's hit-test regions
///   describe where it will be, not the cells it is passing through, for the
///   whole transition. Moving them with the picture would let them win the hit
///   test over a peer control the bounce is standing on, which is a worse
///   failure than a click landing where the eye aimed 100 ms ago.
/// - **Trailing blanks do not erase.** The floated cells are trimmed of
///   trailing padding first; a row that was all padding becomes nothing at all.
///   Leading blanks inside a row that has content do still paint over what they
///   pass, and so do INTERIOR ones — a `Spacer` between two labels erases what
///   is under the gap for as long as the bounce lasts. A layer has one origin,
///   not one per line, and rectangular content rather than a set of inked cells.
/// - **The screen edge cuts rather than pushes.** A view bouncing at the edge
///   loses the columns that fall off it, instead of sliding back on screen the
///   way a menu does.
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
