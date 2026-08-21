//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _UserResizableCore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Handler

/// Drives one user-resizable view: the arrow keys, and the drag anchor the
/// mouse path reads.
///
/// Deliberately the same shape as ``_SplitDividerHandler``, which has been
/// resizing split columns for longer: it records raw INTENT and lets the layout
/// clamp, which is what keeps the arrow keys stepping from the size actually on
/// screen rather than from a stored wish the layout never honoured.
final class _UserResizeHandler: Focusable {
    let focusID: String
    var canBeFocused = true

    /// What the user has asked for, or `nil` while the layout's own size stands.
    var requestedWidth: Int?
    var requestedHeight: Int?

    /// The size the view rendered at last frame — the base a keyboard step
    /// moves from before anything has been requested.
    var currentWidth = 0
    var currentHeight = 0

    /// The size when the current drag began, or `nil` when none is in progress.
    var dragStartWidth: Int?
    var dragStartHeight: Int?

    /// Whether the pointer is over one of the resize edges.
    var isHovered = false

    var axes: ResizableAxes = .all
    var widthBounds: ResizeBounds = .unbounded
    var heightBounds: ResizeBounds = .unbounded

    init(focusID: String) { self.focusID = focusID }

    /// The width a step moves from: what was asked for, else what is on screen.
    var baseWidth: Int { requestedWidth ?? currentWidth }
    var baseHeight: Int { requestedHeight ?? currentHeight }

    func resizeWidth(by delta: Int) {
        guard axes.contains(.horizontal) else { return }
        requestedWidth = widthBounds.clamping(baseWidth + delta)
    }

    func resizeHeight(by delta: Int) {
        guard axes.contains(.vertical) else { return }
        requestedHeight = heightBounds.clamping(baseHeight + delta)
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // Shift is the "further" modifier everywhere else that steps a value
        // (the split divider, Stepper, Slider), so it is five here too.
        let step = event.shift ? 5 : 1
        switch event.key {
        case .left: resizeWidth(by: -step)
        case .right: resizeWidth(by: step)
        case .up: resizeHeight(by: -step)
        case .down: resizeHeight(by: step)
        case .home:
            if axes.contains(.horizontal) { requestedWidth = widthBounds.minimum }
            if axes.contains(.vertical) { requestedHeight = heightBounds.minimum }
        case .end:
            // No maximum means "as much as the layout will give", which the
            // clamp downstream resolves — asking for `Int.max` is how you say
            // that without inventing a number here.
            if axes.contains(.horizontal) { requestedWidth = widthBounds.maximum ?? Int.max }
            if axes.contains(.vertical) { requestedHeight = heightBounds.maximum ?? Int.max }
        case .escape:
            // Back to the size the layout wanted. Nothing else clears these:
            // a resize is meant to persist, so there has to be one gesture that
            // says "never mind".
            guard requestedWidth != nil || requestedHeight != nil else { return false }
            requestedWidth = nil
            requestedHeight = nil
        default:
            return false
        }
        return true
    }
}

// MARK: - Core

/// Named indices, so no bare integer decides which slot holds what. Outside the
/// generic type because a generic may not carry static stored properties.
private enum StateIndex {
    static let focusID = 0
    static let handler = 1
}

/// The rendering half of ``View/userResizable(_:)``.
struct _UserResizableCore<Content: View>: View, Renderable {
    let content: Content
    let axes: ResizableAxes
    let widthBounds: ResizeBounds
    let heightBounds: ResizeBounds

    var body: Never { fatalError("_UserResizableCore renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Measuring must not register focus or mutate the stored size — the
        // measure pass runs speculatively and more than once per frame. See
        // `Documentation/Discarded render passes and redundant frames.md`.
        guard !context.isMeasuring, let stateStorage = context.stateStorage else {
            return TUIkitView.renderToBuffer(content, context: context)
        }

        let focusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: nil,
            defaultPrefix: "resizable",
            propertyIndex: StateIndex.focusID)

        let handler = stateStorage.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.handler),
            default: _UserResizeHandler(focusID: focusID)
        ).value
        handler.axes = axes
        handler.widthBounds = widthBounds
        handler.heightBounds = heightBounds
        handler.canBeFocused = context.environment.isEnabled

        // A disabled view is not resizable and does not take a place in the Tab
        // order — the same rule every other interactive view follows.
        guard context.environment.isEnabled else {
            return TUIkitView.renderToBuffer(content, context: context)
        }
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: focusID)

        // The size this view may occupy: what the user asked for, else the
        // ceiling the caller allowed, else whatever the layout was offering.
        // Clamped by the bounds (what the CALLER allows) and by the space on
        // offer (what the terminal allows), and neither clamp is stored back —
        // so a narrow terminal never destroys a size a wide one can honour.
        //
        // Offered as available SPACE rather than imposed as a frame. A frame
        // does not stretch a child that is not flexible; it pads around it, so
        // imposing one on a `Text` in a border grew the wrapper and left the
        // border where it was, with the grip stranded in the gap. Offering
        // space is what a flexible child follows, and leaving a fixed child
        // alone is right: a fixed size is the author saying "this size", and
        // this modifier has no business overruling them.
        //
        // Note that a ceiling applies even before anything is dragged, which is
        // what makes `width: 12...40` read as "at most 40 wide" rather than
        // "unbounded until someone touches it".
        var childContext = context
        if axes.contains(.horizontal) {
            let target =
                handler.requestedWidth.map { widthBounds.clamping($0) }
                ?? widthBounds.maximum ?? context.availableWidth
            childContext.availableWidth = min(context.availableWidth, target)
        }
        if axes.contains(.vertical) {
            let target =
                handler.requestedHeight.map { heightBounds.clamping($0) }
                ?? heightBounds.maximum ?? context.availableHeight
            childContext.availableHeight = min(context.availableHeight, target)
        }

        var buffer = TUIkitView.renderToBuffer(content, context: childContext)
        handler.currentWidth = buffer.width
        handler.currentHeight = buffer.height
        guard buffer.width > 0, buffer.height > 0 else { return buffer }

        registerDragTarget(
            handler: handler, buffer: &buffer, focusID: focusID, context: context)
        drawGrip(
            into: &buffer, isFocused: isFocused, isHovered: handler.isHovered,
            context: context)
        return buffer
    }

    // MARK: - The drag target

    /// The whole of the live edges is the target; the mark is one cell.
    ///
    /// A terminal cannot change the pointer's shape at an edge, so an
    /// affordance has to be DRAWN, and a drawn mark along two whole edges is
    /// either invisible (if it is subtle) or damage (if it is not). Marking the
    /// corner and accepting the edges resolves that: the mark says where, and
    /// the target is generous enough to hit.
    private func registerDragTarget(
        handler: _UserResizeHandler, buffer: inout FrameBuffer, focusID: String,
        context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        // Motion reporting, so the dispatcher can synthesise the hover
        // enter/exit transitions that light the grip.
        dispatcher.requestFeature(.motion)

        let handlerID = dispatcher.register { event in
            switch event.phase {
            case .entered:
                handler.isHovered = true
                return true
            case .exited:
                handler.isHovered = false
                return true
            default:
                break
            }
            guard event.button == .left else { return false }
            switch event.phase {
            case .pressed:
                handler.dragStartWidth = handler.baseWidth
                handler.dragStartHeight = handler.baseHeight
                context.environment.focusManager?.focus(id: focusID)
                return true
            case .dragged, .released:
                // `event.x` / `.y` arrive localised to the press, so they are
                // already the signed cell delta to apply.
                if handler.axes.contains(.horizontal), let start = handler.dragStartWidth {
                    handler.requestedWidth = handler.widthBounds.clamping(start + event.x)
                }
                if handler.axes.contains(.vertical), let start = handler.dragStartHeight {
                    handler.requestedHeight = handler.heightBounds.clamping(start + event.y)
                }
                if event.phase == .released {
                    handler.dragStartWidth = nil
                    handler.dragStartHeight = nil
                }
                return true
            default:
                return false
            }
        }

        // Two regions rather than one L-shape, because a hit region is a
        // rectangle. They overlap at the corner, which is harmless — the corner
        // is the one cell where dragging either way is meant to work.
        if axes.contains(.vertical) {
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: buffer.height - 1,
                    width: buffer.width, height: 1,
                    handlerID: handlerID, focusID: focusID))
        }
        if axes.contains(.horizontal) {
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: buffer.width - 1, offsetY: 0,
                    width: 1, height: buffer.height,
                    handlerID: handlerID, focusID: focusID))
        }
    }

    // MARK: - The mark

    /// The corner glyph, composited over the view's bottom-right cell.
    ///
    /// `╝` — a double-line corner, which reads as "this corner is special"
    /// against every border style TUIkit draws and is Box Drawing rather than a
    /// pictograph, so every terminal in `Terminal-compatibility.md` advances it
    /// by exactly the one cell claimed. A single-axis view marks the edge it
    /// actually resizes instead, so the mark never promises a direction that
    /// does nothing.
    private func drawGrip(
        into buffer: inout FrameBuffer, isFocused: Bool, isHovered: Bool,
        context: RenderContext
    ) {
        let palette = context.environment.palette
        let glyph: String
        switch (axes.contains(.horizontal), axes.contains(.vertical)) {
        case (true, true): glyph = "╝"
        case (true, false): glyph = "╡"
        case (false, true): glyph = "╧"
        case (false, false): return
        }

        // Focused is loudest, hovered next, resting quiet but present — the
        // same three-step vocabulary every other affordance uses, and floored
        // against the surface it sits on for the same reason.
        let resting = palette.border
        let tint: Color =
            isFocused
            ? palette.accent
            : (isHovered ? palette.hoveredForeground(resting) : resting)
        let background = palette.background
        let styled = ANSIRenderer.colorize(
            glyph,
            foreground: tint.ensuringRenderedContrast(atLeast: 2.4, against: background),
            background: background)

        buffer = buffer.composited(
            with: FrameBuffer(lines: [styled]),
            at: (x: buffer.width - 1, y: buffer.height - 1))
    }
}
