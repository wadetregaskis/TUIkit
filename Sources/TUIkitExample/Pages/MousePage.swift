//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MousePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Mouse demo page.
///
/// Showcases the four public mouse modifiers:
///   - `.onTapGesture` — discrete left-clicks (also covered by Button)
///   - `.onScrollGesture` — wheel ticks
///   - `.onDragGesture` — continuous press / drag / release with translation
///   - `.onMouseEvent` — the raw stream of events, useful for hover
///     effects, right-clicks, and modifier-keyed clicks.
///
/// The built-in controls (Button, Toggle, Slider, Stepper, List) all
/// respond to mouse input directly; this page focuses on the more
/// exotic interactions where you wire mouse events into your own
/// views.
struct MousePage: View {
    @State var tapCount: Int = 0
    @State var lastTapAt: String = "—"
    @State var scrollDeltaY: Int = 0
    @State var scrollDeltaX: Int = 0
    @State var dragPhase: String = L("page.mouse.phaseIdle")
    @State var dragX: Int = 0
    @State var dragY: Int = 0
    @State var dragDeltaX: Int = 0
    @State var dragDeltaY: Int = 0
    @State var rightClicks: Int = 0
    @State var lastModifier: String = "—"
    @State var isHovering: Bool = false
    @State var scrollTicks: Int = 0
    @State var fruits: [String] = ["🍎 Apple", "🍐 Pear", "🍇 Grapes"]
    @State var basket: [String] = []
    @State var basketTargeted: Bool = false
    @State var lastScrollDirection: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection(L("page.mouse.tapCounter")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.tapInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.mouse.clickMe"))
                        .bold()
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onTapGesture { x, y in
                            tapCount += 1
                            // Coordinates are local but the box's own
                            // border + padding mean the reported x/y
                            // can range up to the buffer's full width/
                            // height. Clamp to the visible interior so
                            // the readout is intuitive.
                            let cx = max(0, min(tapBoxWidth - 1, x))
                            let cy = max(0, min(tapBoxHeight - 1, y))
                            lastTapAt = "(\(cx), \(cy))"
                        }
                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.mouse.tapsLabel"), "\(tapCount)")
                        ValueDisplayRow(L("page.mouse.lastTapAtLabel"), lastTapAt)
                    }
                }
            }

            DemoSection(L("page.mouse.scrollCounter")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.scrollInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.mouse.scrollTerminalNote"))
                        .foregroundStyle(.palette.foregroundTertiary)
                        .dim()
                    // 2-D scroll position display. The vertical and
                    // horizontal axes each get their own line so you
                    // can see independent accumulation.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<scrollFieldHeight) { row in
                            Text(scrollField(row: row))
                                .foregroundStyle(.palette.accent)
                        }
                    }
                    .padding(EdgeInsets(horizontal: 2, vertical: 0))
                    .border(color: .palette.border)
                    .onMouseEvent { event in
                        // Use the raw event stream so we can read
                        // shift to route the wheel sideways.
                        switch event.button {
                        case .scrollUp:
                            if event.shift {
                                scrollDeltaX -= 1
                            } else {
                                scrollDeltaY += 1
                            }

                            return true
                        case .scrollDown:
                            if event.shift {
                                scrollDeltaX += 1
                            } else {
                                scrollDeltaY -= 1
                            }

                            return true
                        case .scrollLeft:
                            scrollDeltaX -= 1
                            return true
                        case .scrollRight:
                            scrollDeltaX += 1
                            return true
                        default:
                            return false
                        }
                    }
                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.mouse.verticalLabel"), "\(scrollDeltaY)")
                        ValueDisplayRow(L("page.mouse.horizontalLabel"), "\(scrollDeltaX)")
                    }
                }
            }

            DemoSection(L("page.mouse.dragTracker")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.dragInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.mouse.dragArea"))
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onDragGesture { event in
                            dragPhase = describePhase(event.phase)
                            // Clamp the drag position to the visible
                            // box. Drag-capture lets the gesture
                            // continue when the cursor leaves the
                            // box, so without clamping the reported
                            // coords can go negative or grow huge.
                            dragX = max(0, min(dragBoxWidth - 1, event.x))
                            dragY = max(0, min(dragBoxHeight - 1, event.y))
                            dragDeltaX = event.translationX
                            dragDeltaY = event.translationY
                        }
                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.mouse.phaseLabel"), dragPhase)
                        ValueDisplayRow(L("page.mouse.atLabel"), "(\(dragX), \(dragY))")
                        ValueDisplayRow("Δ:", "(\(dragDeltaX), \(dragDeltaY))")
                    }
                }
            }

            // `.draggable` / `.dropDestination`: press a chip and drag — its
            // preview follows the cursor; the basket highlights while
            // targeted, and DropInfo's modifiers turn a Ctrl-drop into a
            // copy instead of a move.
            DemoSection(L("page.mouse.dragDrop")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.dragDropHint"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    HStack(alignment: .top, spacing: 4) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(fruits, id: \.self) { fruit in
                                Text(fruit)
                                    .padding(EdgeInsets(horizontal: 1, vertical: 0))
                                    .border(color: .palette.border)
                                    .draggable(fruit)
                            }
                        }
                        basketZone
                    }
                }
            }

            DemoSection(L("page.mouse.rawEvents")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.rawEventsInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.mouse.rightOrModifiedClick"))
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onMouseEvent { event in
                            switch event.phase {
                            case .pressed where event.button == .right:
                                rightClicks += 1
                                lastModifier = modifierString(event)
                                return true
                            case .pressed where event.button == .left:
                                lastModifier = modifierString(event)
                                return true
                            default:
                                return false
                            }
                        }
                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.mouse.rightClicksLabel"), "\(rightClicks)")
                        ValueDisplayRow(L("page.mouse.modifiersLabel"), lastModifier)
                    }
                }
            }

            DemoSection(L("page.mouse.hover")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.hoverInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(isHovering ? L("page.mouse.hovering") : L("page.mouse.hoverMe"))
                        .bold()
                        .foregroundStyle(isHovering ? .palette.accent : .palette.foregroundSecondary)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: isHovering ? .palette.accent : .palette.border)
                        .onHover { hovering in
                            isHovering = hovering
                        }
                    ValueDisplayRow(L("page.mouse.stateLabel"), isHovering ? L("page.mouse.stateHovering") : L("page.mouse.stateOutside"))
                }
            }

            DemoSection(L("page.mouse.scrollGesture")) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("page.mouse.scrollGestureInstruction"))
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(L("page.mouse.scrollOverMe"))
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onScrollGesture { direction in
                            scrollTicks += 1
                            lastScrollDirection = describeScroll(direction)
                        }
                    HStack(spacing: 2) {
                        ValueDisplayRow(L("page.mouse.ticksLabel"), "\(scrollTicks)")
                        ValueDisplayRow(L("page.mouse.lastDirectionLabel"), lastScrollDirection)
                    }
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(
                L("page.mouse.title"),
                subtitle:
                    L("page.mouse.subtitle")
            )
        }
    }

    /// Visible interior dimensions of the tap target — used to clamp
    /// reported tap coordinates. Width = label width plus the box's
    /// 2-column horizontal padding on each side, plus the two border
    /// characters. Height = 1 row of content plus the two border rows.
    private var tapBoxWidth: Int { L("page.mouse.clickMe").count + 4 + 2 }
    private var tapBoxHeight: Int { 3 }

    /// Visible interior dimensions of the drag target.
    private var dragBoxWidth: Int { L("page.mouse.dragArea").count + 4 + 2 }
    private var dragBoxHeight: Int { 3 }

    /// Horizontal width of the 2-D scroll field, in cells.
    private var scrollFieldWidth: Int { 41 }

    /// Vertical height of the 2-D scroll field, in rows.
    private var scrollFieldHeight: Int { 9 }

    /// Renders one row of the 2-D scroll field. The cursor (`●`) is
    /// placed at the position determined by accumulated scrollDeltaX
    /// (horizontal) and scrollDeltaY (vertical), clamped to the field's
    /// bounds so the indicator never wanders off the visible area.
    private func scrollField(row: Int) -> String {
        // Vertical position: 0 = top, scrollFieldHeight-1 = bottom.
        // Up-scroll moves the cursor upward (lower y), down moves it
        // downward (higher y). Centre is the rest position.
        let centreY = scrollFieldHeight / 2
        let posY = max(0, min(scrollFieldHeight - 1, centreY - scrollDeltaY))
        let centreX = scrollFieldWidth / 2
        let posX = max(0, min(scrollFieldWidth - 1, centreX + scrollDeltaX))
        var chars = Array(repeating: Character("·"), count: scrollFieldWidth)
        if row == posY {
            chars[posX] = "●"
        } else if row == centreY {
            // Horizontal centre-line baseline for orientation.
            chars[centreX] = "+"
        }
        return String(chars)
    }

    /// The drop zone: highlights while a compatible drag is over it; a plain
    /// drop MOVES the fruit into the basket, a Ctrl-drop COPIES it (DropInfo
    /// carries the modifiers held at release).
    @ViewBuilder private var basketZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("page.mouse.basket")).bold()
            if basket.isEmpty {
                Text(L("page.mouse.basketEmpty"))
                    .foregroundStyle(.palette.foregroundTertiary)
            } else {
                ForEach(basket.indices, id: \.self) { index in
                    Text(basket[index])
                }
            }
        }
        .padding(EdgeInsets(horizontal: 1, vertical: 0))
        .frame(width: 24)
        .border(color: basketTargeted ? .palette.accent : .palette.border)
        .dropDestination(for: String.self) { items, info in
            for item in items {
                basket.append(item)
                if !info.ctrl {
                    fruits.removeAll { $0 == item }
                }
            }
            return true
        } isTargeted: { targeted in
            basketTargeted = targeted
        }
    }

    private func describePhase(_ phase: DragGestureEvent.Phase) -> String {
        switch phase {
        case .began: return L("page.mouse.phaseBegan")
        case .moved: return L("page.mouse.phaseMoved")
        case .ended: return L("page.mouse.phaseEnded")
        }
    }

    private func describeScroll(_ direction: ScrollDirection) -> String {
        switch direction {
        case .up: return L("page.mouse.directionUp")
        case .down: return L("page.mouse.directionDown")
        case .left: return L("page.mouse.directionLeft")
        case .right: return L("page.mouse.directionRight")
        }
    }

    private func modifierString(_ event: MouseEvent) -> String {
        var parts: [String] = []
        if event.shift { parts.append("Shift") }
        if event.ctrl { parts.append("Ctrl") }
        if event.meta { parts.append("Alt") }
        if parts.isEmpty {
            return event.button == .right ? L("page.mouse.plainRightClick") : L("page.mouse.plainLeftClick")
        }
        return parts.joined(separator: "+")
    }
}
