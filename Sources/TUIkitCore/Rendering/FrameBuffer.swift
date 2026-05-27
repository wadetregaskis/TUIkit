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
    /// Mutating `lines` directly recomputes the cached ``width``.
    public var lines: [String] {
        didSet { recomputeWidth() }
    }

    /// The width of the buffer (the length of the longest line in visible characters).
    ///
    /// This is a stored property, recomputed automatically whenever
    /// ``lines`` is mutated. Accessing `width` is O(1) — the expensive
    /// ANSI-stripping regex runs only once per mutation, not per access.
    public private(set) var width: Int

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
    }

    /// Creates a buffer from an array of lines.
    ///
    /// - Parameter lines: The text lines.
    public init(lines: [String]) {
        self.lines = lines
        self.width = Self.computeWidth(lines)
    }

    /// Initializer that accepts pre-computed width.
    ///
    /// Use this when the width is already known to avoid redundant computation.
    public init(lines: [String], width: Int) {
        self.lines = lines
        self.width = width
    }

    /// Creates a buffer containing a single line.
    ///
    /// - Parameter text: The text content.
    public init(text: String) {
        self.lines = [text]
        self.width = text.strippedLength
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

// MARK: - Public API

extension FrameBuffer {
    /// Stacks another buffer below this one with optional spacing.
    ///
    /// - Parameters:
    ///   - other: The buffer to append below.
    ///   - spacing: Number of empty lines between the two buffers.
    public mutating func appendVertically(_ other: Self, spacing: Int = 0) {
        let priorHeight = lines.count

        guard !other.isEmpty else {
            // `other` contributes no visible lines, but may still carry
            // overlay layers and hit-test regions that must not be lost.
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
        if !combined.isEmpty && spacing > 0 {
            combined.append(contentsOf: repeatElement("", count: spacing))
        }
        combined.append(contentsOf: other.lines)

        let carriedOverlays = overlays + other.shiftedOverlays(byX: 0, y: verticalShift)
        let carriedRegions =
            hitTestRegions + other.shiftedHitTestRegions(byX: 0, y: verticalShift)

        // Replace self with new buffer using pre-computed width
        self = FrameBuffer(lines: combined, width: newWidth)
        overlays = carriedOverlays
        hitTestRegions = carriedRegions
    }

    /// Places another buffer to the right of this one with optional spacing.
    ///
    /// - Parameters:
    ///   - other: The buffer to append to the right.
    ///   - spacing: Number of space characters between the two buffers.
    public mutating func appendHorizontally(_ other: Self, spacing: Int = 0) {
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
        overlayShiftX: Int = 0,
        overlayShiftY: Int = 0
    ) -> FrameBuffer {
        var result = FrameBuffer(lines: newLines)
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
    /// Recomputes the cached ``width`` from the current ``lines``.
    ///
    /// Called automatically by the `didSet` observer on ``lines``.
    fileprivate mutating func recomputeWidth() {
        width = Self.computeWidth(lines)
    }

    /// Computes the visible width of a set of lines.
    ///
    /// - Parameter lines: The lines to measure.
    /// - Returns: The length of the longest line in visible characters.
    fileprivate static func computeWidth(_ lines: [String]) -> Int {
        lines.map { $0.strippedLength }.max() ?? 0
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

        // Extract the leading ANSI state from the original (unpadded) base line.
        // The leading sequences contain the full styling setup (BG + FG + dim)
        // before any visible text. This is more reliable than scanning the whole
        // string, because applyPersistentBackground appends a lone BG code after
        // the final reset that doesn't represent the full styling state.
        let styleSource = originalBase ?? base
        let baseStyle = styleSource.leadingANSISequences()

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
