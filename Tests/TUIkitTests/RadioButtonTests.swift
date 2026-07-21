//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RadioButtonTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

private func createTestContext(width: Int = 80, height: Int = 24) -> RenderContext {
    makeRenderContext(width: width, height: height)
}

// MARK: - Radio Button Item Tests

@MainActor
@Suite("RadioButtonItem Tests")
struct RadioButtonItemTests {

    @Test("RadioButtonItem can be created with string value and string label")
    func itemCreationString() {
        let item = RadioButtonItem("option1", "Option 1")
        #expect(item.value == "option1")
    }

    @Test("RadioButtonItem can be created with string value and view label")
    func itemCreationView() {
        let item = RadioButtonItem("option1") {
            Text("Custom Label")
        }
        #expect(item.value == "option1")
    }

    @Test("RadioButtonItem can be created with int value")
    func itemCreationInt() {
        let item = RadioButtonItem(1, "First Option")
        #expect(item.value == 1)
    }
}

// MARK: - Radio Button Group Tests

@MainActor
@Suite("RadioButtonGroup Tests", .serialized)
struct RadioButtonGroupTests {

    @Test("RadioButtonGroup can be created with items")
    func groupCreation() {
        var selection: String = "option1"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding) {
            RadioButtonItem("option1", "First")
            RadioButtonItem("option2", "Second")
            RadioButtonItem("option3", "Third")
        }

        #expect(group.items.count == 3)
        #expect(group.isDisabled == false)
        #expect(group.orientation == .vertical)
    }

    @Test("RadioButtonGroup with horizontal orientation")
    func groupHorizontalOrientation() {
        var selection: String = "a"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding, orientation: .horizontal) {
            RadioButtonItem("a", "A")
            RadioButtonItem("b", "B")
        }

        #expect(group.orientation == .horizontal)
    }

    @Test("RadioButtonGroup disabled modifier")
    func groupDisabledModifier() {
        var selection: String = "x"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding) {
            RadioButtonItem("x", "X")
        }.disabled()

        #expect(group.isDisabled == true)

        let enabled = RadioButtonGroup(selection: binding) {
            RadioButtonItem("x", "X")
        }.disabled(false)

        #expect(enabled.isDisabled == false)
    }

    @Test("RadioButtonGroup renders items vertically")
    func renderVertical() {
        let context = createTestContext()

        var selection: String = "opt1"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding, orientation: .vertical) {
            RadioButtonItem("opt1", "Option 1")
            RadioButtonItem("opt2", "Option 2")
            RadioButtonItem("opt3", "Option 3")
        }

        let buffer = renderToBuffer(group, context: context)

        // Vertical: should have 3 lines (one per item)
        #expect(buffer.height == 3)
        let content = buffer.lines.joined()
        #expect(content.contains("Option 1"))
        #expect(content.contains("Option 2"))
        #expect(content.contains("Option 3"))
    }

    @Test("RadioButtonGroup renders items horizontally")
    func renderHorizontal() {
        let context = createTestContext()

        var selection: String = "a"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding, orientation: .horizontal) {
            RadioButtonItem("a", "Alpha")
            RadioButtonItem("b", "Beta")
            RadioButtonItem("c", "Gamma")
        }

        let buffer = renderToBuffer(group, context: context)

        // Horizontal: should be single line
        #expect(buffer.height == 1)
        let content = buffer.lines.joined()
        #expect(content.contains("Alpha"))
        #expect(content.contains("Beta"))
        #expect(content.contains("Gamma"))
    }

    @Test("Selected item shows filled indicator")
    func selectedIndicator() {
        let context = createTestContext()

        var selection: String = "opt2"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding) {
            RadioButtonItem("opt1", "First")
            RadioButtonItem("opt2", "Second")
            RadioButtonItem("opt3", "Third")
        }

        let buffer = renderToBuffer(group, context: context)

        // Selected item (opt2) should show ●
        let content = buffer.lines.joined()
        #expect(content.contains("●"))
        // Unselected items should show ◯
        #expect(content.contains("◯"))
    }

    @Test("Focus indicator shows pulsing on focused item")
    func focusIndicator() {
        let context = createTestContext()

        var selection: String = "x"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding) {
            RadioButtonItem("x", "X")
            RadioButtonItem("y", "Y")
        }

        let buffer = renderToBuffer(group, context: context)

        // Focused item should have ANSI codes (pulsing)
        let content = buffer.lines.joined()
        #expect(content.contains("\u{1b}["))
    }

    @Test("Disabled group uses tertiary color")
    func disabledGroup() {
        let context = createTestContext()

        var selection: String = "a"
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let group = RadioButtonGroup(selection: binding) {
            RadioButtonItem("a", "Option A")
        }.disabled()

        let buffer = renderToBuffer(group, context: context)

        #expect(buffer.height == 1)
        let content = buffer.lines.joined()
        #expect(content.contains("Option A"))
    }
}

// MARK: - Radio Button Group Handler Tests

@MainActor
@Suite("RadioButtonGroupHandler Tests")
struct RadioButtonGroupHandlerTests {

    @Test(
        "An on-axis arrow navigates focus, not selection",
        arguments: [
            // (key, orientation, startIndex, expectedIndex) — 3 items, selection on the start item
            (Key.down, RadioButtonOrientation.vertical, 0, 1),
            (.up, .vertical, 1, 0),
            (.right, .horizontal, 0, 1),
            (.left, .horizontal, 1, 0),
        ])
    func onAxisArrowNavigatesFocus(
        key: Key, orientation: RadioButtonOrientation, startIndex: Int, expectedIndex: Int
    ) {
        let startValue = AnyHashable("opt\(startIndex + 1)")
        var selection = startValue
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let itemValues = [AnyHashable("opt1"), AnyHashable("opt2"), AnyHashable("opt3")]
        let handler = RadioButtonGroupHandler(
            focusID: "test",
            selection: binding,
            itemValues: itemValues,
            orientation: orientation,
            canBeFocused: true
        )
        handler.focusedIndex = startIndex

        let handled = handler.handleKeyEvent(KeyEvent(key: key))

        #expect(handled == true)
        #expect(handler.focusedIndex == expectedIndex)  // Focus moved
        #expect(selection == startValue)  // Selection unchanged
    }

    @Test("Enter and Space select the focused item", arguments: [Key.enter, .space])
    func selectionKeySelectsFocusedItem(key: Key) {
        var selection = AnyHashable("opt1")
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let itemValues = [AnyHashable("opt1"), AnyHashable("opt2")]
        let handler = RadioButtonGroupHandler(
            focusID: "test",
            selection: binding,
            itemValues: itemValues,
            orientation: .vertical,
            canBeFocused: true
        )
        handler.focusedIndex = 1

        let handled = handler.handleKeyEvent(KeyEvent(key: key))

        #expect(handled == true)
        #expect(selection == AnyHashable("opt2"))
    }

    /// Builds a 2-item vertical handler for the boundary tests.
    private func boundaryHandler() -> RadioButtonGroupHandler {
        var selection = AnyHashable("opt1")
        let binding = Binding(get: { selection }, set: { selection = $0 })
        return RadioButtonGroupHandler(
            focusID: "test",
            selection: binding,
            itemValues: [AnyHashable("opt1"), AnyHashable("opt2")],
            orientation: .vertical,
            canBeFocused: true
        )
    }

    @Test("By default (.contain), arrowing past the edge stays put and consumes")
    func boundaryContainsByDefault() {
        // Up from the first item IS consumed (returns true) and focus does not
        // leave the group — the default containment, like List/Table. You can't
        // overshoot out of the group; Tab is how you leave.
        let handler = boundaryHandler()
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == true)
        #expect(handler.focusedIndex == 0, "focus stays on the first item")

        // Down from the last item likewise stays and consumes.
        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(handler.focusedIndex == 1)
    }

    @Test(".escape relinquishes focus past the edge (does not wrap)")
    func boundaryEscapesWhenOptedIn() {
        // Up from the first item is NOT consumed (returns false), so FocusManager
        // moves to the previous control instead of wrapping to the last item.
        let handler = boundaryHandler()
        handler.edgeBehavior = .escape
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == false)
        #expect(handler.focusedIndex == 0, "focus stays put; the group did not wrap")

        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == false)
        #expect(handler.focusedIndex == 1)
    }

    @Test("Interior arrow presses still move focus within the group and consume")
    func interiorNavigationConsumes() {
        let handler = boundaryHandler()  // focusedIndex 0 of 2
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(handler.focusedIndex == 1)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == true)
        #expect(handler.focusedIndex == 0)
    }

    @Test("A cross-axis arrow relinquishes focus (out of the group)")
    func crossAxisRelinquishes() {
        // A HORIZONTAL group: Up/Down are cross-axis, so they must return
        // false — FocusManager then moves to the control above/below. The
        // bug was that Up on a horizontal group was a consumed no-op, so you
        // could never arrow back to the group above it.
        let selectionBox = { () -> RadioButtonGroupHandler in
            var sel = AnyHashable("a")
            return RadioButtonGroupHandler(
                focusID: "h", selection: Binding(get: { sel }, set: { sel = $0 }),
                itemValues: [AnyHashable("a"), AnyHashable("b"), AnyHashable("c")],
                orientation: .horizontal, canBeFocused: true)
        }
        let h = selectionBox()
        h.focusedIndex = 1  // an interior item — proving it's the AXIS, not the edge
        #expect(h.handleKeyEvent(KeyEvent(key: .up)) == false, "Up relinquishes on a horizontal group")
        #expect(h.handleKeyEvent(KeyEvent(key: .down)) == false, "Down relinquishes on a horizontal group")
        #expect(h.focusedIndex == 1, "focus index untouched by a cross-axis press")
        // On-axis arrows still navigate within it.
        #expect(h.handleKeyEvent(KeyEvent(key: .left)) == true)
        #expect(h.focusedIndex == 0)

        // And symmetrically: Left/Right are cross-axis on a VERTICAL group.
        var vsel = AnyHashable("a")
        let v = RadioButtonGroupHandler(
            focusID: "v", selection: Binding(get: { vsel }, set: { vsel = $0 }),
            itemValues: [AnyHashable("a"), AnyHashable("b")],
            orientation: .vertical, canBeFocused: true)
        #expect(v.handleKeyEvent(KeyEvent(key: .left)) == false)
        #expect(v.handleKeyEvent(KeyEvent(key: .right)) == false)
    }

    @Test(".wrap restores wrap-around at the boundaries")
    func boundaryWrapsWhenOptedIn() {
        let handler = boundaryHandler()
        handler.edgeBehavior = .wrap  // what .radioButtonGroupEdgeBehavior(.wrap) syncs

        // Up from the first item wraps to the last and consumes.
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == true)
        #expect(handler.focusedIndex == 1)
        // Down from the last item wraps back to the first and consumes.
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(handler.focusedIndex == 0)
    }

    @Test("radioButtonGroupEdgeBehavior environment value defaults to .contain; modifier sets it")
    func edgeBehaviorEnvironmentAndModifier() {
        var env = EnvironmentValues()
        #expect(env.radioButtonGroupEdgeBehavior == .contain, "default is contain")
        env.radioButtonGroupEdgeBehavior = .escape
        #expect(env.radioButtonGroupEdgeBehavior == .escape)
        env.radioButtonGroupEdgeBehavior = .wrap
        #expect(env.radioButtonGroupEdgeBehavior == .wrap)
        // The View modifier compiles and returns a view.
        _ = Text("x").radioButtonGroupEdgeBehavior(.escape)
        _ = Text("x").radioButtonGroupEdgeBehavior(.contain)
    }

    @Test("With .escape, past the bottom edge moves focus to the next control")
    func escapeMovesFocusToNeighbour() {
        // End-to-end: an .escape group relinquishing the arrow (returning false)
        // lets FocusManager advance focus to the sibling control — the point of
        // the opt-in escape behaviour.
        let manager = FocusManager()
        var selection = AnyHashable("a")
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let group = RadioButtonGroupHandler(
            focusID: "radio", selection: binding,
            itemValues: [AnyHashable("a"), AnyHashable("b")],
            orientation: .vertical, canBeFocused: true)
        group.edgeBehavior = .escape
        let neighbour = MockFocusable(id: "after", shouldConsumeEvents: false)
        manager.register(group)  // first registered → auto-focused
        manager.register(neighbour)
        manager.focus(group)
        group.focusedIndex = group.itemValues.count - 1  // sit on the last item

        _ = manager.dispatchKeyEvent(KeyEvent(key: .down))  // down past the bottom
        #expect(
            manager.currentFocusedID == "after",
            "focus escaped the group to the next control, not wrapped inside it")
    }

    @Test("With the default .contain, arrowing past the edge keeps focus in the group")
    func containKeepsFocusInGroup() {
        // The complaint fix: with containment (the default), overshooting the
        // bottom does NOT drop you into the next control — you stay in the group.
        let manager = FocusManager()
        var selection = AnyHashable("a")
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let group = RadioButtonGroupHandler(
            focusID: "radio", selection: binding,
            itemValues: [AnyHashable("a"), AnyHashable("b")],
            orientation: .vertical, canBeFocused: true)
        // edgeBehavior defaults to .contain
        let neighbour = MockFocusable(id: "after", shouldConsumeEvents: false)
        manager.register(group)
        manager.register(neighbour)
        manager.focus(group)
        group.focusedIndex = group.itemValues.count - 1

        _ = manager.dispatchKeyEvent(KeyEvent(key: .down))  // down past the bottom
        #expect(
            manager.currentFocusedID == "radio",
            "focus stayed in the group; overshooting does not fall out")
    }

    @Test("Handler handles empty items without crashing")
    func handleEmptyItems() {
        var selection = AnyHashable("a")
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let handler = RadioButtonGroupHandler(
            focusID: "test",
            selection: binding,
            itemValues: [],
            orientation: .vertical,
            canBeFocused: true
        )

        // All key events should return false and not crash
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == false)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == false)
        #expect(handler.handleKeyEvent(KeyEvent(key: .enter)) == false)
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == false)
        #expect(selection == AnyHashable("a"))  // Selection unchanged
    }

    @Test("Handler clamps focusedIndex when items shrink")
    func clampsFocusedIndexOnItemShrink() {
        var selection = AnyHashable("opt1")
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let handler = RadioButtonGroupHandler(
            focusID: "test",
            selection: binding,
            itemValues: [AnyHashable("opt1"), AnyHashable("opt2"), AnyHashable("opt3")],
            orientation: .vertical,
            canBeFocused: true
        )
        handler.focusedIndex = 2  // Focused on third item

        // Simulate items shrinking to 2
        handler.itemValues = [AnyHashable("opt1"), AnyHashable("opt2")]

        // Navigate - should clamp focusedIndex to 1 (last valid index)
        let handled = handler.handleKeyEvent(KeyEvent(key: .enter))
        #expect(handled == true)
        #expect(handler.focusedIndex == 1)
        #expect(selection == AnyHashable("opt2"))  // Selected the clamped item
    }

    @Test("Handler respects canBeFocused property")
    func respectsCanBeFocused() {
        var selection = AnyHashable("a")
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        let itemValues = [AnyHashable("a"), AnyHashable("b")]
        let handler = RadioButtonGroupHandler(
            focusID: "test",
            selection: binding,
            itemValues: itemValues,
            orientation: .vertical,
            canBeFocused: false
        )

        #expect(handler.canBeFocused == false)
    }

    // MARK: - Jump navigation (Home/End/Page/Shift-accelerated)

    /// A vertical handler over `count` options, selection & focus on item 0.
    private func jumpHandler(count: Int) -> RadioButtonGroupHandler {
        var selection = AnyHashable("opt0")
        let binding = Binding(get: { selection }, set: { selection = $0 })
        return RadioButtonGroupHandler(
            focusID: "test", selection: binding,
            itemValues: (0..<count).map { AnyHashable("opt\($0)") },
            orientation: .vertical, canBeFocused: true)
    }

    @Test("Home jumps to the first item, End to the last (consumed, no selection change)")
    func homeAndEndJump() {
        let handler = jumpHandler(count: 6)
        handler.focusedIndex = 3
        var selection = AnyHashable("opt3")
        let binding = Binding(get: { selection }, set: { selection = $0 })
        handler.selection = binding

        #expect(handler.handleKeyEvent(KeyEvent(key: .end)) == true)
        #expect(handler.focusedIndex == 5)
        #expect(handler.handleKeyEvent(KeyEvent(key: .home)) == true)
        #expect(handler.focusedIndex == 0)
        #expect(selection == AnyHashable("opt3"), "jumps move focus only, never the selection")
    }

    @Test("PageUp/PageDown jump to the ends (a radio group has no viewport)")
    func pageIsHomeEnd() {
        let handler = jumpHandler(count: 8)
        handler.focusedIndex = 4
        #expect(handler.handleKeyEvent(KeyEvent(key: .pageDown)) == true)
        #expect(handler.focusedIndex == 7, "PageDown lands on the last item")
        #expect(handler.handleKeyEvent(KeyEvent(key: .pageUp)) == true)
        #expect(handler.focusedIndex == 0, "PageUp lands on the first item")
    }

    @Test("Shift+Down/Up accelerate by the synced multiplier, clamped (no wrap)")
    func shiftAcceleratesByMultiplier() {
        let handler = jumpHandler(count: 10)
        // Sync the multiplier to a NON-default value (3, not the default 5) —
        // proving the handler reads the synced field, not a baked-in constant.
        handler.shiftStepMultiplier = 3

        #expect(handler.handleKeyEvent(KeyEvent(key: .down, shift: true)) == true)
        #expect(handler.focusedIndex == 3, "Shift+Down moves by the multiplier (3)")
        #expect(handler.handleKeyEvent(KeyEvent(key: .down, shift: true)) == true)
        #expect(handler.focusedIndex == 6)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up, shift: true)) == true)
        #expect(handler.focusedIndex == 3, "Shift+Up moves back by the multiplier")

        // Clamps at the ends rather than wrapping.
        handler.focusedIndex = 8
        #expect(handler.handleKeyEvent(KeyEvent(key: .down, shift: true)) == true)
        #expect(handler.focusedIndex == 9, "clamps at the last item")
        handler.focusedIndex = 1
        #expect(handler.handleKeyEvent(KeyEvent(key: .up, shift: true)) == true)
        #expect(handler.focusedIndex == 0, "clamps at the first item")
    }

    @Test("On a horizontal group Shift accelerates Left/Right, not Up/Down")
    func horizontalShiftAxis() {
        var selection = AnyHashable("opt0")
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let handler = RadioButtonGroupHandler(
            focusID: "h", selection: binding,
            itemValues: (0..<10).map { AnyHashable("opt\($0)") },
            orientation: .horizontal, canBeFocused: true)
        handler.shiftStepMultiplier = 4

        #expect(handler.handleKeyEvent(KeyEvent(key: .right, shift: true)) == true)
        #expect(handler.focusedIndex == 4, "Shift+Right accelerates on a horizontal group")
        // Shift+Down is cross-axis here: it relinquishes (false), doesn't accelerate.
        let before = handler.focusedIndex
        #expect(handler.handleKeyEvent(KeyEvent(key: .down, shift: true)) == false)
        #expect(handler.focusedIndex == before, "cross-axis Shift+Down doesn't move within the group")
    }
}

// MARK: - Radio Button Orientation Tests

@MainActor
@Suite("RadioButtonOrientation Tests")
struct RadioButtonOrientationTests {

    @Test("RadioButtonOrientation has vertical and horizontal cases")
    func orientationCases() {
        let vertical: RadioButtonOrientation = .vertical
        let horizontal: RadioButtonOrientation = .horizontal

        #expect(vertical == .vertical)
        #expect(horizontal == .horizontal)
        #expect(vertical != horizontal)
    }
}
