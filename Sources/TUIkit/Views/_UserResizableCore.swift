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

    /// Where the press landed, in the coordinates of the region that captured
    /// the gesture. Every later event in the gesture is localised to that same
    /// region, so the difference is the cell delta to apply — see
    /// `handleResizeEvent`.
    var dragOrigin: (x: Int, y: Int)?

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

/// How many cells of the bottom border the horizontal grabber occupies, and how
/// many rows of the right border the vertical one does.
///
/// Wide enough to read as a handle rather than as a blemish, and odd so it
/// centres exactly. Shrunk to fit on a small view, and dropped entirely when
/// there is no room beside the corners — a handle that runs into the corner it
/// is distinct from says nothing. Outside the generic for the same reason
/// `StateIndex` is.
private enum GripSize {
    static let horizontal = 7
    static let vertical = 3
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

        // One handler per edge, each knowing which dimensions ITS edge changes:
        // the bottom edge is height, the right edge is width, and the corner —
        // registered last, so it wins the overlap — is both.
        func register(_ dragAxes: ResizableAxes) -> HitTestRegion.HandlerID {
            dispatcher.register { event in
                self.handleResizeEvent(
                    event, axes: dragAxes, handler: handler, focusID: focusID, context: context)
            }
        }

        // Regions rather than one L-shape, because a hit region is a rectangle.
        if axes.contains(.vertical) {
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: buffer.height - 1,
                    width: buffer.width, height: 1,
                    handlerID: register(.vertical), focusID: focusID))
        }
        if axes.contains(.horizontal) {
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: buffer.width - 1, offsetY: 0,
                    width: 1, height: buffer.height,
                    handlerID: register(.horizontal), focusID: focusID))
        }
        if axes.contains(.vertical), axes.contains(.horizontal) {
            // The corner, last so the hit test (which searches the
            // registrations in reverse) reaches it before the two edges it sits
            // on. Dragging it moves both dimensions at once — which is what a
            // corner means, and what the marked cell has always promised.
            //
            // Two cells square rather than the one that is marked: a
            // single-cell target is a hard thing to hit with a pointer, and the
            // cells it takes from the two edges are the ones nearest the corner
            // anyway. The mark stays one cell, because two would read as a
            // broken border rather than as a handle.
            let size = min(2, min(buffer.width, buffer.height))
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: buffer.width - size, offsetY: buffer.height - size,
                    width: size, height: size,
                    handlerID: register(axes), focusID: focusID))
        }
    }

    /// One edge's share of a resize gesture.
    ///
    /// The deltas are measured from where the PRESS landed, not read out of the
    /// event. A drag is localised to the region that captured it, so
    /// `event.x`/`event.y` are offsets from that region's top-left: for the
    /// bottom edge the y happens to be the delta (its origin is the pressed
    /// row) and the x is a column number, and for the right edge it is the other
    /// way about. Treating both as deltas made a corner drag apply a column
    /// number as a width — which, on a box already at its widest, simply looked
    /// like the axis not working at all.
    private func handleResizeEvent(
        _ event: MouseEvent, axes dragAxes: ResizableAxes,
        handler: _UserResizeHandler, focusID: String, context: RenderContext
    ) -> Bool {
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
            handler.dragOrigin = (x: event.x, y: event.y)
            context.environment.focusManager?.focus(id: focusID)
            return true
        case .dragged, .released:
            guard let origin = handler.dragOrigin else { return true }
            if dragAxes.contains(.horizontal), let start = handler.dragStartWidth {
                handler.requestedWidth = handler.widthBounds.clamping(start + event.x - origin.x)
            }
            if dragAxes.contains(.vertical), let start = handler.dragStartHeight {
                handler.requestedHeight = handler.heightBounds.clamping(
                    start + event.y - origin.y)
            }
            if event.phase == .released {
                handler.dragStartWidth = nil
                handler.dragStartHeight = nil
                handler.dragOrigin = nil
            }
            return true
        default:
            return false
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
    /// How many cells of the bottom border the horizontal grabber occupies, and
    /// how many rows of the right border the vertical one does.
    ///
    /// Wide enough to read as a handle rather than as a blemish, and odd so it
    /// centres exactly. Shrunk to fit on a small view (and dropped entirely
    /// when there is no room beside the corner), because a handle that runs
    /// into the corner it is distinct from says nothing.

    private func drawGrip(
        into buffer: inout FrameBuffer, isFocused: Bool, isHovered: Bool,
        context: RenderContext
    ) {
        let palette = context.environment.palette
        let corner: String
        switch (axes.contains(.horizontal), axes.contains(.vertical)) {
        case (true, true): corner = "╝"
        case (true, false): corner = "╡"
        case (false, true): corner = "╧"
        case (false, false): return
        }

        // A `.block` border paints its cells rather than drawing lines on them
        // (see `BorderStyle.paintsBackground`), so a line-drawing corner
        // stamped onto one would punch a hole in a solid edge — the mark would
        // read as damage rather than as an affordance. Keep whatever glyph is
        // there in that case and let the TINT do the marking, which is the same
        // three-step vocabulary either way.
        //
        // Read from the cell rather than from the border style, because the
        // border is inside the content and this modifier is outside it: there
        // is no style to consult, only the result.
        let existing = buffer.lines.last?.stripped.last
        let paintsItsCells = existing.map { ("\u{2580}"..."\u{259F}").contains($0) } ?? false
        let glyph = paintsItsCells ? String(existing!) : corner

        // Focused is loudest, hovered next, resting quiet but present — the
        // same three-step vocabulary every other affordance uses, and floored
        // against the surface it sits on for the same reason.
        let resting = palette.border
        let tint: Color =
            isFocused
            ? palette.accent
            : (isHovered ? palette.hoveredForeground(resting) : resting)
        let background = palette.background
        // Focused, the marks breathe — the same affordance every other focused
        // control shows, and the reason is the same: a still highlight on a
        // terminal reads as decoration, a breathing one reads as "this is where
        // the keyboard is".
        let animated = AnimatedColor.activeSection(isFocused, in: context.environment)
        let styled = ANSIRenderer.colorize(
            glyph,
            foreground: tint.ensuringRenderedContrast(atLeast: 2.4, against: background),
            background: background)

        buffer = buffer.composited(
            with: FrameBuffer(lines: [styled]),
            at: (x: buffer.width - 1, y: buffer.height - 1))
        if let run = animated?.run(offsetX: buffer.width - 1, offsetY: buffer.height - 1, draw: {
            ANSIRenderer.colorize(glyph, foreground: $0, background: background)
        }) {
            buffer.animatedCells.append(run)
        }

        guard !paintsItsCells else { return }
        drawEdgeGrips(
            into: &buffer, tint: tint, animated: animated, background: background)
    }

    /// The doubled-line handles in the middle of each live border.
    ///
    /// Purely a hint — the whole edge takes the drag, as it did before these
    /// existed — but a terminal cannot change the pointer's shape at an edge,
    /// so an edge that can be grabbed has to say so in ink. Doubled lines
    /// because they read as "special" against every single-line border style
    /// TUIkit draws, and are Box Drawing rather than pictographs, so every
    /// terminal advances them by exactly the cells claimed.
    private func drawEdgeGrips(
        into buffer: inout FrameBuffer, tint: Color, animated: AnimatedColor?,
        background: Color
    ) {
        func styled(_ text: String, _ colour: Color) -> String {
            ANSIRenderer.colorize(text, foreground: colour, background: background)
        }

        // The bottom border is dragged for HEIGHT, so it is marked when the
        // vertical axis is live; the right border likewise for width.
        if axes.contains(.vertical) {
            // Leaving a cell either side of the corner and the far corner, so
            // the handle never reads as part of them.
            let room = buffer.width - 4
            let width = min(GripSize.horizontal, room)
            if width >= 3 {
                let x = (buffer.width - width) / 2
                let y = buffer.height - 1
                let glyphs = String(repeating: "═", count: width)
                buffer = buffer.composited(
                    with: FrameBuffer(lines: [styled(glyphs, tint)]), at: (x: x, y: y))
                if let run = animated?.run(offsetX: x, offsetY: y, draw: { styled(glyphs, $0) }) {
                    buffer.animatedCells.append(run)
                }
            }
        }

        if axes.contains(.horizontal) {
            let room = buffer.height - 4
            let height = min(GripSize.vertical, room)
            if height >= 1 {
                let x = buffer.width - 1
                let top = (buffer.height - height) / 2
                for row in top..<(top + height) {
                    buffer = buffer.composited(
                        with: FrameBuffer(lines: [styled("║", tint)]), at: (x: x, y: row))
                    if let run = animated?.run(
                        offsetX: x, offsetY: row, draw: { styled("║", $0) })
                    {
                        buffer.animatedCells.append(run)
                    }
                }
            }
        }
    }
}
