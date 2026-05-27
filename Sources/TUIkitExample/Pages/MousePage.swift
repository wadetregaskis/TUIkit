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
    @State var dragPhase: String = "idle"
    @State var dragX: Int = 0
    @State var dragY: Int = 0
    @State var dragDeltaX: Int = 0
    @State var dragDeltaY: Int = 0
    @State var rightClicks: Int = 0
    @State var lastModifier: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("Tap Counter") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Click the box. Coordinates are local to the box's top-left.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("[ Click me ]")
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
                        ValueDisplayRow("Taps:", "\(tapCount)")
                        ValueDisplayRow("Last tap at:", lastTapAt)
                    }
                }
            }

            DemoSection("Scroll Counter") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scroll inside the box. Hold Shift to scroll horizontally.")
                        .foregroundStyle(.palette.foregroundSecondary)
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
                            if event.shift { scrollDeltaX -= 1 }
                            else { scrollDeltaY += 1 }
                            return true
                        case .scrollDown:
                            if event.shift { scrollDeltaX += 1 }
                            else { scrollDeltaY -= 1 }
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
                        ValueDisplayRow("Vertical:", "\(scrollDeltaY)")
                        ValueDisplayRow("Horizontal:", "\(scrollDeltaX)")
                    }
                }
            }

            DemoSection("Drag Tracker") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Press and drag across the box. Coords are clamped to its visible area.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("┊  drag area  ┊")
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
                        ValueDisplayRow("Phase:", dragPhase)
                        ValueDisplayRow("At:", "(\(dragX), \(dragY))")
                        ValueDisplayRow("Δ:", "(\(dragDeltaX), \(dragDeltaY))")
                    }
                }
            }

            DemoSection("Raw Events (right-click / modifiers)") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Right-click the box, or hold Shift / Ctrl / Alt while clicking.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("[ right- or modified-click here ]")
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
                        ValueDisplayRow("Right-clicks:", "\(rightClicks)")
                        ValueDisplayRow("Modifiers:", lastModifier)
                    }
                }
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader(
                "Mouse Demo",
                subtitle:
                    "Tap, scroll, drag, and raw events on arbitrary views"
            )
        }
    }

    /// Visible interior dimensions of the tap target — used to clamp
    /// reported tap coordinates. Width = label width plus the box's
    /// 2-column horizontal padding on each side, plus the two border
    /// characters. Height = 1 row of content plus the two border rows.
    private var tapBoxWidth: Int { "[ Click me ]".count + 4 + 2 }
    private var tapBoxHeight: Int { 3 }

    /// Visible interior dimensions of the drag target.
    private var dragBoxWidth: Int { "┊  drag area  ┊".count + 4 + 2 }
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

    private func describePhase(_ phase: DragGestureEvent.Phase) -> String {
        switch phase {
        case .began: return "began"
        case .moved: return "moved"
        case .ended: return "ended"
        }
    }

    private func modifierString(_ event: MouseEvent) -> String {
        var parts: [String] = []
        if event.shift { parts.append("Shift") }
        if event.ctrl { parts.append("Ctrl") }
        if event.meta { parts.append("Alt") }
        if parts.isEmpty {
            return event.button == .right ? "(plain right-click)" : "(plain left-click)"
        }
        return parts.joined(separator: "+")
    }
}
