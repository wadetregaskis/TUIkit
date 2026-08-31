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
