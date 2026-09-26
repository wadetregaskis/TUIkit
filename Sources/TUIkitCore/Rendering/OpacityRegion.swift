//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityRegion.swift
//
//  A rectangle of a buffer that is drawn at less than full opacity, carried
//  alongside the lines until something knows what is behind it.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A rectangle of cells to be drawn at `opacity`, in its buffer's own
/// coordinates.
///
/// ## Why a region rather than a property of the buffer
///
/// A view with `.opacity(_:)` renders to a buffer, and that buffer is then
/// appended into a stack — `appendVertically` copies its LINES into a larger
/// buffer and nothing else. Anything the faded buffer knew about itself dies
/// there, and a stack sits between the faded view and its destination in very
/// nearly every real tree:
///
/// ```swift
/// ZStack {
///     Color.red
///     VStack { Text("x").opacity(0.5) }   // one stack, and the fade is lost
/// }
/// ```
///
/// So opacity travels the way every other claim about particular cells travels
/// here — as a rectangle that each combining operation shifts, exactly like
/// ``AnimatedCellRun`` and `HitTestRegion`. By the time the buffer reaches
/// something that knows what is underneath, the region still says which cells
/// it meant.
///
/// ## Why it is not resolved earlier
///
/// Because a colour cannot be faded toward a surface the view cannot see. The
/// render-time fade this replaces had to guess, and guessed the app
/// background — right over nothing, wrong over any sibling that painted. See
/// `Documentation/Opacity as composition.md`.
public struct OpacityRegion: Equatable, Sendable {
    /// The region's left edge, in its buffer's coordinates.
    public var offsetX: Int

    /// The region's top edge, in its buffer's coordinates.
    public var offsetY: Int

    /// How many cells wide.
    public var width: Int

    /// How many rows tall.
    public var height: Int

    /// How opaque, `0` through `1`. A region at `1` is the identity and should
    /// not be emitted at all.
    ///
    /// When ``cycle`` is present this is the phase the lines were DRAWN at —
    /// `cycle.phases[step]` — not some other value the animation passes
    /// through. The replay indexes the frames by tick and splices without
    /// consulting the view, so a picture drawn at any other value would be
    /// repainted on the very next tick.
    public var opacity: Double

    /// How opaque the INK in these cells is, beyond whatever ``opacity`` says
    /// about the layer as a whole. 1 when no colour asked for less.
    ///
    /// A translucent `Color` used as a FOREGROUND. Kept apart from ``opacity``
    /// because they are different claims, not different amounts of one: a layer
    /// at 0.3 is 30% *present*, so its glyph competes with whatever is behind it
    /// and the ½ rule decides; ink at 0.3 is faint text that is definitely
    /// drawn. The same number, two questions. Folding them would make
    /// `Text(…).foregroundStyle(.red.opacity(0.3))` vanish rather than fade.
    ///
    /// They compose by multiplication at the blend, so
    /// `.foregroundStyle(.red.opacity(0.5)).opacity(0.5)` is ink at 0.25 inside
    /// a layer contest at 0.5.
    public var inkOpacity: Double

    /// How opaque the FIELD painted in these cells is, beyond ``opacity``. 1
    /// when no colour asked for less.
    ///
    /// A translucent `Color` used as a background, or as a view.
    public var fieldOpacity: Double

    /// The whole of a repeating fade, when this region is one.
    ///
    /// A fade that never ends would otherwise cost a render pass for as long
    /// as the view is on screen. It need not: every phase is the same cells in
    /// different colours, so whatever resolves this region can resolve it once
    /// per phase and hand the run loop the lot as ``AnimatedCellRun``s.
    ///
    /// It has to travel with the region rather than be computed by the view,
    /// because the phases cannot be coloured until what is BEHIND the region is
    /// known — which is the same reason the region exists.
    public var cycle: OpacityCycle?

    /// Where this is a PAINTER's claim on the translucent field it put under content it
    /// did not draw — a `.background`, a list row's fill — which of that field's two
    /// places it is about; `nil` for every other claim: a layer's fade, a colour's own
    /// alpha, a painter's content's fades.
    ///
    /// A painter's field and its content share each cell, one above the other, and a
    /// line holds one field per cell. Folded as one claim, the content's fade scaled the
    /// field too — a label faded to 0.3 inside `.background(blue.opacity(0.5))` drew a
    /// dark patch of the fill the size of the label — and the fill's alpha scaled a field
    /// the content stated itself: a red badge inside the same fill came out half red.
    /// Told apart, the resolution composites the painter's field first and the content
    /// over it (`Opacity as composition.md` §105).
    public var fieldUnderContent: FieldUnderContent?

    public init(
        offsetX: Int, offsetY: Int, width: Int, height: Int, opacity: Double,
        inkOpacity: Double = 1, fieldOpacity: Double = 1,
        cycle: OpacityCycle? = nil, fieldUnderContent: FieldUnderContent? = nil
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.height = height
        // Clamped in this order for the reason `Color.opacity(_:)`'s is: it
        // folds a NaN to the low end, which is the only answer available.
        self.opacity = min(max(opacity, 0), 1)
        self.inkOpacity = min(max(inkOpacity, 0), 1)
        self.fieldOpacity = min(max(fieldOpacity, 0), 1)
        self.cycle = cycle
        self.fieldUnderContent = fieldUnderContent
    }

    /// Whether this region says anything at all — the test that decides whether
    /// it is worth resolving.
    ///
    /// All three channels, because any one of them under 1 is a claim. A region
    /// at `opacity: 1, inkOpacity: 0.5` is translucent INK at full layer
    /// strength, and dropping it would make a faded colour work inside a `ZStack`
    /// and render opaque on a plain page — the worst shape of bug, because the
    /// plain page is the common case.
    public var isTranslucent: Bool {
        opacity < 1 || inkOpacity < 1 || fieldOpacity < 1
    }

    /// This region moved by `(x, y)` — what a combining operation applies when
    /// it places the buffer somewhere.
    public func shifted(byX x: Int, y: Int) -> Self {
        var copy = self
        copy.offsetX += x
        copy.offsetY += y
        return copy
    }

    /// The part of this region inside `columns` × `rows`, or `nil` when none of
    /// it is.
    ///
    /// The trim a CLIPPING CONTAINER performs — a scroll window, a
    /// `clamped(toWidth:height:)` at a container edge, a list row. A region
    /// names cells that are IN the buffer carrying it, so when the container
    /// keeps only some of those cells the claim has to be cut to them: left
    /// whole it goes on naming columns and rows that now belong to a sibling,
    /// and the root reads the alpha of those cells off it.
    ///
    /// The mirror of `HitTestRegion.clipped(toColumns:rows:)`, and deliberately
    /// WITHOUT its `topClip` / `leftClip` accumulators: those exist so a mouse
    /// handler is handed points measured from where its region really BEGAN, and
    /// nothing localises a point against an opacity region — so there is nothing
    /// here for a trim to lose, and shifting and clipping commute freely.
    ///
    /// The ranges are in the carrying buffer's own coordinates and nothing is
    /// re-based, so a caller clipping to a box that does not start at the origin
    /// passes that box's ranges and shifts afterwards (see ``shifted(byX:y:)``).
    ///
    /// - Parameters:
    ///   - columns: The surviving column range.
    ///   - rows: The surviving row range.
    /// - Returns: The trimmed region, `self` when it was already inside, or
    ///   `nil` when nothing of it survives.
    public func clipped(toColumns columns: Range<Int>, rows: Range<Int>) -> Self? {
        let left = Swift.max(offsetX, columns.lowerBound)
        let right = Swift.min(offsetX + width, columns.upperBound)
        let top = Swift.max(offsetY, rows.lowerBound)
        let bottom = Swift.min(offsetY + height, rows.upperBound)
        guard right > left, bottom > top else { return nil }
        guard left != offsetX || top != offsetY || right != offsetX + width
            || bottom != offsetY + height
        else { return self }
        // A copy rather than a fresh value: `opacity` and `cycle` are the whole
        // point of the region, and the initializer would re-clamp the first.
        var trimmed = self
        trimmed.offsetX = left
        trimmed.offsetY = top
        trimmed.width = right - left
        trimmed.height = bottom - top
        return trimmed
    }

    /// Whether `row` falls inside this region, at any column.
    ///
    /// The resolution walks rows and asks this first: a buffer of forty rows
    /// with one faded row in it should cost one row's work, not forty.
    public func spans(row: Int) -> Bool {
        row >= offsetY && row < offsetY + height
    }

    /// Whether `(column, row)` is inside this region.
    public func contains(column: Int, row: Int) -> Bool {
        column >= offsetX && column < offsetX + width
            && row >= offsetY && row < offsetY + height
    }
}

/// Which place of a painter's translucent field a claim is about
/// (``OpacityRegion/fieldUnderContent``).
public enum FieldUnderContent: Hashable, Sendable {
    /// The field the cell shows: the content leaves the cell's field to the painter,
    /// so the line spells the painter's colour there, and the claim's alpha is that
    /// field's and nothing else's.
    case shown

    /// Beneath a field the content states itself, which the line spells in the
    /// painter's place: the painter's colour, as the background escape it painted,
    /// and the claim's alpha is what it lets through under the content's field.
    case beneath(String)
}

/// A repeating opacity animation, laid out as the values it passes through.
///
/// Indexed the way ``AnimatedCellRun/frames`` is — by `tick % count` — so the
/// run built from it replays in step with every other run on the same clock.
public struct OpacityCycle: Equatable, Sendable {
    /// The opacity at each point of the cycle, in order.
    public var phases: [Double]

    /// The clock that advances them.
    public var clock: AnimationClock

    public init(phases: [Double], clock: AnimationClock) {
        self.phases = phases
        self.clock = clock
    }

    /// This cycle with every phase scaled — what nesting one fade inside
    /// another does. See ``OpacityRegion``.
    public func scaled(by factor: Double) -> Self {
        Self(phases: phases.map { $0 * factor }, clock: clock)
    }
}

extension OpacityRegion {
    /// This region with a rectangle removed — the 0 to 4 regions covering what
    /// remains, each keeping this region's alpha and cycle.
    ///
    /// A region names cells of the buffer it rides on. When a composite
    /// REPLACES some of those cells, the claim on them must go with them —
    /// left in place it would fade whatever the new content put there, which
    /// was never under the fade. Subtraction rather than any bookkeeping of
    /// layers: the remainder is still just rectangles over cells that ARE the
    /// faded view's.
    public func subtracting(columns: Range<Int>, rows: Range<Int>) -> [OpacityRegion] {
        let myRows = offsetY..<(offsetY + height)
        let myColumns = offsetX..<(offsetX + width)
        let hitRowStart = Swift.max(myRows.lowerBound, rows.lowerBound)
        let hitRowEnd = Swift.min(myRows.upperBound, rows.upperBound)
        let hitColumnStart = Swift.max(myColumns.lowerBound, columns.lowerBound)
        let hitColumnEnd = Swift.min(myColumns.upperBound, columns.upperBound)
        guard hitRowStart < hitRowEnd, hitColumnStart < hitColumnEnd else { return [self] }
        let hitRows = hitRowStart..<hitRowEnd
        let hitColumns = hitColumnStart..<hitColumnEnd

        var pieces: [OpacityRegion] = []
        func keep(x: Int, y: Int, width: Int, height: Int) {
            guard width > 0, height > 0 else { return }
            var piece = self
            piece.offsetX = x
            piece.offsetY = y
            piece.width = width
            piece.height = height
            pieces.append(piece)
        }
        // Above and below the hole, full width; beside it, only its rows.
        keep(
            x: myColumns.lowerBound, y: myRows.lowerBound,
            width: myColumns.count, height: hitRows.lowerBound - myRows.lowerBound)
        keep(
            x: myColumns.lowerBound, y: hitRows.upperBound,
            width: myColumns.count, height: myRows.upperBound - hitRows.upperBound)
        keep(
            x: myColumns.lowerBound, y: hitRows.lowerBound,
            width: hitColumns.lowerBound - myColumns.lowerBound, height: hitRows.count)
        keep(
            x: hitColumns.upperBound, y: hitRows.lowerBound,
            width: myColumns.upperBound - hitColumns.upperBound, height: hitRows.count)
        return pieces
    }
}
