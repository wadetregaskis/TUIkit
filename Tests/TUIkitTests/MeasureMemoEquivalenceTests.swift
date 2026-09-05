//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeasureMemoEquivalenceTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// The guard on the per-pass measure memo: a frame drawn with it must be
/// byte-for-byte the frame drawn without it.
///
/// The memo answers a `measureChild` from an earlier measurement in the same
/// pass, and since the sizes it stores may be ``ViewSize/isNaturalSize`` it can
/// answer a query made under one vertical budget from a measurement taken under
/// another. That is a claim about every `sizeThatFits` in the subtree, and the
/// only honest way to hold it is to draw the same tree both ways and diff the
/// pixels.
///
/// It has to be said explicitly that the rest of the suite does NOT do this. The
/// memo only engages when a `VolatileReadTracker` is installed — the render loop
/// always installs one, and the gate keeps the memo off standalone measurement
/// paths — and no other test helper installs one, so in every other suite the
/// memo is inert and would pass whether it was sound or not. Hence the
/// ``memoEngages()`` case below: a harness that silently stopped exercising the
/// thing it guards is the failure mode this file exists to avoid.
@MainActor
@Suite("Measure memo equivalence")
struct MeasureMemoEquivalenceTests {

    /// A context shaped like the render loop's: an isolated cache, and the
    /// volatile-read tracker whose presence is what turns the memo on.
    private func context(width: Int, height: Int, memoised: Bool) -> RenderContext {
        var context = makeRenderContext(width: width, height: height)
        context.environment.stateStorage = StateStorage()
        if memoised {
            context.environment.volatileReadTracker = VolatileReadTracker()
        }
        return context
    }

    /// Draws `view` twice — memo live, memo off — and returns both pictures and
    /// how many measurements the memo served.
    private func bothWays(
        _ view: some View, width: Int, height: Int
    ) -> (memoised: String, plain: String, hits: Int) {
        // Every hit checked against a fresh measurement, as well as compared at
        // the pixels below: a wrong size only redraws the screen when it reaches
        // something that draws differently for it, so the picture alone would
        // let a real one through.
        RenderCache.verifiesMeasureMemo = true
        defer { RenderCache.verifiesMeasureMemo = false }
        let memoContext = context(width: width, height: height, memoised: true)
        memoContext.renderCache?.beginRenderPass()
        let memoised = snapshotText(renderToScreen(view, context: memoContext))
        let hits = memoContext.renderCache?.measureMemoTotals.hits ?? 0
        let mismatches = memoContext.renderCache?.measureMemoMismatches ?? []
        let mismatchReport = mismatches.joined(separator: "\n")
        #expect(
            mismatches.isEmpty,
            "the memo served a size a fresh measurement disagrees with:\n\(mismatchReport)")

        let plainContext = context(width: width, height: height, memoised: false)
        plainContext.renderCache?.beginRenderPass()
        let plain = snapshotText(renderToScreen(view, context: plainContext))
        return (memoised, plain, hits)
    }

    /// Asserts the two pictures agree, and reports the hits so the caller can
    /// check the memo was awake.
    @discardableResult
    private func agrees(
        _ label: String, width: Int, height: Int, of view: some View
    ) -> Int {
        agrees(label, view, width: width, height: height)
    }

    @discardableResult
    private func agrees(
        _ label: String, _ view: some View, width: Int, height: Int
    ) -> Int {
        let (memoised, plain, hits) = bothWays(view, width: width, height: height)
        #expect(
            memoised == plain,
            """
            \(label): the memoised frame differs from the un-memoised one — a size \
            was served that a fresh measurement would not have produced.
            \(snapshotDiff(golden: plain, actual: memoised))
            """)
        return hits
    }

    // MARK: - The corpus

    /// The shape the memo exists for: a ScrollView's content is walked twice per
    /// frame — the enclosing column's natural-size ask, then the content-extent
    /// walk — at the same width and two different vertical budgets.
    @Test("a scrolled column draws the same with the memo as without")
    func scrolledColumn() {
        agrees(
            "scrollview-rows", width: 40, height: 10,
            of: VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<24) { i in
                            HStack { Text("row \(i)"); Spacer(); Text("\(i * 3)") }
                        }
                    }
                }
                Text("footer")
            })
    }

    @Test("a lazy column inside a scroll view draws the same either way")
    func lazyColumn() {
        agrees(
            "lazy-rows", width: 32, height: 8,
            of: ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<40) { i in Text("line \(i)\nwrapped \(i)") }
                }
            })
    }

    /// The clamp case: a column whose content is taller than the space it is
    /// offered reports the budget's answer, not its own, and must not answer for
    /// a different budget.
    @Test("a column clamped by a short budget draws the same either way")
    func clampedColumn() {
        for height in [1, 2, 3, 5, 9] {
            agrees(
                "clamped-\(height)", width: 20, height: height,
                of: VStack(spacing: 0) {
                    VStack(spacing: 0) { ForEach(0..<8) { i in Text("r\(i)") } }
                    Text("tail")
                })
        }
    }

    /// Padding's inset is not a constant at every budget — it gives the last cell
    /// to its content — so a padded view measured in a one-row budget must not
    /// answer for a taller one.
    @Test("padded content draws the same either way, at every budget")
    func paddedContent() {
        for height in [1, 2, 3, 4, 8] {
            agrees(
                "padded-\(height)", width: 24, height: height,
                of: VStack(spacing: 0) {
                    Text("hi").padding(1).border()
                    Text("under")
                })
        }
    }

    /// A frame that fills its height reads the budget; a column above it must not
    /// serve one budget's answer to another.
    @Test("flexible frames draw the same either way")
    func flexibleFrames() {
        for height in [2, 4, 12] {
            agrees(
                "flexframe-\(height)", width: 20, height: height,
                of: VStack(spacing: 0) {
                    Text("top").frame(maxHeight: .infinity)
                    Text("bottom")
                })
        }
    }

    /// `ViewThatFits` picks its candidate from the space available, in both axes.
    @Test("ViewThatFits draws the same either way")
    func viewThatFits() {
        let fits = ViewThatFits {
            VStack(spacing: 0) { Text("Alpha"); Text("Beta"); Text("Gamma") }
            Text("Alpha Beta Gamma")
        }
        for height in [1, 2, 3, 6] {
            agrees("viewthatfits-\(height)", fits, width: 24, height: height)
        }
    }

    /// Chrome that reserves rows for a header and a footer, with a body that
    /// saturates — the container reads the budget to decide what it can keep.
    @Test("bordered containers draw the same either way")
    func containers() {
        for height in [3, 6, 12] {
            agrees(
                "dialog-\(height)", width: 30, height: height,
                of: Dialog(title: "Title", footerAlignment: .center) {
                    VStack(spacing: 0) { ForEach(0..<6) { i in Text("body \(i)") } }
                } footer: {
                    Button("OK") {}
                })
        }
    }

    /// Rows behind the row memo, which answers from a store that outlives the
    /// pass: whatever it hands back has to draw the same too.
    @Test("memoized rows draw the same either way")
    func memoizedRows() {
        agrees(
            "list-rows", width: 36, height: 9,
            of: List {
                ForEach(0..<20) { i in
                    HStack { Text("item \(i)"); Spacer(); Text(i.isMultiple(of: 2) ? "on" : "off") }
                }
            })
    }

    /// Wrapping text is the one leaf whose height depends on the width it is
    /// given, and the memo keys on width — so this is the case that would break
    /// first if the key lost a width.
    @Test("wrapped text draws the same either way, at every width")
    func wrappedText() {
        let paragraph = String(repeating: "lorem ipsum dolor ", count: 6)
        for width in [12, 19, 40] {
            agrees(
                "wrapped-\(width)", width: width, height: 8,
                of: ScrollView { VStack(alignment: .leading, spacing: 0) { Text(paragraph); Text("end") } })
        }
    }

    /// The golden corpus's own shapes, drawn both ways. Cheap to keep in step:
    /// what is worth snapshotting is worth checking the memo against.
    @Test("the snapshot corpus draws the same either way")
    func snapshotCorpus() {
        agrees("text-multiline", Text("Hello\nTUIkit world"), width: 20, height: 3)
        agrees(
            "hstack-spacer", HStack { Text("L"); Spacer(); Text("R") }, width: 20, height: 1)
        agrees(
            "hstack-valign-bottom",
            HStack(alignment: .bottom, spacing: 1) { Text("a\nb\nc"); Text("x") },
            width: 12, height: 3)
        agrees("frame-fixed", Text("hi").frame(width: 10, height: 3), width: 16, height: 3)
        agrees(
            "divider", VStack(spacing: 0) { Text("top"); Divider(); Text("bottom") },
            width: 12, height: 3)
        agrees(
            "tabview-bordered",
            TabView(selection: .constant(1)) {
                ForEach(0..<6) { i in Tab("Tab \(i)", value: i) { Text("Content \(i)") } }
            }.tabViewStyle(.bordered),
            width: 30, height: 9)
        agrees(
            "colorpicker-rgb",
            ColorPickerPanel("Accent", selection: .constant(.rgb(80, 160, 255)), isPresented: .constant(true)),
            width: 64, height: 30)
    }

    /// The harness's own guard: if the memo stops engaging, every case above
    /// passes for the wrong reason.
    @Test("the memo actually engages in this harness")
    func memoEngages() {
        let hits = agrees(
            "engagement", width: 40, height: 10,
            of: VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<24) { i in HStack { Text("row \(i)"); Spacer(); Text("\(i)") } }
                    }
                }
                Text("footer")
            })
        #expect(
            hits > 0,
            """
            the measure memo served nothing in this harness, so every equivalence \
            case above compared a frame with itself. Check that the context still \
            installs a VolatileReadTracker and that measureChild still consults \
            the cache.
            """)
    }
}
