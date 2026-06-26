//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// Mutating `lines` directly recomputes the cached ``width`` and
    /// ``linesAreUniformWidth`` and invalidates ``lineWidths`` (it cannot
    /// cheaply produce the per-line widths, so it drops them to `nil` rather
    /// than leave a stale array).
    public var lines: [String] {
        didSet { recomputeWidth() }
    }

    /// The width of the buffer (the length of the longest line in visible characters).
    ///
    /// This is a stored property, recomputed automatically whenever
    /// ``lines`` is mutated. Accessing `width` is O(1) — the expensive
    /// ANSI-stripping regex runs only once per mutation, not per access.
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
    /// excluded from ``==`` (see the custom `Equatable` conformance): two buffers
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
    /// ``Swift/StringProtocol/strippedLength`` re-measure. `nil` means "unknown":
    /// every consumer falls back to measuring per line, exactly as before this
    /// field existed.
    ///
    /// It is maintained with the same discipline as ``linesAreUniformWidth``:
    /// combining/mutating operations either produce the correct array cheaply
    /// (by concatenation, never by re-measuring) or set it to `nil` — a stale
    /// array is never left behind. Like ``linesAreUniformWidth`` it is excluded
    /// from ``==`` (a pure function of ``lines``, so it can never distinguish two
    /// buffers with identical lines).
    ///
    /// - Invariant: when non-`nil`, `lineWidths == lines.map(\.strippedLength)`
    ///   and `lineWidths!.count == lines.count`. Checked in debug builds wherever
    ///   the field is set (see ``assertLineWidthsInvariant(_:file:line:)``).
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

    /// Creates an empty buffer.
    public init() {
        self.lines = []
        self.width = 0
        self.linesAreUniformWidth = true  // vacuously uniform
        self.lineWidths = nil  // no lines → nothing to carry (uniform covers it)
    }

    /// Creates a buffer from an array of lines.
    ///
    /// - Parameter lines: The text lines.
    public init(lines: [String]) {
        self.lines = lines
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
        self.lines = lines
        self.width = width
        self.linesAreUniformWidth = uniformWidth
        self.lineWidths = lineWidths
        Self.assertLineWidthsInvariant(self)
    }

    /// Creates a buffer containing a single line.
    ///
    /// - Parameter text: The text content.
    public init(text: String) {
        self.lines = [text]
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
        self.lines = Array(repeating: " ", count: height)
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
        self.lines = Array(repeating: String(repeating: " ", count: width), count: height)
        self.width = width
        self.linesAreUniformWidth = true  // every line is `width` spaces
        self.lineWidths = nil  // uniform at `width`; no array needed
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
    }
}

// MARK: - Public API

extension FrameBuffer {
    /// Stacks another buffer below this one with optional spacing.
    ///
    /// An empty `other` contributes no height *and* no spacing slot
    /// — the buffers join with the spacing they would have had if
    /// `other` were not in the list at all. This matches SwiftUI's
    /// `VStack` behaviour: `if false { ChildView() }` evaluates to
    /// `Optional<ChildView>.none`, and an `Optional.none` child does
    /// not consume a spacing slot from its parent stack. The same
    /// holds for `EmptyView()` and any other zero-height child. If
    /// callers want to reserve a row whether or not the conditional
    /// fires, they must opt in with a sized placeholder such as
    /// ``Color/clear``-with-frame or ``Spacer/init()``-with-frame —
    /// using `EmptyView()` in an `else` branch will NOT reserve the
    /// row, because `EmptyView()` is also empty.
    ///
    /// - Parameters:
    ///   - other: The buffer to append below.
    ///   - spacing: Number of empty lines between the two buffers.
    ///     Ignored when `other` is empty, by design (see above).
    public mutating func appendVertically(_ other: Self, spacing: Int = 0) {
        let priorHeight = lines.count

        guard !other.isEmpty else {
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
            return
        }

        // `other`'s content lands below the current lines (plus spacing).
        let spacingApplied = priorHeight > 0 ? spacing : 0
        let verticalShift = priorHeight + spacingApplied

        // Pre-compute the new width (avoids redundant computation in didSet)
        let newWidth = max(width, other.width)

        // Build combined array
        var combined = lines
        let selfWasEmpty = combined.isEmpty
        if !selfWasEmpty && spacing > 0 {
            combined.append(contentsOf: repeatElement("", count: spacing))
        }
        combined.append(contentsOf: other.lines)

        // Propagate uniform-width cheaply (no re-measure). The stack is uniform
        // only when both sides are uniform AT THE SAME width and no empty spacer
        // line (visible width 0) was inserted between them. When self was empty,
        // the result is simply `other`. Anything else is "unknown" (false).
        let resultUniform: Bool
        if selfWasEmpty {
            resultUniform = other.linesAreUniformWidth
        } else {
            resultUniform =
                linesAreUniformWidth && other.linesAreUniformWidth
                && width == other.width && spacing == 0
        }

        // Carry per-line widths cheaply (concatenation, no re-measure) — the
        // exact parallel of `combined`'s construction above. Possible only when
        // both sides already know their widths; otherwise the result is "unknown"
        // (nil). When self was empty the result is simply `other`'s widths; the
        // inserted spacing blank lines ("") each have visible width 0.
        let combinedWidths: [Int]?
        if selfWasEmpty {
            combinedWidths = other.lineWidths
        } else if let selfWidths = lineWidths, let otherWidths = other.lineWidths {
            var widths = selfWidths
            if spacing > 0 {
                widths.append(contentsOf: repeatElement(0, count: spacing))
            }
            widths.append(contentsOf: otherWidths)
            combinedWidths = widths
        } else {
            combinedWidths = nil
        }

        let carriedOverlays = overlays + other.shiftedOverlays(byX: 0, y: verticalShift)
        let carriedRegions =
            hitTestRegions + other.shiftedHitTestRegions(byX: 0, y: verticalShift)

        // Replace self with new buffer using pre-computed width
        self = FrameBuffer(
            lines: combined, width: newWidth, uniformWidth: resultUniform,
            lineWidths: combinedWidths)
        overlays = carriedOverlays
        hitTestRegions = carriedRegions
    }

    /// Places another buffer to the right of this one with optional spacing.
    ///
    /// An empty `other` contributes no width *and* no spacing slot
    /// — the buffers join with the spacing they would have had if
    /// `other` were not in the list at all. This matches SwiftUI's
    /// `HStack` behaviour (and ``appendVertically``'s mirror of the
    /// same rule): an `Optional<ChildView>.none`, an `EmptyView`,
    /// or any other zero-width child is treated as if it were not
    /// in the children list at all. To reserve a column whether or
    /// not a conditional fires, opt in with a sized placeholder
    /// such as ``Color/clear``-with-frame or ``Spacer/init()``-
    /// with-frame — `EmptyView()` in an `else` branch will NOT
    /// reserve the column, because `EmptyView()` is also empty.
    ///
    /// - Parameters:
    ///   - other: The buffer to append to the right.
    ///   - spacing: Number of space characters between the two buffers.
    ///     Ignored when `other` is empty, by design (see above).
    public mutating func appendHorizontally(_ other: Self, spacing: Int = 0) {
        let priorWidth = width

        guard !other.isEmpty else {
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
            return
        }

        let maxHeight = max(height, other.height)
        let myWidth = width
        let spacer = String(repeating: " ", count: spacing)

        // Pre-compute the new width
        let newWidth = myWidth + spacing + other.width

        var result: [String] = []
        result.reserveCapacity(maxHeight)

        for row in 0..<maxHeight {
            let left = row < lines.count ? lines[row] : ""
            let right = row < other.lines.count ? other.lines[row] : ""

            // Pad the left side to consistent visible width
            let leftPadded = left.padToVisibleWidth(myWidth)
            result.append(leftPadded + spacer + right)
        }

        // `other`'s content lands to the right, past this buffer + spacing.
        let carriedOverlays = overlays + other.shiftedOverlays(byX: myWidth + spacing, y: 0)
        let carriedRegions =
            hitTestRegions + other.shiftedHitTestRegions(byX: myWidth + spacing, y: 0)

        // Replace self with new buffer using pre-computed width
        self = FrameBuffer(lines: result, width: newWidth)
        overlays = carriedOverlays
        hitTestRegions = carriedRegions
    }

    /// Layers another buffer on top of this one (ZStack behavior).
    ///
    /// Non-empty characters in the overlay replace characters in the base.
    /// For simplicity, this just overlays line by line.
    ///
    /// - Parameter overlay: The buffer to overlay on top.
    public mutating func overlay(_ overlay: Self) {
        let maxHeight = max(height, overlay.height)
        var result: [String] = []
        for row in 0..<maxHeight {
            if row < overlay.lines.count && !overlay.lines[row].isEmpty {
                result.append(overlay.lines[row])
            } else if row < lines.count {
                result.append(lines[row])
            } else {
                result.append("")
            }
        }
        lines = result
        // The overlay is placed flush at (0, 0), so its layers + hit-test
        // regions need no shift.
        overlays.append(contentsOf: overlay.overlays)
        hitTestRegions.append(contentsOf: overlay.hitTestRegions)
    }

    /// Creates a new buffer with another buffer composited on top at the specified position.
    ///
    /// This performs character-level compositing: overlay characters replace base characters
    /// only where the overlay has visible content (non-space characters).
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
            guard !overlay.overlays.isEmpty || !overlay.hitTestRegions.isEmpty else {
                return self
            }
            var result = self
            result.overlays.append(
                contentsOf: overlay.shiftedOverlays(byX: position.x, y: position.y))
            result.hitTestRegions.append(
                contentsOf: overlay.shiftedHitTestRegions(byX: position.x, y: position.y))
            return result
        }

        let resultWidth = max(width, position.x + overlay.width)
        let resultHeight = max(height, position.y + overlay.height)

        var result: [String] = []

        for row in 0..<resultHeight {
            // Keep the original (unpadded) line for ANSI state extraction.
            // padToVisibleWidth appends unstyled spaces that lose the base's
            // ANSI state, so insertOverlay needs the original to restore it.
            let originalLine: String? = row < lines.count ? lines[row] : nil
            var baseLine: String
            if let original = originalLine {
                baseLine = original.padToVisibleWidth(resultWidth)
            } else {
                baseLine = String(repeating: " ", count: resultWidth)
            }

            // Check if this row has overlay content
            let overlayRow = row - position.y
            if overlayRow >= 0 && overlayRow < overlay.lines.count {
                let overlayLine = overlay.lines[overlayRow]
                if !overlayLine.isEmpty {
                    // Insert overlay content at the x position
                    baseLine = insertOverlay(
                        base: baseLine,
                        overlay: overlayLine,
                        atColumn: position.x,
                        originalBase: originalLine
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
        return composited
    }

    /// Returns a copy of this buffer guaranteed to fit within the given bounds.
    ///
    /// Lines wider than `width` are truncated to `width` visible cells
    /// (ANSI-aware — a wide character is dropped rather than split in half);
    /// lines beyond `height` are discarded.
    ///
    /// This is the layout system's safety net: a view that mistakenly
    /// produces an oversized buffer cannot overwrite a sibling or overflow
    /// the terminal — at worst its own content is truncated.
    ///
    /// - Parameters:
    ///   - width: The maximum visible width in cells. Values below 0 are treated as 0.
    ///   - height: The maximum number of lines. Values below 0 are treated as 0.
    /// - Returns: A buffer with `width <= max(0, width)` and `height <= max(0, height)`.
    public func clamped(toWidth width: Int, height: Int) -> FrameBuffer {
        let maxWidth = max(0, width)
        let maxHeight = max(0, height)

        // Fast path: already within bounds.
        if self.width <= maxWidth && self.height <= maxHeight {
            return self
        }

        var clippedLines = self.height > maxHeight ? Array(lines.prefix(maxHeight)) : lines
        var resultWidth = 0
        for index in clippedLines.indices {
            if clippedLines[index].strippedLength > maxWidth {
                clippedLines[index] = clippedLines[index].ansiAwarePrefix(visibleCount: maxWidth)
            }
            resultWidth = max(resultWidth, clippedLines[index].strippedLength)
        }
        var result = FrameBuffer(lines: clippedLines, width: resultWidth)
        // Overlay layers and hit-test regions are free-floating and
        // composited separately at the root — clamping the in-flow
        // content must never discard them.
        result.overlays = overlays
        result.hitTestRegions = hitTestRegions
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
    ///   - overlayShiftX: How far the content moved horizontally.
    ///   - overlayShiftY: How far the content moved vertically.
    /// - Returns: A buffer with the new lines, shifted overlay layers and
    ///   shifted hit-test regions.
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
    public func shiftedHitTestRegions(byX dx: Int, y dy: Int) -> [HitTestRegion] {
        guard !hitTestRegions.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return hitTestRegions }
        return hitTestRegions.map { region in
            var shifted = region
            shifted.offsetX += dx
            shifted.offsetY += dy
            return shifted
        }
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
    /// mutation of `lines` (external assignment, ``overlay(_:)``) changes the
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
    /// - Parameters:
    ///   - base: The base text line (may contain ANSI codes).
    ///   - overlay: The overlay text to insert (may contain ANSI codes).
    ///   - column: The column position (0-based, in visible characters).
    ///   - originalBase: The original base line before padding, used to extract
    ///     the active ANSI state. If `nil`, the state is extracted from `base`.
    /// - Returns: The composited line with base styling preserved around the overlay.
    fileprivate func insertOverlay(
        base: String,
        overlay: String,
        atColumn column: Int,
        originalBase: String? = nil
    ) -> String {
        let overlayVisibleWidth = overlay.strippedLength
        let afterOverlayColumn = column + overlayVisibleWidth

        // Split the base into prefix (before overlay) and suffix (after overlay),
        // preserving all ANSI codes in both segments.
        let prefix = base.ansiAwarePrefix(visibleCount: column)
        let suffix = base.ansiAwareSuffix(droppingVisible: afterOverlayColumn)

        // Restore the styling ACTIVE at the suffix's start column (not the line's
        // leading state). A uniform background set up at the leading is still in
        // force there, so it's preserved; but inline text decorations the prefix
        // turned on and then RESET (e.g. an underlined `DemoSection` header
        // followed by plain padding) are NOT carried onto the suffix — the bug
        // where the cell just past a composited overlay inherited the underline.
        // `ansiStateBefore` nets the escapes before the column, so an open+reset
        // pair leaves nothing while a persistent background (and its lone trailing
        // BG code) nets to the background.
        let styleSource = originalBase ?? base
        let baseStyle = styleSource.ansiStateBefore(visibleColumn: afterOverlayColumn)

        // Build: [prefix] + [reset] + [overlay] + [reset + base style restore] + [suffix]
        var result = prefix
        result += Self.ansiReset
        result += overlay
        result += Self.ansiReset
        result += baseStyle
        result += suffix

        return result
    }
}
