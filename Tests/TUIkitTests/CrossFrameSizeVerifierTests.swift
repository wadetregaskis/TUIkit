//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CrossFrameSizeVerifierTests.swift
//
//  Every size the render cache keeps ACROSS frames is a claim that nothing it
//  was measured from has moved, and `TUIKIT_VERIFY_MEASURE_MEMO` is how that
//  claim is checked: the size is measured again, a disagreement is reported,
//  and the fresh size is the one laid out. The value memo's sizes were checked;
//  the two containers that keep a size of their own in the same table — a
//  hugging `List`'s widest row and a `Table`'s `.fit` column — were not, so a
//  stale one could be caught only by the pixels it happened to move.
//
//  Each test plants the lie those two memos cannot see, the captured-data hole
//  they document: a row closure reading something that is not its row. The
//  data compares equal, the text does not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What the row closures read that is not their row.
private final class Prefix: @unchecked Sendable {
    var text = "a"
}

private struct Item: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
}

private let items = (0..<4).map { Item(id: $0, name: "row\($0)") }

/// Frames of the real loop's lifecycle over one render cache.
@MainActor
private final class SizeLoop {
    let tui = TUIContext()
    /// One manager for every frame, as an app has: a new one each frame would
    /// focus the control afresh every frame, and a focus move clears it.
    let focus = FocusManager()

    func frame(_ view: some View) -> [String] {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        environment.focusManager = focus
        let context = RenderContext(
            availableWidth: 60, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map(\.stripped)
    }
}

@MainActor
@Suite("The measure verifier checks every size kept across frames", .serialized)
struct CrossFrameSizeVerifierTests {
    /// A hugging list beside a bar: the bar lands where the hug ends.
    private func huggedList(_ prefix: Prefix) -> some View {
        HStack(spacing: 0) {
            List(items) { item in Text(verbatim: prefix.text + item.name) }
                .fixedSize(horizontal: true)
            Text("|")
        }
    }

    /// A table whose first column fits its cells, which read the prefix; the
    /// second column's header lands where the first column ends.
    private func fittedTable(_ prefix: Prefix) -> some View {
        Table(items, selection: Binding<Int?>.constant(nil)) {
            TableColumn("Name") { (item: Item) -> String in prefix.text + item.name }
                .width(.fit)
            TableColumn("ID") { (item: Item) in "\(item.id)" }
        }
    }

    /// Where `needle` first appears in any line of `lines`.
    private func column(of needle: Character, in lines: [String]) -> Int? {
        for line in lines {
            if let index = line.firstIndex(of: needle) { return line.distance(from: line.startIndex, to: index) }
        }
        return nil
    }

    /// Settles `view` over a short prefix, lengthens the prefix without
    /// changing the data, and draws once more. Returns that frame and what the
    /// measure verifier reported, verifying or not.
    private func afterTheLie(
        verifying: Bool, _ view: (Prefix) -> some View
    ) -> (lines: [String], reports: [String]) {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        RenderCache.verifiesMeasureMemo = verifying
        let prefix = Prefix()
        let loop = SizeLoop()
        // Three, not two: the control builds its own `@State` on the first
        // frame, which clears its subtree on the second.
        for _ in 0..<3 { _ = loop.frame(view(prefix)) }
        prefix.text = "a much longer "
        let lines = loop.frame(view(prefix))
        return (lines, loop.tui.renderCache.measureMemoMismatches)
    }

    /// What a frame with nothing kept draws for the long prefix.
    private func cold(_ view: (Prefix) -> some View) -> [String] {
        let prefix = Prefix()
        prefix.text = "a much longer "
        return SizeLoop().frame(view(prefix))
    }

    @Test("A hugging list's widest row served stale is reported, and the fresh width is laid out")
    func listHugIsVerified() {
        let fresh = column(of: "|", in: cold(huggedList))
        let served = afterTheLie(verifying: false, huggedList)
        #expect(
            column(of: "|", in: served.lines) != fresh,
            "precondition: without the verifier the stale hug is laid out, or this proves nothing")
        let verified = afterTheLie(verifying: true, huggedList)
        #expect(
            verified.reports.contains { $0.contains("widest row") && $0.contains("(cross-frame)") },
            "the stale hug went unreported: \(verified.reports)")
        #expect(column(of: "|", in: verified.lines) == fresh, "laid out at the stale hug: \(verified.lines)")
    }

    @Test("A table's .fit column width served stale is reported, and the fresh width is laid out")
    func tableFitIsVerified() {
        let fresh = column(of: "I", in: cold(fittedTable))
        let served = afterTheLie(verifying: false, fittedTable)
        #expect(
            column(of: "I", in: served.lines) != fresh,
            "precondition: without the verifier the stale fit is laid out, or this proves nothing")
        let verified = afterTheLie(verifying: true, fittedTable)
        #expect(
            verified.reports.contains { $0.contains("fit width") && $0.contains("(cross-frame)") },
            "the stale fit went unreported: \(verified.reports)")
        #expect(column(of: "I", in: verified.lines) == fresh, "laid out at the stale fit: \(verified.lines)")
    }

    /// A hugging list whose rows each hold a list of their own. The inner list
    /// reads `fixedSizeWidth`, which the outer one clears for its rows before
    /// it extracts them — so a check that re-extracts them without clearing it
    /// measures rows no frame ever drew, and reports a width nothing served.
    private func huggedListOfLists() -> some View {
        HStack(spacing: 0) {
            List(items) { item in
                List([item]) { inner in Text(verbatim: inner.name) }
                    .frame(height: 3)
            }
            .fixedSize(horizontal: true)
            Text("|")
        }
    }

    /// Nothing moves between the frames here, so a report is a false one: the
    /// render path's check re-extracted the rows under the list's own context,
    /// where `fixedSizeWidth` is still set, and the inner lists hugged.
    @Test("A hugging list's check measures its rows as the list does, and reports nothing when nothing moved")
    func listHugCheckMeasuresRowsAsTheListDoes() {
        let was = RenderCache.verifiesMeasureMemo
        defer { RenderCache.verifiesMeasureMemo = was }
        RenderCache.verifiesMeasureMemo = true
        let loop = SizeLoop()
        for _ in 0..<4 { _ = loop.frame(huggedListOfLists()) }
        #expect(loop.tui.renderCache.measureMemoMismatches.isEmpty, "\(loop.tui.renderCache.measureMemoMismatches)")
    }
}
