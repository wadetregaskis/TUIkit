//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientBackgroundTests.swift
//
//  `.background(gradient)`. The background is the harder half of the two: a
//  foreground replaces the colour a leaf was going to use, while a background
//  has to survive being interleaved with whatever the content already emitted.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Gradient backgrounds")
struct GradientBackgroundTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)

    private func context(width: Int = 20, height: Int = 6) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
    }

    /// The truecolor BACKGROUND of each visible cell, `nil` where none.
    private func fills(_ line: String) -> [String?] {
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
            if let range = body.range(of: "48;2;") {
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

    @Test("A vertical ramp fills each row with one colour")
    func verticalFillsRows() {
        let lines = renderToBuffer(
            Text(verbatim: "one\ntwo\nthree")
                .background(
                    LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom)),
            context: context()
        ).lines
        let rows = lines.prefix(3).map { Set(fills($0).compactMap { $0 }) }
        for (index, row) in rows.enumerated() {
            #expect(row.count == 1, "row \(index) was not one colour: \(row)")
        }
        #expect(rows[0] == ["255;0;0"])
        #expect(rows[2] == ["0;0;255"])
    }

    @Test("A horizontal ramp fills across a row")
    func horizontalFillsColumns() {
        let lines = renderToBuffer(
            Text(verbatim: "hello")
                .background(
                    LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)),
            context: context()
        ).lines
        let cells = fills(lines[0]).compactMap { $0 }
        #expect(cells.count == 5, "\(cells)")
        #expect(cells.first == "255;0;0")
        #expect(cells.last == "0;0;255")
        let blues = cells.map { Int($0.split(separator: ";").last ?? "0") ?? 0 }
        #expect(blues == blues.sorted(), "the fill did not run left to right: \(blues)")
    }

    /// The point of slicing rather than rebuilding: the content keeps its own
    /// colours through being cut at the ramp's boundaries.
    @Test("The content's own foreground survives the fill")
    func contentKeepsItsForeground() {
        let lines = renderToBuffer(
            Text(verbatim: "hello").foregroundStyle(Color.rgb(1, 2, 3))
                .background(
                    LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)),
            context: context()
        ).lines
        // Every cell of the word still asks for the stated ink.
        var seen = 0
        var rest = Substring(lines[0])
        while let range = rest.range(of: "38;2;1;2;3") {
            seen += 1
            rest = rest[range.upperBound...]
        }
        #expect(seen >= 1, "the foreground was lost: \(lines[0].debugDescription)")
        let cells = fills(lines[0]).compactMap { $0 }
        #expect(Set(cells).count > 1, "the background did not vary")
    }

    @Test("A plain colour background is unchanged")
    func plainColourIsUnchanged() {
        let gradient = renderToBuffer(
            Text(verbatim: "hi").background(Color.rgb(7, 8, 9)), context: context()
        ).lines
        #expect(Set(fills(gradient[0]).compactMap { $0 }) == ["7;8;9"])
    }

    /// A background under `.gradientExtent(.subtree)` resolves over the same
    /// rectangle a foreground would.
    @Test("A subtree extent reaches the background too")
    func subtreeExtentAppliesToBackgrounds() {
        let lines = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "aa").background(
                    LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom))
                Text(verbatim: "bb").background(
                    LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom))
                Text(verbatim: "cc").background(
                    LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom))
            }
            .gradientExtent(.subtree),
            context: context()
        ).lines
        let rows = lines.prefix(3).compactMap { fills($0).compactMap { $0 }.first }
        #expect(rows.count == 3)
        #expect(rows[0] == "255;0;0", "\(rows)")
        #expect(rows[2] == "0;0;255", "\(rows)")
    }
}
