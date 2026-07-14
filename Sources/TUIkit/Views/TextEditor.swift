//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextEditor.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - TextEditor

/// A control for editing multi-line text, mirroring SwiftUI's `TextEditor`.
///
/// It fills the space it is given and edits the bound string in place. When
/// focused it shows a block cursor. The key bindings follow the macOS text
/// system (Cocoa's `StandardKeyBinding.dict`), so the usual navigation,
/// Emacs-style control chords, and word-wise Option chords all apply:
///
/// | Key | Action |
/// |-----|--------|
/// | Any printable | Insert at the cursor |
/// | Enter | Split the line (insert a newline) |
/// | Backspace / Delete | Delete before / at the cursor (join lines at edges) |
/// | Left / Right | Move by a character, wrapping across lines |
/// | Up / Down | Move by a line, keeping the column where possible |
/// | Home / End | Start / end of the whole field (the document) |
/// | Page Up / Down | Move a screenful up / down |
/// | Ctrl-A / Ctrl-E | Start / end of the current line |
/// | Ctrl-B / Ctrl-F | Back / forward one character |
/// | Ctrl-P / Ctrl-N | Previous / next line |
/// | Ctrl-D | Delete forward |
/// | Ctrl-K | Kill to end of line (yank with Ctrl-Y) |
/// | Ctrl-Y | Yank the last kill |
/// | Ctrl-T | Transpose the two characters around the cursor |
/// | Ctrl-O | Open a new line after the cursor |
/// | Ctrl-V | Page down |
/// | Option-← / → | Move by a word |
/// | Option-B / F | Move by a word (Emacs) |
/// | Option-Backspace / Delete | Delete the word before / after the cursor |
/// | Option-Tab | Insert a literal tab (plain Tab moves focus) |
///
/// Literal tabs are laid out against tab *stops* — by default every 4 columns
/// (a tab advances to the next multiple of 4, so its visual width varies),
/// matching how the macOS text system, terminals and code editors treat tabs.
/// Configure the interval, or switch to a constant advance, for a subtree with
/// ``SwiftUICore/View/tabWidth(_:)``:
///
/// ```swift
/// TextEditor(text: $source)
///     .tabWidth(.periodic(8))   // classic terminal stops
/// // or .tabWidth(.fixed(2))    // every tab exactly two cells
/// ```
///
/// > Note: Option chords require the terminal to *send* Option as Meta
/// > (`ESC` + key). Terminal.app ships with **Use Option as Meta Key**
/// > disabled — enable it in Settings → Profiles → Keyboard (iTerm2: set the
/// > Option key to "Esc+"). Without it the terminal sends the plain key —
/// > Option-Tab arrives byte-identical to Tab, so focus moves; TUIkit never
/// > sees the modifier.
///
/// ```swift
/// @State private var notes = ""
/// TextEditor(text: $notes)
///     .frame(height: 6)
/// ```
///
/// It renders with a subtle field background by default so it reads as a text
/// field (like ``TextField``), not a box; add `.border()` for a boxed look. A
/// vertical scroll indicator appears in the trailing column when the text is
/// taller than the view, so it's clear there's content out of view.
///
/// > Note: Long lines are **not** wrapped — the view scrolls horizontally to
/// > follow the cursor (a common terminal-editor behaviour), and vertically when
/// > the text is taller than the view. Soft word-wrap is a possible future
/// > option.
public struct TextEditor: View {
    let text: Binding<String>
    var focusID: String?
    var isDisabled: Bool

    /// Creates a text editor over a string binding.
    ///
    /// - Parameter text: The multi-line text to edit.
    public init(text: Binding<String>) {
        self.text = text
        self.focusID = nil
        self.isDisabled = false
    }

    public var body: some View {
        _TextEditorCore(text: text, focusID: focusID, isDisabled: isDisabled)
    }
}

// MARK: - Modifiers

extension TextEditor {
    /// Disables editing.
    public func disabled(_ disabled: Bool = true) -> TextEditor {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier.
    public func focusID(_ id: String) -> TextEditor {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core

private enum TextEditorStateIndex {
    static let handler = 0
    static let focusID = 1
}

/// Renders the editor: a windowed view of the text with a block cursor,
/// scrolling to follow the cursor. Greedy on both axes.
private struct _TextEditorCore: View, Renderable, Layoutable {
    let text: Binding<String>
    let focusID: String?
    let isDisabled: Bool

    private typealias StateIndex = TextEditorStateIndex

    var body: Never {
        fatalError("_TextEditorCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let width = proposal.width ?? context.availableWidth
        let contentHeight = max(1, lines(of: text.wrappedValue).count)
        let height = proposal.height ?? min(contentHeight, max(1, context.availableHeight))
        return ViewSize(width: width, height: height, isWidthFlexible: true, isHeightFlexible: true)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.environment.stateStorage!
        let width = max(1, context.availableWidth)
        let height = max(1, context.availableHeight)

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "texteditor", propertyIndex: StateIndex.focusID)

        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<TextEditorHandler> = stateStorage.storage(
            for: handlerKey,
            default: TextEditorHandler(
                focusID: persistedFocusID, text: text, canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.text = text
        handler.canBeFocused = !isDisabled
        handler.viewportHeight = height
        // Synced each render so the handler's vertical motion preserves the
        // same *visual* column the renderer draws the caret at.
        let tabWidth = context.environment.tabWidth
        handler.tabWidth = tabWidth
        handler.clampCursor()

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let displayLines = lines(of: text.wrappedValue)

        // When the text is taller than the view, reserve the trailing column for
        // a scroll indicator so the user can see there's content out of view —
        // the total width is unchanged, so measure == render still holds.
        let hasVerticalOverflow = displayLines.count > height
        let contentWidth = hasVerticalOverflow ? max(1, width - 1) : width

        // Follow the cursor — in DISPLAY columns, since that's the space the
        // scroll window and the caret cell live in (a tab makes the display
        // column run ahead of the character index). Mutates persistent scroll
        // state, so it is gated on the render pass — never during measuring.
        let cursorDisplayColumn = TabLayout.displayColumn(
            ofCharIndex: handler.cursorColumn,
            in: displayLines[min(handler.cursorLine, displayLines.count - 1)],
            tabWidth: tabWidth)
        if !context.isMeasuring {
            followCursor(
                handler, cursorDisplayColumn: cursorDisplayColumn,
                lineCount: displayLines.count, width: contentWidth, height: height)
        }

        // A subtle field background so the editor reads as a text field (like
        // TextField's chrome) rather than plain text — no full box. Opt into the
        // boxed look with `.border()`. The palette's field surface keeps it
        // readable on light and dark palettes alike (the old fixed accent-dim
        // tint multiplied toward black — dark grey behind black text on Basic).
        let fieldBackground: Color? = isDisabled
            ? nil
            : palette.fieldBackground.resolve(with: palette)

        // The caret honours `.textCursor(_:)` exactly like TextField: same
        // shape, same blink/pulse animation, same speed — one setting styles
        // every text input. Computed only while focused: the cursor timer is
        // demand-driven (it keeps ticking only while a frame READS it), so an
        // unfocused editor must not consult it and pin the animation clock.
        let caret: CaretAppearance
        if isFocused {
            let cursorStyle = context.environment.textCursorStyle
            let cursorState = TextFieldContentRenderer.computeCursorState(
                baseColor: palette.cursorColor,
                animation: cursorStyle.animation,
                speed: cursorStyle.speed,
                cursorTimer: context.environment.cursorTimer)
            caret = CaretAppearance(
                shape: cursorStyle.shape, visible: cursorState.visible, color: cursorState.color)
        } else {
            caret = CaretAppearance(shape: .block, visible: false, color: palette.cursorColor)
        }

        var output: [String] = []
        output.reserveCapacity(height)
        for row in 0..<height {
            let lineIndex = handler.scrollLine + row
            guard lineIndex < displayLines.count else {
                output.append(emptyRow(width: contentWidth, background: fieldBackground, palette: palette))
                continue
            }
            let lineChars = displayLines[lineIndex]
            let rowCaret: RowCaret? =
                (isFocused && lineIndex == handler.cursorLine)
                ? RowCaret(column: cursorDisplayColumn, appearance: caret) : nil
            // The handler's selection is character-indexed; the row is painted
            // in display cells, so convert the bounds (a char range maps to a
            // contiguous display range — expansion is monotonic — and a
            // selected tab highlights its whole span, as in any editor).
            let selection: Range<Int>? = isFocused
                ? handler.selectedColumns(inLine: lineIndex, lineLength: lineChars.count).map { range in
                    TabLayout.displayColumn(ofCharIndex: range.lowerBound, in: lineChars, tabWidth: tabWidth)
                        ..< TabLayout.displayColumn(ofCharIndex: range.upperBound, in: lineChars, tabWidth: tabWidth)
                }
                : nil
            output.append(
                styledRow(
                    lineChars, tabWidth: tabWidth,
                    scrollColumn: handler.scrollColumn, width: contentWidth,
                    caret: rowCaret, selection: selection,
                    palette: palette, isDisabled: isDisabled, background: fieldBackground))
        }

        if hasVerticalOverflow {
            appendScrollbar(
                to: &output, height: height, extent: displayLines.count,
                offset: handler.scrollLine, isFocused: isFocused, palette: palette)
        }

        var buffer = FrameBuffer(lines: output)
        registerMouse(
            context: context, buffer: &buffer, handler: handler,
            contentWidth: contentWidth, height: height,
            focusID: persistedFocusID, isDisabled: isDisabled)
        return buffer
    }

    /// Appends a one-column vertical scroll indicator to each row.
    private func appendScrollbar(
        to output: inout [String], height: Int, extent: Int, offset: Int,
        isFocused: Bool, palette: any Palette
    ) {
        let bar = ScrollbarRenderer.verticalScrollbar(
            height: height, extent: extent, viewport: height, offset: offset,
            arrows: .none, proportional: true,
            colors: ScrollbarColors(
                thumb: isFocused ? palette.accent : palette.foregroundSecondary,
                track: palette.foregroundQuaternary,
                arrow: palette.foregroundTertiary))
        for index in 0..<min(height, output.count) {
            output[index] += index < bar.count ? bar[index] : " "
        }
    }

    /// A blank row filled to `width`, painted with the field background.
    private func emptyRow(width: Int, background: Color?, palette: any Palette) -> String {
        guard let background else { return String(asciiSpaces(width)) }
        var style = TextStyle()
        style.backgroundColor = background
        return ANSIRenderer.render(String(asciiSpaces(width)), with: style.resolved(with: palette))
    }

    // MARK: - Helpers

    /// Splits a string into per-line character arrays (always ≥ 1 line).
    private func lines(of string: String) -> [[Character]] {
        let parts = string.split(separator: "\n", omittingEmptySubsequences: false).map { Array($0) }
        return parts.isEmpty ? [[]] : parts
    }

    /// Advances the handler's scroll offsets so the cursor stays visible.
    /// Horizontal scrolling is in display columns (`cursorDisplayColumn` —
    /// the caret's on-screen cell, which runs ahead of the character index
    /// on tab-bearing lines).
    private func followCursor(
        _ handler: TextEditorHandler, cursorDisplayColumn: Int,
        lineCount: Int, width: Int, height: Int
    ) {
        if handler.cursorLine < handler.scrollLine {
            handler.scrollLine = handler.cursorLine
        } else if handler.cursorLine >= handler.scrollLine + height {
            handler.scrollLine = handler.cursorLine - height + 1
        }
        handler.scrollLine = max(0, min(handler.scrollLine, max(0, lineCount - height)))

        if cursorDisplayColumn < handler.scrollColumn {
            handler.scrollColumn = cursorDisplayColumn
        } else if cursorDisplayColumn >= handler.scrollColumn + width {
            handler.scrollColumn = cursorDisplayColumn - width + 1
        }
        handler.scrollColumn = max(0, handler.scrollColumn)
    }

    /// Renders one visible row: the line clipped to the cell window
    /// `[scrollColumn, +width)`, padded to exactly `width` cells. Selected
    /// spans (display columns in `selection`) get a palette highlight and the
    /// cursor cell a caret — both set explicit palette colours rather than
    /// SGR 7 reverse-video (which inverts the terminal's *default* colours
    /// and collapses to dark-on-dark on a mid-tone palette). Consecutive
    /// cells that share a colour coalesce into one ANSI run.
    ///
    /// The walk is in terminal CELLS over the line's characters — the same
    /// model as ``TextFieldContentRenderer``: a tab spans to its stop, a wide
    /// character (emoji, CJK) spans its real width, and an element straddling
    /// either window edge renders as spaces for its visible cells (it can't
    /// be shown half), so the row is always exactly `width` cells.
    /// The caret's resolved per-frame appearance: the configured shape plus
    /// the animation's current visibility/colour (see
    /// ``TextFieldContentRenderer/computeCursorState(baseColor:animation:speed:cursorTimer:)``).
    private struct CaretAppearance {
        let shape: TextCursorStyle.Shape
        let visible: Bool
        let color: Color
    }

    /// The caret as one row sees it: its display column plus the per-frame
    /// appearance. `nil` for rows the caret isn't on.
    private struct RowCaret {
        let column: Int
        let appearance: CaretAppearance
    }

    // The row walk is one coherent cell-clipping pass; splitting it would
    // scatter the window arithmetic its closures share.
    // swiftlint:disable:next function_body_length
    private func styledRow(
        _ chars: [Character], tabWidth: TabWidth, scrollColumn: Int, width: Int,
        caret: RowCaret?, selection: Range<Int>?,
        palette: any Palette, isDisabled: Bool, background: Color?
    ) -> String {
        let windowStart = scrollColumn
        let windowEnd = scrollColumn + width

        let textForeground = isDisabled ? palette.foregroundTertiary : palette.foreground
        let selectionBackground = palette.accent.opacity(
            ViewConstants.selectionIndicator, over: background ?? palette.background)
        let selectionForeground = palette.readableText(on: selectionBackground)

        var result = ""
        var runText = ""
        var runForeground = textForeground
        var runBackground = background
        var hasRun = false

        func flush() {
            guard hasRun else { return }
            var style = TextStyle()
            style.foregroundColor = runForeground
            style.backgroundColor = runBackground
            result += ANSIRenderer.render(runText, with: style.resolved(with: palette))
            runText = ""
            hasRun = false
        }
        func emit(_ character: Character, foreground: Color, background: Color?) {
            if hasRun, foreground != runForeground || background != runBackground {
                flush()
            }
            if !hasRun {
                runForeground = foreground
                runBackground = background
                hasRun = true
            }
            runText.append(character)
        }

        // Walks the line in cell space, clipping each element against the
        // window: fully inside → emitted whole; straddling an edge → spaces
        // for its visible cells; outside → skipped.
        var cellX = 0
        var outputCells = 0
        func emitClipped(_ character: Character, cells: Int, foreground: Color, background: Color?) {
            let start = cellX
            let end = cellX + cells
            cellX = end
            guard end > windowStart, start < windowEnd else { return }
            if start >= windowStart, end <= windowEnd {
                emit(character, foreground: foreground, background: background)
                outputCells += cells
            } else {
                let visible = min(end, windowEnd) - max(start, windowStart)
                for _ in 0..<visible {
                    emit(" ", foreground: foreground, background: background)
                }
                outputCells += visible
            }
        }

        // Draws the caret over a character spanning `cells`:
        // - `.block`: the character itself, in the field's background colour
        //   on a caret-coloured block (covering a wide character whole) —
        //   explicit palette colours, never SGR 7.
        // - `.underscore` over a single-cell non-space: the character itself,
        //   underlined, in the caret colour.
        // - `.bar` (and `.underscore` over a space or a WIDE character,
        //   whose underline support is poor): the shape's standalone glyph
        //   replaces the first cell; the remainder pads with spaces so
        //   nothing after it shifts. A bar caret reads as sitting BEFORE the
        //   character, so it deliberately draws the same left-edge glyph for
        //   every character — a combining-overlay approach was tried and
        //   rejected: terminals compose the overlay differently per base
        //   glyph, often near-invisibly.
        func emitCaret(_ underlying: Character, cells: Int, appearance: CaretAppearance) {
            switch appearance.shape {
            case .block:
                emitClipped(
                    underlying, cells: cells,
                    foreground: palette.background, background: appearance.color)
            case .underscore where cells == 1 && underlying != " ":
                flush()
                var style = TextStyle()
                style.foregroundColor = appearance.color
                style.backgroundColor = background
                style.isUnderlined = true
                result += ANSIRenderer.render(
                    String(underlying), with: style.resolved(with: palette))
                cellX += 1
                outputCells += 1
            case .bar, .underscore:
                emitClipped(
                    appearance.shape.character, cells: 1,
                    foreground: appearance.color, background: background)
                if cells > 1 {
                    emitClipped(
                        " ", cells: cells - 1,
                        foreground: textForeground, background: background)
                }
            }
        }

        for character in chars {
            let cells = TabLayout.advance(from: cellX, over: character, tabWidth: tabWidth) - cellX
            // The caret sits at a character's start cell (its column is
            // derived from a character index), so at most one element
            // matches. Blink-off falls through to normal rendering.
            if let caret, caret.appearance.visible, caret.column == cellX {
                if character == "\t" {
                    // Caret on a tab: the caret occupies the stop run's first
                    // cell, the rest of the run pads.
                    emitCaret(" ", cells: 1, appearance: caret.appearance)
                    if cells > 1 {
                        emitClipped(
                            " ", cells: cells - 1,
                            foreground: textForeground, background: background)
                    }
                } else {
                    emitCaret(character, cells: cells, appearance: caret.appearance)
                }
                continue
            }
            let isSelected = selection.map { $0.contains(cellX) } ?? false
            let foreground = isSelected ? selectionForeground : textForeground
            let cellBackground = isSelected ? selectionBackground : background
            if character == "\t" {
                // A tab is its stop run of spaces — emitted cell by cell so
                // the window clips it naturally (and a selected tab
                // highlights its whole span, as in any editor).
                for _ in 0..<cells {
                    emitClipped(" ", cells: 1, foreground: foreground, background: cellBackground)
                }
            } else {
                emitClipped(character, cells: cells, foreground: foreground, background: cellBackground)
            }
        }
        // The caret past the last character sits on its own cell.
        if let caret, caret.appearance.visible, caret.column == cellX {
            emitCaret(" ", cells: 1, appearance: caret.appearance)
        }
        // Pad to exactly `width` cells.
        while outputCells < width {
            emit(" ", foreground: textForeground, background: background)
            outputCells += 1
        }
        flush()
        return result
    }

    /// A single wide region: a left-click focuses the editor and drops the
    /// caret at the clicked line/column (mapping the click through the current
    /// scroll offsets), and dragging extends a selection from the press point.
    /// Shift-click extends the existing selection instead of starting a new one.
    private func registerMouse(
        context: RenderContext, buffer: inout FrameBuffer, handler: TextEditorHandler,
        contentWidth: Int, height: Int, focusID: String, isDisabled: Bool
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        // Drag reporting is needed for click-and-drag selection.
        mouseDispatcher.requestFeature(.drag)
        let focusManager = context.environment.focusManager

        // Map a buffer-local (x, y) to a text position through the scroll
        // offsets in effect for the displayed frame. The trailing scrollbar
        // column (when present) clamps into the last content column. The click
        // lands in DISPLAY space; the handler's cursor is a character index,
        // so translate through the clicked line's tab layout (a click anywhere
        // in a tab's span puts the caret on the tab).
        let tabWidth = context.environment.tabWidth
        let text = self.text
        func placeCursor(at event: MouseEvent) {
            let row = max(0, min(event.y, height - 1))
            let displayColumn = handler.scrollColumn + max(0, min(event.x, contentWidth))
            let line = handler.scrollLine + row
            let allLines = text.wrappedValue
                .split(separator: "\n", omittingEmptySubsequences: false).map { Array($0) }
            let lineChars = allLines.indices.contains(line) ? allLines[line] : []
            let column = TabLayout.charIndex(
                forDisplayColumn: displayColumn, in: lineChars, tabWidth: tabWidth)
            handler.moveCursor(toLine: line, column: column)
        }

        let handlerID = mouseDispatcher.register { event in
            switch event.phase {
            case .pressed where event.button == .left:
                focusManager?.focus(id: focusID)
                if event.shift {
                    handler.startOrExtendSelection()
                    placeCursor(at: event)
                } else {
                    // Plain click: place the caret and drop any selection. Do
                    // NOT anchor here — a collapsed anchor (anchor == cursor)
                    // shows no highlight but survives into a phantom one-char
                    // selection on the next arrow key. A drag anchors itself on
                    // its first .dragged event (startOrExtendSelection below).
                    placeCursor(at: event)
                    handler.clearSelection()
                }
                return true
            case .dragged:
                handler.startOrExtendSelection()
                placeCursor(at: event)
                return true
            case .released where event.button == .left:
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.height,
                handlerID: handlerID, focusID: focusID))
    }
}
