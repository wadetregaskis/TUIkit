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
/// The flexibility contract (see ``ViewSize``) is now settled: an axis is
/// flexible iff the render *fills* the offered extent past the view's ideal, and
/// `sizeThatFits` is canonical. The size invariant here already enforces it
/// (`flexible ⟹ rendered == available`; `fixed ⟹ rendered == measured`), and
/// ``flexibilityContract()`` pins the exact flag per canonical view. The "+8"
/// probe below is kept only as a *descriptive* diagnostic of the render-to-
/// measure fallback's heuristic — it over-reports flexibility for wrapping
/// content (it calls any view that reflows wider "flexible"), so it is NOT the
/// contract and is intentionally not asserted against.
@MainActor
@Suite("Measure/render equivalence")
struct MeasureRenderEquivalenceTests {
    private func makeContext(width: Int, height: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()).isolatingRenderCache()
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
        check(Dialog(title: "Confirm") { Text("Proceed?") } footer: { Button("OK") {} }, "Dialog+footer")

        // — Adaptive / tab / erased (this session's flexibility-sensitive surface;
        //   the views whose measure/render had to be reconciled by hand) —
        check(
            ViewThatFits {
                HStack(spacing: 1) { Text("Alpha"); Text("Beta"); Text("Gamma") }
                VStack(spacing: 0) { Text("Alpha"); Text("Beta"); Text("Gamma") }
            }, "ViewThatFits")
        // The colour-picker channel-editor row shape — fixed slider + fields wide,
        // stacked narrow — the case whose 1-cell measure drift drove the TabView
        // render-then-clamp centring.
        check(
            ViewThatFits {
                HStack(spacing: 1) {
                    Text("R").frame(width: 2)
                    Slider(value: .constant(0.5), in: 0...1).frame(width: 16)
                    Text("31%").frame(width: 7)
                }
                VStack(spacing: 0) {
                    Text("R")
                    Slider(value: .constant(0.5), in: 0...1)
                }
            }, "ViewThatFits(editorRow)")
        check(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) { Text("alpha") }
                Tab("B", value: 1) { Text("beta") }
            }.tabViewStyle(.compact), "TabView(compact)")
        check(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) { Text("alpha") }
                Tab("B", value: 1) { Text("beta") }
            }.tabViewStyle(.bordered), "TabView(bordered)")
        check(AnyView(Text("erased")), "AnyView(Text)")
        check(AnyView(Text("fill").frame(maxWidth: .infinity)), "AnyView(flexFrame)")
        // AnyView now forwards measurement to the wrapped view; these exercise the
        // forward over composite / flexible / chrome content (the cases the old
        // "forwarded measure differs" objection cited), so they pin that the
        // erased subtree measures structurally and still agrees with the render.
        check(AnyView(VStack { Text("one"); Text("two longer") }), "AnyView(VStack)")
        check(AnyView(HStack { Text("a"); Spacer(); Text("z") }), "AnyView(HStack+spacer)")
        check(AnyView(Text("boxed").border()), "AnyView(border)")

        // — Newly-Layoutable controls (were render-to-measure fallback) —
        check(ZStack { Text("████████"); Text("hi") }, "ZStack")
        check(ZStack { Text("x").frame(maxWidth: .infinity); Text("o") }, "ZStack(flexChild)")
        check(Spinner("Loading"), "Spinner")
        check(ButtonRow { Button("OK") {}; Button("Cancel") {} }, "ButtonRow")
        check(
            Menu(title: "Actions", items: [
                MenuItem(label: "New", shortcut: "n"),
                MenuItem(label: "Open", shortcut: "o"),
            ]), "Menu")
        check(
            Picker("Theme", selection: .constant(0)) {
                Text("Light").tag(0)
                Text("Dark").tag(1)
            }.pickerStyle(.menu), "Picker(menu)")
        check(
            Picker("Theme", selection: .constant(0)) {
                Text("Light").tag(0)
                Text("Dark").tag(1)
            }.pickerStyle(.inline), "Picker(inline)")
        check(
            RadioButtonGroup(selection: .constant(0), items: [
                RadioButtonItem(0) { Text("First") },
                RadioButtonItem(1) { Text("Second") },
            ]), "RadioButtonGroup")
        check(Box(lines: ["pre-styled", "buffer"]), "Box(lines)")
        check(
            ContentUnavailableView {
                Text("No Results")
            } description: {
                Text("Try a different search.")
            } actions: {
                Button("Clear Filters") {}
            }, "ContentUnavailableView")
        check(LazyVStack { Text("a"); Text("bb"); Text("ccc") }, "LazyVStack(plain)")
        check(LazyHStack { Text("a"); Text("bb"); Text("ccc") }, "LazyHStack(plain)")
        // Windowed: more rows/cols than fit → the render truncates on a child
        // boundary, the case an analytical sum-and-clamp would mis-size.
        check(
            LazyVStack(spacing: 1) { ForEach(1...40, id: \.self) { Text("Row \($0)") } },
            "LazyVStack(windowed)")
        check(
            LazyHStack(spacing: 2) { ForEach(1...40, id: \.self) { Text("C\($0)") } },
            "LazyHStack(windowed)")
        check(
            Section {
                Text("Row one"); Text("Row two")
            } header: {
                Text("HEADER")
            } footer: {
                Text("footer note")
            }, "Section")
        check(
            Section {
                Text("Body").frame(maxWidth: .infinity)
            } header: {
                Text("Flexible section")
            }, "Section(flexContent)")

        // — Behavioural decorators (now forward measurement to content) —
        check(Text("watched").onChange(of: 0) { }, "Text.onChange")
        check(Text("keyed").onKeyPress { _ in false }, "Text.onKeyPress")
        check(Text("dimmed").selectionDisabled(), "Text.selectionDisabled")
        check(Text("badged").badge(3), "Text.badge")
        check(VStack { Text("a"); Text("bb") }.focusSection("sec"), "VStack.focusSection")
        // Overlay sizes to max(base, overlay): base wider, then overlay wider.
        check(Text("wide base text").overlay { Text("o") }, "overlay(baseWider)")
        check(Text("b").overlay { Text("wide overlay text") }, "overlay(overlayWider)")
        // Optional view: .some forwards, .none is empty.
        check(Optional(Text("present")), "Optional(some)")
        check(Optional<Text>.none, "Optional(none)")
        // Flexibility must survive the decorator: a maxWidth frame behind onChange.
        check(Text("flex").frame(maxWidth: .infinity).onChange(of: 0) { }, "flexFrame.onChange")

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

    /// AnyView is now `Layoutable` and forwards measurement to the wrapped view,
    /// so its erased subtree measures structurally instead of via measureChild's
    /// render-to-measure fallback. This pins the forward — and would fail if AnyView
    /// reverted to the fallback, whose "+8" probe over-reports a wrapping Text as
    /// width-flexible where the wrapped view's own (canonical) measure does not.
    @Test("AnyView is Layoutable and forwards the wrapped view's measurement")
    func anyViewForwardsMeasurement() {
        #expect(AnyView(Text("hi")) is Layoutable, "AnyView conforms to Layoutable")

        let wrapping = Text("A fairly long line of text that wraps when the width is narrow")
        let proposal = ProposedSize(width: 20, height: nil)
        let direct = measureChild(wrapping, proposal: proposal, context: makeContext(width: 20, height: height))
        let erased = measureChild(AnyView(wrapping), proposal: proposal, context: makeContext(width: 20, height: height))

        #expect(erased.width == direct.width && erased.height == direct.height,
                "erased measure \(erased) matches the wrapped view's \(direct)")
        #expect(!direct.isWidthFlexible, "wrapping Text is fixed (contract)")
        #expect(erased.isWidthFlexible == direct.isWidthFlexible,
                "AnyView carries the wrapped view's flexibility (a fallback would over-report it flexible)")
    }

    /// Behavioural decorators (`onChange`, `onKeyPress`, `focusSection`,
    /// `selectionDisabled`, …) render their content unchanged and now forward
    /// measurement to it. A decorator that fell back to render-to-measure would
    /// report a *fixed* size (the fallback never claims flexible without the +8
    /// probe agreeing, and the probe under-reports), silently dropping the
    /// content's flexibility — which mis-drives a parent stack's width
    /// distribution. This pins that flexibility survives the decorator layer.
    @Test("Behavioural decorators forward the wrapped view's flexibility")
    func decoratorsForwardFlexibility() {
        func widthFlexible<V: View>(_ view: V) -> Bool {
            measureChild(
                view, proposal: ProposedSize(width: 40, height: nil),
                context: makeContext(width: 40, height: height)
            ).isWidthFlexible
        }

        let flex = Text("x").frame(maxWidth: .infinity)
        let fixed = Text("x")

        #expect(widthFlexible(flex.onChange(of: 0) { }), "onChange forwards flexible")
        #expect(!widthFlexible(fixed.onChange(of: 0) { }), "onChange forwards fixed")
        #expect(widthFlexible(flex.onKeyPress { _ in false }), "onKeyPress forwards flexible")
        #expect(widthFlexible(flex.selectionDisabled()), "selectionDisabled forwards flexible")
        #expect(widthFlexible(flex.focusSection("s")), "focusSection forwards flexible")
        #expect(widthFlexible(Optional(flex)), "Optional(.some) forwards flexible")
        #expect(!widthFlexible(Optional<Text>.none), "Optional(.none) is fixed (empty)")
    }

    /// Pins the canonical flexibility values from the ``ViewSize`` contract.
    ///
    /// The size-invariant test above asserts the *relationship* `flexible ⟹
    /// fills`, but a view whose content always fills the proposal (long wrapping
    /// `Text`) would satisfy that relationship even if it wrongly claimed
    /// `flexible`. This nails down the exact `isWidthFlexible` each canonical view
    /// must report, so the "wrapping is fixed, not flexible" decision can't drift.
    /// `sizeThatFits` is the canonical source (per the contract), so these read it
    /// via `measureChild`.
    @Test("Flexibility contract: canonical views report the contracted flag")
    func flexibilityContract() {
        func widthFlexible<V: View>(_ view: V, width: Int = 40) -> Bool {
            measureChild(
                view, proposal: ProposedSize(width: width, height: nil),
                context: makeContext(width: width, height: height)
            ).isWidthFlexible
        }

        // Fixed: render at a specific size, never grow past their ideal.
        #expect(!widthFlexible(Text("Hello")), "short Text is fixed")
        #expect(
            !widthFlexible(Text("A fairly long line of text that wraps when the width is narrow")),
            "wrapping Text is fixed — it reflows up to its ideal but does not fill unbounded space")
        #expect(!widthFlexible(Text("hi").frame(width: 20)), "frame(width:) is fixed")
        #expect(!widthFlexible(VStack { Text("a"); Text("bb") }), "VStack of fixed children is fixed")

        // Flexible: fill the offered width past their ideal.
        #expect(widthFlexible(Text("hi").frame(maxWidth: .infinity)), "frame(maxWidth:.infinity) is flexible")
        #expect(
            widthFlexible(VStack { Text("x").frame(maxWidth: .infinity) }),
            "VStack with a flexible child is flexible")
    }
}
