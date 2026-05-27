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
                    Text("Click the box. Each release counts as one tap.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("[ Click me ]")
                        .bold()
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onTapGesture { x, y in
                            tapCount += 1
                            lastTapAt = "(\(x), \(y))"
                        }
                    HStack(spacing: 2) {
                        ValueDisplayRow("Taps:", "\(tapCount)")
                        ValueDisplayRow("Last tap at:", lastTapAt)
                    }
                }
            }

            DemoSection("Scroll Counter") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scroll the wheel inside the box.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text(scrollBar())
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onScrollGesture { direction in
                            switch direction {
                            case .up: scrollDeltaY += 1
                            case .down: scrollDeltaY -= 1
                            case .left: scrollDeltaX -= 1
                            case .right: scrollDeltaX += 1
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
                    Text("Press and drag across the box — release outside it still tracks.")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Text("┊  drag area  ┊")
                        .foregroundStyle(.palette.accent)
                        .padding(EdgeInsets(horizontal: 2, vertical: 0))
                        .border(color: .palette.border)
                        .onDragGesture { event in
                            dragPhase = describePhase(event.phase)
                            dragX = event.x
                            dragY = event.y
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

    /// Renders a simple visual bar representing accumulated vertical scroll.
    private func scrollBar() -> String {
        let clampedDelta = max(-20, min(20, scrollDeltaY))
        let position = clampedDelta + 20  // 0…40
        let bar = String(repeating: "·", count: 41).enumerated().map { i, ch in
            i == position ? "▲" : String(ch)
        }.joined()
        return bar
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
