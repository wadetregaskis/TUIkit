//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// Maps one character of the text to the character actually drawn — itself
    /// for a `TextField`, a bullet for a `SecureField`.
    ///
    /// Takes the CHARACTER, not its index, and that is not a style preference.
    /// The index form was resolved as `text[text.index(text.startIndex,
    /// offsetBy: index)]`, an O(index) grapheme walk, and three loops call it
    /// once per character — so a field cost O(n²) grapheme steps in its own
    /// text, on every render, plus once per mouse event and so once per drag
    /// motion. Taking the character lets every loop walk the string ONCE,
    /// sequentially, and materialises no array to do it.
    let displayCharacter: (Character) -> Character

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

        /// The cells owing a blend, in the CONTENT's own coordinates — the same
        /// frame ``caret`` is in, so the two callers shift both by the one
        /// `chrome.leadingCells` they already shift the caret by.
        ///
        /// A field's ink is the style cascade's, which an app may have faded
        /// (`.textFieldTextStyle { $0.foreground = .red.opacity(0.5) }`), and its
        /// field surface comes from a palette slot a theme may have faded. Neither
        /// could travel out of here before: `FieldContent` carried a finished line
        /// and a caret, so the alpha had nowhere to ride and was spent on the
        /// escape instead.
        let claims: [OpacityRegion]

        init(line: String, caret: AnimatedCellRun? = nil, claims: [OpacityRegion] = []) {
            self.line = line
            self.caret = caret
            self.claims = claims
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
        cursorTiming: IndicatorCycleTiming? = nil,
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
                return buildPromptContent(
                    palette: palette, background: backgroundColor, width: contentWidth)
            }
            return buildTextWithCursor(
                text: promptString(),
                cursorPosition: 0,
                selectionRange: nil,
                palette: palette,
                cursorStyle: cursorStyle,
                cursorTimer: cursorTimer,
                cursorTiming: cursorTiming,
                background: backgroundColor,
                width: contentWidth,
                foregroundOverride: Self.promptColor(palette: palette, on: backgroundColor),
                // The PROMPT is never masked, so it draws itself even under a
                // secure field's bullet mapping.
                displayOverride: { $0 }
            )
        } else if isFocused {
            return buildTextWithCursor(
                text: text,
                cursorPosition: cursorPosition,
                selectionRange: selectionRange,
                palette: palette,
                cursorStyle: cursorStyle,
                cursorTimer: cursorTimer,
                cursorTiming: cursorTiming,
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

    /// The coalescing accumulator a focused field's cells are written into:
    /// consecutive same-coloured cells become ONE escape run, and each run leaves
    /// behind the claim its colours owe.
    ///
    /// A type rather than six locals and two closures, because it is one thing —
    /// and because the two halves have to agree: the bytes state the OPAQUE
    /// spelling and the claim carries the real alpha, which is the pairing §26.1
    /// describes, and keeping them in one `flush` is what stops them drifting.
    ///
    /// Claims are per RUN rather than one rectangle for the field, because a
    /// focused field's cells genuinely differ: the selection's FIELD is opaque by
    /// construction (`selectionColors` goes through `opacity(_:over:)`), its text is
    /// `readableText(on:)` — a palette slot, floored, carrying that slot's alpha —
    /// and the entered text's are the style cascade's. One rectangle would fade the
    /// highlight along with the text. The run boundaries are already the colour
    /// boundaries — that is what the coalescing is for — so this costs nothing
    /// beyond remembering the column each run opened at.
    ///
    /// Internal rather than private: a `TextEditor`'s rows are written into it too,
    /// for the same reason and with the same out-of-band caret.
    struct RunAccumulator {
        /// The finished line so far.
        private(set) var line = ""

        /// The claims of every run flushed so far, in content coordinates.
        private(set) var claims: [OpacityRegion] = []

        private var text = ""
        private var ink: Color
        private var field: Color?
        private var start = 0
        private var isOpen = false

        init(ink: Color, field: Color?) {
            self.ink = ink
            self.field = field
        }

        /// Closes the open run.
        ///
        /// - Parameter column: The column of the next cell to be written, which is
        ///   what `outputCells` holds at every point a run opens or flushes — the
        ///   same invariant `emitCaret` builds its own run's `offsetX` from.
        mutating func flush(atColumn column: Int) {
            guard isOpen else { return }
            line += ANSIRenderer.colorize(
                text, foreground: ink.opaqueSpelling, background: field?.opaqueSpelling)
            claims +=
                OpacityRegion.claim(
                    offsetX: start, width: column - start, height: 1, ink: ink, field: field)
                .map { [$0] } ?? []
            text = ""
            isOpen = false
        }

        /// Adds one cell, opening a new run where the colours change.
        mutating func append(_ piece: Character, ink: Color, field: Color?, atColumn column: Int) {
            if isOpen, ink != self.ink || field != self.field { flush(atColumn: column) }
            if !isOpen {
                (self.ink, self.field, start, isOpen) = (ink, field, column, true)
            }
            text.append(piece)
        }

        /// Bytes that are not a run: the caret's own self-contained chunk, which is
        /// styled by the frame builder and claims nothing (see ``caretSetup``).
        mutating func appendVerbatim(_ chunk: String) {
            line += chunk
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
        of text: String, displayCharacter: (Character) -> Character
    ) -> [Int] {
        var widths: [Int] = []
        widths.reserveCapacity(text.count)
        for character in text {
            widths.append(max(1, displayCharacter(character).terminalWidth))
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
    private func buildPromptContent(
        palette: any Palette, background: Color?, width: Int
    ) -> FieldContent {
        let promptText = promptString()
        // Truncate and pad by CELLS, not characters — a wide glyph in the
        // prompt must not push the field wider than its neighbours.
        let (truncated, cells) = promptText.ansiAwarePrefixWithWidth(visibleCount: width)
        let paddedPrompt = truncated + String(repeating: " ", count: width - cells)
        let foreground = Self.promptColor(palette: palette, on: background)
        // Not a cascade colour — `promptColor` floors `foregroundTertiary` — so
        // this arm is the second tier: a theme that faded that slot. It claims
        // anyway, and for the same reason the two unfocused arms share their
        // padding rule: they are one field in two states, and a claim on one only
        // would fade a field's text and not its placeholder.
        return FieldContent(
            line: ANSIRenderer.colorize(
                paddedPrompt, foreground: foreground.opaqueSpelling,
                background: background?.opaqueSpelling),
            claims: OpacityRegion.claim(
                width: width, height: 1, ink: foreground, field: background).map { [$0] } ?? [])
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
    ) -> FieldContent {
        var displayText = ""
        var cells = 0
        for source in text {
            let character = displayCharacter(source)
            let characterWidth = max(1, character.terminalWidth)
            if cells + characterWidth > width { break }
            displayText.append(character)
            cells += characterWidth
        }
        let paddedText = displayText + String(repeating: " ", count: width - cells)
        let foreground =
            isDisabled ? palette.foregroundTertiary : resolvedContentForeground(palette)
        // One rectangle, exactly `width` cells, because that is what the padding
        // above guarantees — the whole content field, ink and surface together.
        return FieldContent(
            line: ANSIRenderer.colorize(
                paddedText, foreground: foreground.opaqueSpelling,
                background: background?.opaqueSpelling),
            claims: OpacityRegion.claim(
                width: width, height: 1, ink: foreground, field: background).map { [$0] } ?? [])
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
    static func selectionColors(
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
        cursorTiming: IndicatorCycleTiming? = nil,
        background: Color?,
        width: Int,
        foregroundOverride: Color? = nil,
        displayOverride: ((Character) -> Character)? = nil
    ) -> FieldContent {
        // A SecureField masks its CONTENT, never its prompt — a placeholder
        // rendered as bullets tells the user nothing.
        let displayCharacter = displayOverride ?? self.displayCharacter
        let characterCount = text.count
        let clampedPosition = max(0, min(cursorPosition, characterCount))
        let (widths, scrollStart, windowEnd) = scrollWindow(
            text: text, clampedPosition: clampedPosition, width: width)

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
        var runs = RunAccumulator(ink: textForeground, field: background)
        func flushRun() { runs.flush(atColumn: outputCells) }
        func emit(_ piece: Character, foreground: Color, background: Color?) {
            runs.append(piece, ink: foreground, field: background, atColumn: outputCells)
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
        let (cycle, colors) = Self.caretSetup(
            palette: palette, background: background, textForeground: textForeground,
            selection: (selectionForeground, selectionBackground),
            cursorStyle: cursorStyle, cursorTimer: cursorTimer, timing: cursorTiming)
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
            let drawn = Self.caretFrames(
                cycle, shape: cursorStyle.shape, cells: cells,
                underlying: underlying, isSelected: isSelected, colors: colors)
            flushRun()
            runs.appendVerbatim(drawn.frames[drawn.drawnIndex])
            if cycle.isAnimating {
                caret = AnimatedCellRun(
                    offsetX: outputCells, offsetY: 0, width: cells, frames: drawn.frames,
                    frameDuration: cycle.timing.frameDuration, clock: cycle.timing.clock,
                    alpha: drawn.alpha)
            }
            (cellX, outputCells) = (cellX + cells, outputCells + cells)
        }

        for (index, source) in text.enumerated() {
            let isSelected = selectionRange.map { index >= $0.lowerBound && index < $0.upperBound } ?? false
            let char = displayCharacter(source)
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

        return FieldContent(line: runs.line, caret: caret, claims: runs.claims)
    }

    /// The caret's blink cycle and the five colours its frames pick between —
    /// everything the frames need that does not depend on where the caret landed.
    ///
    /// Its own function because ``buildTextWithCursor`` is at the body-length limit
    /// and this is the one self-contained block in it: nothing here reads the walk's
    /// state, and nothing in the walk changes it.
    ///
    /// **The caret's cells SPEND the ink's alpha instead of claiming it**, and this
    /// is the one place in the field that has to. A caret's frames disagree about
    /// alpha by construction: the blink-OFF frame draws the underlying character in
    /// the text colour, which the cascade may have faded, while the blink-ON frame
    /// draws the caret's own colour, which is opaque. One static region over those
    /// cells would fade the caret glyph along with the character — the §29.2 case
    /// that genuinely wants per-phase alpha, reached by the one control that has a
    /// per-cell animation over app-coloured text.
    ///
    /// Spending is not a *guess* here, unlike the breathing label §29 settles the
    /// same way: a styled field PAINTS its own surface, so `background` is literally
    /// what is behind this ink and compositing over it gives the same answer the
    /// resolver would have given a claim. Only a `.plain` field — which emits no
    /// background at all — falls back to the page, and then only on the cells the
    /// caret occupies while it is visible.
    ///
    /// Static, and shared with `TextEditor`, whose rows draw this same caret.
    static func caretSetup(
        palette: any Palette, background: Color?, textForeground: Color,
        selection: (foreground: Color, background: Color),
        cursorStyle: TextCursorStyle, cursorTimer: CursorTimer?, timing: IndicatorCycleTiming?
    ) -> (cycle: CursorCycle, colors: CaretColors) {
        // The whole cycle, not just this tick's frame: the caret's cells are the
        // only thing that changes while a focused field sits still, and
        // re-rendering the screen 20 times a second to blink one cell is what
        // made an idle form cost 41% of a core. See ``CursorCycle``.
        //
        // `background ?? palette.background` is what the caret is drawn ON: a
        // `.plain` field emits no background, so the caret is over whatever holds
        // the field.
        let ground = background ?? palette.background
        let cycle = Self.computeCursorCycle(
            baseColor: palette.cursorColor, over: ground,
            animation: cursorStyle.animation, speed: cursorStyle.speed,
            cursorTimer: cursorTimer, timing: timing)
        return (
            cycle,
            CaretColors(
                background: background,
                blockText: ground.opaqueSpelling,
                text: textForeground.spendingAlpha(over: ground),
                // Spent over the highlight: the opaque field that is literally behind
                // this ink in the blink-OFF frame, as the ground is behind `text`'s. It
                // is not opaque itself — `readableText(on:)` floors a palette slot and
                // keeps its alpha — so a faded palette's caret on a selected character
                // handed the emitter a translucent colour (§60).
                selectionText: selection.foreground.spendingAlpha(over: selection.background),
                selectionBackground: selection.background)
        )
    }

    // MARK: - The caret's cells

    /// The four colours the caret picks between, gathered so the frame builder
    /// takes one parameter rather than four.
    struct CaretColors {
        /// The field's surface, or `nil` for a plain field with none — the
        /// caret's own cells then take what is behind the field, exactly as
        /// the rest of the line does.
        ///
        /// As AUTHORED, alpha intact. ``caretCells(_:shape:cells:underlying:isSelected:colors:)``
        /// spells it opaque where it paints it and reports the alpha back, so the bytes
        /// and the claim beside them come from the one colour. It used to be stored
        /// already spelled, which is where a faded well's alpha was lost (§61.2).
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
    ) -> Caret {
        let drawn = cycle.states.map {
            caretCells(
                $0, shape: shape, cells: cells,
                underlying: underlying, isSelected: isSelected, colors: colors)
        }
        // One span per frame, the whole caret wide, because a caret paints its cells in
        // ONE field per frame — a block shows its own opaque colour, every other frame
        // shows the well. The ink never owes anything: every foreground the caret can
        // paint is spent or opaque already (§60, §29.3), which is why this is a field
        // statement and not a pair.
        let perFrame = drawn.map { frame in
            frame.fieldAlpha < 1
                ? [AnimatedRunAlpha.Span(start: 0, cells: cells, field: frame.fieldAlpha)]
                : []
        }
        let step = cycle.states.isEmpty ? 0 : cycle.step % cycle.states.count
        return Caret(
            frames: drawn.map(\.cells),
            drawnIndex: step < 0 ? step + cycle.states.count : step,
            alpha: perFrame.contains(where: { !$0.isEmpty })
                ? AnimatedRunAlpha(
                    perFrame: perFrame,
                    drawnIndex: step < 0 ? step + cycle.states.count : step)
                : nil)
    }

    /// A caret's cycle, the frame the render is drawing, and what its cells owe.
    ///
    /// The index comes back with the frames rather than being recomputed at each call
    /// site: the buffer's own line is drawn at it AND ``AnimatedRunAlpha/drawnIndex``
    /// is it, and two spellings of one modulo is exactly how those come apart.
    struct Caret {
        let frames: [String]
        let drawnIndex: Int
        let alpha: AnimatedRunAlpha?
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
    ) -> (cells: String, fieldAlpha: Double) {
        // The FIELD each arm paints, reported beside the bytes so the two cannot
        // disagree about which colour this frame actually put down. A caret's frames
        // disagree about it — a block shows its own opaque colour where the blink-off
        // frame shows a translucent well — which is why no one rectangle can describe
        // the cell and the alpha rides on the run instead (``AnimatedRunAlpha``).
        func owed(_ colour: Color?) -> Double {
            colour.map { OpacityRegion.opacity(of: $0.alpha) } ?? 1
        }
        guard state.visible else {
            let field = isSelected ? colors.selectionBackground : colors.background
            return (
                ANSIRenderer.colorize(
                    String(underlying),
                    foreground: isSelected ? colors.selectionText : colors.text,
                    background: field?.opaqueSpelling),
                owed(field))
        }
        switch shape {
        case .block:
            // Floored against the caret's CURRENT colour, per frame: the block
            // is the cursor's colour and the character is punched out of it, so
            // a palette whose caret sits near its own "text on the caret" tone
            // drew the character invisibly — and the caret pulses, so the pair
            // has to be judged at the shade actually being drawn, not once.
            // The block is the caret's OWN colour, opaque by §29.3, so this frame's
            // cells owe nothing whatever the well beneath them is.
            return (
                ANSIRenderer.colorize(
                    String(underlying),
                    foreground: colors.blockText.ensuringRenderedContrast(
                        atLeast: ViewConstants.labelContrastFloor, against: state.color),
                    background: state.color),
                owed(state.color))
        case .underscore where cells == 1 && underlying != " ":
            return (
                ANSIRenderer.colorize(
                    String(underlying), foreground: state.color,
                    background: colors.background?.opaqueSpelling,
                    underline: true),
                owed(colors.background))
        default:
            let glyph = ANSIRenderer.colorize(
                String(shape.character), foreground: state.color,
                background: colors.background?.opaqueSpelling)
            guard cells > 1 else { return (glyph, owed(colors.background)) }
            return (
                glyph
                    + ANSIRenderer.colorize(
                        String(repeating: " ", count: cells - 1),
                        foreground: colors.text,
                        background: colors.background?.opaqueSpelling),
                owed(colors.background))
        }
    }

    // MARK: - Cursor State

    /// Every frame of the caret's animation, plus where the clock is now.
    ///
    /// Shared by every text-input caret (``TextField``, ``SecureField``,
    /// ``TextEditor``) so one `.textCursor(_:)` setting animates identically
    /// across all of them.
    ///
    /// Building this deliberately does **not** consult the live clock — each
    /// state comes from `CursorTimer`'s static formula — which is what lets the
    /// caret's cells be handed to the run loop and advanced without rendering.
    /// See ``AnimatedCellRun``. There is no this-tick-only counterpart: one
    /// existed, `TextEditor` was its last caller, and keeping it meant a caret
    /// that read the clock and so re-rendered the whole screen 20 times a
    /// second to blink one cell.
    ///
    /// A focused text field is the most expensive idle control there is: it used
    /// to re-render the whole screen 20 times a second to blink one cell. On the
    /// Example's Forms page that was 41% of a core to emit two writes per second
    /// (`Documentation/Performance-profile-2026-08.md` §9).
    struct CursorCycle {
        /// One caret state per frame of a full cycle.
        let states: [(visible: Bool, color: Color)]

        /// Where the clock is now — the state to draw immediately.
        let step: Int

        /// How long each state is shown, and the clock `step` is counted on: what the
        /// caret's run is built with.
        let timing: IndicatorCycleTiming

        /// Whether the caret actually moves. A `.none` animation is one frame:
        /// a still picture the ordinary render already drew.
        var isAnimating: Bool { states.count > 1 }

        /// The state to draw right now.
        var now: (visible: Bool, color: Color) { states[step % states.count] }
    }

    /// The caret's whole cycle, without reading the clock. See ``CursorCycle``.
    static func computeCursorCycle(
        baseColor: Color,
        over surface: Color,
        animation: TextCursorStyle.Animation,
        speed: TextCursorStyle.Speed,
        cursorTimer: CursorTimer?,
        timing forced: IndicatorCycleTiming? = nil
    ) -> CursorCycle {
        let layout = CursorTimer.cycleLayout(of: animation, speed: speed)
        let states = (0..<layout.frameCount).map { frame in
            caretState(
                atFrame: frame, of: layout.frameCount, baseColor: baseColor, over: surface,
                animation: animation)
        }
        // A test may force the timing; nothing else sets it.
        let timing = forced ?? layout.timing
        // `step(on:)` is a plain read: unlike `blinkVisible(for:)` it does not mark
        // the frame as having consulted the clock, so a producer that uses it stays
        // replayable.
        return CursorCycle(states: states, step: timing.step(on: cursorTimer), timing: timing)
    }

    /// The caret's visibility and colour at one frame of a cycle of `frameCount`,
    /// from the static formulas rather than the live clock.
    private static func caretState(
        atFrame frame: Int, of frameCount: Int, baseColor: Color, over surface: Color,
        animation: TextCursorStyle.Animation
    ) -> (visible: Bool, color: Color) {
        switch animation {
        case .none:
            return (true, baseColor.spendingAlpha(over: surface))
        case .blink:
            return (
                CursorTimer.blinkVisible(atFrame: frame),
                baseColor.spendingAlpha(over: surface)
            )
        case .pulse:
            let phase = CursorTimer.pulsePhase(atFrame: frame, of: frameCount)
            // Blended toward the field, not toward black. Bare `opacity` fades
            // to black, which on a light palette makes the dim end of the
            // pulse a DARKER mark than the bright end rather than a fainter
            // one — the caret thickens as it "fades".
            //
            // Through `Color.breathEnds`, so BOTH ends spend a translucent cursor
            // colour's alpha against the field — the fifth copy of §29's pair, and
            // the last. `palette.cursorColor` defaults to the accent, so
            // `.tint(.red.opacity(0.5))` on a text field lerped an opaque dim end
            // toward a translucent bright one and produced a caret at alpha 139 at
            // mid-phase: neither carried nor spent, and straight into the emitter.
            let ends = baseColor.breathEnds(
                dimmedTo: ViewConstants.focusPulseMin, over: surface)
            return (true, Color.lerp(ends.dim, ends.bright, phase: phase))
        }
    }
}
