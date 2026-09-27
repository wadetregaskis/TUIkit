//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionHeldRowTests.swift
//
//  A row held by `.anchorPosition(.row)` in a lazy stack in a section, which
//  relays the scroll window to its content (`ScrollWindowRelay`): the hold
//  keeps the row on its line, the header's lines on screen counting toward
//  it. On the anchored window, which places rows outward from the held one by
//  estimate, the header is on screen only when the rows above the held row
//  leave room for it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// One frame of `view` at 30x8, holding `row` when one is given
/// (`.anchorPosition(.row(id))`).
@MainActor
private func heldBuffer<V: View>(
    _ view: V, holding row: Int?, tui: TUIContext, focusManager: FocusManager
) -> FrameBuffer {
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    environment.applyRuntimeServices(from: tui)
    if let row {
        environment.anchorPosition = AnchorPositionBinding(.constant(.row(AnyHashable(row))))
    }
    let context = RenderContext(
        availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
    tui.stateStorage.beginRenderPass()
    tui.renderCache.beginRenderPass()
    focusManager.beginRenderPass()
    let buffer = renderToBuffer(view, context: context)
    focusManager.endRenderPass()
    tui.stateStorage.endRenderPass()
    tui.renderCache.removeInactive()
    return buffer
}

/// One frame of a section's lazy stack at 30x8, holding `row` when one is
/// given.
@MainActor
private func heldFrame(
    _ items: [Int], holding row: Int?, variable: Bool, textIndicators: Bool = false,
    tui: TUIContext, focusManager: FocusManager
) -> [String] {
    let view = ScrollView {
        Section("header") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.self) { sectionRow($0, variable: variable) }
            }
        }
    }
    .scrollIndicatorStyle(textIndicators ? .text : .scrollbar)
    .frame(height: 8)
    return heldBuffer(view, holding: row, tui: tui, focusManager: focusManager).lines.map(\.stripped)
}

/// One frame of a section's 300 rows under `header`, at 30x8, holding `row`
/// when one is given, scrolled by `box`: one-line rows (the uniform window),
/// or with `variable` one to three lines (the anchored window).
@MainActor
private func underHeaderFrame(
    _ items: [Int], header: String, holding row: Int?, variable: Bool, textIndicators: Bool = false,
    box: SectionProxyBox, tui: TUIContext, focusManager: FocusManager
) -> [String] {
    let view = ScrollView {
        Section {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.self) { sectionRow($0, variable: variable) }
            }
        } header: {
            Text(header)
        }
    }
    .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
    .scrollIndicatorStyle(textIndicators ? .text : .scrollbar)
    .frame(height: 8)
    return heldBuffer(view, holding: row, tui: tui, focusManager: focusManager).lines.map(\.stripped)
}

/// The line on `screen` that `row` starts on.
private func line(of row: Int, on screen: [String]) -> Int? {
    screen.firstIndex { $0.hasPrefix("row \(row) ") }
}

@MainActor
@Suite("A section's lazy stack holds a designated row")
struct SectionHeldRowTests {
    @Test(
        "A held row keeps its line as rows are inserted above it, in a section's stack",
        arguments: [false, true])
    func heldRowKeepsItsLine(variable: Bool) {
        // Uniform rows, and variable rows under 256 (the exact walk): both
        // correct the offset to hold the row, which the scroll view adopts
        // from the reply — the section's reply, moved below its header.
        let (tui, focusManager) = (TUIContext(), FocusManager())
        var items = Array(0..<60)
        var before: [String] = []
        for _ in 0..<4 {
            before = heldFrame(items, holding: 30, variable: variable, tui: tui, focusManager: focusManager)
        }
        let lineBefore = before.firstIndex { $0.hasPrefix("row 30 ") }
        items.insert(contentsOf: 1_000..<1_025, at: 5)
        let after = heldFrame(items, holding: 30, variable: variable, tui: tui, focusManager: focusManager)
        #expect(lineBefore != nil, "the held row is revealed: \(before)")
        #expect(after.firstIndex { $0.hasPrefix("row 30 ") } == lineBefore, "\(before) → \(after)")
    }

    @Test(
        "Holding a row under the header, at the top, leaves it where it sits",
        arguments: [false, true])
    func heldRowUnderTheHeaderStays(variable: Bool) {
        // Held on its line, the row needs the offset the header's line
        // gives it: the section's content can scroll above the stack's top.
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let items = Array(0..<60)
        let before = heldFrame(items, holding: nil, variable: variable, tui: tui, focusManager: focusManager)
        var after: [String] = []
        for _ in 0..<3 {
            after = heldFrame(items, holding: 2, variable: variable, tui: tui, focusManager: focusManager)
        }
        let lineBefore = before.firstIndex { $0.hasPrefix("row 2 ") }
        #expect(lineBefore != nil && before.first?.hasPrefix("header") == true, "precondition: \(before)")
        #expect(after.firstIndex { $0.hasPrefix("row 2 ") } == lineBefore, "\(before) → \(after)")
    }

    @Test("On the anchored window, a row held under the header stays where it sits, the rows above it drawn")
    func anchoredHeldRowUnderTheHeader() {
        // The anchored window places rows from the held one, by estimate, and
        // rode it up until the rows above it alone filled the lines above it:
        // the header's line was not counted, row 0 went, and the header was
        // drawn over row 1's place.
        let (tui, focusManager) = (TUIContext(), FocusManager())
        var items = Array(0..<300)
        let before = heldFrame(items, holding: nil, variable: true, tui: tui, focusManager: focusManager)
        var held: [String] = []
        for _ in 0..<3 {
            held = heldFrame(items, holding: 2, variable: true, tui: tui, focusManager: focusManager)
        }
        items.insert(contentsOf: 1_000..<1_005, at: 3)
        let after = heldFrame(items, holding: 2, variable: true, tui: tui, focusManager: focusManager)
        #expect(before.first?.hasPrefix("header") == true, "precondition: \(before)")
        #expect(held == before, "the hold moves nothing: \(before) → \(held)")
        #expect(after.prefix(5) == before.prefix(5), "an insert below it moves nothing above it: \(after)")
    }

    @Test(
        "On the anchored window, a row designated off screen is shown on its line at the top, without the header",
        arguments: [false, true])
    func anchoredHeldRowFarBelowTheHeader(textIndicators: Bool) {
        // Revealed at the top edge, the row is held on the viewport's top
        // line, or under the "more above" one, and the rows above it fill the
        // lines above it: none of the header can be on screen. The band then
        // starts at or near the stack's 0 without its first row, which its
        // origin cannot say, and only the reply's word for it can. Row 29,
        // above the row, is three lines tall: where the rows above a held row
        // can start is the stack's top at the highest.
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let items = Array(0..<300)
        _ = heldFrame(
            items, holding: nil, variable: true, textIndicators: textIndicators,
            tui: tui, focusManager: focusManager)
        var held: [String] = []
        for _ in 0..<3 {
            held = heldFrame(
                items, holding: 30, variable: true, textIndicators: textIndicators,
                tui: tui, focusManager: focusManager)
        }
        #expect(
            held.firstIndex { $0.hasPrefix("row 30 ") } == (textIndicators ? 1 : 0),
            "the row is shown on its line: \(held)")
        #expect(!held.contains { $0.hasPrefix("header") }, "without the header: \(held)")
    }

    @Test("On the anchored window, a row designated far below the header lands on its line, and a scroll leaves it there")
    func anchoredFarHeldRowKeepsItsLine() {
        // Designated off screen, the row is revealed under the "more above"
        // line — line 1. The rows above it fill that line, so none of the
        // header can be on screen; placed as if the header's line were, the
        // row went to the stack's 0 with nothing above it, the scroll view
        // showed the band from its top, and the row sat on line 0 until the
        // first line scrolled moved it down to line 1.
        let box = SectionProxyBox()
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let view = ScrollView {
            Section("header") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<2_000, id: \.self) { sectionRow($0, variable: true) }
                }
            }
        }
        .scrollPosition(Binding(get: { box.position }, set: { box.position = $0 }))
        .scrollIndicatorStyle(.text)
        .frame(height: 8)
        func frame(holding row: Int?) -> [String] {
            heldBuffer(view, holding: row, tui: tui, focusManager: focusManager).lines.map(\.stripped)
        }
        let before = frame(holding: nil)
        var held: [String] = []
        for _ in 0..<3 { held = frame(holding: 1_000) }
        box.position.scrollTo(y: 2)
        let scrolled = frame(holding: 1_000)
        #expect(before.first?.hasPrefix("header") == true, "precondition: \(before)")
        #expect(held.firstIndex { $0.hasPrefix("row 1000 ") } == 1, "\(held)")
        #expect(!held.contains { $0.hasPrefix("header") }, "\(held)")
        #expect(scrolled.firstIndex { $0.hasPrefix("row 1000 ") } == 1, "\(held) → \(scrolled)")
    }

    @Test("On the anchored window, a designated row not in the data yet moves nothing: the header stays on screen")
    func anchoredAbsentHeldRowLeavesTheHeader() {
        // A designation restored before its data loads names no row, and is a
        // no-op until the row appears. Held anyway, the row at the anchor stood
        // in for the missing one at the viewport's top, over the header's
        // line; and a hold whose rows above fill its line moves the offset to
        // where they start at the stack's top — with none above row 0, from
        // under the header to the stack's 0, the header off screen for good.
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let items = Array(0..<300)
        var held: [String] = []
        for _ in 0..<3 {
            held = heldFrame(
                items, holding: 9_999, variable: true, textIndicators: true,
                tui: tui, focusManager: focusManager)
        }
        #expect(held.first?.hasPrefix("header") == true, "\(held)")
        #expect(held.firstIndex { $0.hasPrefix("row 0 ") } == 1, "\(held)")
    }

    // A header of two lines or more is room above the stack for a held row,
    // and on the anchored window the rows above the row that fill it are
    // placed from the row up: when they run out, the row's place and the
    // offset that holds it are exact, as on the uniform window. Counting only
    // the header's lines on screen at the offset it was handed, the anchored
    // window placed row 0 above the stack's top, which the fill drops: the
    // header went with it, and the row sat off its line.

    @Test(
        "A row held under a two-line header keeps its line through a one-line insert above it",
        arguments: [false, true])
    func heldRowUnderATallHeaderInsertAbove(variable: Bool) {
        let (tui, focusManager, box) = (TUIContext(), FocusManager(), SectionProxyBox())
        var items = Array(0..<300)
        func frame(_ row: Int?) -> [String] {
            underHeaderFrame(
                items, header: "head a\nhead b", holding: row, variable: variable, box: box,
                tui: tui, focusManager: focusManager)
        }
        _ = frame(nil)
        var held: [String] = []
        for _ in 0..<3 { held = frame(1) }
        #expect(line(of: 1, on: held) == 3, "precondition: \(held)")
        items.insert(1_002, at: 0)  // one line (1002 % 3 == 0)
        let after = frame(1)
        #expect(line(of: 1, on: after) == 3, "\(held) → \(after)")
        #expect(after.first?.hasPrefix("head b") == true && line(of: 1_002, on: after) == 1, "\(after)")
    }

    @Test("A row held under a header that grows a line keeps its line", arguments: [false, true])
    func heldRowUnderAGrowingHeader(variable: Bool) {
        let (tui, focusManager, box) = (TUIContext(), FocusManager(), SectionProxyBox())
        let items = Array(0..<300)
        func frame(_ header: String, _ row: Int?) -> [String] {
            underHeaderFrame(
                items, header: header, holding: row, variable: variable, box: box,
                tui: tui, focusManager: focusManager)
        }
        _ = frame("head a", nil)
        var held: [String] = []
        for _ in 0..<3 { held = frame("head a", 1) }
        #expect(line(of: 1, on: held) == 2, "precondition: \(held)")
        let grown = frame("head a\nhead b", 1)
        #expect(line(of: 1, on: grown) == 2, "\(held) → \(grown)")
        #expect(grown.first?.hasPrefix("head b") == true, "\(grown)")
    }

    @Test(
        "A row held under a two-line header stays on its line through a scroll, which moves nothing",
        arguments: [false, true])
    func heldRowUnderATallHeaderScrolled(variable: Bool) {
        // The hold owns the offset: the scroll is undone, as on every path,
        // and does not ride the row up a line, leaving the header's first
        // line unreachable while the row is held.
        let (tui, focusManager, box) = (TUIContext(), FocusManager(), SectionProxyBox())
        let items = Array(0..<300)
        func frame(_ row: Int?) -> [String] {
            underHeaderFrame(
                items, header: "head a\nhead b", holding: row, variable: variable, box: box,
                tui: tui, focusManager: focusManager)
        }
        _ = frame(nil)
        var held: [String] = []
        for _ in 0..<3 { held = frame(0) }
        #expect(line(of: 0, on: held) == 2 && held.first?.hasPrefix("head a") == true, "precondition: \(held)")
        box.position.scrollTo(y: 1)
        let scrolled = frame(0)
        box.position.scrollTo(y: 0)
        let back = frame(0)
        #expect(scrolled == held, "\(held) → \(scrolled)")
        #expect(back == held, "\(held) → \(back)")
    }

    @Test(
        "A row designated at the top under a header taller than the viewport lands on its last line",
        arguments: [false, true])
    func heldRowUnderAHeaderTallerThanTheViewport(variable: Bool) {
        // Row 0 is on line 10, below the viewport; adopted on its last line
        // clear of the "more below" one, line 6, it needs the header's first
        // four lines scrolled off — and the "more above" line saying so.
        let (tui, focusManager, box) = (TUIContext(), FocusManager(), SectionProxyBox())
        let items = Array(0..<300)
        let header = (0..<10).map { "head \($0)" }.joined(separator: "\n")
        func frame(_ row: Int?) -> [String] {
            underHeaderFrame(
                items, header: header, holding: row, variable: variable, textIndicators: true,
                box: box, tui: tui, focusManager: focusManager)
        }
        _ = frame(nil)
        var held: [String] = []
        for _ in 0..<3 { held = frame(0) }
        #expect(line(of: 0, on: held) == 6, "\(held)")
        #expect(held.first?.contains("4 more lines above") == true, "\(held)")
        #expect(held.dropFirst().first?.hasPrefix("head 5") == true, "\(held)")
    }

    @Test("On the anchored window, a header's control left out of the band is kept above it, not over the row on top")
    func anchoredHeaderControlStaysAboveTheBand() {
        // The anchored window's positions are estimates: the row revealed at
        // the top edge sits where the viewport's top is, which under a header
        // is above the stack's 0 — so the header's place, measured from that
        // 0, fell inside the band, and its control's region lay over the row.
        let (tui, focusManager) = (TUIContext(), FocusManager())
        let view = ScrollView {
            Section {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<300, id: \.self) { sectionRow($0, variable: true) }
                }
            } header: {
                Button("top") {}
            }
        }
        .frame(height: 8)
        _ = heldBuffer(view, holding: nil, tui: tui, focusManager: focusManager)
        var buffer = FrameBuffer()
        for _ in 0..<3 { buffer = heldBuffer(view, holding: 30, tui: tui, focusManager: focusManager) }
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.first?.hasPrefix("row 30 ") == true, "precondition: \(lines)")
        let onScreen = buffer.hitTestRegions.filter {
            $0.focusID?.hasPrefix("button-") == true && $0.offsetY + $0.height > 0 && $0.offsetY < 8
        }
        #expect(onScreen.isEmpty, "the header's control is on screen: \(onScreen) over \(lines)")
    }
}
