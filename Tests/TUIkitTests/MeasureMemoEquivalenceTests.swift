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
        // Both halves, deliberately — this is NOT a redundant second write.
        // `RenderContext` mirrors the environment's state storage in a stored
        // field, and an in-place environment write no longer re-derives it (see
        // `RenderContext.environment`). Setting only the environment would
        // leave `@State` binding into the harness's storage while this suite
        // believed it had an isolated one. Same shape, and the same reason, as
        // `RenderContext.isolatingRenderCache()` in `RenderTestSupport.swift`.
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        if memoised {
            // The installer, not a bare assignment: the gate reads the tracker
            // off the render cache, so this is what turns the memo on now.
            context.environment.installVolatileReadTracker(VolatileReadTracker())
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
        // Restored to what it WAS, not to `false`. Under
        // `TUIKIT_VERIFY_MEASURE_MEMO=1` the flag starts true for the whole
        // process and every suite's memo hits are checked against a fresh
        // measurement; a `defer` that put it back to `false` disarmed that for
        // everything scheduled after this suite, in the one mode whose entire
        // purpose is to be armed. The `Stress` and PTY verifier runs are
        // separate processes and were never affected, which is why it went
        // unnoticed.
        let wasVerifying = RenderCache.verifiesMeasureMemo
        RenderCache.verifiesMeasureMemo = true
        defer { RenderCache.verifiesMeasureMemo = wasVerifying }
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

    /// A menu whose rows reflow past its cap: the shape the FIRST attempt at the
    /// reflow fix got wrong, and the reason there is a menu in this corpus at
    /// all. A menu measures its rows twice at one identity — hugging, to learn
    /// its width, and again at that width, because a row drawn into the interior
    /// less its hint column can wrap where the hug did not — and on the clamped
    /// arm those two asks are at the SAME width.
    ///
    /// What it can and cannot claim, said out loud because the case it guards
    /// against is a test that passed while the bug was present. This is a
    /// PROBABILISTIC guard, not a proof: the value hash reads a closure's words
    /// as they are, and a menu row's `ButtonStyleConfiguration` carries
    /// closures, so its hash includes freshly-allocated pointers. Run against the reverted
    /// commit with `measureChild` instrumented, this exact fixture's rows MISSED
    /// on every pass, so the collision never arose and this case passed — while
    /// the same code on the live Example collided forty times in one walk. It
    /// earns its place by putting a menu in the corpus at all (there was none),
    /// and it will catch a collision on any run where the allocator hands back
    /// the same addresses. The deterministic half of the claim is
    /// `MenuRowMeasureKeyingTests`; the reliable end-to-end check is
    /// `TUIKIT_VERIFY_MEASURE_MEMO` over a PTY walk of a real app.
    ///
    /// Width 26 is the band: narrower and the labels wrap during the hug too,
    /// so both asks agree and there is nothing to get wrong; wider and nothing
    /// wraps at all.
    @Test("an inline menu that reflows past its cap draws the same either way")
    func inlineMenuReflow() {
        let menu = Menu {
            ForEach(0..<6, id: \.self) { index in
                Button("Delete Everything \(index)") {}
                    .keyboardShortcut(KeyEquivalent("\u{7F}"))
            }
        } label: {
            Text("Edit")
        }
        .menuStyle(.inline)

        let (memoised, plain, hits) = bothWays(menu, width: 26, height: 12)
        #expect(
            memoised == plain,
            """
            the memoised menu differs from the un-memoised one — the hug's size \
            was served to the reflow.
            \(snapshotDiff(golden: plain, actual: memoised))
            """)
        #expect(hits > 0, "the memo never engaged here, so this case proves nothing")
        // The fixture has to still be IN the band, or it is a menu that fits
        // and the collision it guards cannot arise.
        #expect(
            plain.contains("▲") || plain.contains("▼"),
            "the fixture stopped overflowing its cap, so it is no longer the reflow band:\n\(plain)")
    }

    /// The other half of the harness's own guard: it must leave the
    /// verification mode as it found it."""
    ///
    /// `bothWays` arms `verifiesMeasureMemo` for the duration of a case, and
    /// used to disarm it unconditionally afterwards. Under
    /// `TUIKIT_VERIFY_MEASURE_MEMO=1` — where the whole unit suite is supposed
    /// to check every hit — that turned the mode off for every suite scheduled
    /// after this one, silently, in the run whose only purpose is to have it on.
    ///
    /// Asserted from inside the suite rather than by a sibling that reads the
    /// flag: nothing orders two suites, so a sibling would catch this only on
    /// the runs where the scheduler happened to put it second.
    @Test("the harness restores the verification mode it found")
    func restoresVerificationMode() {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        RenderCache.verifiesMeasureMemo = true
        agrees("restore-probe", Text("hi"), width: 8, height: 1)
        #expect(
            RenderCache.verifiesMeasureMemo,
            "the harness left verification OFF, disarming every suite that runs after it")
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

    /// The CROSS-frame size memo's serves are checked too. They were returned
    /// unchecked, so a size that outlived what it measured showed up only if
    /// it happened to move a pixel. A card that compares by title alone is the
    /// lie that memo cannot see: a longer body under the same title.
    @Test("A size the cross-frame memo serves stale is reported")
    func crossFrameSizeServesAreVerified() {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        RenderCache.verifiesMeasureMemo = true
        let tui = TUIContext()
        func frame(_ body: String) {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tui)
            environment.installVolatileReadTracker(VolatileReadTracker())
            let context = RenderContext(
                availableWidth: 30, availableHeight: 4, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(HStack { TitledCard(title: "t", text: body).equatable(); Text("|") }, context: context)
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
        frame("short")
        frame("short")
        #expect(tui.renderCache.measureMemoMismatches.isEmpty, "an honest serve was reported")
        frame("a much longer body")
        #expect(
            tui.renderCache.measureMemoMismatches.contains { $0.contains("(cross-frame)") },
            "the stale serve went unreported: \(tui.renderCache.measureMemoMismatches)")
    }
}

/// A card that compares by title alone.
private struct TitledCard: View, @preconcurrency Equatable {
    let title: String
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View { Text(verbatim: text) }
}
