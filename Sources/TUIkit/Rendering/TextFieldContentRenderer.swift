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

    /// The field's surface, or `nil` for a `.plain` field that draws none.
    /// See ``TextFieldStyle``.
    var surface: Color?

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

    /// A field's rendered line, plus the caret cells the run loop can advance
    /// on its own.
    ///
    /// `caret` is positioned relative to the *content* — column 0 is the first
    /// content cell — so the caller shifts it by whatever chrome it draws
    /// around the field before attaching it to a buffer. It is `nil` when there
    /// is nothing to animate: an unfocused field, or `.textCursor(.none)`.
    struct FieldContent {
        let line: String
        let caret: AnimatedCellRun?

        init(line: String, caret: AnimatedCellRun? = nil) {
            self.line = line
            self.caret = caret
        }
    }

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
    ) -> FieldContent {
        let isEmpty = text.isEmpty
        // The palette's field surface (the tab-strip tone): palette-aware, so
        // light palettes get a light field. The old fixed accent-dim tint
        // multiplied toward black, rendering dark-on-light fields unreadable.
        //
        // `nil` under `.textFieldStyle(.plain)`, and deliberately nil rather
        // than the palette's background: emitting NO background is what lets
        // the text take the colour of whatever is behind the field, the way
        // ordinary text in a tinted container does.
        let backgroundColor = surface

        if isEmpty, prompt != nil {
            // SwiftUI (and AppKit) keep the placeholder visible in a focused
            // empty field — it only disappears once there is something to
            // read. So the focused-and-empty case renders the prompt too, just
            // with the caret sitting on it; only typing displaces it.
            guard isFocused else {
                return FieldContent(
                    line: buildPromptContent(
                        palette: palette, background: backgroundColor, width: contentWidth))
            }
            return buildTextWithCursor(
                text: promptString(),
                cursorPosition: 0,
                selectionRange: nil,
                palette: palette,
                cursorStyle: cursorStyle,
                cursorTimer: cursorTimer,
                background: backgroundColor,
                width: contentWidth,
                foregroundOverride: Self.promptColor(palette: palette, on: backgroundColor),
                displayOverride: { index, text in
                    text[text.index(text.startIndex, offsetBy: index)]
                }
            )
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
            return FieldContent(
                line: buildTextContent(
                    text: text,
                    palette: palette,
                    background: backgroundColor,
                    width: contentWidth
                ))
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

    /// The prompt's plain text, or `""` when there is no prompt.
    private func promptString() -> String {
        guard let prompt else { return "" }
        let buffer = TUIkit.renderToBuffer(prompt, context: RenderContext(availableWidth: 100, availableHeight: 1))
        return buffer.lines.first?.stripped ?? ""
    }

    /// Builds the prompt content for an UNFOCUSED empty field. The focused
    /// case goes through ``buildTextWithCursor`` instead, so the caret draws
    /// over the prompt using the ordinary cursor machinery.
    private func buildPromptContent(palette: any Palette, background: Color?, width: Int) -> String {
        let promptText = promptString()
        // Truncate and pad by CELLS, not characters — a wide glyph in the
        // prompt must not push the field wider than its neighbours.
        let (truncated, cells) = promptText.ansiAwarePrefixWithWidth(visibleCount: width)
        let paddedPrompt = truncated + String(repeating: " ", count: width - cells)
        return ANSIRenderer.colorize(
            paddedPrompt, foreground: Self.promptColor(palette: palette, on: background),
            background: background)
    }

    /// The placeholder's colour, floored against the surface it is drawn on.
    ///
    /// `foregroundTertiary` is derived against the PAGE, and a field is not the
    /// page — it is a surface a step off it, which is the whole point of
    /// ``Palette/liftedBackground``. Taken raw, the prompt kept the contrast it
    /// had somewhere else: on Violet it landed at 1.3:1 against the field it was
    /// actually painted on. The floor is the disabled one, not the label one —
    /// a placeholder is meant to be quieter than real content, just not
    /// invisible.
    private static func promptColor(palette: any Palette, on background: Color?) -> Color {
        let tertiary = palette.foregroundTertiary.resolve(with: palette)
        guard let background else { return tertiary }
        return tertiary.ensuringRenderedContrast(
            atLeast: ViewConstants.disabledLabelContrastFloor, against: background)
    }

    // MARK: - Unfocused Text

    /// Builds text content without cursor (unfocused state), exactly `width`
    /// cells: characters from the front while they fit whole, then padding.
    private func buildTextContent(
        text: String, palette: any Palette, background: Color?, width: Int
    ) -> String {
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
    /// Cell metrics: per-character display widths, and the end-anchored
    /// scroll window [scrollStart, windowEnd) around the caret. The click-
    /// to-caret inverse of this math lives in TextFieldHandler.
    private func scrollWindow(
        text: String, clampedPosition: Int, width: Int
    ) -> (widths: [Int], scrollStart: Int, windowEnd: Int) {
        let widths = Self.displayCellWidths(of: text, displayCharacter: displayCharacter)
        let cursorCellX = widths[0..<clampedPosition].reduce(0, +)
        let scrollStart = Self.scrollCells(cursorCellX: cursorCellX, width: width)
        return (widths, scrollStart, scrollStart + width)
    }

    /// The selection highlight's background and the text colour that reads on
    /// it.
    ///
    /// A blend needs something concrete to blend TOWARD, and a `.plain` field
    /// has no surface to name — so the palette's background stands in. The
    /// selection is an opaque highlight either way; this only decides its
    /// exact tint.
    private static func selectionColors(
        palette: any Palette, background: Color?
    ) -> (background: Color, foreground: Color) {
        let selection = palette.accent.opacity(
            ViewConstants.selectionIndicator, over: background ?? palette.background)
        return (selection, palette.readableText(on: selection))
    }

    private func buildTextWithCursor(
        text: String,
        cursorPosition: Int,
        selectionRange: Range<Int>?,
        palette: any Palette,
        cursorStyle: TextCursorStyle,
        cursorTimer: CursorTimer?,
        background: Color?,
        width: Int,
        foregroundOverride: Color? = nil,
        displayOverride: ((_ index: Int, _ text: String) -> Character)? = nil
    ) -> FieldContent {
        // A SecureField masks its CONTENT, never its prompt — a placeholder
        // rendered as bullets tells the user nothing.
        let displayCharacter = displayOverride ?? self.displayCharacter
        let characterCount = text.count
        let clampedPosition = max(0, min(cursorPosition, characterCount))
        let (widths, scrollStart, windowEnd) = scrollWindow(
            text: text, clampedPosition: clampedPosition, width: width)

        // The whole cycle, not just this tick's frame: the caret's cells are the
        // only thing that changes while a focused field sits still, and
        // re-rendering the screen 20 times a second to blink one cell is what
        // made an idle form cost 41% of a core. See ``CursorCycle``.
        let cycle = Self.computeCursorCycle(
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
        let textForeground = foregroundOverride ?? resolvedContentForeground(palette)
        let (selectionBackground, selectionForeground) = Self.selectionColors(
            palette: palette, background: background)
        var result = ""
        var runText = ""
        var runForeground = textForeground
        var runBackground: Color? = background
        var hasRun = false

        func flushRun() {
            guard hasRun else { return }
            result += ANSIRenderer.colorize(runText, foreground: runForeground, background: runBackground)
            runText = ""
            hasRun = false
        }
        func emit(_ piece: Character, foreground: Color, background: Color?) {
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
        func emitClipped(_ character: Character, cells: Int, foreground: Color, background: Color?) {
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

        // The caret's cells are emitted as their own self-contained styled
        // chunk — including when the blink is OFF, where they used to coalesce
        // with their neighbours. They are handed to the run loop to repaint on
        // a clock, and a frame that leaned on an escape earlier in the line
        // would take its colour from whatever the line happened to look like
        // when it was spliced in. Costs one escape pair; buys the whole cheap
        // animation path. See ``AnimatedCellRun``.
        let colors = CaretColors(
            background: background, blockText: background ?? palette.background,
            text: textForeground, selectionText: selectionForeground,
            selectionBackground: selectionBackground)
        var caret: AnimatedCellRun?

        func emitCaret(cells: Int, underlying: Character, isSelected: Bool) {
            // The scroll window is anchored so the caret is always fully inside
            // it. If that ever stops holding, fall back to the ordinary clipped
            // character rather than leave a run describing cells that are not
            // on screen — a run outliving its cells repaints, on a clock, over
            // whatever took their place.
            guard cellX >= scrollStart, cellX + cells <= windowEnd else {
                emitClipped(
                    underlying, cells: cells,
                    foreground: isSelected ? selectionForeground : textForeground,
                    background: isSelected ? selectionBackground : background)
                return
            }
            let frames = Self.caretFrames(
                cycle, shape: cursorStyle.shape, cells: cells,
                underlying: underlying, isSelected: isSelected, colors: colors)
            flushRun()
            result += frames[cycle.step % frames.count]
            if cycle.isAnimating {
                caret = AnimatedCellRun(
                    offsetX: outputCells, offsetY: 0, width: cells,
                    frames: frames, clock: .cursor)
            }
            (cellX, outputCells) = (cellX + cells, outputCells + cells)
        }

        for index in 0..<characterCount {
            let isSelected = selectionRange.map { index >= $0.lowerBound && index < $0.upperBound } ?? false
            let char = displayCharacter(index, text)
            if index == clampedPosition {
                emitCaret(cells: widths[index], underlying: char, isSelected: isSelected)
                continue
            }
            emitClipped(
                char, cells: widths[index],
                foreground: isSelected ? selectionForeground : textForeground,
                background: isSelected ? selectionBackground : background)
        }
        // The caret past the last character sits on its own cell.
        if clampedPosition == characterCount {
            emitCaret(cells: 1, underlying: " ", isSelected: false)
        }
        // Pad to exactly `width` cells.
        while outputCells < width {
            emit(" ", foreground: textForeground, background: background)
            outputCells += 1
        }
        flushRun()

        return FieldContent(line: result, caret: caret)
    }

    // MARK: - The caret's cells

    /// The four colours the caret picks between, gathered so the frame builder
    /// takes one parameter rather than four.
    struct CaretColors {
        /// The field's surface, or `nil` for a plain field with none — the
        /// caret's own cells then take what is behind the field, exactly as
        /// the rest of the line does.
        let background: Color?

        /// What a BLOCK caret punches its character out in. The surface where
        /// there is one; a plain field still has to name a colour, a block
        /// being opaque by definition, so it takes the palette's background.
        let blockText: Color

        let text: Color
        let selectionText: Color
        let selectionBackground: Color
    }

    /// Every frame of the caret's cycle, ready to hand to the run loop.
    static func caretFrames(
        _ cycle: CursorCycle,
        shape: TextCursorStyle.Shape,
        cells: Int,
        underlying: Character,
        isSelected: Bool,
        colors: CaretColors
    ) -> [String] {
        cycle.states.map {
            caretCells(
                $0, shape: shape, cells: cells,
                underlying: underlying, isSelected: isSelected, colors: colors)
        }
    }

    /// One frame of the caret: its cells, styled, standing alone.
    ///
    /// Keeps the character beneath the caret readable wherever the shape allows:
    /// - `.block`: the character itself, in the field's background colour on a
    ///   caret-coloured block (covering a wide character whole) — explicit
    ///   palette colours, never SGR 7.
    /// - `.underscore`: the character itself, underlined (SGR 4), in the cursor
    ///   colour — universally supported.
    /// - `.bar` (and `.underscore` over a space or a WIDE character, whose
    ///   underline support is poor): the shape's standalone glyph replaces the
    ///   first cell; the remainder of a wide character pads with spaces so
    ///   nothing after it shifts. A bar caret reads as sitting BEFORE the
    ///   character, so it deliberately draws the same left-edge glyph for every
    ///   character — a combining-overlay approach was tried and rejected:
    ///   terminals compose the overlay differently per base glyph, often
    ///   near-invisibly.
    ///
    /// A blink-off frame shows the underlying character styled like its
    /// neighbours, so the cycle covers both halves of a blink and the run loop
    /// needs to know nothing about carets.
    static func caretCells(
        _ state: (visible: Bool, color: Color),
        shape: TextCursorStyle.Shape,
        cells: Int,
        underlying: Character,
        isSelected: Bool,
        colors: CaretColors
    ) -> String {
        guard state.visible else {
            return ANSIRenderer.colorize(
                String(underlying),
                foreground: isSelected ? colors.selectionText : colors.text,
                background: isSelected ? colors.selectionBackground : colors.background)
        }
        switch shape {
        case .block:
            return ANSIRenderer.colorize(
                String(underlying), foreground: colors.blockText, background: state.color)
        case .underscore where cells == 1 && underlying != " ":
            return ANSIRenderer.colorize(
                String(underlying), foreground: state.color, background: colors.background,
                underline: true)
        default:
            let glyph = ANSIRenderer.colorize(
                String(shape.character), foreground: state.color, background: colors.background)
            guard cells > 1 else { return glyph }
            return glyph
                + ANSIRenderer.colorize(
                    String(repeating: " ", count: cells - 1),
                    foreground: colors.text, background: colors.background)
        }
    }

    // MARK: - Cursor State

    /// Computes the cursor visibility and color based on the animation style
    /// and cursor timer. Shared by every text-input caret (``TextField``,
    /// ``SecureField``, ``TextEditor``) so one `.textCursor(_:)` setting
    /// animates identically across all of them.
    /// Every frame of the caret's animation, plus where the clock is now.
    ///
    /// The counterpart to ``computeCursorState(baseColor:animation:speed:cursorTimer:)``,
    /// which is one frame. Building this deliberately does **not** consult the
    /// live clock — each state comes from `CursorTimer`'s static formula — which
    /// is what lets the caret's cells be handed to the run loop and advanced
    /// without rendering. See ``AnimatedCellRun``.
    ///
    /// A focused text field is the most expensive idle control there is: it used
    /// to re-render the whole screen 20 times a second to blink one cell. On the
    /// Example's Forms page that was 41% of a core to emit two writes per second
    /// (`Documentation/Performance-profile-2026-08.md` §9).
    struct CursorCycle {
        /// One caret state per tick of a full cycle.
        let states: [(visible: Bool, color: Color)]

        /// Where the clock is now — the state to draw immediately.
        let step: Int

        /// Whether the caret actually moves. A `.none` animation is one frame:
        /// a still picture the ordinary render already drew.
        var isAnimating: Bool { states.count > 1 }

        /// The state to draw right now.
        var now: (visible: Bool, color: Color) { states[step % states.count] }
    }

    /// The caret's whole cycle, without reading the clock. See ``CursorCycle``.
    static func computeCursorCycle(
        baseColor: Color,
        animation: TextCursorStyle.Animation,
        speed: TextCursorStyle.Speed,
        cursorTimer: CursorTimer?
    ) -> CursorCycle {
        let states = (0..<CursorTimer.cycleTicks(for: speed, animation: animation)).map { tick in
            caretState(atTick: tick, baseColor: baseColor, animation: animation, speed: speed)
        }
        // `elapsedTicks` is a plain read: unlike `blinkVisible(for:)` it does not
        // mark the frame as having consulted the clock, so a producer that uses
        // it stays replayable.
        return CursorCycle(states: states, step: cursorTimer?.elapsedTicks ?? 0)
    }

    /// The caret's visibility and colour at one tick of the cycle, from the
    /// static formulas rather than the live clock.
    private static func caretState(
        atTick tick: Int, baseColor: Color,
        animation: TextCursorStyle.Animation, speed: TextCursorStyle.Speed
    ) -> (visible: Bool, color: Color) {
        switch animation {
        case .none:
            return (true, baseColor)
        case .blink:
            return (CursorTimer.blinkVisible(atTick: tick, speed: speed), baseColor)
        case .pulse:
            let phase = CursorTimer.pulsePhase(atTick: tick, speed: speed)
            return (
                true,
                Color.lerp(baseColor.opacity(ViewConstants.focusPulseMin), baseColor, phase: phase)
            )
        }
    }

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
