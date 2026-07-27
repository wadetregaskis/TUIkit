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
@MainActor
func renderMenuColumn(_ items: some View, context: RenderContext, capHeight: Int) -> FrameBuffer {
    // The items are `Button`s (SwiftUI's API, which TUIkit matches), but a
    // menu's rows must not LOOK like buttons — `_MenuItemButtonStyle` draws them
    // as menu rows, the same idiom as the Picker drop-down.
    let column = VStack(alignment: .leading, spacing: 0) { items }
        .buttonStyle(_MenuItemButtonStyle())
        .padding(.horizontal, 1)
    let menuView = column.border()
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
        .border()
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
    sectionID: String,
    itemsIndex: Int,
    anchor: (x: Int, y: Int),
    dismiss: @escaping () -> Void,
    context: RenderContext
) {
    guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher
    else { return }

    context.environment.volatileReadTracker?.recordRenderSideEffect()
    let focusManager = context.environment.focusManager
    focusManager?.registerSection(id: sectionID)
    focusManager?.activateSection(id: sectionID)
    // Input-grabbing so global chrome hotkeys don't fire behind the menu.
    focusManager?.markSectionModal(id: sectionID)
    // Take the keyboard for this section. Isolating the presenter's own subtree
    // silences what is BENEATH the menu, but a menu hangs off one view — its
    // siblings are elsewhere in the tree and render into the live dispatcher
    // every frame, keeping their handlers.
    context.environment.keyEventDispatcher!.grabInput(sectionID: sectionID)
    context.environment.keyEventDispatcher!.addHandler(sectionID: sectionID) { event in
        guard event.key == .escape else { return false }
        dismiss()
        return true
    }

    var menuContext = context
        .withChildIdentity(erasedType: Items.self, index: itemsIndex)
        .withAvailableWidth(context.environment.terminalWidth)
        .withAvailableHeight(context.environment.overlayContentHeight)
    menuContext.environment.activeFocusSectionID = sectionID
    menuContext.environment.dismissMenu = DismissMenuAction(action: dismiss)
    // The pop-up holds the focus, so say so the way every other focused
    // container does: the breathing accent that `BorderRenderer` turns into a ●
    // on the top edge. `FocusSectionModifier` computes this for a section
    // declared in the view tree; a presented section has no such modifier around
    // it, so it does the same sum itself.
    let accent = menuContext.environment.palette.accent
    let dim = accent.opacity(
        ViewConstants.focusBorderDim, over: menuContext.environment.palette.background)
    menuContext.environment.focusIndicatorColor = Color.lerp(
        dim, accent, phase: context.environment.pulsePhase)

    var menuBuffer = renderMenuColumn(
        items, context: menuContext, capHeight: context.environment.overlayContentHeight)
    guard !menuBuffer.isEmpty else { return }

    // The screen-covering dismiss backdrop, as the drop-down menus do: a
    // first-registered region that closes the menu on any non-wheel press
    // outside it, while every region of the menu itself wins over it and the
    // wheel still falls through to the page.
    let dismissID = dispatcher.register { event in
        switch event.phase {
        case .pressed where !event.button.isWheel:
            dismiss()
            return true
        case .released:
            return true  // the consumed press's matching release
        default:
            return false
        }
    }
    menuBuffer.hitTestRegions.insert(
        HitTestRegion(
            offsetX: -4096, offsetY: -4096, width: 8192, height: 8192, handlerID: dismissID),
        at: 0)

    // `.popover` level; `anchorHeight: 0` nudges it on-screen at the edges
    // rather than flipping above a control.
    base.overlays.append(
        OverlayLayer(
            offsetX: anchor.x, offsetY: anchor.y, content: menuBuffer,
            level: .popover, anchorHeight: 0))
}
