//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextFieldContentRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Text Field Content Renderer

/// Shared rendering logic for text input fields (TextField, SecureField).
///
/// Both TextField and SecureField share identical rendering patterns for
/// prompt display, cursor positioning, horizontal scrolling, and selection
/// highlighting. The only difference is how characters are displayed:
/// TextField shows the actual text, SecureField shows bullet characters.
///
/// This renderer extracts that shared logic. The caller provides a
/// `displayCharacter` closure that maps text indices to display characters.
@MainActor
struct TextFieldContentRenderer {

    /// The prompt view shown when the field is empty and unfocused.
    let prompt: Text?

    /// Whether the field is disabled.
    let isDisabled: Bool

    /// Returns the display character for a given index in the text.
    /// For TextField: the actual character. For SecureField: a bullet.
    let displayCharacter: (_ index: Int, _ text: String) -> Character

    /// A scoped style-cascade override for the entered text's colour
    /// (`.textFieldTextStyle { … }`), or `nil` to use the palette foreground.
    /// The cursor, selection, and (dim) prompt keep their own colours.
    var contentForeground: Color?

    /// The entered-text foreground, resolved to a concrete colour. A
    /// `.textFieldTextStyle` override may be a *semantic* colour (e.g.
    /// `.palette.accent`); resolving it against the palette here keeps a
    /// semantic value from reaching ``ANSIRenderer``, which traps on
    /// `.semantic`. A concrete colour resolves to itself.
    private func resolvedContentForeground(_ palette: any Palette) -> Color {
        (contentForeground ?? palette.foreground).resolve(with: palette)
    }

    // MARK: - Content Building

    /// Builds the complete field content based on current state.
    func buildContent(
        text: String,
        cursorPosition: Int,
        selectionRange: Range<Int>?,
        isFocused: Bool,
        palette: any Palette,
        cursorStyle: TextCursorStyle,
        cursorTimer: CursorTimer?,
        contentWidth: Int
    ) -> String {
        let isEmpty = text.isEmpty
        // The palette's field surface (the tab-strip tone): palette-aware, so
        // light palettes get a light field. The old fixed accent-dim tint
        // multiplied toward black, rendering dark-on-light fields unreadable.
        let backgroundColor = palette.fieldBackground.resolve(with: palette)

        if isEmpty && !isFocused && prompt != nil {
            return buildPromptContent(palette: palette, background: backgroundColor, width: contentWidth)
        } else if isFocused {
            return buildTextWithCursor(
                text: text,
                cursorPosition: cursorPosition,
                selectionRange: selectionRange,
                palette: palette,
                cursorStyle: cursorStyle,
                cursorTimer: cursorTimer,
                background: backgroundColor,
                width: contentWidth
            )
        } else {
            return buildTextContent(
                text: text,
                palette: palette,
                background: backgroundColor,
                width: contentWidth
            )
        }
    }

    // MARK: - Cell Metrics

    /// The per-character display widths, in terminal cells, for `text`.
    ///
    /// The *display* character decides the width — a `SecureField` bullet is
    /// one cell however wide the hidden character is. Everything that lays the
    /// field out (rendering, horizontal scroll, click-to-caret mapping) must
    /// use these same widths, or a wide character (emoji, CJK) desynchronises
    /// the field's width from its neighbours and its hit regions — the combo
    /// disclosure drifting off its click target was exactly that.
    nonisolated static func displayCellWidths(
        of text: String, displayCharacter: (_ index: Int, _ text: String) -> Character
    ) -> [Int] {
        var widths: [Int] = []
        widths.reserveCapacity(text.count)
        for index in 0..<text.count {
            widths.append(max(1, displayCharacter(index, text).terminalWidth))
        }
        return widths
    }

    /// The horizontal scroll offset, in cells, that keeps the caret visible:
    /// end-anchored, reserving one cell for the caret itself. The inverse
    /// lives in ``TextFieldHandler/characterIndex(forColumn:contentWidth:displayWidths:)``.
    nonisolated static func scrollCells(cursorCellX: Int, width: Int) -> Int {
        max(0, cursorCellX - (max(1, width) - 1))
    }

    // MARK: - Prompt

    /// Builds the prompt content (shown when empty and unfocused).
    private func buildPromptContent(palette: any Palette, background: Color, width: Int) -> String {
        let promptText: String
        if let prompt {
            let buffer = TUIkit.renderToBuffer(prompt, context: RenderContext(availableWidth: 100, availableHeight: 1))
            promptText = buffer.lines.first?.stripped ?? ""
        } else {
            promptText = ""
        }
        // Truncate and pad by CELLS, not characters — a wide glyph in the
        // prompt must not push the field wider than its neighbours.
        let (truncated, cells) = promptText.ansiAwarePrefixWithWidth(visibleCount: width)
        let paddedPrompt = truncated + String(repeating: " ", count: width - cells)
        return ANSIRenderer.colorize(paddedPrompt, foreground: palette.foregroundTertiary, background: background)
    }

    // MARK: - Unfocused Text

    /// Builds text content without cursor (unfocused state), exactly `width`
    /// cells: characters from the front while they fit whole, then padding.
    private func buildTextContent(text: String, palette: any Palette, background: Color, width: Int) -> String {
        var displayText = ""
        var cells = 0
        for index in 0..<text.count {
            let character = displayCharacter(index, text)
            let characterWidth = max(1, character.terminalWidth)
            if cells + characterWidth > width { break }
            displayText.append(character)
            cells += characterWidth
        }
        let paddedText = displayText + String(repeating: " ", count: width - cells)
        let foreground =
            isDisabled ? palette.foregroundTertiary : resolvedContentForeground(palette)
        return ANSIRenderer.colorize(paddedText, foreground: foreground, background: background)
    }

    // MARK: - Focused Text with Cursor

    /// Builds text content with cursor at the specified position (focused state),
    /// exactly `width` cells. Implements horizontal scrolling (in CELLS) to keep
    /// the cursor visible. Selection is highlighted with accent background.
    ///
    /// All layout here is in terminal cells, not characters: a wide display
    /// character (emoji, CJK) occupies its real width, the scroll window is a
    /// cell range, and a wide character straddling either window edge renders
    /// as spaces (it can't be shown half). The block caret is one cell; over a
    /// wide character it covers the first cell and the remainder pads with
    /// spaces, so the caret never changes the field's width.
    private func buildTextWithCursor(
        text: String,
        cursorPosition: Int,
        selectionRange: Range<Int>?,
        palette: any Palette,
        cursorStyle: TextCursorStyle,
        cursorTimer: CursorTimer?,
        background: Color,
        width: Int
    ) -> String {
        let characterCount = text.count
        let clampedPosition = max(0, min(cursorPosition, characterCount))

        // Cell metrics: per-character display widths, the caret's cell x, and
        // the end-anchored scroll window [scrollStart, windowEnd). The click-
        // to-caret inverse of this math lives in TextFieldHandler.
        let widths = Self.displayCellWidths(of: text, displayCharacter: displayCharacter)
        let cursorCellX = widths[0..<clampedPosition].reduce(0, +)
        let scrollStart = Self.scrollCells(cursorCellX: cursorCellX, width: width)
        let windowEnd = scrollStart + width

        // Compute cursor visibility and color based on animation style
        let (cursorVisible, cursorColor) = Self.computeCursorState(
            baseColor: palette.cursorColor,
            animation: cursorStyle.animation,
            speed: cursorStyle.speed,
            cursorTimer: cursorTimer
        )

        // Build output, coalescing consecutive characters that share a colour
        // into ONE ANSI run rather than wrapping each character in its own
        // escape sequence. The per-character form was O(width) `colorize` calls
        // (each an allocation + a full `ESC[…m char ESC[0m`) plus an O(width²)
        // `result +=`; a focused field re-renders every frame for the cursor
        // blink, so this was a render-pass hot spot (~22% of the settings-form
        // profile). The cursor and the selection are the only colour
        // boundaries, so a typical field collapses to a handful of runs. The
        // visible result is identical — just fewer escape sequences.
        // Entered text honours the `.textFieldTextStyle` cascade override; the
        // cursor and selection keep their own colours.
        let textForeground = resolvedContentForeground(palette)
        let selectionBackground = palette.accent.opacity(
            ViewConstants.selectionIndicator, over: background)
        let selectionForeground = palette.readableText(on: selectionBackground)
        var result = ""
        var runText = ""
        var runForeground = textForeground
        var runBackground = background
        var hasRun = false

        func flushRun() {
            guard hasRun else { return }
            result += ANSIRenderer.colorize(runText, foreground: runForeground, background: runBackground)
            runText = ""
            hasRun = false
        }
        func emit(_ piece: Character, foreground: Color, background: Color) {
            if hasRun && (foreground != runForeground || background != runBackground) {
                flushRun()
            }
            if !hasRun {
                runForeground = foreground
                runBackground = background
                hasRun = true
            }
            runText.append(piece)
        }

        // Walks the text in cell space, clipping each element (character or
        // caret) against the scroll window: fully inside → emitted whole;
        // straddling an edge → spaces for the visible part; outside → skipped.
        var cellX = 0
        var outputCells = 0
        func emitClipped(_ character: Character, cells: Int, foreground: Color, background: Color) {
            let start = cellX
            let end = cellX + cells
            cellX = end
            guard end > scrollStart, start < windowEnd else { return }
            if start >= scrollStart && end <= windowEnd {
                emit(character, foreground: foreground, background: background)
                outputCells += cells
            } else {
                let visible = min(end, windowEnd) - max(start, scrollStart)
                for _ in 0..<visible {
                    emit(" ", foreground: foreground, background: background)
                }
                outputCells += visible
            }
        }

        for index in 0..<characterCount {
            if index == clampedPosition && cursorVisible {
                // The caret covers the character's first cell; the remainder of
                // a wide character pads with spaces so nothing after it shifts.
                emitClipped(
                    cursorStyle.shape.character, cells: 1,
                    foreground: cursorColor, background: background)
                if widths[index] > 1 {
                    emitClipped(
                        " ", cells: widths[index] - 1,
                        foreground: textForeground, background: background)
                }
                continue
            }
            // Blink-off at the caret shows the underlying character, styled
            // like its neighbours.
            let char = displayCharacter(index, text)
            let isSelected =
                selectionRange.map { index >= $0.lowerBound && index < $0.upperBound } ?? false
            emitClipped(
                char, cells: widths[index],
                foreground: isSelected ? selectionForeground : textForeground,
                background: isSelected ? selectionBackground : background)
        }
        // The caret past the last character sits on its own cell.
        if clampedPosition == characterCount && cursorVisible {
            emitClipped(
                cursorStyle.shape.character, cells: 1,
                foreground: cursorColor, background: background)
        }
        // Pad to exactly `width` cells.
        while outputCells < width {
            emit(" ", foreground: textForeground, background: background)
            outputCells += 1
        }
        flushRun()

        return result
    }

    // MARK: - Cursor State

    /// Computes the cursor visibility and color based on the animation style
    /// and cursor timer. Shared by every text-input caret (``TextField``,
    /// ``SecureField``, ``TextEditor``) so one `.textCursor(_:)` setting
    /// animates identically across all of them.
    static func computeCursorState(
        baseColor: Color,
        animation: TextCursorStyle.Animation,
        speed: TextCursorStyle.Speed,
        cursorTimer: CursorTimer?
    ) -> (visible: Bool, color: Color) {
        switch animation {
        case .none:
            return (true, baseColor)
        case .blink:
            let visible = cursorTimer?.blinkVisible(for: speed) ?? true
            return (visible, baseColor)
        case .pulse:
            let phase = cursorTimer?.pulsePhase(for: speed) ?? 1.0
            let dimColor = baseColor.opacity(ViewConstants.focusPulseMin)
            let color = Color.lerp(dimColor, baseColor, phase: phase)
            return (true, color)
        }
    }
}
