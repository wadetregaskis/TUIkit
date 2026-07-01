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
///
/// ```swift
/// @State private var notes = ""
/// TextEditor(text: $notes)
///     .frame(height: 6)
/// ```
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

        // Follow the cursor. This mutates persistent scroll state, so it is
        // gated on the render pass — never during measuring.
        if !context.isMeasuring {
            followCursor(handler, lineCount: displayLines.count, width: width, height: height)
        }

        var output: [String] = []
        output.reserveCapacity(height)
        for row in 0..<height {
            let lineIndex = handler.scrollLine + row
            guard lineIndex < displayLines.count else {
                output.append(String(asciiSpaces(width)))
                continue
            }
            let cursorColumn = (isFocused && lineIndex == handler.cursorLine) ? handler.cursorColumn : nil
            output.append(
                styledRow(
                    displayLines[lineIndex], scrollColumn: handler.scrollColumn, width: width,
                    cursorColumn: cursorColumn, palette: palette, isDisabled: isDisabled))
        }

        var buffer = FrameBuffer(lines: output)
        registerMouse(context: context, buffer: &buffer, focusID: persistedFocusID, isDisabled: isDisabled)
        return buffer
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
    /// padded to `width`, with the cursor cell drawn as a block caret when
    /// present.
    private func styledRow(
        _ chars: [Character], scrollColumn: Int, width: Int,
        cursorColumn: Int?, palette: any Palette, isDisabled: Bool
    ) -> String {
        let start = scrollColumn
        let end = min(chars.count, scrollColumn + width)
        var visible: [Character] = start < end ? Array(chars[start..<end]) : []
        while visible.count < width { visible.append(" ") }

        var textStyle = TextStyle()
        textStyle.foregroundColor = isDisabled ? palette.foregroundTertiary : palette.foreground
        let resolved = textStyle.resolved(with: palette)

        guard let cursorColumn, case let cursorCell = cursorColumn - scrollColumn,
            cursorCell >= 0, cursorCell < width
        else {
            return ANSIRenderer.render(String(visible), with: resolved)
        }

        // A block caret: draw the glyph under the cursor in the background
        // colour on a foreground-coloured block. Setting the colours explicitly
        // (rather than relying on SGR 7 reverse-video, which inverts the
        // terminal's *default* colours and collapses to dark-on-dark on a
        // mid-tone palette) keeps the caret visible on every theme.
        var cursorStyle = TextStyle()
        cursorStyle.foregroundColor = palette.background
        cursorStyle.backgroundColor = palette.foreground
        let before = String(visible[0..<cursorCell])
        let cursor = String(visible[cursorCell])
        let after = String(visible[(cursorCell + 1)...])
        return (before.isEmpty ? "" : ANSIRenderer.render(before, with: resolved))
            + ANSIRenderer.render(cursor, with: cursorStyle.resolved(with: palette))
            + (after.isEmpty ? "" : ANSIRenderer.render(after, with: resolved))
    }

    /// A single wide region so a left-click focuses the editor and the wheel
    /// scrolls it. Column-precise caret placement is a documented follow-up.
    private func registerMouse(
        context: RenderContext, buffer: inout FrameBuffer, focusID: String, isDisabled: Bool
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        let handlerID = mouseDispatcher.register { event in
            switch event.phase {
            case .released where event.button == .left:
                focusManager?.focus(id: focusID)
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
