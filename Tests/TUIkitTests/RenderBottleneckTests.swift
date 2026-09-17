//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderBottleneckTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - Render Bottleneck Analysis

/// Deep analysis tests to identify specific render bottlenecks.
@MainActor
@Suite("Render Bottleneck Analysis")
struct RenderBottleneckTests {

    private func testContext(width: Int = 80, height: Int = 24) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    /// CPU seconds this thread spends running `block` `iterations` times.
    ///
    /// The fastest of several batches, scaled back to the full iteration count,
    /// read on the per-thread CPU clock — see `bestCPUSeconds`. The minimum
    /// drops the batches that were interrupted; the CPU clock means an
    /// interrupted batch was never counted as slower to begin with. This used
    /// to be a wall clock, and `analyzeForEachIterations` failed 2 of 6
    /// full-suite runs at `-j 6` because of it.
    private func measure(_ name: String, iterations: Int = 1000, block: () -> Void) -> TimeInterval {
        let batches = 5
        let perBatch = max(1, iterations / batches)
        let best = bestCPUSeconds(batches: batches) {
            for _ in 0..<perBatch {
                block()
            }
        }
        let time = best * Double(iterations) / Double(perBatch)
        let perIteration = (time / Double(iterations)) * 1000
        print("  \(name): \(String(format: "%.3f", perIteration))ms per iteration (best of \(batches) batches)")
        return time
    }

    // MARK: - Stack Depth Analysis

    @Test("Analyze stack nesting depth impact")
    func analyzeStackNestingDepth() {
        let context = testContext()
        let iterations = 500

        print("\n=== Stack Nesting Depth Analysis ===")

        // Depth 1
        let depth1 = VStack { Text("A") }
        let time1 = measure("Depth 1", iterations: iterations) {
            _ = renderToBuffer(depth1, context: context)
        }

        // Depth 2
        let depth2 = VStack { VStack { Text("A") } }
        _ = measure("Depth 2", iterations: iterations) {
            _ = renderToBuffer(depth2, context: context)
        }

        // Depth 3
        let depth3 = VStack { VStack { VStack { Text("A") } } }
        _ = measure("Depth 3", iterations: iterations) {
            _ = renderToBuffer(depth3, context: context)
        }

        // Depth 5
        let depth5 = VStack { VStack { VStack { VStack { VStack { Text("A") } } } } }
        _ = measure("Depth 5", iterations: iterations) {
            _ = renderToBuffer(depth5, context: context)
        }

        // Depth 10
        let depth10 = VStack {
            VStack {
                VStack {
                    VStack {
                        VStack {
                            VStack { VStack { VStack { VStack { VStack { Text("A") } } } } }
                        }
                    }
                }
            }
        }
        let time10 = measure("Depth 10", iterations: iterations) {
            _ = renderToBuffer(depth10, context: context)
        }

        print("=====================================\n")

        // Overhead per nesting level, in units of one depth-1 render. A pure
        // number: the machine divides out, so it means the same on this laptop
        // and on a shared runner five times slower.
        let overheadPerLevel = (time10 - time1) / 9.0 / time1
        print("Overhead per nesting level: \(String(format: "%.2f", overheadPerLevel))x a depth-1 render")

        // Two-pass layout costs a measure and a render at every level, so a
        // level is a fraction of a whole depth-1 render, not a multiple of one:
        // measured 1.50-1.58x.
        #expect(overheadPerLevel < 5, "each nesting level costs \(overheadPerLevel)x a depth-1 render")
    }

    // MARK: - Child Count Analysis

    @Test("Analyze child count impact on VStack")
    func analyzeChildCountVStack() {
        let context = testContext()
        let iterations = 500

        print("\n=== VStack Child Count Analysis ===")

        // 1 child
        let children1 = VStack { Text("A") }
        let time1 = measure("1 child", iterations: iterations) {
            _ = renderToBuffer(children1, context: context)
        }

        // 5 children
        let children5 = VStack {
            Text("A")
            Text("B")
            Text("C")
            Text("D")
            Text("E")
        }
        _ = measure("5 children", iterations: iterations) {
            _ = renderToBuffer(children5, context: context)
        }

        // 10 children
        let children10 = VStack {
            Text("A")
            Text("B")
            Text("C")
            Text("D")
            Text("E")
            Text("F")
            Text("G")
            Text("H")
            Text("I")
            Text("J")
        }
        let time10 = measure("10 children", iterations: iterations) {
            _ = renderToBuffer(children10, context: context)
        }

        print("=====================================\n")

        // Ten rows against one: linear is ~10x, quadratic ~100x, and the bound
        // sits between them and far from both — measured 7.5-7.9x.
        let ratio = time10 / time1
        print("Scale factor (10 vs 1 child): \(String(format: "%.2f", ratio))x")
        #expect(ratio < 25, "a 10-row VStack costs \(ratio)x a 1-row VStack")
    }

    // MARK: - ForEach Analysis

    @Test("Analyze ForEach iteration count impact")
    func analyzeForEachIterations() {
        let context = testContext()
        let iterations = 200

        print("\n=== ForEach Iteration Analysis ===")

        // 5 items
        let items5 = Array(0..<5)
        let forEach5 = VStack {
            ForEach(items5, id: \.self) { i in
                Text("Row \(i)")
            }
        }
        _ = measure("5 items", iterations: iterations) {
            _ = renderToBuffer(forEach5, context: context)
        }

        // 20 items
        let items20 = Array(0..<20)
        let forEach20 = VStack {
            ForEach(items20, id: \.self) { i in
                Text("Row \(i)")
            }
        }
        _ = measure("20 items", iterations: iterations) {
            _ = renderToBuffer(forEach20, context: context)
        }

        // 50 items
        let items50 = Array(0..<50)
        let forEach50 = VStack {
            ForEach(items50, id: \.self) { i in
                Text("Row \(i)")
            }
        }
        let time50 = measure("50 items", iterations: iterations) {
            _ = renderToBuffer(forEach50, context: context)
        }

        // 100 items
        let items100 = Array(0..<100)
        let forEach100 = VStack {
            ForEach(items100, id: \.self) { i in
                Text("Row \(i)")
            }
        }
        let time100 = measure("100 items", iterations: iterations) {
            _ = renderToBuffer(forEach100, context: context)
        }

        print("=====================================\n")

        // Should scale linearly, not exponentially
        let scaleFactor = time100 / time50
        print("Scale factor (100 vs 50 items): \(String(format: "%.2f", scaleFactor))x")
        #expect(scaleFactor < 3.0, "ForEach scaling is worse than linear: \(scaleFactor)x for 2x items")
    }

    // MARK: - Modifier Chain Analysis

    @Test("Analyze modifier chain depth impact")
    func analyzeModifierChainDepth() {
        let context = testContext()
        let iterations = 500

        print("\n=== Modifier Chain Analysis ===")

        // No modifiers
        let noModifiers = Text("Hello")
        let time0 = measure("0 modifiers", iterations: iterations) {
            _ = renderToBuffer(noModifiers, context: context)
        }

        // 1 modifier
        let oneModifier = Text("Hello").bold()
        _ = measure("1 modifier", iterations: iterations) {
            _ = renderToBuffer(oneModifier, context: context)
        }

        // 3 modifiers
        let threeModifiers = Text("Hello").bold().foregroundStyle(.ansi(.red)).dimmed()
        _ = measure("3 modifiers", iterations: iterations) {
            _ = renderToBuffer(threeModifiers, context: context)
        }

        // 5 modifiers
        let fiveModifiers = Text("Hello")
            .bold()
            .foregroundStyle(.ansi(.red))
            .dimmed()
            .padding(1)
            .border(style: .line)
        let time5 = measure("5 modifiers", iterations: iterations) {
            _ = renderToBuffer(fiveModifiers, context: context)
        }

        print("=====================================\n")

        // Five modifiers over the very Text the 0-modifier arm renders bare, so
        // this reads the modifier pipeline almost neat: measured 8.7-9.2x.
        let ratio = time5 / time0
        print("Scale factor (5 modifiers vs 0): \(String(format: "%.2f", ratio))x")
        #expect(ratio < 25, "five modifiers cost \(ratio)x an unmodified Text")
    }

    // MARK: - Interactive Controls Analysis

    @Test("Analyze interactive control overhead")
    func analyzeInteractiveControlOverhead() {
        let context = testContext()
        let iterations = 500

        print("\n=== Interactive Control Analysis ===")

        // Simple Text (baseline)
        let text = Text("Hello")
        let timeText = measure("Text (baseline)", iterations: iterations) {
            _ = renderToBuffer(text, context: context)
        }

        // Button
        let button = Button("Click") {}
        _ = measure("Button", iterations: iterations) {
            _ = renderToBuffer(button, context: context)
        }

        // Toggle
        var isOn = false
        let toggle = Toggle("Enable", isOn: Binding(get: { isOn }, set: { isOn = $0 }))
        _ = measure("Toggle", iterations: iterations) {
            _ = renderToBuffer(toggle, context: context)
        }

        // Menu (more complex)
        let menu = Menu("Menu") {
            Button("A") {}
            Button("B") {}
            Button("C") {}
        }
        .menuStyle(.inline)
        _ = measure("Menu (3 items)", iterations: iterations) {
            _ = renderToBuffer(menu, context: context)
        }

        // RadioButtonGroup
        var selection = "a"
        let radioGroup = RadioButtonGroup(
            selection: Binding(get: { selection }, set: { selection = $0 })
        ) {
            RadioButtonItem("a", "Option A")
            RadioButtonItem("b", "Option B")
            RadioButtonItem("c", "Option C")
        }
        let timeRadio = measure("RadioButtonGroup (3 items)", iterations: iterations) {
            _ = renderToBuffer(radioGroup, context: context)
        }

        print("=====================================\n")

        // The dearest control here against the bare primitive — the baseline
        // this test already measured and then threw away: measured 13.3-14.3x.
        let ratio = timeRadio / timeText
        print("RadioButtonGroup vs Text: \(String(format: "%.2f", ratio))x")
        #expect(ratio < 50, "a 3-item RadioButtonGroup costs \(ratio)x a Text")
    }

    // MARK: - String Operations Analysis

    @Test("Analyze ANSI string operations impact")
    func analyzeStringOperations() {
        let context = testContext()
        let iterations = 500

        print("\n=== String Operations Analysis ===")

        // Short text
        let shortText = Text("Hi")
        let timeShort = measure("Short text (2 chars)", iterations: iterations) {
            _ = renderToBuffer(shortText, context: context)
        }

        // Medium text
        let mediumText = Text("This is a medium length text string")
        _ = measure("Medium text (36 chars)", iterations: iterations) {
            _ = renderToBuffer(mediumText, context: context)
        }

        // Long text
        let longText = Text(String(repeating: "A", count: 200))
        _ = measure("Long text (200 chars)", iterations: iterations) {
            _ = renderToBuffer(longText, context: context)
        }

        // Very long text
        let veryLongText = Text(String(repeating: "B", count: 1000))
        let timeLong = measure("Very long text (1000 chars)", iterations: iterations) {
            _ = renderToBuffer(veryLongText, context: context)
        }

        print("=====================================\n")

        // 1000 characters against 2. A per-character cost that stopped being
        // linear — a width scan that rewalks the string, the defect
        // `TextFieldScalingTests` guards next door — would read in the hundreds,
        // not as a small multiple: measured 1.9-2.1x.
        let ratio = timeLong / timeShort
        print("Scale factor (1000 chars vs 2): \(String(format: "%.2f", ratio))x")
        #expect(ratio < 8, "1000 characters cost \(ratio)x two characters")
    }

    // MARK: - LazyStack vs Regular Stack

    @Test("Compare LazyStack vs regular Stack performance")
    func compareLazyVsRegular() {
        let iterations = 300

        print("\n=== Lazy vs Regular Stack Comparison ===")

        // Large item count, small viewport
        let items = Array(0..<100)
        let smallContext = testContext(height: 10)

        let regularStack = VStack {
            ForEach(items, id: \.self) { i in
                Text("Row \(i)")
            }
        }
        let regularTime = measure("VStack (100 items, 10 visible)", iterations: iterations) {
            _ = renderToBuffer(regularStack, context: smallContext)
        }

        let lazyStack = LazyVStack {
            ForEach(items, id: \.self) { i in
                Text("Row \(i)")
            }
        }
        let lazyTime = measure("LazyVStack (100 items, 10 visible)", iterations: iterations) {
            _ = renderToBuffer(lazyStack, context: smallContext)
        }

        print("=====================================\n")

        let speedup = regularTime / lazyTime
        print("LazyVStack speedup: \(String(format: "%.2f", speedup))x")

        // LazyVStack may have overhead for small datasets, but should not be
        // dramatically slower. Allow up to 3x for measurement variance.
        #expect(lazyTime <= regularTime * 3.0, "LazyVStack should not be dramatically slower than VStack")
    }
}
