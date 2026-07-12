//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextFieldMouseHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Text Field Mouse Handler

/// Shared mouse wiring for the single-line text inputs (``TextField`` and
/// ``SecureField``).
///
/// Both fields render identically — a leading cap, the content, a trailing cap
/// — and share ``TextFieldHandler`` and ``TextFieldContentRenderer``, so they
/// share this too. A click:
/// - focuses the field,
/// - moves the caret to the clicked column (mapping the column back through the
///   field's horizontal scroll via ``TextFieldHandler/characterIndex(forColumn:contentWidth:)``),
/// - and begins a selection anchored there; dragging extends it.
///
/// Shift-click extends the existing selection to the clicked column instead of
/// starting a new one. The hover state machine (``entered`` / ``exited``) rides
/// on the same region. Selection highlighting is handled by the content
/// renderer, which uses explicit palette colours — never a bare reverse-video
/// SGR.
@MainActor
enum TextFieldMouseHandler {
    /// Registers the field's mouse region on `buffer`. No-op while measuring or
    /// when no dispatcher is available; callers gate on `!isDisabled` first.
    ///
    /// - Parameters:
    ///   - buffer: The field's rendered buffer; a hit-test region is appended.
    ///   - context: The current render context.
    ///   - handler: The field's editing handler (caret + selection live here).
    ///   - persistedFocusID: The field's stable focus identifier.
    ///   - hoverBox: Persisted hover flag, toggled on `.entered` / `.exited`.
    ///   - contentWidth: The width of the content area between the caps.
    ///   - leadingCapWidth: Cells occupied by the opening cap (the click column
    ///     is measured from the buffer's left edge, so this is subtracted to get
    ///     the content-relative column). Defaults to 1.
    ///   - disclosureRange: The buffer-x columns of the combo box's `▾`
    ///     disclosure, when the field has one. A click there toggles the
    ///     suggestions menu instead of positioning the caret.
    static func register(
        buffer: inout FrameBuffer,
        context: RenderContext,
        handler: TextFieldHandler,
        persistedFocusID: String,
        hoverBox: StateBox<Bool>,
        contentWidth: Int,
        leadingCapWidth: Int = 1,
        disclosureRange: Range<Int>? = nil
    ) {
        guard !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }

        // Motion drives the hover machine (.entered / .exited); drag drives
        // click-and-drag selection.
        mouseDispatcher.requestFeature(.motion)
        mouseDispatcher.requestFeature(.drag)

        let focusManager = context.environment.focusManager
        let captureFocusID = persistedFocusID
        let captureHoverBox = hoverBox

        // A buffer-local x → character index, discounting the leading cap.
        func index(atBufferX x: Int) -> Int {
            handler.characterIndex(forColumn: x - leadingCapWidth, contentWidth: contentWidth)
        }

        let mouseHandlerID = mouseDispatcher.register { event in
            switch event.phase {
            case .entered:
                captureHoverBox.value = true
                return true
            case .exited:
                captureHoverBox.value = false
                return true
            case .pressed where event.button == .left:
                focusManager?.focus(id: captureFocusID)
                if let disclosureRange, disclosureRange.contains(event.x) {
                    // The `▾` disclosure: toggle the suggestions menu; the
                    // caret stays where it was.
                    handler.toggleSuggestionsOpen()
                    return true
                }
                if event.shift {
                    // Shift-click: keep the anchor, extend to the clicked column.
                    handler.startOrExtendSelection()
                    handler.cursorPosition = index(atBufferX: event.x)
                } else {
                    // Plain click: caret to the column and drop any selection.
                    // Don't anchor here — a drag anchors on its first .dragged
                    // event; anchoring on the press would leave a collapsed
                    // anchor that a later arrow key turns into a phantom
                    // selection.
                    handler.cursorPosition = index(atBufferX: event.x)
                    handler.clearSelection()
                }
                return true
            case .dragged:
                // The press was claimed, so this drag is bound to us: extend the
                // selection to the dragged column, anchor unchanged.
                handler.startOrExtendSelection()
                handler.cursorPosition = index(atBufferX: event.x)
                return true
            case .released where event.button == .left:
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: mouseHandlerID,
                focusID: persistedFocusID
            )
        )
    }
}
