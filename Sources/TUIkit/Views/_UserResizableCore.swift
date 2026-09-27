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
final class _UserResizeHandler: PersistedFocusable {
    var focusID: String
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
    // Negative: infrastructure slots share the wrapped content's identity,
    // and 0... belongs to a composite content view's own @State. See
    // `StateStorage.StateKey`'s reserved-range table.
    static let focusID = -40
    static let handler = -41
}

/// How many cells of the bottom border the horizontal grabber occupies, and how
/// many rows of the right border the vertical one does.
///
/// Wide enough to read as a handle rather than as a blemish, and odd so it
/// centres exactly. Shrunk to fit on a small view, down to the single cell a
/// three-row box has between its corners — being told an edge can be dragged
/// matters more on a small view than the border cell of separation that used to
/// be reserved either side. Outside the generic for the same reason `StateIndex`
/// is.
private enum GripSize {
    static let horizontal = 7
    static let vertical = 3
}

/// The glyphs a grabber is drawn with — chosen to stand out from the border it
/// sits on, which is the whole job of a mark.
private struct GripGlyphs {
    let horizontal: String
    let vertical: String
    let corner: String

    /// Doubled lines against a single-line or heavy border; heavy ones against a
    /// double-line border, where doubles would BE the border and the handle
    /// would say nothing at all. Both families are Box Drawing rather than
    /// pictographs, so every terminal in `Documentation/Terminal-compatibility.md`
    /// advances them by exactly the cells claimed.
    static let doubled = Self(horizontal: "═", vertical: "║", corner: "╝")
    static let heavy = Self(horizontal: "━", vertical: "┃", corner: "┛")

    /// The family that stands out from `border`, the glyph already in the cell.
    ///
    /// Read from the cell rather than from a ``BorderStyle``, because the border
    /// is drawn INSIDE the content and this modifier wraps it from outside:
    /// there is no style here to consult, only the result. U+2550…U+256C is the
    /// Box Drawing block's double-line run — the rounded corners (U+256D…U+2570)
    /// sit just past it, and the heavy glyphs well below, so both correctly ask
    /// for doubles.
    static func standingOut(from border: Character?) -> Self {
        guard let border, ("\u{2550}"..."\u{256C}").contains(border) else { return .doubled }
        return .heavy
    }
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
        //
        // But it MUST make the same size offer, and for a long time it did not:
        // it returned here, handing the content the whole space. A flexible
        // child takes all of it, so `ScrollView { … }.userResizable(height: 6...24)`
        // measured as tall as the canvas it was measured against and drew 24 —
        // 4,096 against 24 inside a page's ScrollView. Everything the enclosing
        // stack placed AFTER it was therefore placed off the end of the canvas
        // and never drawn: the Example's Scroll View page lost every control
        // below its resizable demo, and its scrollbar went on advertising
        // content that could not be reached.
        guard !context.isMeasuring, let stateStorage = context.stateStorage else {
            // The stored size still counts, so a dragged box measures at what
            // it was dragged to — read without creating, which is what makes
            // this safe on a measure pass.
            return TUIkitView.renderToBuffer(
                content, context: offering(context, handler: existingHandler(in: context)))
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
        // The axes the user can actually MOVE. Naming an axis is what makes it
        // resizable, and bounds that pin it to one size take that back: there is
        // nothing to drag, so it gets no target, no mark and no keys. The bounds
        // still bound — `width: 30...30` remains a way to say "this wide", and
        // the offer below honours it — they just leave nothing to grab, and
        // marking an edge that cannot move is a promise the drag cannot keep.
        var liveAxes = axes
        if widthBounds.isFixed { liveAxes.remove(.horizontal) }
        if heightBounds.isFixed { liveAxes.remove(.vertical) }

        handler.axes = liveAxes
        handler.widthBounds = widthBounds
        handler.heightBounds = heightBounds
        handler.canBeFocused = context.environment.isEnabled && !liveAxes.isEmpty

        let childContext = offering(context, handler: handler)

        // The content FIRST, and the registration after it. The Tab ring is
        // registration order — `FocusSection.register` appends, and nothing sorts by
        // position — while a resize handle sits on the bottom and trailing edges of
        // what it resizes, visually after everything the content draws. Registered
        // before the content rendered, the handle led the ring: on the Example's Scroll
        // View page Tab reached the grip before the buttons inside the box and before
        // the ScrollView's own stop. It is the same single render as before, moved;
        // nothing draws twice. `persistFocusID` and the handler fetch stay above, so a
        // `.focused(_:equals:)` claim is still this view's to take.
        //
        // Arrow keys follow the same order, because they fall back to the ring: Up from
        // the control below the box now stops on the grip first, and Down from above
        // enters the content first.
        var buffer = TUIkitView.renderToBuffer(content, context: childContext)

        // Registered whether or not it can be focused, with `canBeFocused`
        // carrying the answer — the convention every other interactive view
        // follows, and the one `FocusManager.hasFocusableElement` is written
        // against: the ring filters a disabled control at move time, and
        // `FocusManager.register` gates auto-focus on the same flag.
        //
        // Unconditional for a second reason as well. `register` is also what
        // marks this identity active for state GC, and nothing else in this view
        // does: `persistFocusID` and `storage(for:)` do not, and `content`
        // renders at this SAME identity, so content that is itself `Renderable`
        // (a `Text` or a `Divider` behind nothing but modifiers) hydrates no
        // body here to mark it either. Skipped on the path below,
        // `StateStorage.endRenderPass` collected the handler at the end of the
        // very first disabled or fully-pinned frame, and the frame after built a
        // fresh one that asked for nothing: a view dragged to 20 of
        // `width: 20...80` went back to the ceiling, 80. Permanently —
        // re-enabling finds nothing left to restore.
        FocusRegistration.register(context: context, handler: handler, focusID: focusID)

        // A disabled view is not resizable, and neither is one whose every axis
        // is pinned: no target, no mark, no keys, and no place in the Tab order,
        // which is what the `canBeFocused` the registration above carried says.
        // Both still get the offer above: the bounds are the caller's, not the
        // user's, and a `.disabled` box that forgot its ceiling would jump the
        // moment it was disabled.
        guard handler.canBeFocused else { return buffer }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: focusID)

        handler.currentWidth = buffer.width
        handler.currentHeight = buffer.height
        guard buffer.width > 0, buffer.height > 0 else { return buffer }

        registerDragTarget(
            handler: handler, axes: liveAxes, buffer: &buffer, focusID: focusID,
            context: context)
        drawGrip(
            into: &buffer, axes: liveAxes, isFocused: isFocused,
            isHovered: handler.isHovered, context: context)
        return buffer
    }

    /// The context the content is laid out in: the size this view may occupy —
    /// what the user asked for, else the ceiling the caller allowed, else
    /// whatever the layout was offering.
    ///
    /// Clamped by the bounds (what the CALLER allows) and by the space on offer
    /// (what the terminal allows), and neither clamp is stored back — so a
    /// narrow terminal never destroys a size a wide one can honour.
    ///
    /// Offered as available SPACE rather than imposed as a frame. A frame does
    /// not stretch a child that is not flexible; it pads around it, so imposing
    /// one on a `Text` in a border grew the wrapper and left the border where it
    /// was, with the grip stranded in the gap. Offering space is what a flexible
    /// child follows, and leaving a fixed child alone is right: a fixed size is
    /// the author saying "this size", and this modifier has no business
    /// overruling them.
    ///
    /// Note that a ceiling applies even before anything is dragged, which is
    /// what makes `width: 12...40` read as "at most 40 wide" rather than
    /// "unbounded until someone touches it".
    ///
    /// One function for both passes on purpose: this is the arithmetic that
    /// decides the view's size, and a measure that skipped it answered a
    /// different question from the one the render asked.
    private func offering(
        _ context: RenderContext, handler: _UserResizeHandler?
    ) -> RenderContext {
        var childContext = context
        if axes.contains(.horizontal) {
            let target =
                handler?.requestedWidth.map { widthBounds.clamping($0) }
                ?? widthBounds.maximum ?? context.availableWidth
            childContext.availableWidth = min(context.availableWidth, target)
        }
        if axes.contains(.vertical) {
            let target =
                handler?.requestedHeight.map { heightBounds.clamping($0) }
                ?? heightBounds.maximum ?? context.availableHeight
            childContext.availableHeight = min(context.availableHeight, target)
        }
        return childContext
    }

    /// The drag handler this view has already persisted, or `nil` if it has not
    /// been rendered yet. Never creates one — see
    /// ``StateStorage/existingStorage(for:)``.
    private func existingHandler(in context: RenderContext) -> _UserResizeHandler? {
        let box: StateBox<_UserResizeHandler>? = context.stateStorage?.existingStorage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.handler))
        return box?.value
    }

    // MARK: - The drag target

    /// The whole of the live edges is the target; the mark is one cell.
    ///
    /// A terminal cannot change the pointer's shape at an edge, so an
    /// affordance has to be DRAWN, and a drawn mark along two whole edges is
    /// either invisible (if it is subtle) or damage (if it is not). Marking the
    /// corner and accepting the edges resolves that: the mark says where, and
    /// the target is generous enough to hit.
    @MainActor
    private func registerDragTarget(
        handler: _UserResizeHandler, axes: ResizableAxes, buffer: inout FrameBuffer,
        focusID: String, context: RenderContext
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        // Motion reporting, so the dispatcher can synthesise the hover
        // enter/exit transitions that light the grip.
        dispatcher.requestFeature(.motion, in: context)

        // One handler per edge, each knowing which dimensions ITS edge changes:
        // the bottom edge is height, the right edge is width, and the corner —
        // registered last, so it wins the overlap — is both.
        //
        // The hover that lights the grip is the handler's, which is no `@State`
        // write, and an unfocused resizable view makes only replayable
        // registrations: the row around it is stored, and was served with the
        // grip at rest under the pointer. So a hover that moved is reported
        // (`HandlerDrawing`), as a scrollbar's lift is. A press focuses the
        // view, and a focus move clears, so a drag needs no report.
        func register(_ dragAxes: ResizableAxes) -> HitTestRegion.HandlerID {
            dispatcher.register(
                in: context, reportingChangesTo: { handler.isHovered },
                { event in
                    self.handleResizeEvent(
                        event, axes: dragAxes, handler: handler, focusID: focusID, context: context)
                })
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
            // The size on SCREEN, not the request: the first event of a
            // gesture turns "no request" into one, and a press and release that
            // moved nothing is a click, which should not move anybody's
            // viewport.
            let before = (
                handler.requestedWidth ?? handler.dragStartWidth,
                handler.requestedHeight ?? handler.dragStartHeight)
            if dragAxes.contains(.horizontal), let start = handler.dragStartWidth {
                handler.requestedWidth = handler.widthBounds.clamping(start + event.x - origin.x)
            }
            if dragAxes.contains(.vertical), let start = handler.dragStartHeight {
                handler.requestedHeight = handler.heightBounds.clamping(
                    start + event.y - origin.y)
            }
            let after = (
                handler.requestedWidth ?? handler.dragStartWidth,
                handler.requestedHeight ?? handler.dragStartHeight)
            if before != after {
                // Tell any enclosing ScrollView to follow, exactly as a keyboard
                // resize does through `dispatchKeyEvent`: grown by its corner
                // near the bottom of a viewport, the view would otherwise take
                // the edge under the cursor off the screen with it.
                context.environment.focusManager?.noteFocusedInteraction()
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

    /// The three marks: a handle in the middle of each live edge, and — only
    /// when BOTH axes are live — the corner that moves them together.
    ///
    /// Purely a hint; the whole of each live edge takes the drag, as it did
    /// before these existed. But a terminal cannot change the pointer's shape at
    /// an edge, so an edge that can be grabbed has to say so in ink.
    ///
    /// A single-axis view marks only its own edge. The corner used to carry a
    /// glyph there too (`╡`, `╧`) and it was worse than nothing: an edge handle
    /// already says which edge moves, and a mark on a corner that moves one axis
    /// looks like a corner that moves both.
    private func drawGrip(
        into buffer: inout FrameBuffer, axes liveAxes: ResizableAxes, isFocused: Bool,
        isHovered: Bool, context: RenderContext
    ) {
        guard !liveAxes.isEmpty else { return }
        let palette = context.environment.palette

        // A `.block` border paints its cells rather than drawing lines on them
        // (see `BorderStyle.paintsBackground`), so a line-drawing glyph stamped
        // onto one would punch a hole in a solid edge — the mark would read as
        // damage rather than as an affordance. Keep whatever glyph is there in
        // that case and let the TINT do the marking, which is the same
        // three-step vocabulary either way.
        let existing = buffer.lines.last?.stripped.last
        let paintsItsCells = existing.map { ("\u{2580}"..."\u{259F}").contains($0) } ?? false
        let glyphs = GripGlyphs.standingOut(from: existing)

        // Focused is loudest, hovered next, resting quiet but present — the
        // same three-step vocabulary every other affordance uses, and floored
        // against the surface it sits on for the same reason.
        let resting = palette.border
        let background = palette.background
        // Focused, the marks breathe — the same affordance every other focused
        // control shows, and the reason is the same: a still highlight on a
        // terminal reads as decoration, a breathing one reads as "this is where
        // the keyboard is".
        let animated = AnimatedColor.activeSection(isFocused, in: context.environment)
        // The ink drawn now. Focused, it is the breath's current frame: the colour
        // the run replays over it on the next tick, opaque at both ends. It used to
        // be the raw accent, floored — so a faded tint reached the emitter, and the
        // grip jumped shade on the first replayed tick (§62).
        let ink =
            animated?.current
            ?? (isHovered ? palette.hoveredForeground(resting) : resting)
                .ensuringRenderedContrast(atLeast: 2.4, against: background)

        // The corner belongs to a two-axis drag. A painted border has no line to
        // replace, so its corner is marked by tint alone — which is the only
        // mark it can carry, and the reason the block case stops there.
        let corner = (x: buffer.width - 1, y: buffer.height - 1)
        if paintsItsCells {
            mark(
                String(existing!), cells: 1, into: &buffer, at: corner,
                ink: ink, animated: animated, background: background)
            return
        }
        if liveAxes == .all {
            mark(
                glyphs.corner, cells: 1, into: &buffer, at: corner,
                ink: ink, animated: animated, background: background)
        }
        drawEdgeGrips(
            into: &buffer, axes: liveAxes, glyphs: glyphs, ink: ink, animated: animated,
            background: background)
    }

    /// Paints `text`, `cells` wide, over the border at `cell` — in `ink`, on the page's
    /// own background — and leaves the focused breath's run over it.
    ///
    /// Through `ClaimingRow`, so the bytes state the opaque spelling and the overlay
    /// carries the claim. `composited` punches the border's own claim from those cells
    /// and lifts this one in its place, so each is claimed once; and the claim holds
    /// for every frame of the run, since the breath's ink is opaque at both ends and
    /// the field is the page's in all of them.
    private func mark(
        _ text: String, cells: Int, into buffer: inout FrameBuffer, at cell: (x: Int, y: Int),
        ink: Color, animated: AnimatedColor?, background: Color
    ) {
        var drawn = ClaimingRow()
        drawn.append(text, cells: cells, ink: ink, field: background)
        var overlay = FrameBuffer(lines: [drawn.text])
        overlay.opacityRegions = drawn.claims
        buffer = buffer.composited(with: overlay, at: cell)
        if let run = animated?.run(offsetX: cell.x, offsetY: cell.y, draw: { colour in
            var frame = ClaimingRow()
            frame.append(text, cells: cells, ink: colour, field: background)
            return frame.text
        }) {
            buffer.animatedCells.append(run)
        }
    }

    /// The handles in the middle of each live border.
    ///
    /// Each sits in the border's own run BETWEEN its two corners, and shrinks to
    /// fit that run rather than reserving separation either side of it: a
    /// three-row box has exactly one border cell down its right edge, and on a
    /// box that small being told the edge can be dragged matters more than the
    /// cell of border that would have said it more prettily.
    private func drawEdgeGrips(
        into buffer: inout FrameBuffer, axes liveAxes: ResizableAxes, glyphs: GripGlyphs,
        ink: Color, animated: AnimatedColor?, background: Color
    ) {
        /// `size` cells of `run`, centred — the border's own span between its
        /// two corners, which is `1..<(extent - 1)`.
        func centred(in extent: Int, size cap: Int) -> Range<Int>? {
            let run = extent - 2
            let size = min(cap, run)
            guard size >= 1 else { return nil }
            return (1 + (run - size) / 2)..<(1 + (run - size) / 2 + size)
        }

        // The bottom border is dragged for HEIGHT, so it is marked when the
        // vertical axis is live; the right border likewise for width.
        if liveAxes.contains(.vertical),
            let span = centred(in: buffer.width, size: GripSize.horizontal)
        {
            mark(
                String(repeating: glyphs.horizontal, count: span.count), cells: span.count,
                into: &buffer, at: (x: span.lowerBound, y: buffer.height - 1),
                ink: ink, animated: animated, background: background)
        }

        if liveAxes.contains(.horizontal),
            let span = centred(in: buffer.height, size: GripSize.vertical)
        {
            let x = buffer.width - 1
            for row in span {
                mark(
                    glyphs.vertical, cells: 1, into: &buffer, at: (x: x, y: row),
                    ink: ink, animated: animated, background: background)
            }
        }
    }
}
