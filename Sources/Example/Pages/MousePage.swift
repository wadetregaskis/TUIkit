//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MousePage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
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
    @State private var tapCount: Int = 0
    @State private var lastTapAt: String = "—"
    @State private var scrollDeltaY: Int = 0
    @State private var scrollDeltaX: Int = 0
    @State private var dragPhase: String = L("page.mouse.phaseIdle")
    @State private var dragX: Int = 0
    @State private var dragY: Int = 0
    @State private var dragDeltaX: Int = 0
    @State private var dragDeltaY: Int = 0
    @State private var rightClicks: Int = 0
    @State private var lastModifier: String = "—"
    @State private var isHovering: Bool = false
    @State private var scrollTicks: Int = 0
    @State private var fruits: [String] = ["🍎 Apple", "🍐 Pear", "🍇 Grapes"]
    @State private var basket: [String] = []
    @State private var basketTargeted: Bool = false
    @State private var shelfTargeted: Bool = false
    @State private var lastScrollDirection: String = "—"

    /// In-flight "poof" removal animations (fruit dragged out of the basket
    /// and dropped in the void), each at its drop point in the drag-and-drop
    /// section's coordinate space.
    @State private var poofs: [PoofPuff] = []
    @State private var poofGeneration: Int = 0
    @AppStorage("mouseDemo.poofStyle") var poofStyleRaw: Int = 0

    /// A fruit dragged OUT of the basket — a distinct payload type, so the
    /// shelf/void destinations accept basket fruit while the basket keeps
    /// accepting shelf fruit (plain `String`).
    struct BasketFruit {
        let index: Int
        let name: String
    }

    /// One live poof: where it plays, how big the thing that vanished was,
    /// and which frame it is on.
    ///
    /// The size is the drag preview's, so a puff is the size of what it
    /// replaced. A fixed six-cell puff read as the same small event whether a
    /// one-word chip or a whole row had gone.
    struct PoofPuff: Identifiable {
        let id: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
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
        // The poof layer and the "void" drop target wrap the WHOLE page, not
        // just the drag-and-drop section.
        //
        // They used to wrap only that section, which made discarding a fruit
        // depend on where in the page you happened to release it: inside the
        // section's bounds it poofed, one row below them the drop was refused
        // and the fruit flew home. Nothing draws those bounds, so the same
        // gesture looked like it did two different things at random. The rule
        // is now the one you would state out loud — a fruit dragged out of the
        // basket is discarded unless it lands on the shelf.
        //
        // `DropInfo`'s coordinates are DESTINATION-LOCAL, so the poof overlay
        // has to be the same view as the drop target or the puff would appear
        // somewhere other than where the fruit was let go.
        ZStack(alignment: .topLeading) {
            pageContent
            ForEach(poofs) { poof in
                poofView(poof)
            }
        }
        .dropDestination(for: BasketFruit.self) { items, info in
            // Anywhere that isn't the shelf (move) or the basket (no-op, it
            // never left) discards the fruit — puffing from the CENTRE of the
            // drag image, where the fruit visually is, not from the cursor.
            for item in items {
                removeFromBasket(item)
                spawnPoof(
                    x: info.previewX + info.previewWidth / 2,
                    y: info.previewY + info.previewHeight / 2,
                    width: info.previewWidth, height: info.previewHeight)
            }
            return true
        }
        .task(id: poofGeneration) {
            await runPoofTicker()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader(
                "menu.item.mouse",
                subtitle:
                    "page.mouse.subtitle"
            )
        }
    }

    @ViewBuilder private var pageContent: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.mouse.tapCounter") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.tapInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.mouse.clickMe")
                        .bold()
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(.palette.border)
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
                        ValueDisplayRow("page.mouse.tapsLabel", "\(tapCount)")
                        ValueDisplayRow("page.mouse.lastTapAtLabel", lastTapAt)
                    }
                }
            }

            DemoSection("page.mouse.scrollCounter") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.scrollInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.mouse.scrollTerminalNote")
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
                    .border(.palette.border)
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
                        ValueDisplayRow("page.mouse.verticalLabel", "\(scrollDeltaY)")
                        ValueDisplayRow("page.mouse.horizontalLabel", "\(scrollDeltaX)")
                    }
                }
            }

            DemoSection("page.mouse.dragTracker") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.dragInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.mouse.dragArea")
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(.palette.border)
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
                        ValueDisplayRow("page.mouse.phaseLabel", dragPhase)
                        ValueDisplayRow("page.mouse.atLabel", "(\(dragX), \(dragY))")
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
            DemoSection("page.mouse.dragDrop") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.dragDropHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.mouse.dragOutHint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // Three drag demos, one per layer, and none of them
                    // spare: this section is the API, the auto-scroll
                    // section below is what a SCROLLABLE does during a
                    // drag, and the Lists page is what ROWS do. The note
                    // says so, so the overlap doesn't read as duplication.
                    Text("page.mouse.dragDropRowsNote")
                        .foregroundStyle(.palette.foregroundTertiary)
                        .dim()
                    HStack(alignment: .top, spacing: 4) {
                        shelfZone
                        basketZone
                        poofStylePicker
                    }
                }
            }

            DragScrollDemoSection()

            DemoSection("page.mouse.rawEvents") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.rawEventsInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // Modifier-click forwarding is terminal-specific and not
                    // queryable (no escape sequence reports it), so the best
                    // we can do is a static note per host. Byte-captured
                    // (Terminal-compatibility.md): iTerm2 forwards ⌘ as the
                    // meta bit and swallows ⌥; Apple Terminal strips ⌘ and
                    // forwards ⌥. iTerm2 also keeps right-clicks for its own
                    // context menu by default.
                    // Asked of TerminalClient, not of TERM_PROGRAM: the
                    // variable is only ONE of the signals that names a host,
                    // and it is the one an ssh hop drops — so reading it
                    // directly made this note disagree with the renderer
                    // whenever the terminal was identified any other way.
                    switch TerminalClient.current.program {
                    case .iTerm2:
                        Text("page.mouse.iTerm2RightClickNote")
                            .foregroundStyle(.palette.foregroundTertiary)
                            .dim()
                    case .appleTerminal:
                        Text("page.mouse.appleTerminalModifierNote")
                            .foregroundStyle(.palette.foregroundTertiary)
                            .dim()
                    default:
                        EmptyView()
                    }
                    Text("page.mouse.rightOrModifiedClick")
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(.palette.border)
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
                        ValueDisplayRow("page.mouse.rightClicksLabel", "\(rightClicks)")
                        ValueDisplayRow("page.mouse.modifiersLabel", lastModifier)
                    }
                }
            }

            DemoSection("page.mouse.hover") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.hoverInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(isHovering ? L("page.mouse.hovering") : L("page.mouse.hoverMe"))
                        .bold()
                        .foregroundStyle(isHovering ? .palette.accent : .palette.foregroundSecondary)
                        .frame(width: hoverLabelWidth, alignment: .center)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(isHovering ? .palette.accent : .palette.border)
                        .onHover { hovering in
                            isHovering = hovering
                        }
                    ValueDisplayRow("page.mouse.stateLabel", isHovering ? L("page.mouse.stateHovering") : L("page.mouse.stateOutside"))
                }
            }

            DemoSection("page.mouse.scrollGesture") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.mouse.scrollGestureInstruction")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("page.mouse.scrollOverMe")
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(.palette.border)
                        .onScrollGesture { direction in
                            scrollTicks += 1
                            lastScrollDirection = describeScroll(direction)
                        }
                    HStack(spacing: 2) {
                        ValueDisplayRow("page.mouse.ticksLabel", "\(scrollTicks)")
                        ValueDisplayRow("page.mouse.lastDirectionLabel", lastScrollDirection)
                    }
                }
            }

            Spacer()
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
            Text("page.mouse.shelf").bold()
            ForEach(fruits, id: \.self) { fruit in
                Text(fruit)
                    .padding(EdgeInsets(horizontal: 1, vertical: 0))
                    .border(.palette.border)
                    .draggable(fruit)
            }
        }
        .padding(EdgeInsets(horizontal: 1, vertical: 0))
        .border(shelfTargeted ? .palette.accent : .palette.border)
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
            Text("page.mouse.basket").bold()
            if basket.isEmpty {
                Text("page.mouse.basketEmpty")
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
        .border(basketTargeted ? .palette.accent : .palette.border)
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
        Picker("page.mouse.poofStyle", selection: $poofStyleRaw) {
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
        let index = min(poof.frame, frames.count - 1)
        // How far through the dispersal this frame is: the puff opens out from
        // a point to the whole footprint of what vanished.
        let progress = Double(index + 1) / Double(frames.count)
        let lines = Self.puffLines(
            pattern: frames[index], progress: progress,
            width: poof.width, height: poof.height)
        let boxWidth = lines.map(\.strippedLength).max() ?? 1
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { row in
                Text(verbatim: row.element)
            }
        }
        .foregroundStyle(.palette.foregroundSecondary)
        .offset(
            x: max(0, poof.x - boxWidth / 2),
            y: max(0, poof.y - lines.count / 2))
    }

    /// One frame of a puff, laid out across the footprint of what vanished.
    ///
    /// The style's frame string is the vocabulary — which glyphs this moment
    /// of the dispersal uses — and `progress` is how much of the box they are
    /// spread over. So the same six frames read as a small puff for a chip and
    /// a large one for a whole row, without a second set of frames per size.
    ///
    /// Widths are counted in CELLS, not characters (`strippedLength`): `💨` is
    /// two of them, and a puff laid out by character count would drift as it grew.
    static func puffLines(
        pattern: String, progress: Double, width: Int, height: Int
    ) -> [String] {
        let glyphs = pattern.filter { !$0.isWhitespace }.map(String.init)
        guard !glyphs.isEmpty else { return [""] }
        // Half again the footprint at the last frame. Proportionate to what
        // vanished, and bigger than it — a puff exactly the size of the thing
        // it replaced reads as a substitution rather than as something
        // dispersing. Never narrower than the pattern itself, so a one-cell
        // item still gets a puff rather than a single glyph.
        let natural = glyphs.reduce(0) { $0 + $1.strippedLength } + glyphs.count - 1
        let spanWidth = max(
            Int((Double(natural) * progress).rounded()),
            Int((Double(width) * 1.5 * progress).rounded()), 1)
        let spanHeight = max(1, Int((Double(height) * 1.5 * progress).rounded()))
        return (0..<spanHeight).map { row in
            // Alternate rows take the glyphs in the other order, so a puff more
            // than one row tall does not draw the same column twice.
            let ordered = row.isMultiple(of: 2) ? glyphs : Array(glyphs.reversed())
            var line = ""
            for (index, glyph) in ordered.enumerated() {
                // Evenly spaced CENTRES: glyph i sits at (2i+1)/2n of the span,
                // which puts one glyph in the middle and never against an edge.
                let centre = (2 * index + 1) * spanWidth / (2 * ordered.count)
                let pad = centre - line.strippedLength
                if pad > 0 { line += String(repeating: " ", count: pad) }
                line += glyph
            }
            return line
        }
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

    private func spawnPoof(x: Int, y: Int, width: Int, height: Int) {
        poofs.append(
            PoofPuff(
                id: poofGeneration, x: x, y: y,
                width: max(1, width), height: max(1, height)))
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

    /// The wider of the two hover captions, in cells.
    ///
    /// The caption swaps when the cursor arrives, and a box that sizes to its
    /// content would resize under the cursor — correct framework behaviour, but
    /// it makes the demo look like the hover moved something. Pinning to the
    /// wider caption keeps the box still while the text inside it changes.
    ///
    /// Measured rather than hard-coded because the two run to very different
    /// lengths across the seven translations, and in cells rather than
    /// characters, so the CJK captions are counted at the two columns they
    /// actually occupy.
    private var hoverLabelWidth: Int {
        func cells(_ text: String) -> Int { text.reduce(0) { $0 + $1.terminalWidth } }
        return max(cells(L("page.mouse.hovering")), cells(L("page.mouse.hoverMe")))
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
