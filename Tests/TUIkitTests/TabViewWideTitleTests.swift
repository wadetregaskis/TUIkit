//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewWideTitleTests.swift
//
//  A tab strip laid out in CELLS, not Characters.
//
//  Every width in the strip — the chip bodies, the row widths, the click
//  regions, the folder-tab walls — was `title.count`, the number of Characters.
//  A CJK title occupies two cells per Character, so the strip drew wider than it
//  measured: the box came out ragged, and the click regions drifted left of the
//  tabs they belong to until the last tab had no region under it at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A tab strip is laid out in cells")
struct TabViewWideTitleTests {

    /// Japanese for Settings / Information / Overview: two Characters each, but
    /// four cells each.
    private static let titles = ["設定", "情報", "概要"]

    private func wideTabs(_ selection: Binding<Int>) -> some View {
        TabView(selection: selection) {
            ForEach(0..<3) { i in
                Tab(Self.titles[i], value: i) { Text("c\(i)") }
            }
        }
    }

    /// The cells `needle` occupies on `line`: its first and last columns.
    private func span(of needle: String, in line: String) -> (first: Int, last: Int)? {
        guard let range = line.range(of: needle) else { return nil }
        let first = String(line[line.startIndex..<range.lowerBound]).strippedLength
        return (first, first + needle.strippedLength - 1)
    }

    @Test("Clicking a wide-titled tab selects that tab", arguments: [0, 1, 2])
    func clickingAWideTabSelectsIt(_ target: Int) {
        // Start somewhere else, so a no-op click is not mistaken for a hit.
        let selected = Box(target == 0 ? 1 : 0)
        let ctx = makeRenderContext(width: 40, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let buffer = renderToBuffer(wideTabs(selected.binding), context: ctx)
        dispatcher.setRegions(buffer.hitTestRegions)

        let lines = buffer.lines.map(\.stripped)
        let title = Self.titles[target]
        guard
            let row = lines.firstIndex(where: { $0.contains(title) }),
            let cells = span(of: title, in: lines[row])
        else {
            Issue.record("tab \(target) not found in:\n\(lines.joined(separator: "\n"))")
            return
        }
        // The last cell of the title as drawn — a region measured in Characters
        // stops short of it, so this is where the drift shows.
        let x = cells.last
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: row))

        #expect(
            selected.value == target,
            """
            clicking cell \(x) of row \(row) — the last cell of "\(title)" as drawn — \
            selects tab \(target), got \(selected.value):
            \(lines.joined(separator: "\n"))
            """)
    }

    @Test("A compact strip of wide titles is no wider than the panel it sits in")
    func compactStripFitsThePanel() {
        let selected = Box(0)
        let buffer = renderToBuffer(
            wideTabs(selected.binding), context: makeRenderContext(width: 40, height: 10))
        let widths = Set(buffer.lines.map(\.stripped.strippedLength))
        #expect(
            widths.count == 1,
            """
            every line of the panel is the same width in cells — a strip measured \
            in Characters draws past the content below it. Widths: \
            \(widths.sorted())
            """)
    }

    @Test("A bordered box of wide titles stays rectangular")
    func borderedBoxStaysRectangular() {
        let selected = Box(0)
        let buffer = renderToBuffer(
            wideTabs(selected.binding).tabViewStyle(.bordered),
            context: makeRenderContext(width: 40, height: 12))
        let lines = buffer.lines.map(\.stripped)
        let widths = Set(lines.map(\.strippedLength))
        #expect(
            widths.count == 1,
            """
            the folder tabs, their walls and the content box all measure the same \
            in cells, so the box is rectangular. Widths: \(widths.sorted())
            \(lines.joined(separator: "\n"))
            """)
        // The walls under the strip must line up with the box's own sides.
        guard let bottom = lines.last else {
            Issue.record("no rendered lines")
            return
        }
        #expect(bottom.hasPrefix("╰"), "the box closes where it opened: \(bottom)")
        #expect(bottom.hasSuffix("╯"), "the box closes where it opened: \(bottom)")
    }

    @Test("An emoji-titled tab is measured at its rendered width too")
    func emojiTitleIsMeasuredInCells() {
        // Emoji are one Character and two cells apiece — the same trap as CJK,
        // reached by a route a developer is far more likely to take by accident.
        let selected = Box(1)
        let ctx = makeRenderContext(width: 40, height: 10) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let view = TabView(selection: selected.binding) {
            Tab("🐛🐞🦋 Bugs", value: 0) { Text("a") }
            Tab("Notes", value: 1) { Text("b") }
        }
        let buffer = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(buffer.hitTestRegions)

        let lines = buffer.lines.map(\.stripped)
        guard
            let row = lines.firstIndex(where: { $0.contains("Bugs") }),
            let cells = span(of: "Bugs", in: lines[row])
        else {
            Issue.record("tabs not found in:\n\(lines.joined(separator: "\n"))")
            return
        }
        // The "s" of the first tab's own word, three cells adrift of where a
        // Character count thinks that tab ends.
        let x = cells.last
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: row))
        #expect(
            selected.value == 0,
            """
            cell \(x) is the "s" of the first tab's own label, so clicking it \
            selects that tab and not its neighbour:
            \(lines.joined(separator: "\n"))
            """)
    }
}

/// A mutable value with a `Binding` onto it.
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
    var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
}
