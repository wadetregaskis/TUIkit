//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListPartialRowTests.swift
//
//  Under `.scrollGranularity(.line)` a viewport may sit mid-row, which means a
//  multi-line row can be cut at BOTH ends: the top row enters with its first
//  lines above the viewport, and the bottom row leaves with its last lines
//  below it. The two are separate mechanisms — a clip at the top, a budget at
//  the bottom — so they are asserted separately, and against a REAL rendered
//  List rather than the handler's arithmetic.
//
//  List only, and deliberately: a `TableColumn` extracts a `String` per cell,
//  so a Table row is one line and the question does not arise there. The twin
//  divergence to watch for is in the window walk both share, which
//  `PageDistanceTests` already pins across the two.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("Partial rows at both ends")
@MainActor
struct ListPartialRowTests {

    /// Four lines per row, each line naming its row and its line, so a clipped
    /// row can be identified by which of its lines survived.
    ///
    /// Four rather than three because a wheel notch moves three lines: with
    /// three-line rows every notch lands back on a row boundary and the top
    /// never clips, which is a property of the test, not of the List. That is
    /// exactly what the first version of this suite reported.
    private struct Row: Identifiable, Hashable {
        let id: Int
        var lines: [String] { (0..<4).map { "r\(id)L\($0)" } }
    }

    private static let rows = (0..<12).map(Row.init(id:))

    @ViewBuilder
    private func cell(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(row.lines, id: \.self) { Text($0) }
        }
    }

    /// Renders a line-granularity List of `height` lines, scrolled by `wheel`
    /// notches, and returns the visible text lines.
    private func listLines(height: Int, wheel: Int) -> [String] {
        let context = makeRenderContext(width: 40, height: height) { environment, _ in
            // The text indicators, not the scrollbar: this suite reads the rows
            // themselves and a scrollbar column would not change the answer, but
            // the text form keeps the reserved lines explicit.
            environment.scrollIndicatorStyle = .text
        }
        let list = List(Self.rows, selection: .constant(nil as Row.ID?)) { cell($0) }
            .scrollGranularity(.line)
            .frame(height: height)
        return renderedLines(list, context: context, wheel: wheel)
    }

    /// Renders, delivers `wheel` scroll notches to the middle of the view, then
    /// renders again so the scroll is reflected. Returns the stripped lines.
    private func renderedLines(_ view: some View, context: RenderContext, wheel: Int) -> [String] {
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)
        var buffer = renderToBuffer(view, context: context)
        for _ in 0..<wheel {
            dispatcher.setRegions(buffer.hitTestRegions)
            guard let region = buffer.hitTestRegions.last else { break }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .scrollDown, phase: .scrolled,
                    x: region.offsetX + region.width / 2,
                    y: region.offsetY + region.height / 2))
            buffer = renderToBuffer(view, context: context)
        }
        return buffer.lines.map(\.stripped)
    }

    /// The row and line a rendered line belongs to, or nil for chrome.
    private func marker(_ line: String) -> (row: Int, line: Int)? {
        guard let range = line.range(of: #"r\d+L\d+"#, options: .regularExpression) else {
            return nil
        }
        let parts = line[range].dropFirst().split(separator: "L")
        guard parts.count == 2, let row = Int(parts[0]), let index = Int(parts[1]) else {
            return nil
        }
        return (row, index)
    }

    private func markers(_ lines: [String]) -> [(row: Int, line: Int)] {
        lines.compactMap(marker)
    }

    /// The scroll positions this suite examines. A sweep rather than one
    /// hand-computed offset, because how many lines a notch moves and how many
    /// the indicators reserve are both free to change; the PROPERTY — that a
    /// viewport sitting mid-row cuts the row it sits on — is not.
    nonisolated private static let offsets = Array(1...7)

    @Test("The top row enters partially")
    func topRowIsClipped() {
        var seen: [[(row: Int, line: Int)]] = []
        for wheel in Self.offsets {
            let visible = markers(listLines(height: 12, wheel: wheel))
            guard let first = visible.first else { continue }
            if first.line != 0 { return }  // clipped, which is what we came for
            seen.append(visible)
        }
        Issue.record("no scroll position clipped the top row: \(seen)")
    }

    @Test("The bottom row leaves partially")
    func bottomRowIsClipped() {
        var seen: [[(row: Int, line: Int)]] = []
        for wheel in Self.offsets {
            let visible = markers(listLines(height: 12, wheel: wheel))
            guard let last = visible.last else { continue }
            if last.line != 3 { return }
            seen.append(visible)
        }
        Issue.record("no scroll position clipped the bottom row: \(seen)")
    }

    @Test("Both ends are cut at once, so the viewport is exactly filled")
    func bothEndsAtOnce() {
        for wheel in Self.offsets {
            let visible = markers(listLines(height: 12, wheel: wheel))
            guard let first = visible.first, let last = visible.last else { continue }
            if first.line != 0 && last.line != 3 { return }
        }
        Issue.record("no scroll position cut both ends of the viewport at once")
    }

    @Test("No line of the viewport is left blank between the two ends", arguments: offsets)
    func viewportIsFull(wheel: Int) {
        let visible = markers(listLines(height: 12, wheel: wheel))
        guard visible.count >= 2 else {
            Issue.record("too little rendered to check: \(visible)")
            return
        }
        // Every row's lines run consecutively, and consecutive rows follow one
        // another — a gap means a row was dropped rather than clipped.
        for index in 1..<visible.count {
            let previous = visible[index - 1]
            let current = visible[index]
            let contiguous =
                (current.row == previous.row && current.line == previous.line + 1)
                || (current.row == previous.row + 1 && current.line == 0 && previous.line == 3)
            #expect(contiguous, "\(previous) is followed by \(current): \(visible)")
        }
    }
}
