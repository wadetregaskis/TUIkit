//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuPopover.swift
//
//  The floating menu presentation shared by `.contextMenu` and a pop-up `Menu`.
//  Both put the same thing on screen — a bordered column of `Button`s that owns
//  the focus and the keyboard until it is dismissed — and differ only in what
//  opens it and where it is anchored.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Renders `items` as a menu: a bordered column of rows, sized to hug its
/// widest, scrolling inside `capHeight` if it cannot fit.
///
/// The shared body of every TUIkit menu — the `.contextMenu` popover, a pop-up
/// ``Menu``, and an inline one — so all three sit on the same grid and answer
/// to the same width arithmetic.
///
/// - Parameters:
///   - items: The menu's rows: `Button`s and `Divider`s, plus whatever heading
///     the caller puts above them.
///   - context: The context to lay out in; its `availableWidth` is the ceiling.
///   - capHeight: The height the menu must fit into, or 0 for no cap. A taller
///     menu scrolls inside it.
///   - borderColor: The frame's stroke, or `nil` for the palette's border colour.
///     A presented menu passes the breathing accent here — see
///     ``presentMenuPopover(items:over:controller:sectionID:itemsIndex:anchor:dismiss:context:)``.
///
/// This is the INLINE menu's assembly. A pop-up goes through
/// ``renderMenuPopup(_:context:controller:)`` instead, which hands the same
/// rows to the `Picker` drop-down's renderer — see
/// `Documentation/Unifying the menu implementations.md`.
@MainActor
func renderMenuColumn(
    _ items: some View, context: RenderContext, capHeight: Int, borderColor: Color? = nil
) -> FrameBuffer {
    let menuView = menuColumnFrame(items, borderColor: borderColor)
    let plan = planMenuColumn(menuView, context: context, capHeight: capHeight)
    guard plan.scrolls else {
        return renderToBuffer(menuView, context: plan.sized)
    }
    // Taller than its budget: scroll inside it. The scroll goes INSIDE the
    // border, not around it — a ScrollView's "N more above/below" indicators
    // replace its first and last visible rows, which around the border would
    // eat the border itself. The content renders at its full height inside the
    // viewport, which is what lets the reveal bring an off-screen item back
    // (`ScrollViewReveal`).
    let scrolled = ScrollView(.vertical) { menuColumnBody(items) }
        .frame(height: max(1, capHeight - 2))
        .bordered(style: nil, colour: borderColor.map(AnimatedColor.init), width: 1)
    return renderToBuffer(scrolled, context: plan.sized.withAvailableHeight(capHeight))
}

/// The size ``renderMenuColumn(_:context:capHeight:borderColor:)`` comes back
/// as, without drawing a cell.
///
/// It can answer from the plan alone because the plan is what decides the
/// menu's size: the width is its hug clamped to the space, and the height is
/// either the content's or the cap it scrolls inside. Nothing downstream of
/// that adds a row or a column — the border is already inside the measured
/// view, and the scrolled arm is framed to exactly the cap.
///
/// It matters because a menu was drawn to be measured. Two-pass layout measures
/// a stack's children before it renders them, so an inline `Menu` in a page
/// rendered its whole column twice a frame and threw one away — and each of
/// those renders measures the column again first, for the hug. Four walks of
/// the tree to put one menu on screen; this makes it three.
/// `MenuMeasureParityTests` renders the matrix and compares, because "the same
/// plan" is a claim about code that has to be checked against what it draws.
@MainActor
func measureMenuColumn(
    _ items: some View, context: RenderContext, capHeight: Int, borderColor: Color? = nil
) -> ViewSize {
    let menuView = menuColumnFrame(items, borderColor: borderColor)
    let plan = planMenuColumn(menuView, context: context, capHeight: capHeight)
    guard !plan.scrolls else { return ViewSize.fixed(plan.width, capHeight) }
    // ``MenuColumnPlan/drawnHeight`` has already accounted for any reflow: the
    // plan had to know the drawn height to decide whether the menu scrolls at
    // all, so the one walk that answers it serves both questions.
    return ViewSize.fixed(plan.width, plan.drawnHeight)
}

/// The menu's rows, styled and padded — everything inside the border.
///
/// The items are `Button`s (SwiftUI's API, which TUIkit matches), but a menu's
/// rows must not LOOK like buttons — `_MenuItemButtonStyle` draws them as menu
/// rows, the same idiom as the Picker drop-down.
@MainActor
private func menuColumnBody(_ items: some View) -> some View {
    VStack(alignment: .leading, spacing: 0) { items }
        .buttonStyle(_MenuItemButtonStyle())
        .padding(.horizontal, 1)
}

/// ``menuColumnBody(_:)`` in its border — the whole menu, as one view.
@MainActor
private func menuColumnFrame(_ items: some View, borderColor: Color?) -> some View {
    menuColumnBody(items)
        .bordered(style: nil, colour: borderColor.map(AnimatedColor.init), width: 1)
}

/// Where a menu column sits and how big it is — the one owner of the hug
/// arithmetic, so the measure and the render cannot answer differently.
private struct MenuColumnPlan {
    /// The width the menu draws at.
    var width: Int
    /// The height the column actually draws at ``width``.
    ///
    /// The hug height where nothing was squeezed, and the RE-MEASURED height
    /// where it was. A hugging row is measured against the menu's whole
    /// interior, while a drawn one gets that interior less the hint column
    /// beside it, and a label can wrap into the difference — so where the hug
    /// wanted every cell it was offered, its height is a lower bound and not the
    /// number anything should be decided from.
    ///
    /// Deciding from it is exactly what went wrong: the overflow probe was gated
    /// on the hug height, so a menu whose rows reflowed PAST the cap while
    /// hugging under it never asked the question, took the non-scrolling arm, and
    /// had its trailing rows clipped away with no scrollbar and no way to reach
    /// them.
    var drawnHeight: Int
    /// The context it draws in: clamped to `width`, with the row width and the
    /// menu verb handed down, in a measure generation of its own.
    var sized: RenderContext
    /// Whether the content is taller than the cap, so the menu scrolls inside
    /// its border rather than hugging.
    var scrolls = false
}

/// Sizes `menuView` to its own content and prepares the context it draws in.
@MainActor
private func planMenuColumn(
    _ menuView: some View, context: RenderContext, capHeight: Int
) -> MenuColumnPlan {
    // Size the menu to its own content before rendering it. Laying it out
    // against the whole screen made a menu of three short items span the
    // terminal: `Divider` MEASURES as one cell but RENDERS at the width it is
    // offered, and a VStack takes its width from what its children actually
    // drew — so one separator inflated the popover to whatever it was handed.
    // Measuring first (where the divider claims its true one cell and the
    // buttons hug their labels) yields the natural hug width; rendering at that
    // width then makes the divider span exactly the menu's interior, which is
    // the separator look we want anyway.
    //
    // Measured through the SAME context the render uses, so `@State` and focus
    // slots resolve to the same identities either way (362c8839).
    let natural = measureChild(
        menuView,
        proposal: ProposedSize(
            width: context.availableWidth, height: capHeight > 0 ? capHeight : nil),
        context: context)
    let menuWidth = max(1, min(natural.width, context.availableWidth))
    var sized = context.withAvailableWidth(menuWidth)
    // Now that the width is known, hand it to the rows so their highlight reads
    // as a bar across the menu rather than a tag around the label. Deliberately
    // AFTER the measure: a row that knew its width up front would report it, and
    // the menu would size itself from its own guess.
    //
    // The chrome is 6 cells, not 4: `.border()` is a `ContainerView`, which
    // insets its content by one cell on each side on top of its two border
    // columns, and the `.padding(.horizontal, 1)` above adds two more. Getting
    // this wrong told the rows they had two cells they did not, which the
    // border then clipped — invisible while a row was just a left-aligned
    // label, fatal once a row has something at its trailing edge.
    sized.environment.menuRowWidth = max(1, menuWidth - 6)
    // For the Return verb: a row of an open pop-up is a row of a menu too.
    sized.environment.isInsideMenu = true
    // Everything from here down is a DIFFERENT question from the hug above, and
    // the measure memo has to be told so: it keys on identity, widths, view type
    // and view bytes, and on this arm `menuWidth == context.availableWidth`, so
    // the hug and the draw are one key. It answered the draw with the hug — at
    // `_ButtonCore`, whose size comes from the `ButtonStyle` it reads out of the
    // environment, so no amount of moving the row width into a view's value can
    // separate them. See ``RenderContext/measureGeneration``; 20 stale serves on
    // one walk of the Example without this line.
    sized = sized.invalidatingMeasureMemo()

    // Two questions remain, and ONE walk answers both: how tall the column
    // actually draws, and whether that clears the cap.
    //
    // The hug height answers neither on its own. It is a lower bound: a hugging
    // row is measured against the menu's whole interior while a drawn one gets
    // that interior less the hint column beside it, so a label with a space in
    // it wraps into the difference and the column comes out taller than the hug
    // said. And it cannot answer the cap question in either direction, because a
    // measure is CLAMPED to the context's `availableHeight` — for an inline menu
    // the cap IS that height — so a hug that comes back exactly at the cap might
    // have been truncated and one below it demonstrably was not.
    //
    // So the walk is against a budget ONE ROW past the cap, in the context the
    // rows are actually drawn in. A report at `capHeight + 1` was clamped, which
    // is precisely "it does not fit"; anything at or below the cap is the
    // column's own drawn height, which is the other thing wanted. (Where this
    // used to offer `max(capHeight * 64, 4096)` it was a ceiling wearing a
    // generous canvas's clothes, and cost a walk 4,096 rows deep to learn one
    // bit. How FAR past the cap the content goes is nobody's business here: the
    // scrolled arm frames its viewport at the cap and its `ScrollView` measures
    // its own content with no limit at all.)
    //
    // Skipped when nothing can have moved: an unclamped menu gave every row at
    // least the width it asked for, so nothing reflows, and a hug strictly under
    // the cap was not truncated either — the hug height IS the drawn height and
    // the answer is already known. That is the common case (a handful of rows in
    // a terminal-sized slot), and it is what keeps this off the ordinary path.
    //
    // The gate used to be `natural.height >= capHeight` alone, and that is the
    // bug: a menu whose rows reflowed PAST the cap while hugging under it never
    // asked, took the non-scrolling arm, and had its trailing rows clipped away
    // with no scrollbar and no way to reach them. Six rows at width 26 against a
    // twelve-row cap: the hug is eight rows and the draw is fourteen.
    let wasSqueezed = natural.width >= context.availableWidth
    guard capHeight > 0, wasSqueezed || natural.height >= capHeight else {
        return MenuColumnPlan(width: menuWidth, drawnHeight: natural.height, sized: sized)
    }
    let drawnHeight = measureChild(
        menuView, proposal: ProposedSize(width: menuWidth, height: nil),
        context: sized.withAvailableHeight(capHeight + 1)
    ).height
    let fits = MenuColumnPlan(
        width: menuWidth, drawnHeight: min(drawnHeight, capHeight), sized: sized)
    guard drawnHeight > capHeight else { return fits }
    var scrolls = fits
    scrolls.scrolls = true
    return scrolls
}

/// Renders `items` as an open POP-UP menu, through the same drop-down renderer
/// a `Picker` and a combo box use.
///
/// The two engines met here. The rows stay VIEWS — that is what gives `Menu`
/// arbitrary `@ViewBuilder` content, `ButtonRole`, per-row `.disabled()` and key
/// equivalents — and are drawn by `_MenuItemButtonStyle` exactly as before. But
/// they are then handed to ``DropdownMenu`` already drawn, so the menu inherits
/// what only the procedural side had: a scrollbar in its own COLUMN rather than
/// "N more" lines eating two rows of content, hover-follows-cursor, and a
/// highlight that spans the whole interior instead of leaving two gutters the
/// pointer cannot hit.
///
/// Slicing a column of views back into rows is possible because each row already
/// publishes a hit-test region tagged with its ordinal (``menuRowRegionID``), so
/// the exact line range of every row is known without guessing at heights or
/// classifying lines by what they look like. Lines no row claims — a `Divider`,
/// a heading — become unselectable rows: placed as drawn, never highlighted,
/// never clickable.
@MainActor
func renderMenuPopup(
    _ items: some View, context: RenderContext, controller: MenuPopupController,
    dismiss: @escaping () -> Void
) -> FrameBuffer {
    let rowsOnly = VStack(alignment: .leading, spacing: 0) { items }
        .buttonStyle(_MenuItemButtonStyle())

    // Size to the content first, exactly as the inline assembly does and for
    // the same reason: a `Divider` MEASURES as one cell but RENDERS at whatever
    // width it is offered, so laying out against the screen would inflate the
    // menu to the terminal. The chrome here is the drop-down's two border
    // columns plus its one-cell padding on each side.
    let inset = 1
    let widthCap = max(1, context.availableWidth - 2 - 2 * inset)
    let natural = measureChild(
        rowsOnly, proposal: ProposedSize(width: widthCap, height: nil), context: context)
    let rowWidth = max(1, min(natural.width, widthCap)) + 2 * inset

    // Rendered against a canvas as tall as the column actually is, on purpose:
    // the renderer below is what windows the menu, and it can only window rows
    // that exist. Laid out in the space actually available, the column would be
    // clipped to the overlay's height first and the rows past the fold would
    // never be drawn at all — so the scrollbar would have nothing to scroll to.
    //
    // The canvas used to be `max(context.availableHeight * 64, 4096)`, and that
    // is a ceiling wearing a generous canvas's clothes: a menu of 9,000 rows
    // rendered exactly **4,096** of them (measured), so the highlight could
    // walk to ordinal 8,999 while the drop-down had no line to slice for it.
    // `measureNaturalExtent`'s ladder starts at the same generous budget — one
    // measure for every menu anybody will ever build by hand — and, unlike the
    // constant, keeps going when the content is taller.
    var sized = context.withAvailableWidth(rowWidth)
    sized.environment.menuRowInset = inset
    // Set before the extent is measured, not after: a row that hugs is measured
    // against the menu's whole interior and a row that is drawn gets that
    // interior less its hint column, and a label can wrap into the difference —
    // which would make the canvas a row short of what the render then draws.
    sized.environment.menuRowWidth = rowWidth
    // …and having changed what a row measures to, say so, or the extent walk and
    // the render below can be answered from the hug above. The two asks here
    // happen to differ in width today, so this is a guard rather than a fix —
    // but it is the same two-question shape as the inline menu's, where it was
    // not a guard. See ``RenderContext/measureGeneration``.
    sized = sized.invalidatingMeasureMemo()
    sized = sized.withAvailableHeight(
        max(1, measureNaturalExtent(
            rowsOnly, along: .vertical,
            proposal: ProposedSize(width: rowWidth, height: nil), context: sized,
            startingBudget: naturalExtentStartingBudget(forVisible: context.availableHeight)
        ).height))
    // Rows report to the column, not to the focus ring. Only a render pass
    // claims an ordinal, so the measure above cannot shift the numbering.
    controller.sink.beginPass()
    sized.environment.menuRowSink = controller.sink
    sized.environment.menuHighlightedOrdinal = controller.highlightedOrdinal
    let column = TUIkit.renderToBuffer(rowsOnly, context: sized)
    controller.adoptRenderedRows()

    // Which lines belong to which row, from the regions the rows themselves
    // published. A line no row claimed is chrome the caller drew.
    var ordinalByLine: [Int: Int] = [:]
    for region in column.hitTestRegions {
        guard let focusID = region.focusID, let ordinal = menuRowOrdinal(fromRegionID: focusID)
        else { continue }
        for line in region.offsetY..<(region.offsetY + region.height) {
            ordinalByLine[line] = ordinal
        }
    }
    let selectable = Set(controller.highlight.selectable)
    var rows: [DropdownMenu.Row] = []
    var rowByOrdinal: [Int: Int] = [:]
    for (line, content) in column.lines.enumerated() {
        if let ordinal = ordinalByLine[line] {
            rowByOrdinal[ordinal] = rows.count
        }
        rows.append(
            .rendered(
                content,
                isSelectable: ordinalByLine[line].map(selectable.contains) ?? false))
    }

    let ordinalByRow = Dictionary(
        uniqueKeysWithValues: rowByOrdinal.map { ($0.value, $0.key) })
    return DropdownMenu.popup(
        DropdownMenu.Configuration(
            rows: rows,
            highlightedRow: controller.highlightedOrdinal.flatMap { rowByOrdinal[$0] },
            innerWidth: rowWidth,
            scroll: controller.scroll,
            followHighlight: controller.highlight.consumeFollowPending(),
            autoRepeatToken: "menu-popup-scrollbar-\(context.identity.path)"),
        context: context,
        // Hover follows the cursor, which a view-composed menu never did: its
        // rows had a hover state of their own but nothing joined it up to the
        // highlight the keyboard was driving.
        onHover: { row in ordinalByRow[row].map(controller.highlight.point(at:)) },
        onActivate: { row in ordinalByRow[row].map(controller.sink.activate(ordinal:)) },
        onDismiss: dismiss)
}

/// Where a presented menu hangs, and off what.
struct MenuAnchor {
    /// The menu's top-left column, in the presenter's own coordinate space.
    let x: Int

    /// The menu's top row, likewise.
    let y: Int

    /// The width to centre the menu within, starting at ``x``, or `nil` to put
    /// its left edge at ``x``.
    ///
    /// A pointer-opened menu is anchored at the cell that was clicked, because
    /// the pointer is about to pick from it and wants the rows in a predictable
    /// place under itself. A KEYBOARD-opened one has no pointer to be
    /// predictable for, so it centres on the view it belongs to and reads as
    /// that view's menu rather than as something that landed in the corner.
    var centredWithin: Int?

    /// How many rows the control immediately above ``y`` occupies.
    ///
    /// `1` for a pop-up ``Menu``, whose trigger is the row above it; `0` for a
    /// `.contextMenu`, which hangs off the cell that was clicked and has
    /// nothing above it to clear. The number does two jobs — the flip when
    /// there is no room below, and an enclosing `ScrollView`'s overlay culling
    /// — and both go wrong when it is understated. See
    /// ``OverlayLayer/anchorHeight``.
    let controlHeight: Int

    init(x: Int, y: Int, controlHeight: Int, centredWithin: Int? = nil) {
        self.x = x
        self.y = y
        self.controlHeight = controlHeight
        self.centredWithin = centredWithin
    }
}

/// Presents `items` as a floating menu over `base`, anchored at
/// (`anchor.x`, `anchor.y`) in `base`'s own coordinate space.
///
/// Takes the focus section, the keyboard, and the screen-covering dismiss
/// backdrop; renders the items as menu rows sized to hug their widest; and
/// appends the result to `base` as a `.popover` overlay. A no-op on a measure
/// pass — presentation is a render-pass side effect, and an ancestor measuring
/// by rendering must not register a phantom section.
///
/// - Parameters:
///   - items: The menu's content: `Button`s and `Divider`s.
///   - base: The buffer to float the menu over; the overlay is appended to it.
///   - controller: The menu's highlight, persisted by the caller across frames.
///     The caller tells it how the menu was opened (``MenuPopupController/opened(withSelection:)``)
///     at the moment it opens, when only the caller knows which device did it.
///   - sectionID: The focus section this menu owns while it is up.
///   - itemsIndex: The child-identity index for `items` under `context`, so its
///     `@State` and focus slots stay distinct from the presenter's own.
///   - anchor: Where the menu's top-left goes, and how tall the control above
///     it is — see ``MenuAnchor``.
///   - dismiss: Closes the menu — run by Escape, by an outside click, and by
///     any item that fires.
///   - context: The presenter's render context.
@MainActor
func presentMenuPopover<Items: View>(
    items: Items,
    over base: inout FrameBuffer,
    controller: MenuPopupController,
    sectionID: String,
    itemsIndex: Int,
    anchor: MenuAnchor,
    dismiss: @escaping () -> Void,
    context: RenderContext
) {
    // A mouse dispatcher is what makes a presentation possible at all — the
    // dismiss backdrop and every row's click region go through it.
    guard !context.isMeasuring, context.environment.mouseEventDispatcher != nil else { return }

    context.environment.volatileReadTracker?.recordRenderSideEffect()
    let focusManager = context.environment.focusManager
    focusManager?.registerSection(id: sectionID)
    focusManager?.activateSection(id: sectionID)
    // Input-grabbing so global chrome hotkeys don't fire behind the menu.
    focusManager?.markSectionModal(id: sectionID)
    // The section deliberately holds NO focus: a pop-up's rows report to the
    // controller, not to the focus ring. Something may still register in here
    // (a tall menu's own ScrollView does), and without this the end of the
    // render pass would hand it the focus for want of anything better.
    focusManager?.markSectionFocusOptional(id: sectionID)
    // Take the keyboard for this section. Isolating the presenter's own subtree
    // silences what is BENEATH the menu, but a menu hangs off one view — its
    // siblings are elsewhere in the tree and render into the live dispatcher
    // every frame, keeping their handlers.
    context.environment.keyEventDispatcher!.grabInput(sectionID: sectionID)
    // Escape closes the MENU, not the page. Claiming the label is what makes
    // that true as well as discoverable: `InputHandler` routes ESC to the focus
    // system before the status bar when an override is posted, and without it
    // the status bar's own "⎋ back" won — so Escape in an open Menu dismissed
    // the whole page behind it. The Picker drop-down has always claimed it;
    // this is the same claim, from the presentation both share.
    context.environment.statusBar?.escapeLabelOverride = MenuPresentationLabels.popUp.close
    attachMenuKeys(controller: controller, sectionID: sectionID, dismiss: dismiss, context: context)

    var menuContext = context
        .withChildIdentity(erasedType: Items.self, index: itemsIndex)
        .withAvailableWidth(context.environment.terminalWidth)
        .withAvailableHeight(context.environment.overlayContentHeight)
    menuContext.environment.activeFocusSectionID = sectionID
    menuContext.environment.dismissMenu = DismissMenuAction(action: dismiss)
    // Explicitly NOT the top-border ●: that mark reads as "this titled
    // container has the focus", and a menu has no title, so a lone dot floating
    // in an otherwise dead frame reads as debris. Left nil, which is also what
    // stops an enclosing section's indicator leaking in. (The FRAME still
    // breathes — the drop-down renderer draws its own border on the shared
    // `SelectionEmphasis` clock, so two menus on one screen agree.)
    menuContext.environment.focusIndicator = nil

    var menuBuffer = renderMenuPopup(
        items, context: menuContext, controller: controller, dismiss: dismiss)
    guard !menuBuffer.isEmpty else { return }

    // The same screen-covering dismiss backdrop the drop-down menus use.
    DropdownMenu.attachDismissBackdrop(to: &menuBuffer, context: context, onDismiss: dismiss)

    // `.popover` level, declaring the control above it. That number does two
    // jobs, and getting it wrong broke both: an enclosing `ScrollView` culls an
    // overlay by `offsetY - anchorHeight`, so a menu whose trigger is the last
    // visible row starts exactly AT the viewport's bottom edge and was thrown
    // away before the compositor saw it (the `Picker` drop-down's version of
    // this is why `anchorHeight` exists); and with no room below, the flip puts
    // the menu's bottom flush with the anchor's TOP, which without a height is
    // flush with the trigger itself — landing the menu on the control that
    // opened it.
    // Centring can only happen here: the menu's width is not known until it has
    // been laid out to its own content.
    var offsetX = anchor.x
    if let span = anchor.centredWithin {
        offsetX = anchor.x + max(0, (span - menuBuffer.width) / 2)
    }
    base.overlays.append(
        OverlayLayer(
            offsetX: offsetX, offsetY: anchor.y, content: menuBuffer,
            level: .popover, anchorHeight: anchor.controlHeight))
}

/// Gives the open menu the whole keyboard: the arrows, the jump gestures every
/// other list-like control in TUIkit answers (Home, End, PageUp, PageDown,
/// Shift+arrow), Enter/Space to choose a row, and Escape to close.
///
/// One handler, because the menu owns an ordinal rather than a focus id — there
/// is no ring underneath to implement half of this. The gestures themselves come
/// from ``OptionListNavigation``, the same helper the `Picker` drop-down, the
/// combo box and `RadioButtonGroup` use, so a menu and a drop-down move
/// identically for the same keystroke.
///
/// Only what the menu acts on is swallowed — exactly what the focus ring
/// swallowed for it before. A key equivalent typed with the menu open must still
/// reach the shortcut registry (`InputHandler` layer 3.5, below this one), which
/// is how a menu row's accelerator fires while its own menu is showing.
@MainActor
private func attachMenuKeys(
    controller: MenuPopupController, sectionID: String, dismiss: @escaping () -> Void,
    context: RenderContext
) {
    guard let dispatcher = context.environment.keyEventDispatcher else { return }
    let multiplier = context.environment.shiftStepMultiplier
    // A page is the menu's visible rows; the cap is what the column was given.
    let pageSize = max(1, context.environment.overlayContentHeight - 2)

    dispatcher.addHandler(sectionID: sectionID) { event in
        switch event.key {
        case .escape:
            dismiss()
            return true
        case .enter, .space:
            return controller.activateHighlighted()
        case .left, .right:
            // On the focus ring these act as Up/Down (`dispatchKeyEvent` treats
            // the axes alike), which in a vertical menu is simply wrong. The
            // Picker drop-down has always eaten them.
            return true
        default:
            return controller.highlight.handle(
                event, multiplier: multiplier, pageSize: pageSize)
        }
    }
}
