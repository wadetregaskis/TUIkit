//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListAlternatingRowTests.swift
//
//  `ListStyle.alternatingRowColors` tints "every even-indexed row within a
//  section". Both of `_ListCore`'s composers counted that index from the first
//  row they DREW, which is the row's own index only while the list sits at the
//  top: scrolled to an odd row, every stripe moved onto the row beside it, and
//  each wheel tick moved them all again. The only render test rendered three
//  rows that could not scroll, and checked that SOMETHING was tinted, never
//  which rows were.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Alternating row colours stay on their rows as a List scrolls")
struct ListAlternatingRowTests {

    /// Turns the stripes on or off and changes nothing else, so two renders that
    /// differ only in `alternatingRowColors` differ only on the tinted lines.
    private struct ZebraListStyle: ListStyle {
        let alternatingRowColors: Bool
        var showsBorder: Bool { false }
        var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
    }

    /// Twice the viewport, so the wheel has somewhere to go. No label is part of
    /// another once the letters and digits are pulled out of a line.
    private static let labels = (0..<16).map { "r\($0)" }

    private func context(style: ScrollIndicatorStyle) -> RenderContext {
        makeRenderContext(width: 24, height: 8) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.scrollIndicatorStyle = style
            environment.terminalWidth = 24
            environment.terminalHeight = 8
        }
    }

    /// The windowed path: an all-content source, where the row's index is the
    /// stripe index.
    private func flatList(zebra: Bool) -> some View {
        List(selection: .constant(String?.none)) {
            ForEach(Self.labels, id: \.self) { Text($0) }
        }
        .listStyle(ZebraListStyle(alternatingRowColors: zebra))
    }

    /// The eager path: a header at row 0, so `r0` is row 1 and the stripe index
    /// is one less than the row's.
    private func sectionedList(zebra: Bool) -> some View {
        List(selection: .constant(String?.none)) {
            Section("Letters") {
                ForEach(Self.labels, id: \.self) { Text($0) }
            }
        }
        .listStyle(ZebraListStyle(alternatingRowColors: zebra))
    }

    /// Every frame of `list` from the top to past the bottom, one wheel tick (three
    /// rows) apart, raw. The wheel rather than the keyboard, so the cursor stays on
    /// the first row and off every later frame.
    private func wheeledFrames(_ list: some View, style: ScrollIndicatorStyle) -> [[String]] {
        let ctx = context(style: style)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        var latest = renderToBuffer(list, context: ctx)
        var frames = [latest.lines]
        for _ in 0..<Self.labels.count {
            dispatcher.setRegions(latest.hitTestRegions)
            _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
            latest = renderToBuffer(list, context: ctx)
            frames.append(latest.lines)
        }
        return frames
    }

    /// The label rows drawn in one frame, top to bottom, each with its stripe index
    /// and whether it is tinted. Tinted means the line differs from the same line
    /// with the stripes off, because nothing else differs between the two renders.
    /// Matched EXACTLY, so an indicator line like "▼ 3 more rows below" is not
    /// read as a row.
    private func drawnRows(striped: [String], plain: [String]) -> [(index: Int, tinted: Bool)] {
        var rows: [(index: Int, tinted: Bool)] = []
        for (stripedLine, plainLine) in zip(striped, plain) {
            let text = String(plainLine.stripped.filter { $0.isLetter || $0.isNumber })
            if Self.labels.contains(text), let index = Int(text.dropFirst()) {
                rows.append((index, stripedLine != plainLine))
            }
        }
        return rows
    }

    /// Every drawn row that breaks "tinted exactly when its index is even", and
    /// whether any frame put an odd row at the top of the window. That is the case
    /// the bug needs, so a run that never reached one proves nothing.
    private func stripeOffenders(zebra: [[String]], flat: [[String]]) -> (offenders: [String], oddTop: Bool) {
        var offenders: [String] = []
        var oddTop = false
        for (frame, (striped, plain)) in zip(zebra, flat).enumerated() {
            let rows = drawnRows(striped: striped, plain: plain)
            if let top = rows.first, !top.index.isMultiple(of: 2) { oddTop = true }
            // The cursor starts on r0 and the wheel leaves it there. Its focus
            // highlight replaces the stripe in BOTH renders, so r0 says nothing.
            for row in rows where row.index != 0 && row.tinted != row.index.isMultiple(of: 2) {
                offenders.append("frame \(frame): r\(row.index) \(row.tinted ? "tinted" : "plain")")
            }
        }
        return (offenders, oddTop)
    }

    @Test("A scrolled flat List keeps its stripes on its even rows", arguments: ScrollIndicatorStyle.allCases)
    func flatListStripesStayOnTheirRows(style: ScrollIndicatorStyle) {
        let result = stripeOffenders(
            zebra: wheeledFrames(flatList(zebra: true), style: style),
            flat: wheeledFrames(flatList(zebra: false), style: style))
        #expect(result.oddTop, "the wheel never put an odd row at the top, so nothing was checked")
        #expect(result.offenders.isEmpty, "a stripe left its row as the list scrolled: \(result.offenders)")
    }

    /// The header is part of the row count but not of the stripe count. A seed
    /// taken from the row index alone would be off by one here, which is why the
    /// eager path walks back to the header.
    @Test(
        "A scrolled Section keeps its stripes on its even rows once the header is gone",
        arguments: ScrollIndicatorStyle.allCases)
    func sectionStripesStayOnTheirRows(style: ScrollIndicatorStyle) {
        let result = stripeOffenders(
            zebra: wheeledFrames(sectionedList(zebra: true), style: style),
            flat: wheeledFrames(sectionedList(zebra: false), style: style))
        #expect(result.oddTop, "the wheel never put an odd row at the top, so nothing was checked")
        #expect(result.offenders.isEmpty, "a stripe left its row as the list scrolled: \(result.offenders)")
    }
}
