//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedRunAlpha.swift
//
//  What an ``AnimatedCellRun``'s cells owe the compositor, stated per FRAME.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The alpha an ``AnimatedCellRun``'s own cells owe, one statement per frame.
///
/// ## Why the run and not a region
///
/// Bytes state a colour's opaque spelling and the alpha travels beside them as an
/// ``OpacityRegion``. That pairing works for anything drawn once, and a run is drawn
/// many times: the loop splices a later frame over the same cells without asking the
/// view anything, so one rectangle has to describe every frame. It can, as long as the
/// frames agree about alpha — and where they do, a plain region is still the right
/// answer and this type is not used.
///
/// Where they disagree, no rectangle can be true of them all. A breathing border whose
/// two ends have different alphas, or a blinking block caret that shows a translucent
/// well on one frame and its own opaque colour on the next, has no single answer. Both
/// used to state nothing at all, so those cells rendered at full strength — correct
/// bytes, silently wrong colour.
///
/// Stating it here rather than as a second kind of region is what makes the frames and
/// their alphas impossible to misalign: they are the same array, in the same order, on
/// the same value. A parallel list of phases keyed by index is the shape
/// ``OpacityCycle`` needs for a *layer* fade, where the phases genuinely belong to
/// something else and `combinedTicks` has to reconcile two clocks. Here they belong to
/// the run, so there is nothing to reconcile and nothing to drift.
///
/// ## Coordinates
///
/// Spans are **run-relative**: column 0 is the run's first cell, whatever column that
/// is in the carrying buffer. So ``AnimatedCellRun/shifted(byX:y:)`` and
/// ``AnimatedCellRun/movedTo(row:)`` are the identity for this payload and every
/// compositing shift leaves it alone — which is also what lets a producer build one
/// payload and share it across every copy of a run, as `ContainerViewCore` does with a
/// border's side walls.
public struct AnimatedRunAlpha: Sendable, Equatable {

    /// A span of the run's cells owing one pair of alphas.
    ///
    /// Ink and field only, and deliberately no layer channel. A layer's alpha nests and
    /// ``OpacityFade`` has already folded every enclosing `.opacity(_:)` into the
    /// regions it carries up; it cannot see a payload riding on a run, so a layer value
    /// here would be one this type could never keep current. Ink and field do not nest,
    /// which is exactly why they can be stated here and multiplied in later.
    public struct Span: Sendable, Equatable {
        /// The first cell, relative to the run's own first cell.
        public var start: Int

        /// How many cells.
        ///
        /// Named `cells` rather than `count` so `cells > 0` is not read as a collection
        /// emptiness test — it is a width, and a span of none is simply nothing.
        public var cells: Int

        /// What the glyphs owe: 1 where they are opaque.
        public var ink: Double

        /// What the cells' background owes: 1 where it is opaque.
        public var field: Double

        public init(start: Int, cells: Int, ink: Double = 1, field: Double = 1) {
            self.start = start
            self.cells = cells
            self.ink = ink
            self.field = field
        }

        /// Whether this says anything the resolver would act on.
        var isTranslucent: Bool { ink < 1 || field < 1 }
    }

    /// One entry per frame of the run, in the run's own frame order.
    ///
    /// A frame owing nothing carries an empty list rather than being absent, so the
    /// indices line up with ``AnimatedCellRun/frames`` by construction.
    public var perFrame: [[Span]]

    /// The frame the carrying buffer's LINES were drawn at.
    ///
    /// The render draws one frame into the lines and the loop replays the rest over
    /// them. Both sets of bytes exist and both must resolve the same way, so the drawn
    /// one has to be identifiable: this is what the buffer's own cells owe until the
    /// first replay tick, and what they fall back to wherever the run cannot go.
    public var drawnIndex: Int

    public init(perFrame: [[Span]], drawnIndex: Int) {
        self.perFrame = perFrame
        self.drawnIndex = drawnIndex
    }

    /// The payload for a run of `width` cells at `(offsetX, row)`, sliced out of one
    /// list of ordinary regions per frame.
    ///
    /// For a producer that already has a function stating what a thing owes as regions —
    /// `BorderRenderer.opacityClaims` is the one this was written for — and needs the
    /// same answer per frame, for a run. Calling that function once per frame and
    /// slicing here means the claim and the bytes come from one colour per frame and
    /// cannot drift; deriving the spans by hand beside it is the drift.
    ///
    /// `nil` when no frame owes anything, so an opaque producer attaches nothing.
    public init?(
        slicing perFrameRegions: [[OpacityRegion]],
        row: Int, offsetX: Int, width: Int, drawnIndex: Int
    ) {
        let columns = offsetX..<(offsetX + width)
        let sliced = perFrameRegions.map { regions in
            regions.compactMap { region -> Span? in
                guard region.spans(row: row) else { return nil }
                let kept = (region.offsetX..<(region.offsetX + region.width)).clamped(to: columns)
                guard !kept.isEmpty else { return nil }
                return Span(
                    start: kept.lowerBound - offsetX, cells: kept.count,
                    ink: region.inkOpacity, field: region.fieldOpacity)
            }
        }
        guard sliced.contains(where: { !$0.isEmpty }) else { return nil }
        self.init(perFrame: sliced, drawnIndex: drawnIndex)
    }

    /// The spans for frame `index`, wrapped like ``AnimatedCellRun/frame(atIndex:)``.
    public func spans(atFrame index: Int) -> [Span] {
        guard !perFrame.isEmpty else { return [] }
        let wrapped = index % perFrame.count
        return perFrame[wrapped < 0 ? wrapped + perFrame.count : wrapped]
    }

    /// The spans the carrying buffer's lines were drawn with.
    public var drawnSpans: [Span] { spans(atFrame: drawnIndex) }

    /// Whether the frames actually disagree — the whole reason this exists.
    ///
    /// A payload whose every frame says the same thing is a static claim written the
    /// long way, and the producer should have stated a region instead. Asked by
    /// ``AnimatedCellRun/isAnimating``, so a run whose only motion is its alpha is not
    /// mistaken for a still picture and dropped by the clip and punch paths.
    public var varies: Bool {
        guard let first = perFrame.first else { return false }
        return perFrame.contains { $0 != first }
    }

    /// Whether any frame owes anything at all.
    public var isTranslucent: Bool {
        perFrame.contains { $0.contains(where: \.isTranslucent) }
    }

    /// This payload cut to `columns` of the run's own cells, rebased so column
    /// `columns.lowerBound` becomes 0.
    ///
    /// Called by ``AnimatedCellRun/clipped(toColumns:)`` in the same breath as the
    /// frames are cut, so a slice's spans describe the cells the slice actually kept.
    func sliced(toRunColumns columns: Range<Int>) -> Self {
        Self(
            perFrame: perFrame.map { spans in
                spans.compactMap { span in
                    let kept = (span.start..<(span.start + span.cells)).clamped(to: columns)
                    guard !kept.isEmpty else { return nil }
                    return Span(
                        start: kept.lowerBound - columns.lowerBound, cells: kept.count,
                        ink: span.ink, field: span.field)
                }
            },
            drawnIndex: drawnIndex)
    }

    /// The drawn frame's spans as ordinary regions, for a run sitting at
    /// `(offsetX, offsetY)` in its buffer.
    ///
    /// The degradation a dropped run leaves behind. A run is the one payload this
    /// codebase discards where a region is clipped and kept — a `ScrollView` drops a
    /// run wider than its viewport while clipping every region, and the punch and clamp
    /// paths drop a cut that stopped animating — and a producer using this type states
    /// no region of its own, so a dropped run would take the only statement about those
    /// cells with it and leave them at full strength.
    ///
    /// Appending these at the point of the drop degrades them instead to exactly what a
    /// static claim would have said: right at the drawn frame, frozen after. Only where
    /// the run is actually discarded — beside a surviving run these would fold a second
    /// time and fade it twice.
    public func drawnRegions(forRunAt offsetX: Int, offsetY: Int) -> [OpacityRegion] {
        // Built directly rather than through `OpacityRegion.claim`, which lives a module
        // above this one: `opacity` is 1 because this is a statement about PAINT and
        // never about how present the layer is, which is the same split `claim` makes.
        // A span owing nothing states nothing, for `claim`'s reason — every resolving
        // path is gated on `opacityRegions.isEmpty`, so an identity region costs a walk
        // to reach the answer it started with.
        drawnSpans.compactMap { span in
            guard span.isTranslucent, span.cells > 0 else { return nil }
            return OpacityRegion(
                offsetX: offsetX + span.start, offsetY: offsetY,
                width: span.cells, height: 1, opacity: 1,
                inkOpacity: span.ink, fieldOpacity: span.field)
        }
    }
}
