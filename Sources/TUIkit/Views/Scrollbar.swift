//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scrollbar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Scrollbar configuration

/// How end arrows are drawn on a scrollbar.
public enum ScrollbarArrows: Sendable, Hashable, CaseIterable {
    /// No arrows; the track spans the whole scrollbar.
    case none
    /// One arrow at each end pointing away from the centre (`▲` … `▼`,
    /// `◀` … `▶`) — the classic scrollbar.
    case single
    /// Both arrows at each end (`▲▼` … `▲▼`), as on a classic Mac scrollbar.
    case double
}

/// *Whether* a scrolling view says it can scroll — SwiftUI's
/// `ScrollIndicatorVisibility`, spelled the same.
///
/// This is one half of the question; ``ScrollIndicatorStyle`` is the other.
/// Visibility governs whether ANY indicator is drawn, style governs which one.
/// SwiftUI has only the one half because a graphical scroll view has only one
/// kind of indicator — a terminal also has the "42 more rows below" line, and
/// conflating "show me nothing" with "show me the other kind" would leave no
/// way to ask for nothing at all.
///
/// The case names are SwiftUI's, which is what matters at a call site: nobody
/// writes the type, they write `.scrollIndicators(.visible)`.
public enum ScrollIndicatorVisibility: Sendable, Hashable, CaseIterable {
    /// Let the scrolling view decide — here, show an indicator while the
    /// content overflows its viewport. The default.
    ///
    /// SwiftUI defines `.automatic` as deferring to "the policies of the
    /// component accepting the visibility configuration", which is a
    /// delegation rather than a behaviour: on macOS it resolves through the
    /// user's *Show scroll bars* preference and overlay scrollers that fade.
    /// A terminal has neither, so the policy is stated here, and overflow is
    /// the only thing there is to go on.
    case automatic
    /// Always show the indicator (even when everything fits).
    ///
    /// A scrollbar then draws a full-length thumb; the text style draws both
    /// "N more" lines at every offset, with a count that is legitimately zero.
    /// It used to draw nothing at an edge with nothing behind it, which made
    /// ``automatic`` and ``visible`` the same thing for it — and denied an app
    /// the one thing it asks `.visible` for, a viewport that does not resize
    /// under the reader as it scrolls (`d1c54212`).
    case visible
    /// Do not show any indicator.
    case hidden
    /// Never show any indicator.
    ///
    /// In SwiftUI this differs from ``hidden``: that one is a request a
    /// platform convention may still override, this one is unconditional.
    /// Nothing here can override a hidden indicator, so the two behave
    /// identically — it exists so that source written against SwiftUI compiles
    /// and means what it says.
    case never
}

/// *Which* indicator a scrolling view draws, when ``ScrollIndicatorVisibility``
/// says to draw one.
///
/// TUI-specific: SwiftUI has no equivalent because it has only one kind of
/// indicator to choose from.
public enum ScrollIndicatorStyle: Sendable, Hashable, CaseIterable {
    /// A scrollbar along the trailing edge (vertical) or the bottom
    /// (horizontal): a thumb sized to the visible fraction and positioned at
    /// sub-cell precision, so it shows *where* in the content the viewport is.
    /// Costs one column (or row) of the viewport, for the bar's whole length.
    ///
    /// The default, and the only style the horizontal axis has.
    case scrollbar
    /// A line of text at an edge with content behind it — "3 more rows above",
    /// "42 more rows below". Names *how much* is hidden rather than showing
    /// where the viewport sits, and under the default
    /// ``ScrollIndicatorVisibility/automatic`` costs a row only at an edge that
    /// actually has something to report. Under
    /// ``ScrollIndicatorVisibility/visible`` both lines are there at every
    /// offset, count and all, so the content area never changes size as the
    /// view scrolls (`d1c54212`).
    ///
    /// Vertical only: there is no horizontal equivalent, so a horizontally
    /// scrolling view under this style still draws its bar.
    case text
}

extension ScrollIndicatorVisibility {
    /// Whether an indicator is drawn at all, given whether the content
    /// overflows.
    ///
    /// The one place the four cases are turned into a yes/no. Every scrolling
    /// view asked this question by hand before, as `!= .hidden && (== .visible
    /// || overflows)` — a shape that silently answers "yes" for any case added
    /// later, which is exactly what ``never`` would have been.
    ///
    /// - Parameter overflowing: Whether the content exceeds its viewport.
    ///   An autoclosure because deciding that can mean measuring the whole
    ///   content, and the fixed cases (``hidden``, ``visible``, ``never``)
    ///   never need to know.
    func showsIndicator(overflowing: @autoclosure () -> Bool) -> Bool {
        switch self {
        case .visible: true
        case .automatic: overflowing()
        case .hidden, .never: false
        }
    }
}

/// What a scrolling view draws this frame to show that it scrolls: at most one
/// of a bar and the text lines, resolved from a visibility and a style.
///
/// The two are separate flags rather than an enum because the arithmetic reads
/// them separately — a bar narrows the content by a column for its whole
/// height, text steals a row at an edge — and because "neither" is
/// a real answer (``ScrollIndicatorVisibility/hidden``).
struct ResolvedScrollIndicators {
    /// A scrollbar is reserved down the trailing edge.
    let bar: Bool
    /// "N more above / below" lines are reserved — at the overflowing edges, or
    /// at BOTH edges at every offset under
    /// ``ScrollIndicatorVisibility/visible`` (`d1c54212`). Which of the two this
    /// is, the flag does not say: each of the three views works it out per frame.
    let text: Bool

    /// Nothing is drawn: the content scrolls silently.
    static let none = Self(bar: false, text: false)

    /// The shortest content area the "▲/▼ N more" lines can be drawn into:
    /// both may show at once, and at least one line of content has to survive
    /// them.
    ///
    /// A hard floor rather than a tolerance. The text indicators are LINES of
    /// the content area — `ScrollView` writes them over its first and last,
    /// `List` and `Table` reserve them out of the rows' budget — so a one- or
    /// two-line view scrolled away from the top is 100% chrome: "▲ N more rows
    /// above" as the entire view, advertising content that is then unreachable
    /// at every offset.
    static let minimumTextHeight = 3

    /// The same answer with the "N more" lines dropped when `contentHeight`
    /// cannot hold both of them and a row.
    ///
    /// Dropped rather than clipped, and dropped rather than swapped for a bar.
    /// A bar was tempting — it costs a COLUMN, so it fits a viewport of any
    /// height, and it would keep some affordance where this keeps none — but
    /// it silently overrides the style the app asked for, and `ScrollView`
    /// would then be the only one of the three that omits. Showing some
    /// content beats showing none, and three views agreeing beats cleverness
    /// in two of them. The resulting state is exactly `.scrollIndicators
    /// (.hidden)`, which every consumer downstream already handles.
    func fitting(contentHeight: Int) -> Self {
        guard text, contentHeight < Self.minimumTextHeight else { return self }
        return Self(bar: bar, text: false)
    }
}

extension EnvironmentValues {
    /// The vertical indicator this subtree's scrolling views draw.
    ///
    /// - Parameter overflowing: Whether the content exceeds its viewport.
    ///   An autoclosure for the reason ``ScrollIndicatorVisibility/showsIndicator(overflowing:)``
    ///   takes one: only ``ScrollIndicatorVisibility/automatic`` has to know,
    ///   and finding out can mean measuring the whole content.
    func verticalScrollIndicators(
        overflowing: @autoclosure () -> Bool
    ) -> ResolvedScrollIndicators {
        guard verticalScrollIndicatorVisibility.showsIndicator(overflowing: overflowing())
        else { return .none }
        switch scrollIndicatorStyle {
        case .scrollbar: return ResolvedScrollIndicators(bar: true, text: false)
        case .text: return ResolvedScrollIndicators(bar: false, text: true)
        }
    }

    /// Whether a vertical "N more" line is drawn even with nothing hidden that
    /// way — so the two lines are always there and the content area never
    /// changes size as the view scrolls.
    ///
    /// ``ScrollIndicatorVisibility/visible`` means visible. It used to mean
    /// "visible when it has something to say": at the top the "▲ N more above"
    /// line was absent, at the bottom the "▼ N more below" line was, and the rows
    /// gained a line at each end — so the thing an app asks for `.visible` to get,
    /// a viewport that does not resize under it, was the one thing it did not get.
    ///
    /// Only the text form has anything to answer here. A scrollbar spends a
    /// column for its whole height whatever is hidden, so it is already always
    /// there, and hidden indicators are always absent.
    var alwaysShowsVerticalTextIndicators: Bool {
        verticalScrollIndicatorVisibility == .visible && scrollIndicatorStyle == .text
    }

    /// Whether this subtree's horizontally scrolling views reserve a bottom
    /// scrollbar. There is no horizontal text indicator, so the style does not
    /// enter into it — a `.text` subtree still gets its horizontal bar.
    func showsHorizontalScrollbar(overflowing: @autoclosure () -> Bool) -> Bool {
        horizontalScrollIndicatorVisibility.showsIndicator(overflowing: overflowing())
    }
}

/// Which edges carry a scrollbar.
public struct ScrollbarEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The right edge (the default for vertical scrolling).
    public static let trailing = Self(rawValue: 1 << 0)
    /// The left edge.
    public static let leading = Self(rawValue: 1 << 1)
    /// The bottom edge (the default for horizontal scrolling).
    public static let bottom = Self(rawValue: 1 << 2)
    /// The top edge.
    public static let top = Self(rawValue: 1 << 3)
}

// MARK: - Environment & modifiers

// `.automatic` by default, as in SwiftUI: a view that scrolls says so.
//
// It is not free — `.automatic` has to know whether the content overflows, and
// on a ScrollView finding that out means measuring the content — but the
// alternative was worse than the cost. With scrollbars opt-in, the only way to
// get a plain scrolling view was to leave the visibility alone, so `.hidden`
// had to keep drawing the text indicators to say anything at all; there was
// then no value of this that meant "no indicator", and asking for one silently
// switched styles instead. See ``ScrollIndicatorStyle``.
private struct VerticalScrollIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue: ScrollIndicatorVisibility = .automatic
}

private struct HorizontalScrollIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue: ScrollIndicatorVisibility = .automatic
}

private struct ScrollIndicatorStyleKey: EnvironmentKey {
    static let defaultValue: ScrollIndicatorStyle = .scrollbar
}

private struct ScrollbarArrowsKey: EnvironmentKey {
    static let defaultValue: ScrollbarArrows = .single
}

private struct ScrollbarProportionalKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether scrolling views in this subtree draw a VERTICAL indicator —
    /// SwiftUI's `\.verticalScrollIndicatorVisibility`. Defaults to
    /// ``ScrollIndicatorVisibility/automatic``.
    ///
    /// Set through ``View/scrollIndicators(_:axes:)``; two values rather than
    /// one because that modifier takes an axis set, and a view scrolling both
    /// ways must be able to show one indicator and not the other.
    public internal(set) var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[VerticalScrollIndicatorVisibilityKey.self] }
        set { self[VerticalScrollIndicatorVisibilityKey.self] = newValue }
    }

    /// Whether scrolling views in this subtree draw a HORIZONTAL scrollbar —
    /// SwiftUI's `\.horizontalScrollIndicatorVisibility`. Defaults to
    /// ``ScrollIndicatorVisibility/automatic``.
    public internal(set) var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[HorizontalScrollIndicatorVisibilityKey.self] }
        set { self[HorizontalScrollIndicatorVisibilityKey.self] = newValue }
    }

    /// Which indicator scrolling views in this subtree draw, when their
    /// visibility says to draw one. Defaults to
    /// ``ScrollIndicatorStyle/scrollbar``.
    ///
    /// Set through ``View/scrollIndicatorStyle(_:)``. One value for both axes:
    /// only the vertical axis has a choice to make (see
    /// ``ScrollIndicatorStyle/text``).
    public internal(set) var scrollIndicatorStyle: ScrollIndicatorStyle {
        get { self[ScrollIndicatorStyleKey.self] }
        set { self[ScrollIndicatorStyleKey.self] = newValue }
    }

    /// The end-arrow style for scrollbars in this subtree. Defaults to
    /// ``ScrollbarArrows/single``.
    public var scrollbarArrows: ScrollbarArrows {
        get { self[ScrollbarArrowsKey.self] }
        set { self[ScrollbarArrowsKey.self] = newValue }
    }

    /// Whether a scrollbar's thumb is sized to the visible/total ratio (`true`,
    /// the default) or a fixed one cell (`false`).
    public var scrollbarProportionalThumb: Bool {
        get { self[ScrollbarProportionalKey.self] }
        set { self[ScrollbarProportionalKey.self] = newValue }
    }
}

extension View {
    /// Sets whether scrolling views (``ScrollView``, ``Table``, ``List``) within
    /// this view show that they scroll.
    ///
    /// Mirrors SwiftUI's `scrollIndicators(_:axes:)`, and governs *whether* an
    /// indicator is drawn, not which one — that is
    /// ``View/scrollIndicatorStyle(_:)``. So `.hidden` and `.never` mean no
    /// indicator of any kind, and the default,
    /// ``ScrollIndicatorVisibility/automatic``, shows one whenever the content
    /// overflows its viewport.
    ///
    /// ```swift
    /// ScrollView { content }.scrollIndicators(.hidden)   // scrolls silently
    /// ScrollView([.horizontal, .vertical]) { grid }
    ///     .scrollIndicators(.visible, axes: .vertical)   // always, one axis
    /// ```
    ///
    /// - Parameters:
    ///   - visibility: When an indicator is drawn.
    ///   - axes: Which axes it applies to. Defaults to both.
    /// - Returns: A view whose scrolling descendants follow the setting.
    public func scrollIndicators(
        _ visibility: ScrollIndicatorVisibility,
        axes: Axis.Set = [.horizontal, .vertical]
    ) -> some View {
        // Each axis is written only when named, which is what lets two calls
        // compose — `.scrollIndicators(.visible, axes: .vertical)` above
        // `.scrollIndicators(.automatic, axes: .horizontal)` leaves each bar
        // with its own policy instead of the second clobbering the first.
        // `transformEnvironment` rather than `environment` for exactly that: an
        // unnamed axis has to keep whatever it inherited, which is a value this
        // call cannot see.
        transformEnvironment(\.verticalScrollIndicatorVisibility) {
            if axes.contains(.vertical) { $0 = visibility }
        }
        .transformEnvironment(\.horizontalScrollIndicatorVisibility) {
            if axes.contains(.horizontal) { $0 = visibility }
        }
    }

    /// Sets which indicator scrolling views within this view draw — a
    /// scrollbar (the default) or "N more above / below" text.
    ///
    /// TUI-specific, and orthogonal to ``View/scrollIndicators(_:axes:)``:
    /// visibility decides whether anything is drawn, this decides what. A view
    /// whose indicators are hidden draws nothing whatever this says.
    ///
    /// ```swift
    /// List(rows) { … }.scrollIndicatorStyle(.text)   // "42 more rows below"
    /// ```
    ///
    /// - Parameter style: The indicator to draw.
    /// - Returns: A view whose scrolling descendants follow the setting.
    public func scrollIndicatorStyle(_ style: ScrollIndicatorStyle) -> some View {
        environment(\.scrollIndicatorStyle, style)
    }

    /// Sets the end-arrow style of scrollbars within this view.
    public func scrollbarArrows(_ arrows: ScrollbarArrows) -> some View {
        environment(\.scrollbarArrows, arrows)
    }

    /// Sets whether scrollbar thumbs within this view are sized proportionally to
    /// the visible region (`true`) or a fixed single cell (`false`).
    public func scrollbarProportionalThumb(_ proportional: Bool) -> some View {
        environment(\.scrollbarProportionalThumb, proportional)
    }
}

// MARK: - Track cell

/// One cell of a rendered scrollbar track.
///
/// `inverted` distinguishes the two anchorings that share a glyph set: a
/// bottom-/left-anchored partial is drawn directly (thumb colour as the glyph
/// ink), while a top-/right-anchored partial is drawn by *inverting* the
/// complementary block — the thumb colour becomes the cell background — because
/// Unicode has no top-/right-anchored partial-block series. See
/// ``ScrollbarRenderer``.
struct ScrollbarCell: Equatable {
    /// The block glyph (or a space for an empty track cell, `█` for a full one).
    let glyph: Character
    /// `true` when the thumb colour is the cell *background* (top/right anchor).
    let inverted: Bool

    static let empty = Self(glyph: " ", inverted: false)
    static let full = Self(glyph: "█", inverted: false)
}

/// The three colours a scrollbar draws with: the thumb (handle), the track
/// (groove behind it), and the end arrows.
struct ScrollbarColors {
    let thumb: Color
    let track: Color
    let arrow: Color

    /// The bar-relative cell the pointer is over, and the tone to draw it in —
    /// `nil` when the pointer is elsewhere.
    ///
    /// A cell rather than a *part*, so `.double` arrows work: both ends carry
    /// an up-arrow and a down-arrow, and lighting "the up arrow" would light
    /// the one at the far end too. Only one cell is ever under the pointer.
    var hover: (cell: Int, color: Color)?

    /// The arrow colour, in the hover tone when the pointer is on cell `index`.
    ///
    /// **Arrows only, and deliberately.** The thumb is drawn as a filled cell
    /// background rather than a glyph, so lifting the one cell under the
    /// pointer put a brighter block in the middle of a solid bar — which reads
    /// as a block cursor parked on the scroller rather than as a hover state,
    /// and was reported as one. An arrow is a single cell and IS the control it
    /// draws, so there the lift means exactly what it looks like.
    func arrowColor(atCell index: Int) -> Color {
        hover.map { $0.cell == index ? $0.color : arrow } ?? arrow
    }

    /// The standard palette for a bar that doubles as its container's focus
    /// indicator: quiet secondary/tertiary tones unfocused, and a PULSING
    /// accent thumb + arrows when focused — the same SelectionIndicator
    /// convention (and `.selectionIndicatorStyle` knob) every other focused
    /// control breathes with. The steady accent alone was too subtle a
    /// focus cue.
    /// - Parameter hoveredCell: the bar-relative cell under the pointer, if
    ///   any. A scrollbar's arrows and thumb are controls — the only ones that
    ///   had no answer to the pointer at all — so the cell under it lifts, the
    ///   way every other control's foreground does (``Palette/hoveredForeground(_:)``).
    @MainActor
    static func focusIndicating(
        isFocused: Bool, hoveredCell: Int? = nil, context: RenderContext
    ) -> Self {
        let palette = context.environment.palette
        // §1.2 of the scroll-anchoring spec: when the user may not adjust the
        // scroll position, the chrome still renders — in a disabled state. One
        // step quieter than the resting bar, so the view reads as pinned rather
        // than as having no more content.
        // A bar that cannot be scrolled is not a control, so it does not
        // answer the pointer either.
        guard context.environment.isScrollEnabled else {
            return Self(
                thumb: palette.foregroundTertiary,
                track: Self.track(in: palette),
                arrow: Self.track(in: palette))
        }
        guard isFocused else {
            return Self(
                thumb: palette.foregroundSecondary,
                track: Self.track(in: palette),
                arrow: palette.foregroundTertiary,
                hover: hoveredCell.map {
                    ($0, palette.hoveredForeground(palette.foregroundSecondary))
                })
        }
        // The cycle, not the live phase: building it reads no clock, so a
        // focused bar no longer forces a full re-render on every tick. The
        // cells are handed to the run loop instead — see `focusCycle` and
        // ``AnimatedCellRun``.
        let cycle = context.environment.selectionEmphasis.cycle(true)
        // The dim end strictly — it is the thumb's RESTING state, and a resting
        // thumb quieter than its groove is the hole this all exists to stop.
        // The bright end and every point between are the breath, and are
        // separated from the track without that second rule: see `pulseLift`
        // for the three palettes that have no room to satisfy both.
        let now = Self.separated(
            cycle.colorNow(
                dim: Self.separated(palette.accent.resolve(with: palette), in: palette),
                bright: Self.pulseLift(palette)),
            in: palette, standingOffThePage: false)
        return Self(
            thumb: now,
            track: Self.track(in: palette),
            arrow: now,
            hover: hoveredCell.map { ($0, palette.hoveredForeground(now)) })
    }

    /// The far end of the focused bar's breath: the accent LIFTED, away from
    /// the page — brighter on a dark palette, darker on a light one.
    ///
    /// The breath used to run the other way, from the accent down to
    /// `accent.opacity(focusPulseMin, over: background)`, which is what every
    /// other focused control does. On a thumb it did not work, and the reason
    /// is that a thumb is an AREA rather than an outline: a button's border
    /// fading toward the page still has its label, while a solid block fading
    /// toward the page is a hole. Measured on the green palette, the recessive
    /// end came out `rgb(11, 27, 11)` — darker than the track it sits in
    /// (`rgb(22, 90, 22)`) and all but the background (`rgb(5, 10, 5)`), so the
    /// scroller read as pulsing in and out of existence.
    ///
    /// ``Palette/hoveredForeground(_:)`` is the framework's existing answer to
    /// "one step away from the page, whichever way that is": brighter on a dark
    /// palette, and on a light one — or on a palette whose accent is already at
    /// the extreme, like the white terminal's — darker instead. The same rule
    /// the pointer's own lift follows, which is why the hovered cell can go on
    /// stepping one further from wherever the breath currently is.
    /// …and where there is no room in that direction, the other one.
    ///
    /// `hoveredForeground` steps AWAY from the page, and a palette whose accent
    /// already sits at the far end has nowhere to step: measured on **Ocean**,
    /// whose accent is `215,255,255`, both ends of the breath came out at
    /// `215,255,255` — a focused scrollbar that did not move. Man Page's had
    /// collapsed onto black the same way, from the other side, once its own
    /// track separation pushed it there.
    ///
    /// So the lift is floored against the RESTING end, and
    /// ``Color/ensuringRenderedContrast(atLeast:against:)`` takes whichever
    /// direction has the room. Toward the page is not the fault the breath's
    /// direction was reversed to fix: that was a fade all the way down to
    /// `focusPulseMin`, which turns a solid block into a hole, and this is the
    /// smallest step that can be seen at all — with the track separation put
    /// back afterwards, so it cannot land in its own groove.
    @MainActor
    static func pulseLift(_ palette: any Palette) -> Color {
        let lifted = separated(palette.hoveredForeground(palette.accent), in: palette)
        let resting = separated(palette.accent.resolve(with: palette), in: palette)
        guard renderedRatio(lifted, resting) < ViewConstants.chromePulseFloor else { return lifted }
        // A fixed proportional step toward whichever extreme the resting colour
        // is FURTHER from, rather than another contrast walk: the walk moves in
        // 1% lightness steps and a colour this close to an extreme needs a
        // large move to change its contrast at all, so it stopped short every
        // time. A fifth of the way to the far end is always a visible change
        // and never more than a breath.
        let extreme: Color =
            renderedRatio(resting, .rgb(255, 255, 255)) >= renderedRatio(resting, .rgb(0, 0, 0))
            ? .rgb(255, 255, 255) : .rgb(0, 0, 0)
        // The SMALLEST step that can be seen, not a fixed one: a fixed depth
        // barely moved a colour already near an extreme and flung a mid-tone
        // one across the range (Man Page measured a 5.50:1 breath, which is a
        // flash rather than a breath). Largest surviving fraction first, so the
        // first acceptable answer is the least movement that clears the floor.
        //
        // A LIFT, not a composite: nothing is drawn behind the bar in white or
        // black — the extreme is only a direction to step the resting accent in.
        // `compositing` mixes the two and returns a fresh opaque `.rgb`, dropping
        // the accent's own alpha, and a step that re-spells the accent has to
        // carry it, as `hoveredForeground` — the first exit — does. Dropped, a
        // faded accent breathed from 128 to 255 whenever this loop was taken,
        // and no one claim could describe the run's frames (§44).
        func towardExtreme(_ surviving: Double) -> Color {
            resting.compositing(surviving, over: extreme).carryingAlpha(of: resting)
        }
        for surviving in stride(from: 0.98, through: ViewConstants.chromePulseDepth, by: -0.02) {
            let candidate = separated(
                towardExtreme(surviving), in: palette, standingOffThePage: false)
            if renderedRatio(candidate, resting) >= ViewConstants.chromePulseFloor {
                return candidate
            }
        }
        return separated(
            towardExtreme(ViewConstants.chromePulseDepth), in: palette, standingOffThePage: false)
    }

    /// `thumb`, pushed until it is legible against `track`.
    ///
    /// Applied to EVERY point of the breath, not only to its recessive end.
    /// Flooring the endpoints is not enough, and the reason is the cube: the
    /// points between them are interpolated in RGB and then quantised, and a
    /// quiet accent and a quiet grey collapse onto one 256-entry somewhere in
    /// the middle of a span whose ends are both clear of each other. So the
    /// thumb still vanished into its track once per breath — a scroll position
    /// that flickers out is worse than one drawn flat, because the eye is
    /// tracking it.
    ///
    /// Through the cube (``Color/ensuringRenderedContrast(atLeast:against:)``),
    /// because that is where the collapse happens; measured in sRGB it never
    /// shows up at all.
    /// The thumb is also never allowed to end up QUIETER against the page than
    /// its own track. ``Color/ensuringRenderedContrast(atLeast:against:)`` takes
    /// the NEARER of the two directions that clear the track and has no opinion
    /// about which side of the page it lands on — and on a palette whose accent
    /// and track sit close together the nearer direction is toward the page.
    /// Measured on **Man Page** (a pale yellow page, `rgb(254, 244, 156)`, a
    /// track at `rgb(157, 151, 96)` and an accent 1.03:1 from it): the accent
    /// stood 3.67:1 off the page and came back at 2.21:1, against a track at
    /// 3.56:1 — a hole in its own groove. That is the same fault the breath's
    /// direction was reversed to fix, arriving from the other end.
    ///
    /// Three answers, in order of how little they move the colour:
    ///
    /// 1. The plain separation, when it is already at least as loud as the
    ///    groove — which it is on every palette but one.
    /// 2. The MINIMAL colour that stands as far off the page as the track does,
    ///    when that is also clear of the track. It rarely is: standing off the
    ///    page by exactly the track's own amount tends to land ON the track.
    /// 3. A step of ``Palette/hoveredForeground(_:)`` — the framework's "one
    ///    step away from the page, whichever way that is", the same primitive
    ///    ``pulseLift(_:)`` uses — from there. Man Page clears both on the
    ///    first step (6.46:1 off the page, 1.81:1 off the track).
    ///
    /// One step, not a walk: `hoveredForeground` is not monotone under
    /// repetition (it bottoms out and comes back), so iterating it wanders
    /// rather than converges. Failing all three the plain separation stands —
    /// being tellable from the track is the more important of the two
    /// properties, and it is the one a caller cannot recover.
    /// - Parameter standingOffThePage: Whether the answer must also be at least
    ///   as loud against the page as the track is. True for anything drawn as
    ///   the thumb's resting state; false for the far end of a BREATH, where
    ///   the alternative is no breath at all — the smallest visible step cannot
    ///   read as a hole, and three palettes have no room to make it in the
    ///   other direction.
    @MainActor
    static func separated(
        _ thumb: Color, in palette: any Palette, standingOffThePage: Bool = true
    ) -> Color {
        let track = Self.track(in: palette)
        let page = palette.background.resolve(with: palette)
        let floored = thumb.ensuringRenderedContrast(
            atLeast: ViewConstants.chromeSeparationFloor, against: track)
        let groove = renderedRatio(track, page)
        func standsOff(_ color: Color) -> Bool {
            (!standingOffThePage || renderedRatio(color, page) >= groove)
                && renderedRatio(color, track) >= ViewConstants.chromeSeparationFloor
        }
        guard !standsOff(floored) else { return floored }
        let offThePage = floored.ensuringRenderedContrast(atLeast: groove, against: page)
        if standsOff(offThePage) { return offThePage }
        let stepped = palette.hoveredForeground(offThePage)
        return standsOff(stepped) ? stepped : floored
    }

    /// The colour a scroll TRACK is drawn in: the palette's quietest rung,
    /// moved along its own line until it is tellable from both the accent
    /// drawn on it and the page it sits on.
    ///
    /// Six of the sixteen shipped profiles derive `foregroundQuaternary` within
    /// the chrome-separation floor of their own accent, and Ocean's lands on
    /// the SAME 256-colour entry: a groove the colour of its own thumb.
    /// `separated` then pushes the thumb to an extreme to clear it, where it
    /// has no room left to breathe — which is why a focused scrollbar did not
    /// move on those profiles.
    ///
    /// Fixed here rather than in the derivation, deliberately. The requirement
    /// belongs to the scrollbar: it is the one place the accent is drawn ON the
    /// quietest rung, and constraining the rung itself would have moved a
    /// colour that spinners, pickers and menu chrome also draw in — measured on
    /// Grass, it took the quaternary from a muted green to a pale yellow to get
    /// clear of the amber accent, which is a large change to a theme for one
    /// control's benefit.
    ///
    /// Toward the page first at each step, because a groove wants to be the
    /// quieter of the two; toward the ink when that direction runs out (Grass's
    /// page is a teal its track already sits near, so quieting it further
    /// erases it). Failing both, the palette's own rung stands: a groove too
    /// close to its thumb is a worse bar than one too close to its page, and an
    /// INVISIBLE groove is worse than either.
    @MainActor
    static func track(in palette: any Palette) -> Color {
        let base = palette.foregroundQuaternary.resolve(with: palette)
        let accent = palette.accent.resolve(with: palette)
        let page = palette.background.resolve(with: palette)
        let ink = palette.foreground.resolve(with: palette)
        // Every input of `resolvedTrack` is in the key. The ink was not, so two
        // palettes alike but for their foreground shared one answer — and the
        // answer can be the FALLBACK, cached from a palette whose ink offered
        // no acceptable rung and served to one whose ink would have.
        let key = TrackKey(base: base, accent: accent, page: page, ink: ink)
        if let cached = trackCache[key] { return cached }
        let answer = resolvedTrack(base: base, accent: accent, page: page, ink: ink)
        // Sixteen palettes and one entry each; the cap is a backstop against an
        // app generating palettes per frame, not a working set.
        if trackCache.count > 64 { trackCache.removeAll(keepingCapacity: true) }
        trackCache[key] = answer
        return answer
    }

    private struct TrackKey: Hashable {
        let base: Color
        let accent: Color
        let page: Color
        let ink: Color
    }

    /// Up to 24 quantisations per palette, so it is answered once and kept —
    /// this is asked per scrollbar per frame.
    @MainActor private static var trackCache: [TrackKey: Color] = [:]

    /// Internal, not private, so the memo test can ask for a cold answer.
    static func resolvedTrack(base: Color, accent: Color, page: Color, ink: Color) -> Color {
        func acceptable(_ candidate: Color) -> Bool {
            renderedRatio(candidate, accent) >= ViewConstants.chromeSeparationFloor
                && renderedRatio(candidate, page) >= ViewConstants.chromeGrooveFloor
        }
        guard !acceptable(base) else { return base }
        for step in 1...12 {
            let phase = Double(step) / 12
            for candidate in [
                Color.lerp(base, page, phase: phase), Color.lerp(base, ink, phase: phase),
            ] where acceptable(candidate) {
                return candidate
            }
        }
        return base
    }

    /// Two colours' contrast AS DRAWN — through the 256-colour cube, which is
    /// where chrome this quiet collapses. See ``separated(_:in:)``.
    private static func renderedRatio(_ lhs: Color, _ rhs: Color) -> Double {
        lhs.downsampledToPalette256().contrastRatio(against: rhs.downsampledToPalette256())
    }

    /// Everything the bar's ANIMATION is coloured from, or nil when nothing
    /// about it moves — not focused, scrolling disabled, or
    /// `.selectionIndicatorStyle(.none)`.
    ///
    /// A caller that gets one must hand the bar's cells to the run loop as
    /// ``AnimatedCellRun``s; a caller that gets nil has a still bar and needs no
    /// runs. Nothing here reads a clock.
    ///
    /// Takes `hoveredCell` for the same reason
    /// ``focusIndicating(isFocused:hoveredCell:context:)`` does, and the two
    /// calls sit together at every call site so that stays visible: the runs
    /// REPLACE the drawn cells from the first tick, so anything the draw
    /// answered the pointer with has to be in them too.
    @MainActor
    static func focusPulse(
        isFocused: Bool, hoveredCell: Int?, context: RenderContext
    ) -> ScrollbarPulse? {
        guard context.environment.isScrollEnabled, isFocused else { return nil }
        let cycle = context.environment.selectionEmphasis.cycle(true)
        guard cycle.isAnimating else { return nil }
        return ScrollbarPulse(
            cycle: cycle, hoveredCell: hoveredCell, palette: context.environment.palette)
    }
}

/// The colours a focused scrollbar breathes through — one ``ScrollbarColors``
/// per point of its cycle.
///
/// A type rather than three parameters travelling side by side, because it is
/// the ONLY thing that builds the colours a run replays, and a run replaces
/// the cells rather than decorating them: every input the drawn bar's colours
/// have, these need too. Kept apart, the pointer's lift was left out of the
/// runs and the first tick painted it away — see §9 of
/// `Documentation/Animating your own view efficiently.md`.
struct ScrollbarPulse {
    /// The emphasis cycle, whose points become the frames.
    let cycle: SelectionEmphasisCycle

    /// The bar-relative cell under the pointer, if any.
    let hoveredCell: Int?

    let palette: any Palette

    /// One set of colours per point of the cycle, in cycle order.
    @MainActor
    var frames: [ScrollbarColors] {
        cycle.colors(
            dim: ScrollbarColors.separated(palette.accent.resolve(with: palette), in: palette),
            bright: ScrollbarColors.pulseLift(palette)
        )
        .map { ScrollbarColors.separated($0, in: palette, standingOffThePage: false) }
            .map { accent in
                ScrollbarColors(
                    thumb: accent, track: ScrollbarColors.track(in: palette), arrow: accent,
                    // The same step further the live draw takes, so the hovered
                    // cell breathes WITH the bar rather than sitting at a fixed
                    // tone while everything around it moves.
                    hover: hoveredCell.map { ($0, palette.hoveredForeground(accent)) })
            }
    }
}

// MARK: - Renderer

/// Computes the sub-cell-precise glyphs for a scrollbar track.
///
/// The thumb's size is proportional to `viewport / extent` and its position to
/// `offset / (extent − viewport)`, both measured in *eighths* of a cell so the
/// thumb's ends can land at fractional cell positions. The fractional ends use
/// partial block glyphs; a minimum thumb of one whole cell guarantees the two
/// ends always fall in different cells, so each partial cell is cleanly anchored
/// to one edge.
enum ScrollbarRenderer {
    /// The `count` track cells for the given scroll metrics.
    ///
    /// - Parameters:
    ///   - count: The track length, in cells.
    ///   - extent: The total content size (lines, or columns).
    ///   - viewport: The visible size.
    ///   - offset: The current scroll offset, in `0...(extent − viewport)`.
    ///   - proportional: When `true` the thumb is sized to `viewport / extent`;
    ///     when `false` it is a fixed one cell.
    ///   - vertical: `true` for a vertical scrollbar (lower-block glyphs,
    ///     inverting for the top-anchored end); `false` for a horizontal one
    ///     (left-block glyphs, inverting for the right-anchored end).
    static func trackCells(
        count: Int, extent: Int, viewport: Int, offset: Int,
        proportional: Bool = true, vertical: Bool
    ) -> [ScrollbarCell] {
        guard count > 0 else { return [] }
        // Everything fits: the thumb fills the whole track.
        guard extent > viewport, viewport > 0 else {
            return Array(repeating: .full, count: count)
        }

        let span = thumbSpan(
            count: count, extent: extent, viewport: viewport, offset: offset, proportional: proportional)
        let start = span.start
        let end = span.end

        var cells: [ScrollbarCell] = []
        cells.reserveCapacity(count)
        for cell in 0..<count {
            let cellLo = cell * 8
            let lo = max(start, cellLo) - cellLo  // 0...8 within the cell
            let hi = min(end, cellLo + 8) - cellLo
            if hi <= lo {
                cells.append(.empty)
            } else if lo == 0 && hi == 8 {
                cells.append(.full)
            } else if lo == 0 {
                // Covered from the cell's start edge (top / left).
                cells.append(
                    vertical
                        ? ScrollbarCell(glyph: Self.lowerBlock(8 - hi), inverted: true)
                        : ScrollbarCell(glyph: Self.leftBlock(hi), inverted: false))
            } else {
                // Covered to the cell's far edge (bottom / right).
                cells.append(
                    vertical
                        ? ScrollbarCell(glyph: Self.lowerBlock(8 - lo), inverted: false)
                        : ScrollbarCell(glyph: Self.leftBlock(lo), inverted: true))
            }
        }
        return cells
    }

    /// The thumb's covered sub-cell range `start..<end` (eighths of a cell) within
    /// a `count`-cell track, shared by ``trackCells`` (rendering) and the hit-test
    /// (interaction) so the two never disagree about where the thumb is. The range
    /// spans `0...(count*8)`; the thumb is at least one whole cell (8 sub-units).
    static func thumbSpan(
        count: Int, extent: Int, viewport: Int, offset: Int, proportional: Bool
    ) -> (start: Int, end: Int) {
        let totalSub = count * 8
        guard count > 0, extent > viewport, viewport > 0 else { return (0, totalSub) }
        let proportionalSub = Int((Double(viewport) / Double(extent) * Double(totalSub)).rounded())
        let thumbSub = min(totalSub, max(8, proportional ? proportionalSub : 8))
        let travel = totalSub - thumbSub
        let maxOffset = extent - viewport
        let rawStart = maxOffset > 0
            ? Int((Double(offset) / Double(maxOffset) * Double(travel)).rounded())
            : 0
        let start = max(0, min(travel, rawStart))
        return (start, start + thumbSub)
    }

    /// The lower block filled `eighths`/8 from the bottom: `▁`…`▇`, `█` at 8.
    static func lowerBlock(_ eighths: Int) -> Character {
        guard eighths >= 1 else { return " " }
        return Character(UnicodeScalar(0x2580 + min(8, eighths))!)
    }

    /// The left block filled `eighths`/8 from the left: `▏`…`▉`, `█` at 8.
    static func leftBlock(_ eighths: Int) -> Character {
        guard eighths >= 1 else { return " " }
        return Character(UnicodeScalar(0x2590 - min(8, eighths))!)
    }

    /// The glyph one track cell draws, and the colours it draws it in.
    ///
    /// Fully-covered and empty cells are drawn as a *space* coloured by background
    /// — the thumb colour and the track colour respectively — never as a `█` glyph.
    /// Two reasons: adjacent block glyphs leave a hairline gap in some terminals
    /// (notably Terminal.app, the same gap seen between box-drawing characters),
    /// whereas contiguous background colour is seamless; and a background fill
    /// covers the *whole* cell, so a one-cell thumb is as solid as a multi-cell one
    /// instead of looking thinner. Only the fractional end cells need a partial
    /// glyph: a bottom-/left-anchored end draws the partial block in the thumb
    /// colour over the track, an inverted (top-/right-anchored) end swaps them so
    /// the thumb colour is the cell background — which is also how the two anchors
    /// Unicode lacks a partial-block series for are produced.
    ///
    /// A description rather than bytes. It used to return the styled cell, which was
    /// the one place a bar cell became bytes and so the one place its claim belonged
    /// — with nowhere to put one. The row or column the cell lands in now turns this
    /// into bytes AND a claim in one statement, and an end cell is why that has to
    /// know both colours: its glyph is one of thumb and track and its field the
    /// other, the same two-channel cell as `.blockFine`'s boundary (§31.1).
    static func paint(
        of cell: ScrollbarCell, thumb: Color, track: Color
    ) -> (glyph: String, ink: Color?, field: Color) {
        if cell.glyph == " " { return (" ", nil, track) }
        if cell.glyph == "█" { return (" ", nil, thumb) }
        if cell.inverted { return (String(cell.glyph), track, thumb) }
        return (String(cell.glyph), thumb, track)
    }

    /// The number of cells an arrow configuration reserves at each *end* combined
    /// (so a vertical bar loses this many track cells overall).
    static func arrowReserve(_ arrows: ScrollbarArrows) -> Int {
        switch arrows {
        case .none: return 0
        case .single: return 2
        case .double: return 4
        }
    }

    /// A vertical scrollbar `height` cells tall: a `▲`/`▼` arrow assembly at each
    /// end (per `arrows`) wrapped around a sub-cell-precise track. One cell per
    /// line, with the claims its colours owe in the bar's own coordinates — the
    /// caller knows which column the bar lands in and shifts them there. Arrows are
    /// dropped if the bar is too short to also show a track.
    static func verticalScrollbar(
        height: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, colors: ScrollbarColors
    ) -> ClaimingColumn {
        var bar = ClaimingColumn()
        guard height > 0 else { return bar }
        let reserve = height > arrowReserve(arrows) ? arrowReserve(arrows) : 0
        func arrow(_ glyph: String, atCell cell: Int) {
            bar.append(glyph, ink: colors.arrowColor(atCell: cell), field: colors.track)
        }
        // `single` → ▲ … ▼; `double` → ▲▼ … ▲▼ (both arrows at each end).
        let last = height - 1
        if reserve > 0 { arrow("▲", atCell: 0) }
        if reserve == 4 { arrow("▼", atCell: 1) }
        for cell in trackCells(
            count: height - reserve, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional, vertical: true)
        {
            let drawn = paint(of: cell, thumb: colors.thumb, track: colors.track)
            bar.append(drawn.glyph, ink: drawn.ink, field: drawn.field)
        }
        if reserve == 4 { arrow("▲", atCell: last - 1) }
        if reserve > 0 { arrow("▼", atCell: last) }
        return bar
    }

    /// The vertical bar's animation runs: one per row whose cell actually
    /// changes across the cycle.
    ///
    /// Built by rendering the WHOLE bar once per colour of the cycle and
    /// keeping the rows that differ — so the glyph logic (thumb spans in
    /// eighths, partial end cells, arrow reserve) is written once and the
    /// animation cannot disagree with the render about which cells are thumb.
    /// Empty track cells come out identical at every colour and so earn no run,
    /// which is what keeps a tall bar from repainting its whole length 20 times
    /// a second to move a two-cell thumb.
    ///
    /// Offsets are relative to the bar's own column, row 0 — the caller knows
    /// where the bar sits and shifts them.
    @MainActor
    static func verticalScrollbarRuns(
        height: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, pulse: ScrollbarPulse
    ) -> [AnimatedCellRun] {
        let frames = pulse.frames.map { colors in
            verticalScrollbar(
                height: height, extent: extent, viewport: viewport, offset: offset,
                arrows: arrows, proportional: proportional, colors: colors)
        }
        guard let first = frames.first else { return [] }
        assertOneClaim(frames.map(\.claims))
        return (0..<first.count).compactMap { row in
            let cells = frames.map { $0.lines.indices.contains(row) ? $0.lines[row] : "" }
            guard Set(cells).count > 1 else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: row, width: cells[0].strippedLength,
                frames: cells, clock: .cursor)
        }
    }

    /// The horizontal bar's run: the whole bar row.
    ///
    /// One run rather than per-cell, because a horizontal bar is a single row
    /// and splitting it would mean diffing styled cells to find the animated
    /// span. The static track cells are repainted with it — one row's worth of
    /// bytes per tick, which is the price of not writing a second cell-diffing
    /// routine that could disagree with the renderer.
    @MainActor
    static func horizontalScrollbarRun(
        width: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, pulse: ScrollbarPulse
    ) -> AnimatedCellRun? {
        let rows = pulse.frames.map { colors in
            horizontalScrollbar(
                width: width, extent: extent, viewport: viewport, offset: offset,
                arrows: arrows, proportional: proportional, colors: colors)
        }
        assertOneClaim(rows.map(\.claims))
        let frames = rows.map(\.text)
        guard let first = frames.first, Set(frames).count > 1 else { return nil }
        return AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: first.strippedLength,
            frames: frames, clock: .cursor)
    }

    /// Traps, in a debug build, when a pulse's frames do not all owe the same
    /// claims.
    ///
    /// A run replays BYTES, and the bytes are opaque spellings. The alpha is in the
    /// drawn bar's claims, which the resolver applies to every frame of a run at one
    /// alpha per cell (§29.2) — so a run is right only if every frame owes exactly
    /// what the drawn bar does, and the drawn bar is one of these frames (its colour
    /// is `colorNow`, which indexes the same cycle). That holds by construction while
    /// both ends of the breath carry the accent's alpha. A breath whose ends disagree
    /// would blend all but one of its frames at the wrong alpha with nothing on
    /// screen to say so, since the bytes are fine; this is what says so.
    private static func assertOneClaim(_ claims: [[OpacityRegion]]) {
        assert(
            claims.allSatisfy { $0 == claims.first },
            "a scrollbar's pulse frames owe different claims: its breath's two ends disagree about alpha (§29)")
    }

    /// A horizontal scrollbar `width` cells wide: a `◀`/`▶` arrow assembly at each
    /// end wrapped around a sub-cell-precise track, as one row with the claims its
    /// colours owe.
    static func horizontalScrollbar(
        width: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, colors: ScrollbarColors
    ) -> ClaimingRow {
        var bar = ClaimingRow()
        guard width > 0 else { return bar }
        let reserve = width > arrowReserve(arrows) ? arrowReserve(arrows) : 0
        func arrow(_ glyph: String, atCell cell: Int) {
            bar.append(glyph, cells: 1, ink: colors.arrowColor(atCell: cell), field: colors.track)
        }
        let last = width - 1
        if reserve > 0 { arrow("◀", atCell: 0) }
        if reserve == 4 { arrow("▶", atCell: 1) }
        for cell in trackCells(
            count: width - reserve, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional, vertical: false)
        {
            let drawn = paint(of: cell, thumb: colors.thumb, track: colors.track)
            bar.append(drawn.glyph, cells: 1, ink: drawn.ink, field: drawn.field)
        }
        if reserve == 4 { arrow("◀", atCell: last - 1) }
        if reserve > 0 { arrow("▶", atCell: last) }
        return bar
    }
}
