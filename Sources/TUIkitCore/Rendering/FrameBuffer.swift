//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A 2D text buffer that views render into before flushing to the terminal.
///
/// `FrameBuffer` enables a two-pass rendering approach:
/// 1. Each view renders into its own buffer (measuring its size)
/// 2. Layout containers combine child buffers (horizontally, vertically, or layered)
/// 3. The final root buffer is flushed to the terminal
///
/// Each line in the buffer is a string that may contain ANSI escape codes.
///
/// - Important: This is framework infrastructure used as the rendering primitive in
///   ``ViewModifier/modify(buffer:context:)``. Most developers don't need to interact
///   with this type directly.
public struct FrameBuffer: Sendable, Equatable {
    /// The lines of rendered content (may contain ANSI escape codes).
    ///
    /// Assigning `lines` recomputes the cached ``width`` and
    /// ``linesAreUniformWidth`` and invalidates ``lineWidths`` (it cannot
    /// cheaply produce the per-line widths, so it drops them to `nil` rather
    /// than leave a stale array).
    public var lines: [String] {
        // Borrowed rather than returned: `lines` is read constantly (every
        // `height`, every combine, every consumer walking the rows) and a
        // plain `get` would hand back a +1 retained array each time. Measured
        // at ~1% on the `deep` Stress scenario, which is all reads.
        _read { yield storage }
        set {
            storage = newValue
            recomputeWidth()
        }
    }

    /// Backing store for ``lines``.
    ///
    /// The recompute belongs on the *public* door, not on the storage: it is
    /// a whole-buffer measure, so a mutator writing rows one at a time through
    /// an observer pays it once per row. ``composite(with:at:)`` does exactly
    /// that, and already knows the resulting geometry exactly — an Instruments
    /// trace of a custom `Layout` placing 160 children spent 29.4% of the run
    /// re-measuring the canvas per child only to have the answer overwritten.
    /// Mutators inside this file write `storage` and maintain ``width``,
    /// ``linesAreUniformWidth`` and ``lineWidths`` themselves; everyone else
    /// goes through ``lines`` and cannot tell the difference.
    private var storage: [String]

    /// The width of the buffer (the length of the longest line in visible characters).
    ///
    /// This is a stored property, recomputed automatically whenever
    /// ``lines`` is mutated. Accessing `width` is O(1) — the per-line
    /// `String.strippedLength` scan runs only once per mutation, not per
    /// access. It was an ANSI-stripping regex when this cache was introduced
    /// (`176cfc0d`, 2026-02-02); since `74fc7ea8` (2026-08-12) it is a
    /// byte-at-a-time CSI walk with an all-ASCII fast path, and no regex
    /// survives anywhere on the width path.
    public private(set) var width: Int

    /// Whether every line in ``lines`` has the same visible width (``width``).
    ///
    /// A performance hint with a deliberately conservative meaning: `true` means
    /// "definitely uniform", `false` means "unknown — measure per line". A parent
    /// that pads or borders these lines to a target width can, when this is
    /// `true`, skip re-measuring each line's visible width (it already knows each
    /// is exactly ``width``). That per-line `strippedLength` is the dominant cost
    /// in deeply-nested bordered layouts, where the same lines are otherwise
    /// re-measured at every enclosing level — O(depth²).
    ///
    /// Empty and single-line buffers are trivially uniform. Combining operations
    /// propagate it via cheap width comparisons, never by re-measuring, so it
    /// never reintroduces the cost it exists to remove. It is intentionally
    /// excluded from `==` (see the custom `Equatable` conformance): two buffers
    /// with identical lines are interchangeable, and `true` is only ever set when
    /// the lines genuinely are uniform.
    public private(set) var linesAreUniformWidth: Bool

    /// Per-line visible widths, or `nil` when unknown ("measure on demand").
    ///
    /// A performance hint that complements ``linesAreUniformWidth`` for *ragged*
    /// content. When a producer already knows each line's visible width — most
    /// importantly ``Text``, which gets the widths for free while word-wrapping —
    /// it carries them here so a consumer that pads ragged lines to a target width
    /// (e.g. a `VStack` aligning a column of wrapped text) skips the per-line
    /// `String.strippedLength` re-measure. `nil` means "unknown":
    /// every consumer falls back to measuring per line, exactly as before this
    /// field existed.
    ///
    /// It is maintained with the same discipline as ``linesAreUniformWidth``:
    /// combining/mutating operations either produce the correct array cheaply
    /// (by concatenation, never by re-measuring) or set it to `nil` — a stale
    /// array is never left behind. Like ``linesAreUniformWidth`` it is excluded
    /// from `==` (a pure function of ``lines``, so it can never distinguish two
    /// buffers with identical lines).
    ///
    /// - Invariant: when non-`nil`, `lineWidths == lines.map(\.strippedLength)`
    ///   and `lineWidths!.count == lines.count`. Checked in debug builds wherever
    ///   the field is set (see `assertLineWidthsInvariant(_:file:line:)`).
    public private(set) var lineWidths: [Int]?

    /// The height of the buffer (number of lines).
    public var height: Int {
        lines.count
    }

    /// Whether the buffer is empty.
    ///
    /// - Note: Reflects only the in-flow ``lines``. A buffer with no visible
    ///   lines may still carry ``overlays``; combining operations check for
    ///   that case explicitly so overlay layers are never silently dropped.
    public var isEmpty: Bool {
        lines.isEmpty || lines.allSatisfy { $0.isEmpty }
    }

    /// Whether the buffer is *visually* empty: every line is blank or
    /// whitespace-only once ANSI codes are stripped.
    ///
    /// Stronger than ``isEmpty``, which only treats zero-length lines as
    /// empty. A line of spaces (or ANSI-styled blanks, e.g. a `Text("")` that
    /// padded itself) is blank here but not "empty". Containers use this to
    /// decide whether optional chrome — a header, a label, a footer — actually
    /// draws anything, so an empty title doesn't reserve a blank row.
    ///
    /// - Note: Considers only the in-flow ``lines``; a buffer carrying only
    ///   ``overlays`` is still reported blank.
    public var isBlank: Bool {
        lines.allSatisfy { $0.stripped.allSatisfy(\.isWhitespace) }
    }

    /// Free-floating layers composited above the content at render time.
    ///
    /// Most buffers carry none. A view emits a layer to draw outside its own
    /// bounds — for example a `Picker` drop-down — without disturbing sibling
    /// layout. Each layer's offset is relative to this buffer's top-left and
    /// is shifted by every combining operation, so it becomes absolute by the
    /// time the buffer reaches the root. See ``OverlayLayer``.
    public var overlays: [OverlayLayer] = []

    /// Mouse hit-test rectangles that ride alongside this buffer's
    /// content as parents combine it.
    ///
    /// Every combining operation shifts these regions by the same
    /// amount it shifts the buffer's lines, so by the time the buffer
    /// reaches the root each region's offset is in absolute screen
    /// coordinates. The `MouseEventDispatcher` collects them at root
    /// composite time and uses them for hit-testing.
    public var hitTestRegions: [HitTestRegion] = []

    /// Short runs of cells that animate on their own — a breathing focus ring,
    /// a blinking cursor — carried and shifted exactly like ``hitTestRegions``,
    /// because a run *is* a claim about particular cells. See ``AnimatedCellRun``.
    public var animatedCells: [AnimatedCellRun] = []

    /// Rectangles of this buffer that are drawn at less than full opacity,
    /// carried and shifted exactly like ``hitTestRegions`` and ``animatedCells``
    /// — because opacity, like a run, is a claim about particular cells.
    ///
    /// Empty for almost every buffer, which is the identity and costs nothing.
    ///
    /// A view with `.opacity(_:)` emits one of these rather than fading its own
    /// colours, because **a colour cannot be faded toward a surface the view
    /// cannot see**. The fade is deferred to whatever finally draws the buffer
    /// onto something — a `ZStack`, an overlay, or the root — where the
    /// destination is known. See ``OpacityRegion`` and
    /// `Documentation/Opacity as composition.md`.
    public var opacityRegions: [OpacityRegion] = []

    /// Creates an empty buffer.
    public init() {
        self.storage = []
        self.width = 0
        self.linesAreUniformWidth = true  // vacuously uniform
        self.lineWidths = nil  // no lines → nothing to carry (uniform covers it)
    }

    /// Creates a buffer from an array of lines.
    ///
    /// - Parameter lines: The text lines.
    public init(lines: [String]) {
        self.storage = lines
        let measured = Self.measure(lines)
        self.width = measured.width
        self.linesAreUniformWidth = measured.uniform
        // The single-pass `measure` tracks only the min/max width, not the full
        // per-line array; producing one here would re-walk every line, so leave
        // the per-line widths unknown (measure on demand). A producer that has
        // them cheaply uses `init(lines:width:uniformWidth:lineWidths:)`.
        self.lineWidths = nil
    }

    /// Initializer that accepts pre-computed width.
    ///
    /// Use this when the width is already known to avoid redundant computation.
    ///
    /// - Parameters:
    ///   - lines: The buffer's content, one string per terminal row, ANSI included.
    ///   - width: The visible width in cells, which the caller is asserting
    ///     rather than the buffer measuring. It is what every consumer lays out
    ///     against, so a wrong value misplaces content as surely as wrong
    ///     lines would; `uniformWidth` and `lineWidths` are claims ABOUT it.
    ///   - uniformWidth: Pass `true` only when the caller knows every line in
    ///     `lines` is exactly `width` visible columns (e.g. it just padded them
    ///     to that width). Defaults to `false` — "unknown", the safe value that
    ///     makes any consumer fall back to measuring per line.
    ///   - lineWidths: The per-line visible widths, when the caller already knows
    ///     them (e.g. ``Text`` from word-wrapping). Defaults to `nil` —
    ///     "unknown", matching `uniformWidth`'s default. When supplied it MUST
    ///     equal `lines.map(\.strippedLength)` (asserted in debug builds); pass
    ///     `nil` rather than a guess.
    public init(
        lines: [String],
        width: Int,
        uniformWidth: Bool = false,
        lineWidths: [Int]? = nil
    ) {
        self.storage = lines
        self.width = width
        self.linesAreUniformWidth = uniformWidth
        self.lineWidths = lineWidths
        Self.assertLineWidthsInvariant(self)
    }

    /// Creates a buffer containing a single line.
    ///
    /// - Parameter text: The text content.
    public init(text: String) {
        self.storage = [text]
        self.width = text.strippedLength
        self.linesAreUniformWidth = true  // a single line is trivially uniform
        // Trivially uniform at `width`; `linesAreUniformWidth` already lets
        // consumers skip the per-line measure, so don't allocate a 1-element
        // array redundantly.
        self.lineWidths = nil
    }

    /// Creates a spacer buffer with the specified height.
    ///
    /// The buffer contains lines with a single space character to ensure
    /// it is not considered "empty" by layout algorithms. This is important
    /// for Spacer views which need to occupy vertical space even without
    /// visible content.
    ///
    /// - Parameter height: The number of lines.
    public init(emptyWithHeight height: Int) {
        // Use a single space instead of empty string so the buffer
        // is not considered "empty" by appendVertically
        self.storage = Array(repeating: " ", count: height)
        self.width = 1
        self.linesAreUniformWidth = true  // all lines are a single space
        self.lineWidths = nil  // uniform at width 1; no array needed
    }

    /// Creates a buffer of empty spaces with the specified width and height.
    ///
    /// Used by horizontal stacks for Spacer views which need to occupy
    /// horizontal space across multiple rows.
    ///
    /// - Parameters:
    ///   - width: The width in characters.
    ///   - height: The number of lines.
    public init(emptyWithWidth width: Int, height: Int) {
        self.storage = Array(repeating: String(repeating: " ", count: width), count: height)
        self.width = width
        self.linesAreUniformWidth = true  // every line is `width` spaces
        self.lineWidths = nil  // uniform at `width`; no array needed
    }

    /// Creates a footprint: `height` rows that paint no cell at all, declaring
    /// itself `width` cells wide.
    ///
    /// NOT ``init(emptyWithWidth:height:)``, whose rows are spaces. Those
    /// PAINT: compositing is opaque per cell, so a blank-filled buffer erases
    /// whatever is beneath it — the opposite of what a view wants when it has
    /// floated its drawing somewhere else (``OverlayLayer``) and is leaving
    /// behind the space the measure pass promised.
    ///
    /// Both halves are load-bearing, and each was a shipped bug:
    ///
    /// - the rows have to EXIST. A buffer with no lines is not "a blank view"
    ///   to a stack, it is "no child": `appendVertically` drops it, spacing and
    ///   all, so every sibling after it moves up and the floated drawing lands
    ///   on whatever took its place.
    /// - the WIDTH has to be declared, even though no cell carries it, because
    ///   a container that aligns its children asks each buffer how wide it is —
    ///   a zero-width answer centres an 8-cell label 4 cells off centre.
    ///
    /// - Parameters:
    ///   - width: The width to declare, in cells.
    ///   - height: The number of rows to reserve.
    public init(footprintWidth width: Int, height: Int) {
        self.storage = Array(repeating: "", count: max(0, height))
        self.width = max(0, width)
        self.linesAreUniformWidth = false  // no line is `width` cells; none is drawn
        self.lineWidths = nil
    }

    // MARK: - Combining Arrays

    /// Creates a vertically stacked buffer from an array of buffers.
    ///
    /// TupleViews use this to combine their children vertically by default
    /// (the parent stack then decides the actual layout direction).
    ///
    /// - Parameter buffers: The buffers to stack vertically.
    public init(verticallyStacking buffers: [Self]) {
        self.init()
        for buffer in buffers {
            appendVertically(buffer)
        }
    }
}

// MARK: - Equatable

extension FrameBuffer {
    /// Equality compares rendered content only: ``lines``, ``overlays``, and
    /// ``hitTestRegions``.
    ///
    /// ``width`` is a pure function of ``lines`` so it adds nothing, and both
    /// ``linesAreUniformWidth`` and ``lineWidths`` are conservative performance
    /// hints excluded by design — two buffers with identical lines are
    /// interchangeable, and each hint is only ever populated when it genuinely
    /// describes those lines. Including them would spuriously distinguish
    /// otherwise-equal buffers and could defeat the render / measure memo that
    /// keys on buffer equality.
    public static func == (lhs: FrameBuffer, rhs: FrameBuffer) -> Bool {
        lhs.lines == rhs.lines
            && lhs.overlays == rhs.overlays
            && lhs.hitTestRegions == rhs.hitTestRegions
            && lhs.animatedCells == rhs.animatedCells
            // Opacity is CONTENT, not a hint: the render and measure memos key
            // on this equality, so leaving it out would serve an unfaded buffer
            // where a faded one was wanted — and the two are identical in every
            // other respect, which is exactly when a memo hits.
            && lhs.opacityRegions == rhs.opacityRegions
    }
}

// MARK: - Public API

extension FrameBuffer {
    /// Stacks another buffer below this one with optional spacing.
    ///
    /// A buffer with **no lines** contributes no height *and* no spacing slot
    /// — the buffers join with the spacing they would have had if `other` were
    /// not in the list at all. This matches SwiftUI's `VStack` behaviour:
    /// `if false { ChildView() }` evaluates to `Optional<ChildView>.none`, and
    /// an `Optional.none` child does not consume a spacing slot from its parent
    /// stack. The same holds for `EmptyView()` and any other zero-height child.
    /// If callers want to reserve a row whether or not the conditional fires,
    /// they must opt in with a sized placeholder such as
    /// `Color.clear`-with-frame or `Spacer.init()`-with-frame — using
    /// `EmptyView()` in an `else` branch will NOT reserve the row, because
    /// `EmptyView()` is also empty.
    ///
    /// Height is what decides that, not paint: a buffer of N *empty* lines has
    /// a height of N and takes N rows, though it paints nothing in them. That
    /// is the shape a floated view leaves behind (``OffsetView``,
    /// ``PositionView``) — the footprint its measure promised, with the drawing
    /// carried off in an overlay layer. Reading "paints nothing" as "is not
    /// here" collapsed those rows and pulled the following sibling up into
    /// them.
    ///
    /// - Parameters:
    ///   - other: The buffer to append below.
    ///   - spacing: Number of empty lines between the two buffers.
    ///     Ignored when `other` has no lines, by design (see above).
    public mutating func appendVertically(_ other: Self, spacing: Int = 0) {
        let priorHeight = lines.count

        guard !other.lines.isEmpty else {
            // `other` contributes no visible lines and no spacing
            // slot (see doc comment above). It may still carry
            // overlay layers and hit-test regions that must be
            // preserved — those are anchored to its (zero-height)
            // position, not to any inter-child spacing.
            if !other.overlays.isEmpty {
                overlays.append(contentsOf: other.shiftedOverlays(byX: 0, y: priorHeight))
            }
            if !other.hitTestRegions.isEmpty {
                hitTestRegions.append(
                    contentsOf: other.shiftedHitTestRegions(byX: 0, y: priorHeight))
            }
            if !other.animatedCells.isEmpty {
                animatedCells.append(
                    contentsOf: other.shiftedAnimatedCells(byX: 0, y: priorHeight))
            }
            if !other.opacityRegions.isEmpty {
                opacityRegions.append(
                    contentsOf: other.shiftedOpacityRegions(byX: 0, y: priorHeight))
            }
            return
        }

        // `other`'s content lands below the current lines (plus spacing).
        let spacingApplied = priorHeight > 0 ? spacing : 0
        let verticalShift = priorHeight + spacingApplied

        // Pre-compute the new width (avoids redundant computation in didSet)
        let newWidth = max(width, other.width)
        let selfWasEmpty = storage.isEmpty

        // Propagate uniform-width cheaply (no re-measure). The stack is uniform
        // only when both sides are uniform AT THE SAME width and no empty spacer
        // line (visible width 0) was inserted between them. When self was empty,
        // the result is simply `other`. Anything else is "unknown" (false).
        //
        // Computed BEFORE the append below, which overwrites the geometry this
        // reads.
        let resultUniform: Bool
        if selfWasEmpty {
            resultUniform = other.linesAreUniformWidth
        } else {
            resultUniform =
                linesAreUniformWidth && other.linesAreUniformWidth
                && width == other.width && spacing == 0
        }

        // Carry per-line widths cheaply (extension, no re-measure) — the exact
        // parallel of `storage`'s growth below. Possible only when both sides
        // already know their widths; otherwise the result is "unknown" (nil).
        // When self was empty the result is simply `other`'s widths; the
        // inserted spacing blank lines ("") each have visible width 0.
        // A uniform side carries no array ("uniform covers it"), but it KNOWS
        // every width — so it is spelled out here rather than dropped, or a
        // stack of uniform rows of two different widths would forget all of
        // them and every consumer downstream (a scroll window, a scrollbar,
        // the writer's pad) would scan the lines to learn them again.
        if selfWasEmpty {
            lineWidths = other.lineWidths
        } else if resultUniform {
            lineWidths = nil
        } else if let mine = lineWidths ?? (linesAreUniformWidth ? Array(repeating: width, count: storage.count) : nil),
            let theirs = other.lineWidths
                ?? (other.linesAreUniformWidth ? Array(repeating: other.width, count: other.lines.count) : nil)
        {
            var merged = mine
            merged.reserveCapacity(mine.count + spacing + theirs.count)
            if spacing > 0 {
                merged.append(contentsOf: repeatElement(0, count: spacing))
            }
            merged.append(contentsOf: theirs)
            lineWidths = merged
        } else {
            lineWidths = nil
        }

        // Grow the accumulator IN PLACE rather than building a fresh array per
        // child. A stack appends its children one at a time into a single
        // buffer, so copying the accumulated rows on each append made the
        // combine O(n²) in the child count — and, because the rows are
        // `String`s, it retained/released every accumulated row each time.
        // Measured on a plain accumulation of single-line children: 500 → 8000
        // rows cost 0.53 → 103 ms, ~4× per doubling. Appending in place is
        // amortised O(rows added), which is what the loop as a whole needs to
        // be linear.
        //
        // `storage` (not `lines`) deliberately: the public setter recomputes the
        // whole-buffer width per write, and the geometry is already known
        // exactly here — the same reasoning `composite(with:at:)` documents.
        if !selfWasEmpty && spacing > 0 {
            storage.append(contentsOf: repeatElement("", count: spacing))
        }
        storage.append(contentsOf: other.lines)
        width = newWidth
        linesAreUniformWidth = resultUniform
        Self.assertLineWidthsInvariant(self)

        // Same story for the three carried side-channels: `a + b` allocates and
        // copies both sides every child, so accumulating N children's overlays
        // or hit regions was quadratic in their total count.
        if !other.overlays.isEmpty {
            overlays.append(contentsOf: other.shiftedOverlays(byX: 0, y: verticalShift))
        }
        if !other.hitTestRegions.isEmpty {
            hitTestRegions.append(
                contentsOf: other.shiftedHitTestRegions(byX: 0, y: verticalShift))
        }
        if !other.animatedCells.isEmpty {
            animatedCells.append(
                contentsOf: other.shiftedAnimatedCells(byX: 0, y: verticalShift))
        }
        if !other.opacityRegions.isEmpty {
            opacityRegions.append(
                contentsOf: other.shiftedOpacityRegions(byX: 0, y: verticalShift))
        }
    }

    /// Places another buffer to the right of this one with optional spacing.
    ///
    /// An `other` with no columns contributes no width *and* no spacing slot
    /// — the buffers join with the spacing they would have had if
    /// `other` were not in the list at all. This matches SwiftUI's
    /// `HStack` behaviour (and `appendVertically`'s mirror of the
    /// same rule): an `Optional<ChildView>.none`, an `EmptyView`,
    /// or any other zero-width child is treated as if it were not
    /// in the children list at all. To reserve a column whether or
    /// not a conditional fires, opt in with a sized placeholder
    /// such as `Color.clear`-with-frame or `Spacer.init()`-
    /// with-frame — `EmptyView()` in an `else` branch will NOT
    /// reserve the column, because `EmptyView()` is also empty.
    ///
    /// - Parameters:
    ///   - other: The buffer to append to the right.
    ///   - spacing: Number of space characters between the two buffers.
    ///     Ignored when `other` has no columns, and when this buffer is still
    ///     empty — a gap is charged only between two occupied column ranges.
    public mutating func appendHorizontally(_ other: Self, spacing: Int = 0) {
        let priorWidth = width

        // Not `!other.isEmpty` alone. `isEmpty` asks whether the LINE STRINGS
        // carry anything, and a buffer that declares columns while painting
        // none of them answers yes to that — which is exactly what `.offset`
        // and `.position` hand a stack (`OffsetView`: empty lines reserve the
        // rows, the declared width reserves the columns, and the drawing floats
        // as a layer so nothing is painted over what lies beneath). Sending one
        // of those down the contributes-nothing path dropped its columns, and
        // every later sibling closed up into the space it had been promised:
        // `HStack { Text("AB").offset(y: 1); Text("CD") }` drew "CD" at column
        // 0. `appendVertically`'s mirror asks `other.lines.isEmpty`, which is
        // why the row was held and only the columns were lost.
        guard !other.isEmpty || other.width > 0 else {
            // `other` contributes no visible columns and no spacing
            // slot (see doc comment above). It may still carry
            // overlay layers and hit-test regions that must be
            // preserved — those are anchored to its (zero-width)
            // position, not to any inter-child spacing.
            if !other.overlays.isEmpty {
                overlays.append(contentsOf: other.shiftedOverlays(byX: priorWidth, y: 0))
            }
            if !other.hitTestRegions.isEmpty {
                hitTestRegions.append(
                    contentsOf: other.shiftedHitTestRegions(byX: priorWidth, y: 0))
            }
            if !other.animatedCells.isEmpty {
                animatedCells.append(
                    contentsOf: other.shiftedAnimatedCells(byX: priorWidth, y: 0))
            }
            if !other.opacityRegions.isEmpty {
                opacityRegions.append(
                    contentsOf: other.shiftedOpacityRegions(byX: priorWidth, y: 0))
            }
            return
        }

        let maxHeight = max(height, other.height)
        let myWidth = priorWidth

        // A gap belongs BETWEEN two occupied column ranges. With no columns yet
        // — an HStack whose leading child rendered empty — `other` is the first
        // thing in the row and must start at column 0, not be indented by a slot
        // it never earned. The mirror of `appendVertically`'s `priorHeight > 0`:
        // rows there, columns here.
        //
        // The predicate is `width`, not `isEmpty`, deliberately: `isEmpty` asks
        // whether the LINE STRINGS carry content, which is the right question
        // for `other` (a buffer of non-empty zero-width lines still contributes
        // HEIGHT below) and the wrong one here, where the question is whether
        // any columns are occupied. A styled-but-empty `Text` would otherwise
        // still earn a phantom indent.
        // …and BETWEEN two of them: `other` declaring no columns earns no gap
        // either, or a row's width would depend on whether any SGR bytes were
        // emitted. That is not hypothetical: a `Text("")` allocated 0 columns
        // renders one line of pure escape bytes (its foreground always resolves,
        // so `ANSIRenderer.render` wraps even an empty string), and `clamped`
        // returns it untouched because its width is ALREADY 0 — so `isEmpty` is
        // false and it reached here as a contributor. `HStack(spacing: 2) {
        // Text("A"); Text(""); Text("B") }` drew 6 cells in colour and 4 with
        // `--no-color`, and no reported width can be right in both.
        //
        // Only the GAP is withheld. `other` still merges its rows: the
        // `!other.isEmpty` half of the guard above exists for the footprint an
        // `.offset`/`.position` child leaves behind, and that one declares
        // columns (`other.width > 0`), so it is untouched here.
        let spacingApplied = priorWidth > 0 && other.width > 0 ? spacing : 0

        // Pre-compute the new width
        let newWidth = myWidth + spacingApplied + other.width

        var result: [String] = []
        result.reserveCapacity(maxHeight)

        for row in 0..<maxHeight {
            let left = row < lines.count ? lines[row] : ""
            let right = row < other.lines.count ? other.lines[row] : ""

            // Build each combined row in place: the left line padded to `myWidth`,
            // then `spacing` spaces, then the right line. This is byte-identical to
            // `left.padToVisibleWidth(myWidth) + spacer + right` but allocates the
            // row once (capacity reserved) and appends the padding/gap as borrowed
            // spaces — no per-row `String(repeating:)` spacer and no `+`-chain
            // intermediates. The left pad replicates `padToVisibleWidth`: append
            // `myWidth - leftWidth` trailing spaces only when the line is narrower.
            // Reuse a known visible width instead of re-measuring per row: a
            // uniform buffer's lines are each exactly `myWidth`, and a ragged
            // buffer that carries `lineWidths` already knows each row's width.
            // Only an unmeasured ragged buffer falls back to `strippedLength`
            // (the dominant cost this avoids). Rows past this buffer's height
            // are zero-wide.
            let leftWidth: Int
            if row >= lines.count {
                leftWidth = 0
            } else if linesAreUniformWidth {
                leftWidth = myWidth
            } else if let knownWidths = lineWidths {
                leftWidth = knownWidths[row]
            } else {
                leftWidth = left.strippedLength
            }
            let leftPad = max(0, myWidth - leftWidth)
            var combined = ""
            combined.reserveCapacity(
                left.utf8.count + leftPad + spacingApplied + right.utf8.count)
            combined += left
            if leftPad > 0 { combined += asciiSpaces(leftPad) }
            if spacingApplied > 0 { combined += asciiSpaces(spacingApplied) }
            combined += right
            result.append(combined)
        }

        // Supply the uniform-width hint the
        // bare `FrameBuffer(lines:width:)` used to discard (it defaults the flag
        // to false), so downstream consumers can skip their per-line padding walk
        // — the same hint discipline `appendVertically` follows. Each combined
        // row's left half is exactly `myWidth` when this buffer is uniform (its
        // lines are each `myWidth`, and the rows past its height pad up to
        // `myWidth`); its right half is uniformly `other.width` only when `other`
        // is uniform AND no row falls past `other.height` (a short-right row would
        // be zero-wide). So the result is uniform exactly when both sides are
        // uniform and `other` is at least as tall — anything less certain stays
        // the safe `false` ("unknown", byte-identical: the consumer re-measures).
        let resultUniform =
            linesAreUniformWidth && other.linesAreUniformWidth && height <= other.height
        storage = result
        width = newWidth
        linesAreUniformWidth = resultUniform
        lineWidths = nil

        // `other`'s content lands to the right, past this buffer + spacing.
        // Appended in place rather than via `a + b`, which allocates and copies
        // both sides on every child — quadratic in the accumulated count for a
        // stack of many interactive children. Mirrors `appendVertically`.
        if !other.overlays.isEmpty {
            overlays.append(
                contentsOf: other.shiftedOverlays(byX: myWidth + spacingApplied, y: 0))
        }
        if !other.hitTestRegions.isEmpty {
            hitTestRegions.append(
                contentsOf: other.shiftedHitTestRegions(byX: myWidth + spacingApplied, y: 0))
        }
        if !other.animatedCells.isEmpty {
            animatedCells.append(
                contentsOf: other.shiftedAnimatedCells(byX: myWidth + spacingApplied, y: 0))
        }
        if !other.opacityRegions.isEmpty {
            opacityRegions.append(
                contentsOf: other.shiftedOpacityRegions(byX: myWidth + spacingApplied, y: 0))
        }
    }

    /// This buffer with `background` in force on every cell that names none of
    /// its own — the buffer-level twin of `String.paintedOver(background:)`.
    ///
    /// What makes a floating layer opaque. A cell that already states its own
    /// background is untouched, so a dialog that paints itself comes back
    /// byte-identical and only the blanks a surface never got round to
    /// colouring are filled.
    ///
    /// - Parameter background: A background escape
    ///   (`SGRState.renderedBackground`), or `""` to leave the buffer alone.
    package func paintedOver(background: String) -> Self {
        guard !background.isEmpty else { return self }
        // Through `replacingLines`, and with the geometry handed back rather
        // than recomputed: painting inserts ESCAPES and no visible cells, so
        // every width this buffer already knows is still true. Letting
        // `FrameBuffer(lines:)` re-measure would walk every line of every
        // floating layer, every frame, to arrive at the numbers above.
        return replacingLines(
            storage.map { $0.paintedOver(background: background) },
            width: width, uniformWidth: linesAreUniformWidth, lineWidths: lineWidths)
    }

    /// Creates a new buffer with another buffer composited on top at the specified position.
    ///
    /// Compositing replaces the base cell under every cell of the overlay,
    /// blanks included — a buffer that should not erase what it covers must be
    /// trimmed before it gets here (see ``trimmingTrailingBlankCells()``).
    /// Only a zero-length overlay line is skipped.
    ///
    /// The **field** is the exception, and it is not an exception to the rule
    /// so much as a second statement about the same cell. A glyph and the
    /// colour behind it are two things, and an overlay cell that names no
    /// background of its own has said nothing about the field it lands on — so
    /// it keeps the one that is there. That is what makes
    /// `ZStack { Color.red; Text("hi") }` draw the letters ON the red instead
    /// of punching a hole in it, and it costs nothing where the base has no
    /// background, which is the ordinary case. An overlay that names its own
    /// background still wins: its escapes are the later statement.
    ///
    /// - Parameters:
    ///   - overlay: The buffer to composite on top.
    ///   - position: The (x, y) offset where the overlay should be placed.
    /// - Returns: A new buffer with the overlay composited.
    public func composited(with overlay: Self, at position: (x: Int, y: Int)) -> Self {
        guard !overlay.isEmpty else {
            // Nothing visible to draw, but the overlay may still carry its
            // own nested layers / hit-test regions that need to be
            // lifted into the result.
            // All FOUR payloads, as the in-place twin's guard names them: a
            // faded subtree clamped to no rows is exactly a line-empty overlay
            // whose only payload is its opacity region, and this returned
            // `self` for it while `composite(with:at:)` lifted the region.
            guard !overlay.overlays.isEmpty || !overlay.hitTestRegions.isEmpty
                || !overlay.animatedCells.isEmpty || !overlay.opacityRegions.isEmpty
            else {
                return self
            }
            var result = self
            result.overlays.append(
                contentsOf: overlay.shiftedOverlays(byX: position.x, y: position.y))
            result.hitTestRegions.append(
                contentsOf: overlay.shiftedHitTestRegions(byX: position.x, y: position.y))
            // …and the runs, which the guard above already tests for and this
            // did not lift. The in-place twin `composite(with:at:)` does lift
            // them, so the two disagreed about a zero-size overlay carrying an
            // animation: through this path the run was dropped, and a dropped
            // run is not a lost animation but a FROZEN one, since the loop keeps
            // the clock alive only from the runs that reach the final buffer.
            result.animatedCells.append(
                contentsOf: overlay.shiftedAnimatedCells(byX: position.x, y: position.y))
            result.opacityRegions.append(
                contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
            return result
        }

        let resultWidth = max(width, position.x + overlay.width)
        let resultHeight = max(height, position.y + overlay.height)

        var result: [String] = []

        for row in 0..<resultHeight {
            var baseLine =
                row < lines.count
                ? lines[row].padToVisibleWidth(resultWidth)
                : String(repeating: " ", count: resultWidth)

            // Check if this row has overlay content
            let overlayRow = row - position.y
            if overlayRow >= 0 && overlayRow < overlay.lines.count {
                let overlayLine = overlay.lines[overlayRow]
                if !overlayLine.isEmpty {
                    // Insert overlay content at the x position
                    baseLine = Self.insertOverlay(
                        base: baseLine,
                        overlay: overlayLine,
                        atColumn: position.x
                    )
                }
            }

            result.append(baseLine)
        }

        var composited = Self(lines: result)
        // Keep this buffer's own layers + hit-test regions; lift the
        // overlay's nested ones, shifted to where the overlay was placed.
        composited.overlays =
            overlays + overlay.shiftedOverlays(byX: position.x, y: position.y)
        composited.hitTestRegions =
            hitTestRegions
            + overlay.shiftedHitTestRegions(byX: position.x, y: position.y)
        // The base's runs are dropped where the overlay covers them, for the
        // same reason its regions are punched below: a run replays its cells
        // over whatever is on screen, and a spinner under a freshly-opened
        // popup would repaint itself THROUGH the popup within one tick. The
        // modal and alert presenters cleared base runs by hand for exactly
        // this; every other overlap — popovers, menus, toasts, ZStack
        // siblings — went uncovered. A partly covered run is CUT to the cells
        // still showing, not dropped whole — `FrameBuffer+Punching.swift` has
        // the reasoning (688a9aa7; it used to be dropped, and a spinner half
        // under a popover froze). The in-place twin below defers here.
        composited.animatedCells =
            animatedCellsPunched(by: overlay, at: position)
            + overlay.shiftedAnimatedCells(byX: position.x, y: position.y)
        // BOTH sides. The result is built from a bare `Self(lines:)`, so the
        // DESTINATION's own regions are as easy to drop here as the overlay's
        // — and dropping them un-fades a faded buffer the moment anything is
        // composited into it, which is what `_UserResizableCore` and `Grid` do
        // to their contents routinely.
        //
        // The destination's regions are PUNCHED first: they name cells of the
        // base, and the overlay just replaced some of those cells. A claim
        // left standing over the replaced footprint would fade the overlay's
        // content at the root — content that was never under the fade, as in
        // `.opacity(0.5).overlay { … }`, where the overlay applies to the
        // already-faded view.
        composited.opacityRegions =
            opacityRegionsPunched(by: overlay, at: position)
            + overlay.shiftedOpacityRegions(byX: position.x, y: position.y)
        return composited
    }

    /// Composites `overlay` on top at `position`, **in place**, touching only
    /// the rows the overlay actually covers.
    ///
    /// Identical in result to ``composited(with:at:)``, and there for the case
    /// that method is quadratic in: compositing many small children into one
    /// canvas. `composited` rebuilds — and re-pads — *every* line of the whole
    /// buffer per call, so folding n children through it costs n × canvas even
    /// when each child covers two rows. A custom `Layout` placing 160 subviews
    /// paid 160 full-canvas rebuilds, which is most of what made it slow.
    ///
    /// Only valid while the receiver's lines are uniform width, which is what
    /// lets the width bookkeeping stay incremental; otherwise it falls back to
    /// the copying path, so callers need not check.
    public mutating func composite(with overlay: Self, at position: (x: Int, y: Int)) {
        guard !overlay.isEmpty else {
            // No visible cells, but nested layers and hit regions still lift.
            guard !overlay.overlays.isEmpty || !overlay.hitTestRegions.isEmpty
                || !overlay.animatedCells.isEmpty || !overlay.opacityRegions.isEmpty
            else { return }
            overlays.append(
                contentsOf: overlay.shiftedOverlays(byX: position.x, y: position.y))
            hitTestRegions.append(
                contentsOf: overlay.shiftedHitTestRegions(byX: position.x, y: position.y))
            animatedCells.append(
                contentsOf: overlay.shiftedAnimatedCells(byX: position.x, y: position.y))
            opacityRegions.append(
                contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
            return
        }
        guard linesAreUniformWidth else {
            self = composited(with: overlay, at: position)
            return
        }

        let resultWidth = Swift.max(width, position.x + overlay.width)
        let resultHeight = Swift.max(height, position.y + overlay.height)

        // Written through `storage`, not `lines`: the row writes below are the
        // whole point of this method, and each one through the public property
        // would re-measure the entire canvas to derive a width this method
        // already knows and overwrites at the end.
        //
        // Grow to the final size. Rows the overlay does not reach keep their
        // contents; they are re-padded only when the width actually grew, which
        // is what keeps every line the same width (and the bookkeeping below
        // honest) without touching them on the common in-bounds path.
        if storage.count < resultHeight {
            storage.append(
                contentsOf: Array(
                    repeating: String(repeating: " ", count: resultWidth),
                    count: resultHeight - storage.count))
        }
        if resultWidth > width {
            for row in storage.indices {
                storage[row] = storage[row].padToVisibleWidth(resultWidth)
            }
        }

        for overlayRow in overlay.lines.indices {
            let row = position.y + overlayRow
            guard row >= 0, row < storage.count else { continue }
            let overlayLine = overlay.lines[overlayRow]
            guard !overlayLine.isEmpty else { continue }
            storage[row] = Self.insertOverlay(
                base: storage[row].padToVisibleWidth(resultWidth),
                overlay: overlayLine,
                atColumn: position.x)
        }

        width = resultWidth
        linesAreUniformWidth = true
        lineWidths = nil
        overlays.append(contentsOf: overlay.shiftedOverlays(byX: position.x, y: position.y))
        hitTestRegions.append(
            contentsOf: overlay.shiftedHitTestRegions(byX: position.x, y: position.y))
        // Punched, then lifted — same reasoning as the copying twin above: the
        // overlay replaced base cells that pending regions were claiming and
        // runs were repainting.
        animatedCells = animatedCellsPunched(by: overlay, at: position)
        animatedCells.append(
            contentsOf: overlay.shiftedAnimatedCells(byX: position.x, y: position.y))
        opacityRegions = opacityRegionsPunched(by: overlay, at: position)
        opacityRegions.append(
            contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
    }

    /// A copy with each line's trailing unstyled blank cells removed.
    ///
    /// For buffers that are drawn OVER something — a floating drag preview,
    /// above all. Compositing is opaque per cell, so a row padded to its
    /// container's width erases a column of whatever it passes over for every
    /// blank it carries. Trailing blanks that carry a background are kept:
    /// there they are fill, not padding.
    ///
    /// Lines are left ragged, which ``FrameBuffer`` supports (see
    /// ``linesAreUniformWidth``) and ``composited(with:at:)`` honours line by
    /// line — so a multi-line preview keeps its own silhouette.
    public func trimmingTrailingBlankCells() -> FrameBuffer {
        var trimmed = lines
        var changed = false
        for index in trimmed.indices {
            let keep = trimmed[index].visibleWidthBeforeTrailingBlanks()
            let lineWidth = trimmed[index].strippedLength
            guard keep < lineWidth else { continue }
            trimmed[index] = trimmed[index].ansiAwarePrefix(
                visibleCount: keep, knownVisibleWidth: lineWidth)
            changed = true
        }
        guard changed else { return self }
        var copy = self
        copy.lines = trimmed  // didSet remeasures the width and drops the stale per-line widths
        return copy
    }

    /// A copy cut to fit `width` × `height` cells, or `self` when it already
    /// does.
    ///
    /// The boundary every container enforces on content that came back larger
    /// than the space it was given. Rows past `height` are dropped whole;
    /// lines longer than `width` are cut with
    /// ``String/ansiAwarePrefix(visibleCount:knownVisibleWidth:)``, so
    /// the cut counts terminal cells rather than characters, never splits a
    /// wide glyph, and keeps the styling that was in force.
    ///
    /// Hit-test regions are trimmed to the surviving box and dropped when
    /// nothing of them remains — a clamp at a container edge is final, and a
    /// region kept for cells that were cut away would be a phantom click
    /// target wherever the next sibling lands. Overlay layers are *kept*
    /// regardless: they float free of the flow and are composited at the root
    /// (see ``overlays``).
    ///
    /// - Parameters:
    ///   - width: Maximum width in terminal cells. Negative values clamp to 0.
    ///   - height: Maximum height in lines. Negative values clamp to 0.
    /// - Returns: The clamped buffer.
    public func clamped(toWidth width: Int, height: Int) -> FrameBuffer {
        let maxWidth = max(0, width)
        let maxHeight = max(0, height)

        // Fast path: already within bounds.
        if self.width <= maxWidth && self.height <= maxHeight {
            return self
        }

        var clippedLines = self.height > maxHeight ? Array(lines.prefix(maxHeight)) : lines
        var resultWidth = 0
        // The widths this walk learns are carried out: a consumer that pads
        // these lines next (a scroll window, a scrollbar, the writer) then
        // does not scan them again to learn what was just measured here.
        var clippedWidths: [Int] = []
        clippedWidths.reserveCapacity(clippedLines.count)
        for index in clippedLines.indices {
            // `self.width`: the parameter `width` is the TARGET, and shadows it.
            let known: Int? = linesAreUniformWidth ? self.width : lineWidths?[index]
            let lineWidth = known ?? clippedLines[index].strippedLength
            if lineWidth > maxWidth {
                let (clipped, clippedWidth) = clippedLines[index].ansiAwarePrefixWithWidth(
                    visibleCount: maxWidth, knownVisibleWidth: lineWidth)
                clippedLines[index] = clipped
                resultWidth = max(resultWidth, clippedWidth)
                clippedWidths.append(clippedWidth)
            } else {
                resultWidth = max(resultWidth, lineWidth)
                clippedWidths.append(lineWidth)
            }
        }
        let uniform = clippedWidths.allSatisfy { $0 == resultWidth }
        var result = FrameBuffer(
            lines: clippedLines, width: resultWidth,
            uniformWidth: uniform, lineWidths: uniform ? nil : clippedWidths)
        // Overlay layers are free-floating and composited separately at the
        // root — clamping the in-flow content must never discard them. The
        // old comment claimed the same for hit regions, but theirs describe
        // IN-FLOW cells: a clamp at a container boundary is final, and a
        // region kept for rows or columns that were clipped away is a
        // phantom click target sitting wherever later siblings land. Trimmed
        // to the box, dropped when nothing remains.
        result.overlays = overlays
        // Opacity regions are IN-FLOW, like hit regions — a rectangle over
        // cells that are in this buffer — and are trimmed on the same rule.
        // Carried verbatim, a region kept for clipped-away rows named
        // whatever a later sibling put there: a TabView's filler rows and its
        // bottom rule faded because a tab's content had been cut to the panel.
        result.opacityRegions = opacityRegions.compactMap { region -> OpacityRegion? in
            region.clipped(toColumns: 0..<maxWidth, rows: 0..<maxHeight)
        }
        result.hitTestRegions = hitTestRegions.compactMap { region -> HitTestRegion? in
            region.clipped(toColumns: 0..<maxWidth, rows: 0..<maxHeight)
        }
        // Runs describe CELLS, so unlike the free-floating layers above they
        // follow the clip. A run whose ROW is clipped away is gone — scrolled
        // out of a viewport it must stop, or it keeps repainting over whatever
        // took its place. A run the WIDTH cuts through is cut to the cells that
        // survive, not dropped: dropping it whole froze the visible part of a
        // pulsing label at a container's right edge, which read as the
        // animation dying wherever a clamp happened to fall. The same cut the
        // overlay punch makes (`animatedCellsPunched`).
        result.animatedCells = animatedCells.compactMap {
            $0.clipped(toCanvasColumns: maxWidth, rows: maxHeight)
        }
        return result
    }
}

// MARK: - Overlay Layer Propagation

extension FrameBuffer {
    /// Returns this buffer's ``overlays``, each shifted by `(dx, dy)`.
    ///
    /// Combining operations call this to keep an overlay layer pinned to the
    /// content it was emitted alongside: the layer moves by exactly the same
    /// amount as the lines it accompanies.
    ///
    /// - Parameters:
    ///   - dx: The horizontal shift in columns.
    ///   - dy: The vertical shift in rows.
    /// - Returns: The shifted overlay layers (empty if there are none).
    public func shiftedOverlays(byX dx: Int, y dy: Int) -> [OverlayLayer] {
        guard !overlays.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return overlays }
        return overlays.map { $0.shifted(byX: dx, y: dy) }
    }

    /// Returns a buffer with `newLines` as its content, carrying this buffer's
    /// overlay layers shifted by `(overlayShiftX, overlayShiftY)`.
    ///
    /// Use this in place of `FrameBuffer(lines:)` whenever a view or modifier
    /// rebuilds its line content from a child buffer (padding, borders,
    /// alignment, …). The shift should match however far the child's content
    /// moved within `newLines` — for example, padding shifts by its leading /
    /// top insets, a border by `(1, 1)`.
    ///
    /// - Parameters:
    ///   - newLines: The rebuilt line content.
    ///   - width: The result's visible width, when the caller already knows it
    ///     (padding: the input width plus its horizontal insets). Skips the
    ///     per-line re-measure `FrameBuffer(lines:)` would do. `nil` keeps that
    ///     measuring path.
    ///   - uniformWidth: As ``init(lines:width:uniformWidth:lineWidths:)``, and
    ///     honoured only alongside an explicit `width` — the measuring path
    ///     works uniformity out for itself.
    ///   - lineWidths: Likewise, and carried verbatim rather than shifted:
    ///     per-line widths are position-independent.
    ///   - overlayShiftX: How far the content moved horizontally.
    ///   - overlayShiftY: How far the content moved vertically.
    /// - Returns: A buffer with the new lines and all four side payloads
    ///   shifted: overlay layers, hit-test regions, animated cell runs and
    ///   opacity regions.
    public func replacingLines(
        _ newLines: [String],
        width: Int? = nil,
        uniformWidth: Bool = false,
        lineWidths: [Int]? = nil,
        overlayShiftX: Int = 0,
        overlayShiftY: Int = 0
    ) -> FrameBuffer {
        // When the caller already knows the result width (e.g. padding: the
        // input width plus the horizontal insets), pass it to skip the
        // re-measure of every line that `FrameBuffer(lines:)` → `computeWidth`
        // would do. `nil` keeps the original recompute behaviour. `uniformWidth`
        // and `lineWidths` are only honoured alongside an explicit `width`; the
        // measuring path computes width/uniformity itself and leaves the per-line
        // widths unknown. Per-line widths are position-independent, so they are
        // carried verbatim (no shift) when the caller supplies them.
        var result = width.map {
            FrameBuffer(
                lines: newLines, width: $0, uniformWidth: uniformWidth, lineWidths: lineWidths)
        } ?? FrameBuffer(lines: newLines)
        result.overlays = shiftedOverlays(byX: overlayShiftX, y: overlayShiftY)
        result.hitTestRegions = shiftedHitTestRegions(
            byX: overlayShiftX, y: overlayShiftY)
        // Runs move with the cells they describe, exactly like the regions
        // above. Omitting them here is not a missing animation but a FROZEN one:
        // the run loop keeps the clock alive on the strength of the runs it
        // finds on the final buffer, so a run lost on the way up stops the clock
        // for everything (see `AnimatedRunPropagationTests`).
        result.animatedCells = shiftedAnimatedCells(byX: overlayShiftX, y: overlayShiftY)
        // Content-preserving, so the faded regions travel with the content. A
        // `.padding` or `.frame` around a faded view must not make it opaque,
        // and the shift is the same one its runs and regions take.
        result.opacityRegions = shiftedOpacityRegions(byX: overlayShiftX, y: overlayShiftY)
        return result
    }
}

// MARK: - Hit-Test Region Propagation

extension FrameBuffer {
    /// Returns this buffer's ``hitTestRegions``, each shifted by `(dx, dy)`.
    ///
    /// Mirrors ``shiftedOverlays(byX:y:)`` — combining operations call
    /// this so a region tracks the lines it was emitted with as the
    /// surrounding view tree composes its parent.
    /// This buffer's ``animatedCells``, each shifted by `(dx, dy)`.
    public func shiftedAnimatedCells(byX dx: Int, y dy: Int) -> [AnimatedCellRun] {
        guard !animatedCells.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return animatedCells }
        return animatedCells.map { $0.shifted(byX: dx, y: dy) }
    }

    /// This buffer's ``opacityRegions``, each shifted by `(dx, dy)`.
    ///
    /// Mirrors ``shiftedAnimatedCells(byX:y:)`` — and for the same reason: a
    /// combining operation that moves the cells must move every claim about
    /// them, or the claim lands on somebody else's content.
    public func shiftedOpacityRegions(byX dx: Int, y dy: Int) -> [OpacityRegion] {
        guard !opacityRegions.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return opacityRegions }
        return opacityRegions.map { $0.shifted(byX: dx, y: dy) }
    }

    /// This buffer's ``hitTestRegions``, each moved by `(dx, dy)`.
    ///
    /// The sibling of ``shiftedOverlays(byX:y:)`` and
    /// ``shiftedAnimatedCells(byX:y:)``, and load-bearing for the same reason:
    /// a region records where a control is *clickable*, in this buffer's
    /// coordinates. Any operation that places these cells somewhere else —
    /// padding, bordering, stacking, windowing — must carry the regions by the
    /// same offset, or the control keeps taking clicks at the position it used
    /// to occupy while drawing somewhere new.
    ///
    /// - Parameters:
    ///   - dx: Cells to move right; negative moves left.
    ///   - dy: Lines to move down; negative moves up.
    /// - Returns: The shifted regions, or the originals when the offset is zero.
    public func shiftedHitTestRegions(byX dx: Int, y dy: Int) -> [HitTestRegion] {
        guard !hitTestRegions.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return hitTestRegions }
        return hitTestRegions.map { $0.shifted(byX: dx, y: dy) }
    }

    /// `line` with `frame` redrawn over the `width` cells starting at `column`.
    ///
    /// This is the animation tick — the one splice that happens *after* a frame
    /// is finished, rather than while one is being assembled, and the difference
    /// matters for exactly one reason: **the background**.
    ///
    /// ``composited(with:at:)`` resets before an overlay, so an overlay stating
    /// no background of its own lands on the terminal's default. During assembly
    /// that is harmless, because a container paints its background across the
    /// whole finished row afterwards (`ANSIRenderer.applyPersistentBackground`
    /// re-injects it after every reset). Nothing does that here — the row is
    /// already on screen — so a foreground-only frame, which is what colouring a
    /// glyph produces and therefore what most focus indicators leave behind,
    /// punched a hole through to the terminal background on every tick: a white
    /// box around a breathing checkbox on a light-background terminal.
    ///
    /// So the frame is drawn over the background the line already had at that
    /// column, and *only* the background — the foreground, bold and underline in
    /// force there belong to the glyph being replaced, not to the surface under
    /// it.
    ///
    /// The background is re-stated after every reset *inside* the frame, not
    /// only in front of it, for the same reason `applyPersistentBackground`
    /// does it: a frame is often several coloured pieces (`colorize(arrow) +
    /// colorize(label)`, `colorize("[") + mark + colorize("]")`, a glyph and
    /// the blank cell after it), and each piece ends with a reset. A leading
    /// background alone survives only to the first of them — which is why the
    /// "N more above" arrow kept its surface while its label did not, why a
    /// focused button's `●` kept it and the space beside it did not, and why an
    /// ASCII toggle kept it for `[` and nothing after.
    public static func patchingAnimatedCells(
        in line: String, with frame: String, atColumn column: Int, width: Int
    ) -> String {
        // The cells about to be replaced may carry a host's cursor-advance
        // compensation, put there by `buildLine` when the row was rendered. The
        // frame brings its own, so the old pair has to go — see
        // `String.removingCursorCompensation(coveringColumns:)`, which
        // is where the story of the extra `CUF` is written down.
        let base = line.removingCursorCompensation(
            coveringColumns: column..<(column + width))
        // One walk of the line. The split already knows the background in
        // force where the run starts and the line's width, which used to be
        // two more walks (`ansiSGRStateAt`, `strippedLength`) and a pad that
        // walked a third time — per run, per tick, 11% of a live frame. A line
        // shorter than the run's end is padded by the insert, not here.
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + frame.strippedLength)
        let background = split.backgroundUnderOverlay
        return insertOverlay(
            split: split,
            overlay: background + restating(background, afterResetsIn: frame),
            atColumn: column,
            // The line used to be padded out to the run's END before the
            // split, so a frame narrower than its run left the pad's spaces
            // after it; the same spaces come from the suffix shortfall now.
            minimumTotalWidth: column + width)
    }

    /// `line` with `span` spliced over it starting at `column`, the line's own
    /// styling restored where the span ends.
    ///
    /// The same surgery ``patchingAnimatedCells(in:with:atColumn:width:)``
    /// performs, without the background re-statement — a caller that has
    /// already decided every cell's colours (opacity resolution) wants its span
    /// taken literally, while a pre-baked animation frame was coloured against
    /// an assumed background and needs the real one restated around it.
    public static func splicing(_ span: String, into line: String, atColumn column: Int) -> String {
        let width = span.strippedLength
        guard width > 0 else { return line }
        // As above: the split is the one walk; a short line is padded by the
        // insert.
        return insertOverlay(
            split: line.ansiOverlaySplit(prefixColumns: column, suffixDropColumns: column + width),
            overlay: span,
            atColumn: column)
    }

    /// `frame` with `background` re-stated after every reset that has cells
    /// after it.
    ///
    /// A trailing reset is left bare deliberately: nothing follows it inside the
    /// run, and `insertOverlay` restores the line's own styling where the suffix
    /// begins — so a background there would be bytes emitted per tick, per run,
    /// to change nothing.
    private static func restating(_ background: String, afterResetsIn frame: String) -> String {
        guard !background.isEmpty, frame.contains(ansiReset) else { return frame }
        var rebuilt = ""
        var remainder = Substring(frame)
        while let reset = remainder.range(of: ansiReset) {
            rebuilt += remainder[..<reset.upperBound]
            remainder = remainder[reset.upperBound...]
            if !remainder.isEmpty { rebuilt += background }
        }
        return rebuilt + remainder
    }
}

// MARK: - Private Helpers

extension FrameBuffer {

    /// ANSI SGR reset sequence. Inlined to avoid depending on ANSIRenderer.
    fileprivate static let ansiReset = "\u{1B}[0m"

    /// Debug-only check of the ``lineWidths`` invariant: when non-`nil`, it must
    /// equal `buffer.lines.map(\.strippedLength)` (so a carried width is never
    /// allowed to drift from the line it describes).
    ///
    /// Compiled out of release builds entirely — the per-line `strippedLength`
    /// walk it performs is exactly the cost ``lineWidths`` exists to avoid, so it
    /// must never run in production. Call it wherever the field is assigned a
    /// non-`nil` value.
    fileprivate static func assertLineWidthsInvariant(
        _ buffer: FrameBuffer, file: StaticString = #fileID, line: UInt = #line
    ) {
        #if DEBUG
        guard let widths = buffer.lineWidths else { return }
        assert(
            widths.count == buffer.lines.count,
            "FrameBuffer.lineWidths count \(widths.count) != lines count \(buffer.lines.count)",
            file: file, line: line)
        let measured = buffer.lines.map(\.strippedLength)
        assert(
            widths == measured,
            "FrameBuffer.lineWidths \(widths) != measured \(measured)",
            file: file, line: line)
        #endif
    }
    /// Recomputes the cached ``width`` and ``linesAreUniformWidth`` from the
    /// current ``lines``, and invalidates ``lineWidths``.
    ///
    /// Called automatically by the `didSet` observer on ``lines``. A direct
    /// mutation of `lines` (external assignment) changes the
    /// line content, so any previously-carried per-line widths no longer match;
    /// the single-pass `measure` does not produce the full per-line array, so
    /// they are dropped to `nil` (measure on demand) rather than left stale.
    fileprivate mutating func recomputeWidth() {
        let measured = Self.measure(lines)
        width = measured.width
        linesAreUniformWidth = measured.uniform
        lineWidths = nil
    }

    /// Measures a set of lines in a single pass: the widest line's visible width
    /// and whether every line shares that width.
    ///
    /// Uniformity falls out of tracking the min and max visible width together —
    /// they are equal iff all lines match — so it costs nothing beyond the
    /// per-line `strippedLength` the width already needs. Empty / single-line
    /// inputs are trivially uniform.
    ///
    /// - Parameter lines: The lines to measure.
    /// - Returns: The widest line's visible width and whether all lines match it.
    fileprivate static func measure(_ lines: [String]) -> (width: Int, uniform: Bool) {
        guard let first = lines.first else { return (0, true) }
        var minWidth = first.strippedLength
        var maxWidth = minWidth
        for line in lines.dropFirst() {
            let w = line.strippedLength
            if w < minWidth { minWidth = w }
            if w > maxWidth { maxWidth = w }
        }
        return (maxWidth, minWidth == maxWidth)
    }

    /// Inserts overlay text into base text at the specified column position.
    ///
    /// Splits the base line at visible-character boundaries (ignoring ANSI codes)
    /// and preserves the base's ANSI styling in the prefix and suffix regions.
    /// The overlay replaces the base in its column range, with its own styling intact.
    ///
    /// After the overlay, the base's active ANSI state is restored before the
    /// suffix so the dimmed background (or any other base styling) continues
    /// seamlessly to the right of the overlay.
    ///
    /// Everything it needs about `base` comes from one
    /// `String.ansiOverlaySplit(prefixColumns:suffixDropColumns:)`. It
    /// used to come from five separate ANSI-aware walks of the line, which is
    /// quadratic where it hurts most: a canvas row grows with every styled child
    /// already composited into it, so placing n children rescanned an
    /// ever-longer line 5n times.
    ///
    /// - Parameters:
    ///   - base: The base text line (may contain ANSI codes), already padded to
    ///     the width of the row being built.
    ///   - overlay: The overlay text to insert (may contain ANSI codes).
    ///   - column: The column position (0-based, in visible characters).
    /// - Returns: The composited line with base styling preserved around the overlay.
    fileprivate static func insertOverlay(
        base: String,
        overlay: String,
        atColumn column: Int
    ) -> String {
        // An overlay starting LEFT of the base is cut to the part that is on it and
        // inserted at column 0 — the answer both composite twins already give a negative
        // ROW, which they skip. It used to pass straight through: the split has no prefix
        // before a negative column and drops only `column + width` cells of the base, so
        // the WHOLE overlay went in at column 0 and the base's own cells slid right behind
        // it. The row came out `-column` cells wider than the canvas, and the in-place
        // twin then stamped the canvas's width and `linesAreUniformWidth = true` over it —
        // a lie every consumer that trusts the hint mis-pads on: a parent `HStack` starts
        // its next child inside the row, and a row past the terminal edge wraps onto the
        // next. The public route is a custom `Layout` placing a subview's centre at x: 0
        // with `place(at:anchor:)`, which does not clamp (its `place(in:)` sibling does).
        //
        // Here, and not at the two twins' call sites, because this is the function only
        // they call: the run splice and the opacity splice share the split-taking overload
        // below, and every column reaching them is already clamped non-negative.
        guard column >= 0 else {
            guard column + overlay.strippedLength > 0 else { return base }
            return insertOverlay(
                base: base, overlay: overlay.ansiAwareCuttingLeadingColumns(-column), atColumn: 0)
        }
        let overlayVisibleWidth = overlay.strippedLength

        // Split the base into prefix (before overlay) and suffix (after overlay),
        // preserving all ANSI codes in both segments.
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + overlayVisibleWidth)
        return insertOverlay(split: split, overlay: overlay, atColumn: column)
    }

    /// ``insertOverlay(base:overlay:atColumn:)`` for a caller that has already
    /// split the base at the overlay's columns — the split carries the
    /// overlay's end, so nothing is measured again.
    fileprivate static func insertOverlay(
        split: ANSIOverlaySplit,
        overlay: String,
        atColumn column: Int,
        minimumTotalWidth: Int = 0
    ) -> String {
        let afterOverlayColumn = split.suffixDropColumns

        // Either split point can land in the MIDDLE of a wide character
        // (emoji, CJK): the split drops the straddling character whole, so
        // the prefix comes back short and the suffix starts late. Pad each
        // shortfall with spaces (a wide glyph can't be half-drawn — the gap is
        // the standard treatment), otherwise every base row with a straddling
        // wide character composites the overlay one cell left and pulls the
        // rest of the row in behind it — ragged pop-up borders next to emoji.
        let prefix = split.prefixWidth < column
            ? split.prefix + String(repeating: " ", count: column - split.prefixWidth)
            : split.prefix
        var suffix = split.suffix
        let expectedSuffixWidth = max(0, split.totalWidth - afterOverlayColumn)
        let suffixShortfall = expectedSuffixWidth - split.suffixWidth
        if suffixShortfall > 0 {
            suffix = String(repeating: " ", count: suffixShortfall) + suffix
        }
        // A caller that wants the line to reach a column past everything the
        // base had (a run's end, when its frame is narrower than the run) gets
        // the extra cells as plain spaces AFTER the suffix — where a pad of the
        // base before the split would have put them.
        let trailing = minimumTotalWidth - max(split.totalWidth, afterOverlayColumn)
        if trailing > 0 {
            suffix += String(repeating: " ", count: trailing)
        }

        // Restore the styling ACTIVE at the suffix's start column (not the line's
        // leading state). A uniform background set up at the leading is still in
        // force there, so it's preserved; but inline text decorations the prefix
        // turned on and then RESET (e.g. an underlined `DemoSection` header
        // followed by plain padding) are NOT carried onto the suffix — the bug
        // where the cell just past a composited overlay inherited the underline.
        // The split nets the escapes before the column, so an open+reset pair
        // leaves nothing while a persistent background (and its lone trailing BG
        // code) nets to the background.
        //
        // Reading that state off the PADDED base rather than the unpadded
        // original is not a shortcut: padding only ever appends plain spaces
        // after every escape the line has, so the set of SGRs before any column
        // is the same in both. (It used to be passed in separately, which cost a
        // whole extra scan to reach the same answer.)

        // A cell has a glyph AND a field, and an overlay cell that states no
        // background of its own has said nothing about the field — so it keeps
        // the one it lands on. `ZStack { Color.red; Text("hi") }` is the case
        // that wants this: the letters are drawn ON the red rather than
        // punching a hole in it. An overlay that states its own background
        // still wins, because its escapes come after this one.
        //
        // Nothing to do — and nothing emitted — where the base states no
        // background, which is the ordinary case.
        let overlay = overlay.paintedOver(background: split.backgroundUnderOverlay)

        // Build: [prefix] + [reset] + [overlay] + [reset + base style restore] + [suffix]
        var result = prefix
        result += Self.ansiReset
        result += overlay
        result += Self.ansiReset
        result += split.styleBeforeSuffix
        result += suffix

        return result
    }
}

extension FrameBuffer {
    /// Where a reveal should scroll to for the control identified by `focusID`.
    ///
    /// A focusable container emits SEVERAL regions under one id: a whole-
    /// control region (which spans its border), and a smaller one for whatever
    /// is currently active inside it — a List's selected row, say. Which one to
    /// reveal depends on what just happened, and the two answers differ:
    ///
    /// - `wholeControl` (focus just MOVED here): you tabbed to the *list*, so
    ///   show as much of the list as will fit — its border and header included.
    ///   Selecting a row is a secondary effect of arriving, not the point.
    ///   Returns the union of every region carrying the id.
    /// - otherwise (focus moved WITHIN a control that already had it): you are
    ///   moving between rows, not regarding the list as a whole, so reveal only
    ///   the thing that changed. Returns the smallest region — the active row —
    ///   which is what keeps a cursor visible while walking a long table.
    ///
    /// Revealing the union in BOTH cases pushes the cursor off-screen on every
    /// arrow key; revealing the row in both leaves a bordered control's top rule
    /// just above the fold. Hence the split.
    public func revealTarget(focusID: String, wholeControl: Bool) -> (top: Int, height: Int)? {
        var top = Int.max
        var bottom = Int.min
        var smallest: HitTestRegion?
        for region in hitTestRegions where region.focusID == focusID {
            // The union grows by whatever chrome an ancestor drew flush against
            // the region — the border it is framed by is part of "the control"
            // when you have just arrived at it. The smallest region, which the
            // within-control path uses, deliberately ignores the outsets: a
            // cursor moving row to row is not re-revealing the frame.
            top = Swift.min(top, region.offsetY - region.revealOutsetTop)
            bottom = Swift.max(bottom, region.offsetY + region.height + region.revealOutsetBottom)
            if smallest == nil || region.height < smallest!.height { smallest = region }
        }
        guard top <= bottom, let smallest else { return nil }
        return wholeControl ? (top, bottom - top) : (smallest.offsetY, smallest.height)
    }
}
