//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MeasureRenderEquivalenceTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// Regression guard (and diagnostic) for the measure-pass correctness work.
///
/// For a corpus covering each `Layoutable` view, at a matrix of widths, it
/// compares the *analytical* measure (`measureChild` → `sizeThatFits`) against
/// the *observed* rendered size (`renderToBuffer`). The `Layoutable` contract
/// says these must agree; where they don't, the two-pass layout mis-sizes the
/// view. **Size is the asserted invariant** (the renderer is the oracle): the
/// test fails if any view *type* diverges beyond the two known-benign edges
/// (`Spacer` standalone, `Slider` at sub-viable widths). It also prints the
/// full report for diagnosis. This is the oracle that caught the identity-keyed
/// measure-cache mis-sizing and the container measure bugs.
///
/// Flexibility is reported separately and NOT asserted: a single render can't
/// reveal it, and the render-twice "+8" probe is imprecise (it calls any
/// wrapping view flexible). That awaits the flexibility-contract decision.
@MainActor
@Suite("Measure/render equivalence")
struct MeasureRenderEquivalenceTests {
    private func makeContext(width: Int, height: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext())
    }

    /// Widths to probe. `nil` = unspecified proposal (context width 80).
    private let widths: [Int?] = [nil, 80, 40, 20, 12]
    private let height = 24

    /// Per-axis check. Working contract: a NON-flexible axis must measure
    /// exactly what it renders; a FLEXIBLE axis reports a *minimum* and the
    /// renderer *fills* the available extent — so the bug conditions are
    /// "min over-reports past available" or "flexible axis didn't fill".
    private func axisBug(measured: Int, rendered: Int, available: Int, flexible: Bool, axis: String) -> String? {
        if flexible {
            if measured > available { return "\(axis): min over-reports \(measured) > available \(available)" }
            if rendered != available { return "\(axis): flexible but rendered \(rendered) != available \(available)" }
            return nil  // measured(min) ≤ rendered(filled) is expected
        }
        if measured != rendered { return "\(axis): measured \(measured) != rendered \(rendered)" }
        return nil
    }

    /// Compares analytical vs rendered size for one view across the width
    /// matrix; returns `(sizeDivergences, flexibilityNotes)`.
    private func compare<V: View>(_ view: V, _ label: String) -> (size: [String], flex: [String]) {
        var sizeOut: [String] = []
        var flexOut: [String] = []
        for w in widths {
            let availableWidth = w ?? 80
            let proposal = w.map { ProposedSize(width: $0, height: nil) } ?? .unspecified
            let wLabel = w.map(String.init) ?? "nil"

            let measured = measureChild(view, proposal: proposal, context: makeContext(width: availableWidth, height: height))
            let rendered = renderToBuffer(view, context: makeContext(width: availableWidth, height: height))

            var bugs: [String] = []
            if let b = axisBug(measured: measured.width, rendered: rendered.width, available: availableWidth,
                               flexible: measured.isWidthFlexible, axis: "W") { bugs.append(b) }
            if let b = axisBug(measured: measured.height, rendered: rendered.height, available: height,
                               flexible: measured.isHeightFlexible, axis: "H") { bugs.append(b) }
            if !bugs.isEmpty {
                sizeOut.append("  \(label) @w=\(wLabel) [flexW=\(measured.isWidthFlexible)]: " + bugs.joined(separator: "; "))
            }

            // Flexibility (descriptive only): sizeThatFits's claim vs the
            // imprecise +8 render probe.
            var probeCtx = makeContext(width: rendered.width + 8, height: height)
            probeCtx.hasExplicitWidth = false
            let probedWidth = renderToBuffer(view, context: probeCtx).width
            let probeGrew = probedWidth > rendered.width
            if measured.isWidthFlexible != probeGrew {
                flexOut.append(
                    "  \(label) @w=\(wLabel): sizeThatFits.flexW=\(measured.isWidthFlexible) vs +8-probe-grew=\(probeGrew)")
            }
        }
        return (sizeOut, flexOut)
    }

    @ViewBuilder private func conditional(_ flag: Bool) -> some View {
        if flag { Text("true branch text") } else { Text("false") }
    }

    @Test("sizeThatFits matches render across the Layoutable corpus (size invariant)")
    func report() {
        var sizeDiv: [String] = []
        var flexDiv: [String] = []
        var divergedTypes: Set<String> = []

        func check<V: View>(_ view: V, _ label: String) {
            let (s, flex) = compare(view, label)
            if !s.isEmpty { divergedTypes.insert(label); sizeDiv += s }
            flexDiv += flex
        }

        // — Leaves —
        check(Text("Hello"), "Text(short)")
        check(Text("A fairly long line of text that wraps when the width is narrow"), "Text(long/wrapping)")
        check(Spacer(), "Spacer")
        check(EmptyView(), "EmptyView")

        // — Stacks —
        check(VStack { Text("a"); Text("bb"); Text("ccc") }, "VStack(plain)")
        check(VStack(alignment: .leading) { Text("First"); Text("A longer second line that can wrap") }, "VStack(wrapping)")
        check(VStack { Text("x").frame(maxWidth: .infinity) }, "VStack(flexChild)")
        check(HStack { Text("a"); Text("bb") }, "HStack(plain)")
        check(HStack { Text("a"); Spacer(); Text("z") }, "HStack(spacer)")

        // — Frames —
        check(Text("hi").frame(maxWidth: .infinity), "frame(maxWidth:.infinity)")
        check(Text("hi").frame(width: 20), "frame(width:20)")
        check(Text("hi").frame(minWidth: 10), "frame(minWidth:10)")
        check(Text("hi").frame(minWidth: 10, maxWidth: .infinity), "frame(minWidth:10,maxWidth:.infinity)")

        // — Modifiers / wrappers —
        check(Text("hi").padding(), "padding")
        check(Text("hi").background(.blue), "background")
        check(Text("box").border(), "Text.border()")
        check(VStack { Text("A"); Text("B") }.border(), "VStack.border()")
        check(Text("fill").frame(maxWidth: .infinity).border(), "frame(infinity).border()")
        check(conditional(true), "Conditional(true)")
        check(conditional(false), "Conditional(false)")

        // — Controls (mostly Renderable-not-Layoutable → fallback = render) —
        check(Button("Save") { }, "Button")
        check(Toggle("On", isOn: .constant(true)), "Toggle")
        check(Slider(value: .constant(0.5), in: 0...1), "Slider")
        check(Stepper("Qty", value: .constant(3), in: 0...10), "Stepper")
        check(TextField("prompt", text: .constant("hello")), "TextField")

        // — Containers —
        check(ScrollView { VStack { Text("a"); Text("b") } }, "ScrollView")
        check(Panel("Settings") { Text("Network"); Text("Display") }, "Panel")
        check(Panel("Info") { Text("Body line") } footer: { Text("Footer") }, "Panel+footer")
        check(Card { Text("Card body") }, "Card")
        check(Dialog(title: "Confirm") { Text("Proceed?") }, "Dialog")

        // — The nested alignment row (the historical sore spot) —
        check(
            HStack(spacing: 2) {
                VStack(alignment: .leading) {
                    Text("Panel").bold().underline()
                    VStack(alignment: .leading) { Text("Primary"); Text("Secondary") }.border()
                }
                VStack(alignment: .leading) {
                    Text("Content Alignment").bold().underline()
                    HStack(spacing: 1) {
                        VStack { Text("Leading"); Text("short") }.frame(maxWidth: .infinity).border()
                        VStack { Text("Center"); Text("short") }.frame(maxWidth: .infinity).border()
                        VStack { Text("Trailing"); Text("short") }.frame(maxWidth: .infinity).border()
                    }
                }
            },
            "nestedAlignmentRow")

        print("\n========== MEASURE vs RENDER — SIZE DIVERGENCES ==========")
        if sizeDiv.isEmpty { print("  (none)") } else { sizeDiv.forEach { print($0) } }
        print("---- diverged types (size): \(divergedTypes.sorted().joined(separator: ", "))")
        print("\n========== FLEXIBILITY: sizeThatFits vs +8 probe (descriptive, NOT a bug list) ==========")
        if flexDiv.isEmpty { print("  (none)") } else { flexDiv.forEach { print($0) } }
        print("=========================================================\n")

        // Regression guard. Size is a clean invariant — the renderer is the
        // oracle — so no view type may diverge, EXCEPT two known-benign edges
        // that are not measure bugs:
        //   • Spacer: standalone it renders 1×1 but reports flexible; it only
        //     has meaning inside a stack, which distributes the slack. Measuring
        //     it in isolation is the artificial case, not a mis-size.
        //   • Slider: at sub-viable widths its minimum (track + arrows + value
        //     field) legibly over-reports rather than collapsing illegibly.
        // Any OTHER divergence is a genuine measure/render mismatch and fails.
        let knownBenign: Set<String> = ["Spacer", "Slider"]
        let unexpected = divergedTypes.subtracting(knownBenign).sorted()
        #expect(
            unexpected.isEmpty,
            "Unexpected measure/render size divergence (see report above): \(unexpected)")
    }
}
