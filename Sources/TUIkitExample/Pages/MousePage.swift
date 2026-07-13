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
    @State var shelfTargeted: Bool = false
    @State var lastScrollDirection: String = "—"

    /// In-flight "poof" removal animations (fruit dragged out of the basket
    /// and dropped in the void), each at its drop point in the drag-and-drop
    /// section's coordinate space.
    @State var poofs: [PoofPuff] = []
    @State var poofGeneration: Int = 0
    @AppStorage("mouseDemo.poofStyle") var poofStyleRaw: Int = 0

    /// A fruit dragged OUT of the basket — a distinct payload type, so the
    /// shelf/void destinations accept basket fruit while the basket keeps
    /// accepting shelf fruit (plain `String`).
    struct BasketFruit {
        let index: Int
        let name: String
    }

    /// One live poof: where it plays and which frame it is on.
    struct PoofPuff: Identifiable {
        let id: Int
        let x: Int
        let y: Int
        var frame: Int = 0
    }

    /// The removal animation, macOS-Dock style: a short frame sequence that
    /// disperses over ~half a second. Each frame draws centred on the drop
    /// point. The styles are deliberately easy to extend — add a case and a
    /// frame list to audition a new look.
    enum PoofStyle: Int, CaseIterable {
        case clouds, sparkle, rings, smoke

        var frames: [String] {
            switch self {
            case .clouds: return ["·", "○", "☁", "☁ ☁", "˚ ˚ ˚", "˚   ˚"]
            case .sparkle: return ["·", "✦", "✸", "✶ ✶", "✧ ✧ ✧", "· ·"]
            case .rings: return ["·", "●", "◉", "○", "◯", "◌"]
            case .smoke: return ["💨", "💨", "☁️", "☁️ ☁️", "· ·"]
            }
        }

        /// A representative glyph — the picker labels the styles with their
        /// own look, so no localization is needed for them.
        var glyph: String {
            switch self {
            case .clouds: return "☁"
            case .sparkle: return "✶"
            case .rings: return "◉"
            case .smoke: return "💨"
            }
        }
    }

    var poofStyle: PoofStyle { PoofStyle(rawValue: poofStyleRaw) ?? .clouds }

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
            // copy instead of a move. Basket fruit drags back OUT: onto the
            // shelf to return it, anywhere else to discard it with a poof —
            // the whole section is the "anywhere else" destination, and the
            // poof plays as a ZStack layer at the drop point.
            DemoSection(L("page.mouse.dragDrop")) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("page.mouse.dragDropHint"))
                            .foregroundStyle(.palette.foregroundSecondary)
                        Text(L("page.mouse.dragOutHint"))
                            .foregroundStyle(.palette.foregroundSecondary)
                        HStack(alignment: .top, spacing: 4) {
                            shelfZone
                            basketZone
                            poofStylePicker
                        }
                    }
                    ForEach(poofs) { poof in
                        poofView(poof)
                    }
                }
                .dropDestination(for: BasketFruit.self) { items, info in
                    // The void: anywhere in the section that isn't the shelf
                    // or the basket discards the fruit with a poof.
                    for item in items {
                        removeFromBasket(item)
                        spawnPoof(x: info.x, y: info.y)
                    }
                    return true
                }
            }
            .task(id: poofGeneration) {
                await runPoofTicker()
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

    /// The shelf: the fruit chips' home, and a drop zone that takes basket
    /// fruit BACK (highlighting while a basket drag hovers it).
    @ViewBuilder private var shelfZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("page.mouse.shelf")).bold()
            ForEach(fruits, id: \.self) { fruit in
                Text(fruit)
                    .padding(EdgeInsets(horizontal: 1, vertical: 0))
                    .border(color: .palette.border)
                    .draggable(fruit)
            }
        }
        .padding(EdgeInsets(horizontal: 1, vertical: 0))
        .border(color: shelfTargeted ? .palette.accent : .palette.border)
        .dropDestination(for: BasketFruit.self) { items, _ in
            for item in items {
                removeFromBasket(item)
                if !fruits.contains(item.name) {
                    fruits.append(item.name)
                }
            }
            return true
        } isTargeted: { targeted in
            shelfTargeted = targeted
        }
    }

    /// The drop zone: highlights while a compatible drag is over it; a plain
    /// drop MOVES the fruit into the basket, a Ctrl-drop COPIES it (DropInfo
    /// carries the modifiers held at release). Basket fruit is itself
    /// draggable — back to the shelf, or into the void for a poof.
    @ViewBuilder private var basketZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("page.mouse.basket")).bold()
            if basket.isEmpty {
                Text(L("page.mouse.basketEmpty"))
                    .foregroundStyle(.palette.foregroundTertiary)
            } else {
                ForEach(basket.indices, id: \.self) { index in
                    Text(basket[index])
                        .draggable(BasketFruit(index: index, name: basket[index]))
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
        // Dropping basket fruit back onto the basket is a no-op — without
        // this, it would fall through to the section's void catcher and
        // poof a fruit that never left home.
        .dropDestination(for: BasketFruit.self) { _, _ in true }
    }

    /// The poof style chooser: the styles label themselves with their own
    /// glyphs, so the look is visible before you pick it.
    @ViewBuilder private var poofStylePicker: some View {
        Picker(L("page.mouse.poofStyle"), selection: $poofStyleRaw) {
            ForEach(PoofStyle.allCases, id: \.rawValue) { style in
                Text(style.glyph).tag(style.rawValue)
            }
        }
        .frame(width: 16)
    }

    /// One poof, drawn centred on its drop point in the section's
    /// coordinate space. `.offset` floats the glyphs there WITHOUT painting
    /// anything else — padding would blank the whole rectangle above-left of
    /// the drop point (ZStack children paint their full bounding box).
    @ViewBuilder private func poofView(_ poof: PoofPuff) -> some View {
        let frames = poofStyle.frames
        let frame = frames[min(poof.frame, frames.count - 1)]
        Text(frame)
            .foregroundStyle(.palette.foregroundSecondary)
            .offset(x: max(0, poof.x - frame.strippedLength / 2), y: max(0, poof.y))
    }

    private func removeFromBasket(_ item: BasketFruit) {
        // The index was captured at drag start; the basket can't mutate
        // mid-drag, but validate anyway and fall back to a name match.
        if basket.indices.contains(item.index), basket[item.index] == item.name {
            basket.remove(at: item.index)
        } else if let index = basket.firstIndex(of: item.name) {
            basket.remove(at: index)
        }
    }

    private func spawnPoof(x: Int, y: Int) {
        poofs.append(PoofPuff(id: poofGeneration, x: x, y: y))
        poofGeneration += 1
    }

    /// Ticks the live poofs' frames (~90 ms cadence) until they all finish;
    /// each spawn bumps `poofGeneration`, restarting the `.task(id:)`.
    private func runPoofTicker() async {
        let frameCount = poofStyle.frames.count
        while !poofs.isEmpty {
            try? await Task.sleep(nanoseconds: 90_000_000)
            poofs = poofs.compactMap { poof in
                var advanced = poof
                advanced.frame += 1
                return advanced.frame < frameCount ? advanced : nil
            }
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
