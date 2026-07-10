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
        handler.clampCursor()

        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        let displayLines = lines(of: text.wrappedValue)

        // When the text is taller than the view, reserve the trailing column for
        // a scroll indicator so the user can see there's content out of view —
        // the total width is unchanged, so measure == render still holds.
        let hasVerticalOverflow = displayLines.count > height
        let contentWidth = hasVerticalOverflow ? max(1, width - 1) : width

        // Follow the cursor. This mutates persistent scroll state, so it is
        // gated on the render pass — never during measuring.
        if !context.isMeasuring {
            followCursor(handler, lineCount: displayLines.count, width: contentWidth, height: height)
        }

        // A subtle field background so the editor reads as a text field (like
        // TextField's chrome) rather than plain text — no full box. Opt into the
        // boxed look with `.border()`.
        let fieldBackground: Color? = isDisabled
            ? nil
            : palette.accent.opacity(ViewConstants.focusBorderDim)

        var output: [String] = []
        output.reserveCapacity(height)
        for row in 0..<height {
            let lineIndex = handler.scrollLine + row
            guard lineIndex < displayLines.count else {
                output.append(emptyRow(width: contentWidth, background: fieldBackground, palette: palette))
                continue
            }
            let cursorColumn = (isFocused && lineIndex == handler.cursorLine) ? handler.cursorColumn : nil
            let selection =
                isFocused
                ? handler.selectedColumns(inLine: lineIndex, lineLength: displayLines[lineIndex].count)
                : nil
            output.append(
                styledRow(
                    displayLines[lineIndex], scrollColumn: handler.scrollColumn, width: contentWidth,
                    cursorColumn: cursorColumn, selection: selection, palette: palette,
                    isDisabled: isDisabled, background: fieldBackground))
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
    private func followCursor(_ handler: TextEditorHandler, lineCount: Int, width: Int, height: Int) {
        if handler.cursorLine < handler.scrollLine {
            handler.scrollLine = handler.cursorLine
        } else if handler.cursorLine >= handler.scrollLine + height {
            handler.scrollLine = handler.cursorLine - height + 1
        }
        handler.scrollLine = max(0, min(handler.scrollLine, max(0, lineCount - height)))

        if handler.cursorColumn < handler.scrollColumn {
            handler.scrollColumn = handler.cursorColumn
        } else if handler.cursorColumn >= handler.scrollColumn + width {
            handler.scrollColumn = handler.cursorColumn - width + 1
        }
        handler.scrollColumn = max(0, handler.scrollColumn)
    }

    /// Renders one visible row: the line clipped to `[scrollColumn, +width)`,
    /// padded to `width`. Selected cells (columns in `selection`) get a palette
    /// highlight and the cursor cell a block caret — both set explicit palette
    /// colours rather than SGR 7 reverse-video (which inverts the terminal's
    /// *default* colours and collapses to dark-on-dark on a mid-tone palette).
    /// Consecutive cells that share a colour coalesce into one ANSI run.
    private func styledRow(
        _ chars: [Character], scrollColumn: Int, width: Int,
        cursorColumn: Int?, selection: Range<Int>?,
        palette: any Palette, isDisabled: Bool, background: Color?
    ) -> String {
        let start = scrollColumn
        let end = min(chars.count, scrollColumn + width)
        var visible: [Character] = start < end ? Array(chars[start..<end]) : []
        while visible.count < width { visible.append(" ") }

        let textForeground = isDisabled ? palette.foregroundTertiary : palette.foreground
        let selectionForeground = palette.background
        let selectionBackground = palette.accent.opacity(ViewConstants.selectionIndicator)
        let cursorCell = cursorColumn.map { $0 - scrollColumn }

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

        for cell in 0..<width {
            let column = scrollColumn + cell
            if cell == cursorCell {
                // Block caret: glyph in the background colour on a
                // foreground-coloured block.
                emit(visible[cell], foreground: palette.background, background: palette.foreground)
            } else if let selection, selection.contains(column) {
                emit(visible[cell], foreground: selectionForeground, background: selectionBackground)
            } else {
                emit(visible[cell], foreground: textForeground, background: background)
            }
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
        // column (when present) clamps into the last content column.
        func placeCursor(at event: MouseEvent) {
            let row = max(0, min(event.y, height - 1))
            let column = max(0, min(event.x, contentWidth))
            handler.moveCursor(toLine: handler.scrollLine + row, column: handler.scrollColumn + column)
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
