//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarFirstRoundTests.swift
//
//  An automatic vertical scrollbar is decided in rounds: the content is measured
//  at the full width, and when it overflows, again a column narrower, where the
//  bar leaves it and the render draws it. The first round only has to learn
//  WHETHER the content overflows, and asked over the whole natural-extent
//  ladder it climbed that ladder at a width nothing is drawn at. These count
//  what the frame after a write costs — on the shape the shortcut is for, and
//  on the ones it must leave alone — and pin that it answers whether the
//  content overflows as the ladder would.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Counts the measures its rows answer; a size the memo serves is not one.
/// `@unchecked`: driven on the main actor.
private final class RowMeasures: @unchecked Sendable {
    var count = 0
}

/// A one-line row that counts its own measures. It claims no natural size —
/// nor do padded, bordered or framed content, a button or a custom layout — so
/// the pass's measure memo serves it only to an ask at the budget it answered.
/// One that `readsViewport` reads the scroll view's viewport as it measures,
/// as an image fitted to the viewport does, and the memo keeps none of what
/// depended on that read.
private struct CountedRow: View, Layoutable {
    let text: String
    let measures: RowMeasures
    var readsViewport = false
    var body: Never { fatalError("CountedRow renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measures.count += 1
        if readsViewport { _ = context.environment.scrollViewportSize }
        return ViewSize.fixed(text.count, 1)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: [text])
    }
}

/// What a page's scroll view holds.
enum ScrollbarRoundShape: Sendable, CustomStringConvertible {
    /// A lazy stack, the scroll view's direct content, of rows one and two
    /// lines tall by turns — past the windowing threshold, so its measure is
    /// the anchored estimate.
    case lazy(rows: Int)
    /// An eager column of counted rows.
    case counted(rows: Int)
    /// An eager column of counted rows that read the viewport.
    case viewportReading(rows: Int)
    /// A scroll view of counted rows inside another scroll view's content,
    /// between two lines: asked its ideal height, it is drawn at all of it, so
    /// its content fits it — however many rows it has. The outer view's own bar
    /// is hidden.
    case nested(rows: Int)
    /// An eager column of `from` rows that the write above cuts to `to`: on
    /// the frame after it, content that overflowed at the scroll view's last
    /// render and fits now.
    case shrinking(from: Int, to: Int)

    var description: String {
        switch self {
        case .lazy(let rows): "a lazy stack of \(rows) rows"
        case .counted(let rows): "an eager column of \(rows) rows"
        case .viewportReading(let rows): "an eager column of \(rows) rows that read the viewport"
        case .nested(let rows): "a scroll view of \(rows) rows drawn whole in another"
        case .shrinking(let from, let to): "an eager column of \(from) rows cut to \(to)"
        }
    }
}

private struct RoundsApp: App {
    let shape: ScrollbarRoundShape
    let indicators: ScrollIndicatorVisibility
    let measures: RowMeasures

    init() { self.init(shape: .counted(rows: 1), indicators: .automatic, measures: RowMeasures()) }
    init(shape: ScrollbarRoundShape, indicators: ScrollIndicatorVisibility, measures: RowMeasures) {
        self.shape = shape
        self.indicators = indicators
        self.measures = measures
    }

    var body: some Scene {
        WindowGroup { RoundsPage(shape: shape, indicators: indicators, measures: measures) }
    }
}

/// A line over the scroll view that `t` rewrites: a `@State` write above it,
/// so no memo beneath it survives into the next frame — the frame a live app
/// pays on every write.
private struct RoundsPage: View {
    let shape: ScrollbarRoundShape
    let indicators: ScrollIndicatorVisibility
    let measures: RowMeasures
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tick \(tick)")
            content
        }
        .onKeyPress(.character("t")) { tick += 1 }
    }

    @ViewBuilder private var content: some View {
        switch shape {
        case .lazy(let rows):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { index in
                        Text(index.isMultiple(of: 2) ? "row \(index)" : "row \(index)\nsecond line")
                    }
                }
            }
            .scrollIndicators(indicators)
        case .counted(let rows):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { CountedRow(text: "row \($0)", measures: measures) }
                }
            }
            .scrollIndicators(indicators)
        case .viewportReading(let rows):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) {
                        CountedRow(text: "row \($0)", measures: measures, readsViewport: true)
                    }
                }
            }
            .scrollIndicators(indicators)
        case .nested(let rows):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("above")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<rows, id: \.self) { CountedRow(text: "row \($0)", measures: measures) }
                        }
                    }
                    .scrollIndicators(indicators)
                    Text("below")
                }
            }
            // The outer view draws no bar, so the only one on the screen can
            // be the inner view's, and decides none, so both twins pay alike.
            .scrollIndicators(.hidden)
        case .shrinking(let from, let to):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<(tick == 0 ? from : to), id: \.self) { Text("row \($0)") }
                }
            }
            .scrollIndicators(indicators)
        }
    }
}

@MainActor
@Suite("The scrollbar's first round asks only whether the content overflows")
struct ScrollbarFirstRoundTests {
    private static let frame: Int64 = 16_666_667

    /// What the frame after a write above the scroll view costs, and what it
    /// shows — and what the frame before it showed. Two frames first, so
    /// nothing here depends on an opening frame.
    private func writeFrame(
        _ shape: ScrollbarRoundShape, indicators: ScrollIndicatorVisibility
    ) -> (lookups: Int, rowMeasures: Int, screen: [String], screenBefore: [String], split: String) {
        let measures = RowMeasures()
        let app = HeadlessApp(
            RoundsApp(shape: shape, indicators: indicators, measures: measures), width: 40, height: 20)
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.frame)
        let screenBefore = app.screen.map(\.stripped)
        let lookupsBefore = app.renderCache.measureMemoTotals
        let measuresBefore = measures.count
        app.send(KeyEvent(key: .character("t")))
        app.frame(atNanos: 2 * Self.frame)
        let lookupsAfter = app.renderCache.measureMemoTotals
        return (
            lookups: lookupsAfter.hits + lookupsAfter.misses - lookupsBefore.hits - lookupsBefore.misses,
            rowMeasures: measures.count - measuresBefore,
            screen: app.screen.map(\.stripped),
            screenBefore: screenBefore,
            split: "\(lookupsAfter.hits - lookupsBefore.hits) hits, "
                + "\(lookupsAfter.misses - lookupsBefore.misses) misses, "
                + "\(measures.count - measuresBefore) rows measured")
    }

    private func drawsBar(_ screen: [String]) -> Bool {
        screen.contains { $0.contains("▲") || $0.contains("▼") }
    }

    /// The shape the shortcut is for. A lazy stack past the windowing threshold
    /// answers from a sample of its rows and reports the budget whenever its
    /// estimate runs past it, so the ladder climbs by eight from 4,096 lines
    /// until its budget clears the estimate: two rungs for 10,000 rows of one
    /// and two lines, three for 100,000, each one the sample asked again.
    /// Climbed at the full width in the scrollbar's first round, the frame's
    /// cost grew with the row count though nothing drawn did.
    ///
    /// What deciding the bar costs is the frame against its twin with the bar
    /// hidden, which decides nothing and measures the content once, where it
    /// draws it. Measure-memo lookups, the frame after a write: 70 against 52
    /// with the ladder climbed in the first round (the difference one rung,
    /// 18 lookups), 34 against 34 with the first round stopped at its first
    /// rung.
    @Test("Deciding the bar over a lazy stack costs the same at 100,000 rows as at 10,000")
    func barCostDoesNotGrowWithTheRows() {
        // Linux reported costs from 27 to 39, differing between the two row
        // counts and from run to run, where macOS reports equal ones; nothing
        // on macOS reproduces it. The split says which side moved.
        var splits: [String] = []
        func barCost(rows: Int) -> Int {
            let decided = writeFrame(.lazy(rows: rows), indicators: .automatic)
            let hidden = writeFrame(.lazy(rows: rows), indicators: .hidden)
            #expect(drawsBar(decided.screen), "precondition: \(rows) rows draw the bar: \(decided.screen)")
            #expect(!drawsBar(hidden.screen), "precondition: the twin draws none: \(hidden.screen)")
            splits.append("\(rows) rows — decided: \(decided.split); hidden: \(hidden.split)")
            return decided.lookups - hidden.lookups
        }
        let tenThousand = barCost(rows: 10_000)
        let hundredThousand = barCost(rows: 100_000)
        #expect(
            hundredThousand == tenThousand,
            """
            deciding the bar cost \(hundredThousand) lookups over 100,000 rows, \(tenThousand) over 10,000
            \(splits.joined(separator: "\n"))
            """)
    }

    /// The shapes the shortcut must leave alone. For content that fits, "does
    /// it overflow?" is the ladder's first rung asked twice, and the second
    /// ask is served the first only where the pass's memo keeps it. Rows that
    /// read the viewport are never kept, and asked on every frame they were
    /// measured once more a frame (20 row measures against 15), so the question
    /// is asked only of content that overflowed at the scroll view's last
    /// render. The other two are kept but claim no natural size: asked on every
    /// frame and one line past the viewport instead of at the first rung, where
    /// no answer could be served across the two budgets, a column of them cost
    /// the same 20 against 15, and a scroll view of them drawn whole inside
    /// another 2,400 against 2,000.
    @Test(
        "Content that fits is measured no more often with an automatic scrollbar than with none",
        arguments: [ScrollbarRoundShape.counted(rows: 5), .viewportReading(rows: 5), .nested(rows: 400)])
    func fittingContentPaysNothing(shape: ScrollbarRoundShape) {
        let decided = writeFrame(shape, indicators: .automatic)
        let hidden = writeFrame(shape, indicators: .hidden)
        #expect(!drawsBar(decided.screen), "precondition: \(shape) fits: \(decided.screen)")
        #expect(
            decided.rowMeasures == hidden.rowMeasures,
            "\(shape): \(decided.rowMeasures) row measures with the bar decided, \(hidden.rowMeasures) without")
    }

    /// An eager column measures every row whatever its budget, so the shortcut
    /// saves it nothing — and must cost it nothing either: deciding the bar is
    /// one measure of each row, the first round's, at the width the bar then
    /// narrows. Asked at a budget of its own and then climbed anyway, it would
    /// be two: rows that claim no natural size are served only to the budget
    /// they answered.
    @Test("An eager column that overflows is measured once more to decide the bar, not twice")
    func eagerColumnPaysOneRound() {
        let rows = 400
        let decided = writeFrame(.counted(rows: rows), indicators: .automatic)
        let hidden = writeFrame(.counted(rows: rows), indicators: .hidden)
        #expect(drawsBar(decided.screen), "precondition: \(rows) rows draw the bar: \(decided.screen)")
        #expect(
            decided.rowMeasures - hidden.rowMeasures == rows,
            "\(decided.rowMeasures) row measures with the bar decided, \(hidden.rowMeasures) without")
    }

    /// The content's height as last recorded picks which question the first
    /// round asks first, and never the answer. Content that overflowed and fits
    /// now is asked whether it overflows, says no, and is measured over the
    /// ladder as before — so the bar goes on the frame the content shrank,
    /// not a frame later. A round that took the old height for the answer
    /// would reserve a bar, and a column, for content that fits.
    @Test("Content that overflowed and fits now loses its bar on the frame it shrank")
    func shrunkContentDropsTheBarAtOnce() {
        let shrunk = writeFrame(.shrinking(from: 30, to: 5), indicators: .automatic)
        #expect(drawsBar(shrunk.screenBefore), "precondition: thirty rows draw the bar: \(shrunk.screenBefore)")
        #expect(shrunk.screen.contains { $0.hasPrefix("row 4") }, "the five rows are drawn: \(shrunk.screen)")
        #expect(!drawsBar(shrunk.screen), "the frame the rows were cut to five draws no bar: \(shrunk.screen)")
    }
}

// MARK: - The assumption

/// Where the shortcut and the ladder disagree on whether `content` overflows,
/// among the viewport heights given — each asked in a context of its own, so
/// that neither is served the other's answer. The content is laid out
/// `contentWidth` wide, as the scrollbar's round asks it, in a context that
/// offers `availableWidth`. With `oneLinePast`, the shortcut is asked one line
/// past the viewport, and only its yeses are held to the ladder: a no there is
/// never trusted, and the round measures the ladder after it.
@MainActor
private func disagreements(
    _ name: String, _ content: some View, heights: [Int], contentWidth: Int, availableWidth: Int,
    oneLinePast: Bool = false
) -> [String] {
    func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = StateStorage()
        return RenderContext(
            availableWidth: availableWidth, availableHeight: 20, environment: environment,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }
    let core = _ScrollViewCore(axes: .vertical, content: content, explicitFocusID: nil, isDisabled: false)
    var found: [String] = []
    for height in heights {
        let shortcut = core.contentOverflowsCanvas(
            contentWidth: contentWidth, viewportHeight: height, oneLinePast: oneLinePast, context: context())
        let ladder =
            core.contentExtents(
                contentWidth: contentWidth, viewportHeight: height, horizontal: false, context: context()
            ).height > height
        if oneLinePast ? shortcut && !ladder : shortcut != ladder {
            found.append("\(name) at \(height): the shortcut said \(shortcut), the ladder \(ladder)")
        }
    }
    return found
}

/// ``disagreements(_:_:heights:contentWidth:availableWidth:)`` for every content
/// the agreement tests hold the shortcut to: rows, a padded and bordered
/// column, lazy stacks direct, under a header and in the rows of an outer one,
/// a wrapped paragraph alone and beside a mark in a row, a spacer, a filling
/// frame, a colour, a nested scroll view, a list, a geometry reader, and
/// content that picks its layout by the height it is offered.
@MainActor
private func disagreementsOverEveryContent(
    heights: [Int], contentWidth: Int, availableWidth: Int, oneLinePast: Bool = false
) -> [String] {
    func ask(_ name: String, _ content: some View) -> [String] {
        disagreements(
            name, content, heights: heights, contentWidth: contentWidth, availableWidth: availableWidth,
            oneLinePast: oneLinePast)
    }
    var found: [String] = []
    found += ask(
        "ten rows",
        VStack(alignment: .leading, spacing: 0) { ForEach(0..<10, id: \.self) { Text("row \($0)") } })
    found += ask(
        "twenty-six rows, padded and bordered to thirty lines",
        VStack(alignment: .leading, spacing: 0) { ForEach(0..<26, id: \.self) { Text("row \($0)") } }
            .padding(1).border())
    found += ask(
        "a lazy stack of 300 rows of one and two lines",
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<300, id: \.self) { Text($0.isMultiple(of: 2) ? "row \($0)" : "row \($0)\nmore") }
        })
    found += ask(
        "a lazy stack of 20 rows",
        LazyVStack(alignment: .leading, spacing: 0) { ForEach(0..<20, id: \.self) { Text("row \($0)") } })
    found += ask(
        "a lazy stack of 300 rows under a header",
        VStack(alignment: .leading, spacing: 0) {
            Text("header")
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<300, id: \.self) { Text($0 < 16 ? "row \($0)" : "row \($0)\nmore") }
            }
        })
    found += ask(
        "three groups, each a header over a lazy stack of 300 rows, in an outer lazy stack",
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text("group \(group)")
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<300, id: \.self) { Text("g\(group) r\($0)") }
                    }
                }
            }
        })
    found += ask("a wrapped paragraph", Text(String(repeating: "words that wrap ", count: 18)))
    // Of all these, the one whose height moves with the width its context
    // offers while the width it is proposed stays put: at a viewport no column
    // wide, a canvas that did not state its width answered differently for
    // this content and for no other in this list. So it is what says which
    // width the shortcut's canvas stated.
    found += ask(
        "a wrapped paragraph beside a mark, in a row",
        HStack {
            Text(String(repeating: "words that wrap ", count: 18))
            Text("x")
        })
    found += ask(
        "a spacer between two lines",
        VStack(spacing: 0) {
            Text("top")
            Spacer()
            Text("bottom")
        })
    found += ask("a line in a frame that fills its height", Text("x").frame(maxHeight: .infinity))
    found += ask("a colour", Color.red)
    found += ask(
        "a scroll view of fifty rows",
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { ForEach(0..<50, id: \.self) { Text("row \($0)") } }
        })
    found += ask("a list of twenty rows", List { ForEach(0..<20, id: \.self) { Text("row \($0)") } })
    found += ask("a geometry reader", GeometryReader { _ in Text("geometry") })
    found += ask(
        "twenty rows or a line, whichever fits",
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) { ForEach(0..<20, id: \.self) { Text("row \($0)") } }
            Text("short")
        })
    return found
}

@MainActor
@Suite("The scrollbar's shortcut agrees with the natural-extent ladder")
struct ScrollbarShortcutAgreementTests {
    /// Around each content's own height, where an off-by-one would show: a
    /// viewport a line short of it, exactly it, and a line more.
    private static let heights = [
        0, 1, 4, 9, 10, 11, 19, 20, 21, 29, 30, 31, 299, 300, 301, 449, 450, 451, 902, 903, 904,
    ]

    /// The shortcut is the ladder's first rung, not climbed. Where that rung
    /// does not fill its budget the ladder ends on it, so the two cannot
    /// differ; where it does, the content filled thousands of lines and
    /// overflows any viewport, and the ladder agrees unless the content shrinks
    /// as it is offered more. A yes the ladder contradicts would reserve a bar
    /// for content that fits; a no it contradicts would only cost the climb.
    /// Content that picks its layout by the height it is offered is here too,
    /// since a smaller budget would have had it pick another.
    @Test("The shortcut says what the ladder says, around every content's own height")
    func shortcutAgreesWithTheLadder() {
        let found = disagreementsOverEveryContent(heights: Self.heights, contentWidth: 30, availableWidth: 30)
        #expect(found.isEmpty, "\(found.count) disagreements:\n\(found.joined(separator: "\n"))")
    }

    /// A scroll view given no column at all. Its first round asks at a width
    /// of one — `resolveScrollbars` never probes narrower — in a context that
    /// offers none, and the ladder lays the content out at the width it asks
    /// at, whatever the context offers. So must the shortcut: it states the
    /// width on its canvas (`contentOverflowsCanvas`'s `availableWidth`), and
    /// it is this case, where the two widths differ, that says so.
    @Test("The shortcut says what the ladder says at a viewport no column wide")
    func shortcutAgreesWithTheLadderAtNoWidth() {
        let found = disagreementsOverEveryContent(heights: Self.heights, contentWidth: 1, availableWidth: 0)
        #expect(found.isEmpty, "\(found.count) disagreements:\n\(found.joined(separator: "\n"))")
    }

    /// For content it has seen walk a nested lazy stack, the round asks one
    /// line past the viewport, where each such stack stops a screenful in
    /// rather than walking every row it holds. A yes there reserves the bar
    /// with no ladder after it, so every yes must be the ladder's; a no is
    /// followed by the ladder, which decides, so a no may differ — and does,
    /// for content that picks a shorter layout when it is offered less.
    @Test("One line past the viewport, every yes the shortcut says is the ladder's", arguments: [false, true])
    func oneLinePastSaysOnlyTheLaddersYes(noColumn: Bool) {
        let found = disagreementsOverEveryContent(
            heights: Self.heights, contentWidth: noColumn ? 1 : 30, availableWidth: noColumn ? 0 : 30,
            oneLinePast: true)
        #expect(found.isEmpty, "\(found.count) disagreements:\n\(found.joined(separator: "\n"))")
    }
}
