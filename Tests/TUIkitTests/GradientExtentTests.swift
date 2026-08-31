//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientExtentTests.swift
//
//  `.gradientExtent(.subtree)` — the TUI-specific half. SwiftUI has no way to
//  say "span this set of controls" (measured: `ShapeStyle.in(_:)` re-anchors at
//  every leaf, and the mask idiom costs the content's interactivity), so this
//  is an addition and it needs its own evidence.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Gradient extent")
struct GradientExtentTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)

    private func context(width: Int = 40, height: Int = 10) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// The truecolor ink of each visible cell of a line, `nil` where none.
    private func inks(_ line: String) -> [String?] {
        var out: [String?] = []
        var current: String?
        var rest = Substring(line)
        while let escape = rest.firstIndex(of: "\u{1B}") {
            for character in rest[rest.startIndex..<escape] {
                out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
            }
            rest = rest[escape...]
            guard let end = rest.firstIndex(of: "m") else { break }
            let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<end]
            if let range = body.range(of: "38;2;") {
                current = body[range.upperBound...].split(separator: ";").prefix(3)
                    .joined(separator: ";")
            } else if body == "0" {
                current = nil
            }
            rest = rest[rest.index(after: end)...]
        }
        for character in rest {
            out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
        }
        return out
    }

    private func firstInk(_ line: String) -> String? { inks(line).compactMap { $0 }.first }

    private func vertical() -> LinearGradient {
        LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom)
    }

    private func horizontal() -> LinearGradient {
        LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - The feature

    /// The headline, and the one the request asked for: first row red, last row
    /// blue, with every row a step along the way — rather than each row running
    /// the whole ramp inside itself.
    @Test("A vertical ramp spans the rows of a stack")
    func verticalSpansRows() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines

        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        #expect(rows[3] == "0;0;255", "the last row is not the ramp's end: \(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "rows repeat: \(rows)")
    }

    /// Without the modifier the same tree is SwiftUI's meaning: every leaf runs
    /// the whole ramp inside itself, so a one-row leaf takes the midpoint and
    /// they all look alike.
    @Test("Without it, each row runs its own ramp — the default is unchanged")
    func leafExtentIsTheDefault() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical()),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "the default spanned the stack: \(rows)")
    }

    /// `.leaf` put back inside a `.subtree` returns to per-leaf resolution — the
    /// modifier is a scope, not a switch thrown once.
    @Test("An inner .leaf overrides an outer .subtree")
    func innerLeafOverrides() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .gradientExtent(.leaf)
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "\(rows)")
    }

    /// The horizontal half, through an `HStack`, whose own axis is the one it
    /// distributes — so this is the exact case rather than the predicted one.
    @Test("A horizontal ramp spans the columns of a row")
    func horizontalSpansColumns() {
        let lines = renderToBuffer(
            HStack(spacing: 0) {
                Text(verbatim: "AA")
                Text(verbatim: "BB")
                Text(verbatim: "CC")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let cells = inks(lines[0]).compactMap { $0 }
        #expect(cells.count == 6, "\(cells)")
        #expect(cells.first == "255;0;0")
        #expect(cells.last == "0;0;255")
        // Monotone across the whole row: each column is further along than the
        // one before it, which is what "one ramp" means.
        let blues = cells.map { Int($0.split(separator: ";").last ?? "0") ?? 0 }
        #expect(blues == blues.sorted(), "the ramp did not run left to right: \(blues)")
    }

    /// A leaf still resolves over the EXTENT, not its own box, so a short leaf
    /// at the far end takes the far end's colour rather than the whole ramp.
    @Test("A short leaf takes its own slice of the extent, not the whole ramp")
    func shortLeafTakesItsSlice() {
        let lines = renderToBuffer(
            HStack(spacing: 0) {
                Text(verbatim: "AAAAAA")
                Text(verbatim: "B")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let cells = inks(lines[0]).compactMap { $0 }
        #expect(cells.count == 7, "\(cells)")
        #expect(cells.last == "0;0;255", "the last cell is not the ramp's end")
        #expect(cells[5] != "0;0;255", "the wide leaf reached the end on its own")
    }

    // MARK: - Nothing when unused

    @Test("A context with no subtree gradient carries no frame")
    func noFrameWhenUnused() {
        var seen: GradientFrame??
        _ = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                _FrameProbe { seen = $0 }
            },
            context: context())
        #expect(seen == .some(nil), "a frame was published with no .gradientExtent in force")
    }
}

// MARK: - `.in(_:)`, the other half

extension GradientExtentTests {

    /// SwiftUI's own extent knob fixes the ramp's SCALE: four cells of a ramp
    /// told to run over forty only get the first tenth of it, so a text that
    /// would have ended blue ends barely off red.
    @Test("`.in(_:)` resolves over the size it names, not the leaf's own")
    func fixedExtentRescalesTheRamp() {
        let plain = renderToBuffer(
            Text(verbatim: "AAAA").foregroundStyle(horizontal()), context: context()
        ).lines[0]
        let scaled = renderToBuffer(
            Text(verbatim: "AAAA")
                .foregroundStyle(horizontal().in(CellRect(x: 0, y: 0, width: 40, height: 1))),
            context: context()
        ).lines[0]

        #expect(inks(plain).compactMap { $0 }.last == "0;0;255", "four cells, the whole ramp")
        let end = inks(scaled).compactMap { $0 }.last
        #expect(end != "0;0;255", "the ramp was not rescaled: \(String(describing: end))")
        let red = end.flatMap { Int($0.split(separator: ";")[0]) } ?? 0
        #expect(red > 200, "four cells of forty should still be red: \(String(describing: end))")
    }

    /// And it fixes ONLY the scale. Each leaf still anchors the ramp at
    /// itself, so four rows told to resolve over eight all take the same early
    /// slice — measured in SwiftUI, and the reason `.in(_:)` cannot express
    /// "one ramp across a set" however tempting it looks.
    @Test("`.in(_:)` re-anchors at every leaf, so it cannot span a set")
    func fixedExtentReAnchorsPerLeaf() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical().in(CellRect(x: 0, y: 0, width: 4, height: 8))),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "rows differ, so it anchored once: \(rows)")
        // And it did something: a bare one-row leaf takes the ramp's far end,
        // where a row of eight takes its start.
        #expect(rows[0] != "0;0;255", "the rescaling did not happen: \(rows)")
    }

    /// Two knobs, one question, so the order has to be stated: `.in(_:)` names
    /// the rectangle outright, and outright wins.
    @Test("`.in(_:)` overrides an enclosing .gradientExtent(.subtree)")
    func fixedExtentBeatsSubtree() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical().in(CellRect(x: 0, y: 0, width: 4, height: 8)))
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "the subtree extent won: \(rows)")
    }

    // MARK: - Lazy stacks

    /// A `LazyVStack` is the same core as `VStack` under a different overflow
    /// policy, but a different render path — one that renders as it walks, so
    /// it cannot learn its own extent on the way and has to measure the rows
    /// that will fit before it starts. It got no ramp at all until it did.
    @Test("A vertical ramp spans the rows of a LazyVStack")
    func lazyVerticalSpansRows() {
        let lines = renderToBuffer(
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
                Text(verbatim: "DDDD")
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context()
        ).lines

        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        #expect(rows[3] == "0;0;255", "the last row is not the ramp's end: \(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "rows repeat: \(rows)")
    }

    /// The horizontal twin, through `LazyHStack`'s own append-while-it-fits
    /// walk.
    @Test("A horizontal ramp spans the columns of a LazyHStack")
    func lazyHorizontalSpansColumns() {
        let lines = renderToBuffer(
            LazyHStack(spacing: 0) {
                Text(verbatim: "AA")
                Text(verbatim: "BB")
                Text(verbatim: "CC")
                Text(verbatim: "DD")
            }
            .foregroundStyle(horizontal())
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let cells = inks(lines[0]).prefix(8).compactMap { $0 }
        #expect(cells.first == "255;0;0", "the first column is not the start: \(cells)")
        #expect(cells.last == "0;0;255", "the last column is not the end: \(cells)")
    }

    /// The rule a scrolling list needs: the ramp spans the CONTENT, not the
    /// viewport. Ten rows of forty are on screen, so they take the first
    /// quarter of the ramp — a row keeps its colour as it scrolls rather than
    /// the whole column re-inking under a ramp pinned to the screen.
    @Test("A ramp over scrolling content spans the content, not the window")
    func lazyRampSpansContentNotViewport() {
        let lines = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in
                        Text(verbatim: "row \(index)")
                    }
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context(height: 10)
        ).lines

        let rows = lines.prefix(10).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        // Row 9 of 40 is a quarter of the way down a red→blue ramp: still
        // mostly red. Pinned to the viewport it would be full blue.
        let last = rows[9]?.split(separator: ";").compactMap { Int($0) }
        #expect(last?.count == 3, "no ink on the last visible row: \(rows)")
        if let last, last.count == 3 {
            #expect(last[0] > last[2], "the window took the whole ramp: \(rows)")
            #expect(last[0] < 255, "the ramp did not advance down the window: \(rows)")
        }
        #expect(Set(rows.compactMap { $0 }).count > 1, "rows repeat: \(rows)")
    }

    /// Variable-height rows in a scroll window take the exact slot walk rather
    /// than the arithmetic seek — a third render path, with its own idea of
    /// where each row is, and the ramp has to agree with it.
    @Test("A ramp spans content the exact slot walk places")
    func lazyRampAcrossExactWalk() {
        let lines = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "AAAA")
                    Text(verbatim: "BBBB")
                    Text(verbatim: "CCCC")
                    Text(verbatim: "DDDD")
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context(height: 4)
        ).lines

        let rows = lines.prefix(4).map { firstInk($0) }
        #expect(rows[0] == "255;0;0", "the first row is not the ramp's start: \(rows)")
        #expect(rows[3] == "0;0;255", "the last row is not the ramp's end: \(rows)")
        #expect(Set(rows.compactMap { $0 }).count == 4, "rows repeat: \(rows)")
    }

    /// Past the anchored threshold with variable-height rows, the stack stops
    /// walking the content at all and works outward from an anchor on
    /// estimates. The ramp is estimated with it — approximate by construction,
    /// and required to still start at the start and advance downward.
    @Test("A ramp over anchored content advances from the top")
    func lazyRampAcrossAnchoredWalk() {
        let lines = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<300, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "row \(index)")
                            if index.isMultiple(of: 2) { Text(verbatim: "more") }
                        }
                    }
                }
            }
            .foregroundStyle(vertical())
            .gradientExtent(.subtree),
            context: context(height: 8)
        ).lines

        let rows = lines.prefix(8).compactMap { firstInk($0) }
        #expect(rows.first == "255;0;0", "the first row is not the ramp's start: \(rows)")
        // Eight lines of three hundred rows: a sliver at the very top of the
        // ramp, so every visible row is red-dominant and none is the end.
        for row in rows {
            let channels = row.split(separator: ";").compactMap { Int($0) }
            #expect(channels.count == 3, "malformed ink \(row)")
            if channels.count == 3 {
                #expect(channels[0] > channels[2], "the ramp ran to its end on screen: \(rows)")
            }
        }
    }

    /// A lazy stack under the default extent is still SwiftUI's meaning.
    @Test("Without the modifier a LazyVStack row runs its own ramp")
    func lazyLeafExtentIsTheDefault() {
        let lines = renderToBuffer(
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB")
                Text(verbatim: "CCCC")
            }
            .foregroundStyle(vertical()),
            context: context()
        ).lines
        let rows = lines.prefix(3).map { firstInk($0) }
        #expect(Set(rows.compactMap { $0 }).count == 1, "the default spanned the stack: \(rows)")
    }
}

/// Reports the render context's gradient frame and draws nothing.
private struct _FrameProbe: View {
    let report: (GradientFrame?) -> Void
    var body: Never { fatalError("renders via Renderable") }
}

extension _FrameProbe: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        report(context.gradientFrame)
        return FrameBuffer(lines: ["."])
    }
}
