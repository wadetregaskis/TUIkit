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

    public init(
        offsetX: Int, offsetY: Int, width: Int, height: Int, opacity: Double,
        cycle: OpacityCycle? = nil
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.height = height
        self.opacity = min(max(opacity, 0), 1)
        self.cycle = cycle
    }

    /// This region moved by `(x, y)` — what a combining operation applies when
    /// it places the buffer somewhere.
    public func shifted(byX x: Int, y: Int) -> Self {
        var copy = self
        copy.offsetX += x
        copy.offsetY += y
        return copy
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
