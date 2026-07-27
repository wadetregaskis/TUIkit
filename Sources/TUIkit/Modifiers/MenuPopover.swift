//  🖥️ TUIKit — Terminal UI Kit for Swift
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
///   - controller: The open pop-up's highlight, or `nil` for an INLINE menu —
///     whose rows are the page's own focus stops and must stay that way (see
///     `Documentation/Unifying the menu implementations.md`). When present the
///     rows report themselves to it instead of to the focus manager.
@MainActor
func renderMenuColumn(
    _ items: some View, context: RenderContext, capHeight: Int, borderColor: Color? = nil,
    controller: MenuPopupController? = nil
) -> FrameBuffer {
    // The items are `Button`s (SwiftUI's API, which TUIkit matches), but a
    // menu's rows must not LOOK like buttons — `_MenuItemButtonStyle` draws them
    // as menu rows, the same idiom as the Picker drop-down.
    let column = VStack(alignment: .leading, spacing: 0) { items }
        .buttonStyle(_MenuItemButtonStyle())
        .padding(.horizontal, 1)
    let menuView = column.border(color: borderColor)
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
    // A pop-up's rows answer to the column, not to the focus ring: each claims
    // an ordinal here and reports its action back, and the highlighted one is
    // named as the reveal target so a menu taller than its cap scrolls to it
    // (the rows have no focus id for the usual reveal to find).
    //
    // Set on `sized`, after the width is known: a row that learned its width up
    // front would report it, and the menu would size itself from its own guess.
    // Only the render pass claims an ordinal, so the measures either side of it
    // cannot shift the numbering.
    if let controller {
        controller.sink.beginPass()
        sized.environment.menuRowSink = controller.sink
        sized.environment.menuHighlightedOrdinal = controller.highlightedOrdinal
        sized.environment.revealTargetID = controller.revealTargetID
    }
    defer { controller?.adoptRenderedRows() }

    // Does it fit? Measured against a canvas TALLER than the cap, because a
    // measure is clamped to the context's `availableHeight` — and for an inline
    // menu the cap IS the available height, so measuring in place always
    // answers "it fits" and the overflowing rows are simply dropped. The canvas
    // is the same generous one `ScrollView` measures its own content against.
    let canvas = sized.withAvailableHeight(max(capHeight * 64, 4096))
    let fullHeight = measureChild(
        menuView, proposal: ProposedSize(width: menuWidth, height: nil), context: canvas
    ).height
    guard capHeight > 0, fullHeight > capHeight else {
        return renderToBuffer(menuView, context: sized)
    }
    // Taller than its budget: scroll inside it. The scroll goes INSIDE the
    // border, not around it — a ScrollView's "N more above/below" indicators
    // replace its first and last visible rows, which around the border would
    // eat the border itself. The content renders at its full height inside the
    // viewport, which is what lets the reveal bring an off-screen item back
    // (`ScrollViewReveal`).
    let scrolled = ScrollView(.vertical) { column }
        .frame(height: max(1, capHeight - 2))
        .border(color: borderColor)
    return renderToBuffer(scrolled, context: sized.withAvailableHeight(fullHeight))
}

/// Presents `items` as a floating menu over `base`, anchored at
/// (`anchorX`, `anchorY`) in `base`'s own coordinate space.
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
///   - anchor: Where the menu's top-left goes, in `base`'s coordinates.
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
    anchor: (x: Int, y: Int),
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
    context.environment.statusBar.escapeLabelOverride = "close menu"
    attachMenuKeys(controller: controller, sectionID: sectionID, dismiss: dismiss, context: context)

    var menuContext = context
        .withChildIdentity(erasedType: Items.self, index: itemsIndex)
        .withAvailableWidth(context.environment.terminalWidth)
        .withAvailableHeight(context.environment.overlayContentHeight)
    menuContext.environment.activeFocusSectionID = sectionID
    menuContext.environment.dismissMenu = DismissMenuAction(action: dismiss)
    // The pop-up holds the focus and the keyboard while it is up, so its whole
    // FRAME breathes — the same affordance the Picker drop-down uses, on the
    // same clock (`SelectionEmphasis`), so two menus on one screen agree.
    //
    // Explicitly NOT the top-border ●: that mark reads as "this titled
    // container has the focus", and a menu has no title, so a lone dot floating
    // in an otherwise dead frame reads as debris. Left nil, which is also what
    // stops an enclosing section's indicator leaking in.
    menuContext.environment.focusIndicatorColor = nil
    let palette = menuContext.environment.palette
    let accent = palette.accent
    let borderColor = SelectionIndicator.resolve(isFocused: true, context: menuContext)
        .color(dim: accent.opacity(ViewConstants.focusBorderDim, over: palette.background),
               bright: accent)

    var menuBuffer = renderMenuColumn(
        items, context: menuContext, capHeight: context.environment.overlayContentHeight,
        borderColor: borderColor, controller: controller)
    guard !menuBuffer.isEmpty else { return }

    // The same screen-covering dismiss backdrop the drop-down menus use.
    DropdownMenu.attachDismissBackdrop(to: &menuBuffer, context: context, onDismiss: dismiss)

    // `.popover` level; `anchorHeight: 0` nudges it on-screen at the edges
    // rather than flipping above a control.
    base.overlays.append(
        OverlayLayer(
            offsetX: anchor.x, offsetY: anchor.y, content: menuBuffer,
            level: .popover, anchorHeight: 0))
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
