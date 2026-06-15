//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuRenderTests.swift
//
//  Buffer-level rendering tests for Menu.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Menu rendering")
struct MenuRenderTests {

    // MARK: - Helpers

    private func makeContext(width: Int = 40, height: Int = 12) -> RenderContext {
        RenderContext(
            availableWidth: width,
            availableHeight: height,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func lines(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map { $0.stripped }
    }

    /// Default border is the appearance default (rounded): ╭ ╮ ╰ ╯ ─ │ ├ ┤.
    private let tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│", lt = "├", rt = "┤"

    // MARK: - Default (titled) menu

    @Test("A titled menu renders title, divider, items, and continuous border")
    func titledMenu() {
        let menu = Menu(
            title: "Main Menu",
            items: [
                MenuItem(label: "Text Styles", shortcut: "1"),
                MenuItem(label: "Colors", shortcut: "2"),
                MenuItem(label: "Quit", shortcut: "q"),
            ],
            selectedIndex: 1
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))

        #expect(result.count == 7, "top + title + divider + 3 items + bottom")
        #expect(result[0].hasPrefix(tl) && result[0].hasSuffix(tr), "Top border corners")
        #expect(result[1].contains("Main Menu"), "Title row")
        #expect(result[2].hasPrefix(lt) && result[2].hasSuffix(rt), "T-junction divider under title")
        #expect(result[3].contains("[1] Text Styles"))
        #expect(result[4].contains("[2] Colors"))
        #expect(result[5].contains("[q] Quit"))
        #expect(result[6].hasPrefix(bl) && result[6].hasSuffix(br), "Bottom border corners")
    }

    @Test("All bordered rows share one width and the borders are continuous")
    func uniformWidthAndContinuousBorders() {
        let menu = Menu(
            title: "Menu",
            items: [
                MenuItem(label: "One", shortcut: "1"),
                MenuItem(label: "A longer entry", shortcut: "2"),
            ],
            selectedIndex: 0
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))

        let widths = Set(result.map { $0.count })
        #expect(widths.count == 1, "Every row (borders + content) must be the same visible width: \(result.map { $0.count })")

        // Every interior row begins with a left edge: a side border on
        // content/title rows, or the left T-junction on the divider row.
        for row in result.dropFirst().dropLast() {
            #expect(row.hasPrefix(v) || row.hasPrefix(lt),
                    "Interior row '\(row)' should start with a side border or junction")
        }
    }

    // MARK: - Untitled menu

    @Test("An untitled menu has no title row and no divider")
    func untitledMenu() {
        let menu = Menu(
            items: [
                MenuItem(label: "One"),
                MenuItem(label: "Two"),
            ],
            selectedIndex: 0
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))

        #expect(result.count == 4, "top + 2 items + bottom (no title, no divider)")
        #expect(result[0].hasPrefix(tl))
        #expect(result[1].contains("One"))
        #expect(result[2].contains("Two"))
        #expect(result[3].hasPrefix(bl))
        // No divider/junction row anywhere.
        #expect(!result.contains(where: { $0.hasPrefix(lt) }), "No T-junction divider without a title")
        // No stray blank content.
        #expect(!result.contains(where: { $0.dropFirst().dropLast().allSatisfy { $0 == " " } && $0.count > 2 }),
                "No fully-blank content row in an untitled menu")
    }

    @Test("An empty-string title is treated as no title — no blank title row or divider")
    func emptyTitleMenu() {
        let menu = Menu(
            title: "",
            items: [
                MenuItem(label: "One"),
                MenuItem(label: "Two"),
            ],
            selectedIndex: 0
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))

        // Identical shape to an untitled menu: top + 2 items + bottom.
        #expect(result.count == 4, "An empty title must not reserve a title row + divider: \(result)")
        #expect(result[0].hasPrefix(tl))
        #expect(!result.contains(where: { $0.hasPrefix(lt) }), "No divider for an empty title")
        #expect(!result.contains(where: { $0.dropFirst().dropLast().allSatisfy { $0 == " " } && $0.count > 2 }),
                "No fully-blank content row for an empty title")
    }

    // MARK: - Shortcuts / labels

    @Test("Items with shortcuts render the [x] prefix; items without get 4 leading spaces")
    func shortcutPrefixing() {
        let withShortcut = Menu(items: [MenuItem(label: "Save", shortcut: "s")], selectedIndex: 0)
        let r1 = lines(renderToBuffer(withShortcut, context: makeContext()))
        #expect(r1[1].contains("[s] Save"))

        let withoutShortcut = Menu(items: [MenuItem(label: "Plain")], selectedIndex: 0)
        let r2 = lines(renderToBuffer(withoutShortcut, context: makeContext()))
        // 4 leading spaces stand in for the absent "[x] " — label is right of them.
        #expect(r2[1].contains("    Plain"))
        #expect(!r2[1].contains("["), "No bracket when there is no shortcut")
    }

    @Test("CJK labels still yield uniform-width rows")
    func cjkUniformWidth() {
        let menu = Menu(
            items: [
                MenuItem(label: "文件"),   // 4 cells
                MenuItem(label: "AB"),     // 2 cells
            ],
            selectedIndex: 0
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))
        let contentWidths = Set(result.dropFirst().dropLast().map { $0.strippedLength })
        #expect(contentWidths.count == 1, "CJK content rows must align: \(contentWidths)")
    }

    // MARK: - selectedIndex clamping

    @Test("An out-of-range selectedIndex is clamped and does not crash or add rows")
    func outOfRangeSelection() {
        let menu = Menu(
            items: [MenuItem(label: "One"), MenuItem(label: "Two")],
            selectedIndex: 99
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))
        #expect(result.count == 4, "Clamped selection still renders exactly the two items")
        #expect(result[1].contains("One"))
        #expect(result[2].contains("Two"))
    }

    @Test("A negative selectedIndex is clamped to the first item")
    func negativeSelection() {
        let menu = Menu(
            items: [MenuItem(label: "One"), MenuItem(label: "Two")],
            selectedIndex: -5
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))
        #expect(result.count == 4)
        #expect(result[1].contains("One"))
    }

    // MARK: - Explicit border styles

    @Test("An explicit line border uses square corners and T-junctions")
    func lineBorderStyle() {
        let menu = Menu(
            title: "Menu",
            items: [MenuItem(label: "One", shortcut: "1")],
            selectedIndex: 0,
            borderStyle: BorderStyle.line
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))

        #expect(result[0].hasPrefix("┌") && result[0].hasSuffix("┐"))
        #expect(result[2].hasPrefix("├") && result[2].hasSuffix("┤"))
        #expect(result.last?.hasPrefix("└") == true && result.last?.hasSuffix("┘") == true)
    }

    @Test("An explicit heavy border uses heavy box-drawing characters")
    func heavyBorderStyle() {
        let menu = Menu(
            items: [MenuItem(label: "One")],
            selectedIndex: 0,
            borderStyle: BorderStyle.heavy
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))
        #expect(result[0].hasPrefix("┏") && result[0].hasSuffix("┓"))
        #expect(result.last?.hasPrefix("┗") == true && result.last?.hasSuffix("┛") == true)
        #expect(result[1].hasPrefix("┃") && result[1].hasSuffix("┃"))
    }

    @Test("BorderStyle.none draws spaces in place of border glyphs")
    func noneBorderStyle() {
        let menu = Menu(
            items: [MenuItem(label: "One")],
            selectedIndex: 0,
            borderStyle: BorderStyle.none
        )
        let result = lines(renderToBuffer(menu, context: makeContext()))
        // Top and bottom "borders" are entirely blank.
        #expect(result[0].allSatisfy { $0 == " " }, "Top border row is all spaces for .none")
        #expect(result.last?.allSatisfy { $0 == " " } == true, "Bottom border row is all spaces for .none")
        // The item text still renders.
        #expect(result[1].contains("One"))
    }

    // MARK: - Selection styling (visible in ANSI, not in stripped text)

    @Test("The selected row carries distinct ANSI styling from unselected rows")
    func selectedRowIsStyledDistinctly() {
        let menu = Menu(
            items: [
                MenuItem(label: "One", shortcut: "1"),
                MenuItem(label: "Two", shortcut: "2"),
            ],
            selectedIndex: 0
        )
        let buffer = renderToBuffer(menu, context: makeContext())
        // Row 1 is the selected item, row 2 is unselected. The raw (un-stripped)
        // ANSI must differ — selection is conveyed via bold + accent color.
        let selectedRaw = buffer.lines[1]
        let unselectedRaw = buffer.lines[2]
        #expect(selectedRaw != unselectedRaw, "Selected and unselected rows must be visually different")
        #expect(selectedRaw.contains("\u{1B}[1;"), "Selected row should be bold")
    }
}
