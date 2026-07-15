//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ShortTerminalCrashTests.swift
//
//  The app's content area is `terminalHeight - statusBarHeight - appHeaderHeight`
//  (RenderLoop). None of those subtractions were clamped, so a terminal shorter
//  than its own chrome produced a NEGATIVE available height — which
//  `WindowGroup.centerBuffer` then fed straight into `0..<(targetHeight -
//  verticalOffset)`, trapping with "Range requires lowerBound <= upperBound"
//  before a single frame was drawn. Reproduced end-to-end: TUIkitExample died at
//  1, 2, 4 and 5 rows with exactly that message, backtrace at App.swift:563.
//
//  Two invariants are pinned here:
//    1. The framework never offers a negative available size (clamp at source).
//    2. A renderer handed one anyway must not trap (total at the sink).
//  Both, because either alone leaves the other free to regress.
//
//  These are exit tests: the scenario runs in a child process, so a trap is
//  reported as a test failure instead of killing the whole test run.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct Row: Identifiable, Sendable {
    let id: Int
    var name: String { "row-\(id)" }
}

@MainActor
@Suite("Terminal shorter than its chrome")
struct ShortTerminalCrashTests {

    @Test("A WindowGroup handed a negative height must not trap")
    func windowGroupSurvivesNegativeHeight() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                // `terminalHeight - statusBarHeight - appHeaderHeight` goes
                // negative the moment the terminal is shorter than the chrome.
                for height in [-5, -1, 0, 1] {
                    let scene = WindowGroup {
                        VStack {
                            Text("hello")
                            Text("world")
                        }
                    }
                    var context = makeRenderContext(width: 20, height: max(1, height))
                    context.availableHeight = height
                    context.hasExplicitWidth = true
                    context.hasExplicitHeight = true
                    // Trapped here pre-fix: 0..<negative in centerBuffer.
                    _ = scene.renderScene(context: context)
                }
            }
        }
    }

    @Test("A negative width must not trap either")
    func windowGroupSurvivesNegativeWidth() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                for width in [-5, -1, 0, 1] {
                    let scene = WindowGroup { Text("hello") }
                    var context = makeRenderContext(width: max(1, width), height: 5)
                    context.availableWidth = width
                    context.hasExplicitWidth = true
                    context.hasExplicitHeight = true
                    _ = scene.renderScene(context: context)
                }
            }
        }
    }

    @Test("A Table in a terminal shorter than its chrome must not trap")
    func tableInAShortTerminal() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let rows = (0..<50).map { Row(id: $0) }
                for height in [-3, -1, 0, 1, 2, 3] {
                    let scene = WindowGroup {
                        Table(rows, selection: .constant(Int?.none)) {
                            TableColumn("Name", value: \Row.name)
                        }
                    }
                    var context = makeRenderContext(width: 40, height: max(1, height))
                    context.availableHeight = height
                    context.hasExplicitWidth = true
                    context.hasExplicitHeight = true
                    _ = scene.renderScene(context: context)
                }
            }
        }
    }

    @Test("A Table column ratio of NaN or infinity must not trap")
    func tableRatioColumnSurvivesNonFiniteRatio() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                // `.ratio` takes an unvalidated Double from public API, and a
                // computed ratio (a / b with b == 0) is NaN or ±infinity.
                // `Int(Double)` traps on both.
                let rows = (0..<5).map { Row(id: $0) }
                for ratio in [Double.nan, .infinity, -.infinity, 1e30, -1] {
                    let view = Table(rows, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \Row.name).width(.ratio(ratio))
                    }
                    let context = makeRenderContext(width: 40, height: 10)
                    _ = renderToBuffer(view, context: context)
                }
            }
        }
    }

    @Test("A negative columnSpacing must not trap")
    func tableSurvivesNegativeColumnSpacing() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                // `columnSpacing:` is a public init parameter with no validation;
                // it reached `String(repeating:count:)`, which traps when negative.
                let rows = (0..<5).map { Row(id: $0) }
                let view = Table(rows, selection: .constant(Int?.none), columnSpacing: -2) {
                    TableColumn("Name", value: \Row.name)
                    TableColumn("Also", value: \Row.name)
                }
                let context = makeRenderContext(width: 40, height: 10)
                _ = renderToBuffer(view, context: context)
            }
        }
    }
}
